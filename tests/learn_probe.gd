extends SceneTree
## IS THE THROW A SKILL? One intention, thrown N times through a noisy hand
## (tests/hand_noise.gd), and the OUTCOME DISTRIBUTION read - at the winning
## stroke, on a ladder of near-misses walking back toward it, and across the
## edge of the aim basin. THE SIM HAS NO RNG; the hand model does, seeded per
## (tag, sample), so every number here re-runs to the bit.
##
## Three readings, kept apart:
##   SKILL       P(green) at the winner under a human hand (same intention ->
##               same outcome?), and whether P rises MONOTONICALLY as a
##               near-miss is walked back toward the winner (does feedback
##               point the right way?)
##   DIFFICULTY  how far from the winner P(green) falls, and how wide the
##               0.9 -> 0.1 transition is at the basin's edge, in mm of hand
##               and in ticks of press timing
##   CHANCE      1 - max(P, 1-P) at the winner: the rate at which the SAME
##               intention comes out differently under noise a hand cannot
##               practice away
##
## THE THROW is route_bot's stroke shape as lab_throw / crit_basin / crit_jitter
## throw it (windup at a0, stroke to a1 for sd ticks, optional pull, then a1),
## with the noise on the (cursor, grip) surface only. The hand closes on
## lab_throw's cue (taut wrap >= 2.6 rad) shifted by the throw's timing jitter;
## a NEGATIVE shift is made by rewinding the sim that many ticks through
## snapshot/restore (bit-exact, save_test) and closing the hand from there.
## After the first press the hand follows throw_once's re-arm rule unchanged
## (re-open when GRIP_WINDOW lapses empty, re-close on the cue, four closes).
##
##   godot --headless --path . -s res://tests/learn_probe.gd -- <mode> [N] [station...]
##   modes: null | tiers | ladder | edge | all | time   (default all, N 50)
##   stations: beam thin door   (default beam thin)
const MAIN := preload("res://main.gd")
const HN := preload("res://tests/hand_noise.gd")
const TL := preload("res://tests/tapelib.gd")

const CUE_RAD := 2.6
const SETTLE := 90
const HOLD := 55
const LADDER_TIER := "mouse1"        # "1 px / +/-2 ticks" in the brief's words:
                                     # 16.7 mm at the source's own px

const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]

var N := 50

# ------------------------------------------------------------- stations ----
func station(name: String) -> Dictionary:
	if name == "door":
		return {"name": "DOOR r0.11 (traverse k3)", "level": "", "k": 3}
	if name == "thin":
		return {"name": "THIN BEAM r0.11 (lab k1)", "level": "lab", "k": 1}
	return {"name": "BEAM r0.22 (lab k0)", "level": "lab", "k": 0}

# ONE SIM PER LEVEL, restored to its post-setup snapshot before every throw.
# restore() is bit-exact (tests/save_test.gd), so this is the same fresh sim
# a new MAIN.new() + setup_sim() would give, without rebuilding the level
# ~4000 times. new_sim() never enters the tree; no save file can be written.
var sims := {}
var fresh := {}

func new_sim(level: String) -> Node2D:
	if not sims.has(level):
		var m: Node2D = MAIN.new()
		m.external_drive = true
		m.level_id = level
		m.setup_sim()
		m.save_enabled = false
		sims[level] = m
		fresh[level] = m.snapshot()
		return m
	var m2: Node2D = sims[level]
	m2.restore(fresh[level])
	return m2

# ------------------------------------------------------------- one throw ---
# stance: teleport onto the floor under x, lead metres before the anchor; the
# 90-tick settle with the hand back at a0 (stand_at's posture) runs here so
# the tremor covers it. Returns the outcome and the final state hash.
func one(st: Dictionary, lead: float, c: Dictionary, tier: String,
		tag: String, sample: int, jfix: int = 999) -> Dictionary:
	var hn := HN.new(tier, tag, sample)
	if jfix != 999:
		hn.jit = jfix
	var m := new_sim(String(st["level"]))
	var k := int(st["k"])
	var x := float(m.a_pos[k].x) - lead
	m.teleport(Vector2(x, TL.floor_y(m, x) - m.BODY_R))
	var j: int = hn.jit
	var sp: float = hn.speed
	var a0 := float(c["a0"])
	var a1 := float(c["a1"])
	var pull := bool(c["pull"])
	var w := maxi(1, roundi(int(c.get("w", 120)) * sp))
	var sd := maxi(1, roundi(int(c["sd"]) * sp))
	var pw := maxi(1, roundi(10.0 * sp))
	var ring: Array = []                # start-of-tick states, for an early press
	var T := SETTLE + w + 130
	var t := 0
	var g0 := -1
	var press := -1
	var grip := false
	var closes := 0
	var caught := false
	while t < T:
		if g0 < 0 and j < 0:
			ring.push_back({"s": m.snapshot(), "h": hn.save_state(), "t": t})
			if ring.size() > -j + 1:
				ring.pop_front()
		var cue := absf(float(m.a_theta[k])) >= CUE_RAD \
			and float(m.a_freelen[k]) < 0.0
		if g0 < 0 and cue and t >= SETTLE:
			g0 = t
			if j < 0:
				var e: Dictionary = ring[0]
				m.restore(e["s"])
				hn.restore_state(e["h"])
				t = int(e["t"])
				ring.clear()
				cue = absf(float(m.a_theta[k])) >= CUE_RAD \
					and float(m.a_freelen[k]) < 0.0
			press = maxi(g0 + j, SETTLE)
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		if not grip and float(m.a_freelen[k]) < 0.0:
			if closes == 0 and press >= 0 and t >= press:
				grip = true
				closes = 1
			elif closes > 0 and closes < 4 and cue:
				grip = true
				closes += 1
		var ts := t - SETTLE
		var ang := a0
		var amp := 1.0
		if ts < w:
			ang = a0
		elif ts < w + sd:
			ang = a1
		elif pull and ts < w + sd + pw:
			ang = a0
			amp = 0.7
		else:
			ang = a1
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(ang), sin(ang)) * m.REACH * amp + hn.tick()
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			break
		t += 1
	var green := false
	var held := false
	if caught:
		for i in HOLD:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		held = float(m.a_freelen[k]) >= 0.0
		green = bool(m._holds(k))
	var r := {"caught": caught, "held": held, "green": green,
		"g0": g0 - SETTLE if g0 >= 0 else -1,
		"press": press - SETTLE if press >= 0 else -1, "j": j, "speed": sp,
		"off": hn.offset, "hash": m.state_hash()}
	return r

# the 108-cell search crit_basin uses, under the null tier: the first green
func find_winner(st: Dictionary) -> Dictionary:
	for lead in [1.6, 2.0, 2.4]:
		for ang: Array in GRID:
			for sd in [9, 14, 5]:
				for pull in [false, true]:
					var c := {"a0": ang[0], "a1": ang[1], "sd": sd,
						"pull": pull, "w": 120}
					if bool(one(st, lead, c, "null", "search", 0)["green"]):
						c["lead"] = lead
						return c
	return {}

func cstr(c: Dictionary) -> String:
	return "lead %.2f a0 %.3f a1 %.3f sd %d pull %s w %d" % [float(c["lead"]),
		float(c["a0"]), float(c["a1"]), int(c["sd"]), str(bool(c["pull"])),
		int(c.get("w", 120))]

# ------------------------------------------------------------- sampling ----
# N throws of one intention under one tier. The tag names the row so any
# sample can be re-run alone: HN.new(tier, tag, i).
func sample(st: Dictionary, c: Dictionary, tier: String, tag: String,
		n: int, jfix: int = 999) -> Dictionary:
	var caught := 0
	var held := 0
	var green := 0
	var nocue := 0
	var hashes := {}
	for i in n:
		var r := one(st, float(c["lead"]), c, tier, tag, i, jfix)
		if bool(r["caught"]):
			caught += 1
		if bool(r["held"]):
			held += 1
		if bool(r["green"]):
			green += 1
		if int(r["g0"]) < 0:
			nocue += 1
		hashes[int(r["hash"])] = true
	return {"n": n, "caught": caught, "held": held, "green": green,
		"nocue": nocue, "distinct": hashes.size(),
		"p": float(green) / float(n)}

func wilson(k: int, n: int) -> String:
	if n == 0:
		return "-"
	var z := 1.96
	var p := float(k) / float(n)
	var d := 1.0 + z * z / n
	var cc := (p + z * z / (2.0 * n)) / d
	var h := z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / d
	return "%.2f-%.2f" % [maxf(0.0, cc - h), minf(1.0, cc + h)]

func row(label: String, s: Dictionary) -> String:
	return "  %-32s n %3d  caught %3d  held %3d  GREEN %3d  P %.2f [%s]  nocue %2d  distinct %3d" % [
		label, int(s["n"]), int(s["caught"]), int(s["held"]), int(s["green"]),
		float(s["p"]), wilson(int(s["green"]), int(s["n"])), int(s["nocue"]),
		int(s["distinct"])]

func chance(p: float) -> float:
	return 1.0 - maxf(p, 1.0 - p)

# ------------------------------------------------------------------ NULL ---
func run_null(st: Dictionary, c: Dictionary) -> void:
	print("")
	print("NULL - the instrument. All sigmas 0, 8 replays of the winner over 8")
	print("sample indices: the state hashes must be ONE value and the verdict green.")
	var s := sample(st, c, "null", "null", 8)
	print(row("null x8", s))
	print("  %s" % ("PASS: 1 distinct hash, 8/8 green"
		if int(s["distinct"]) == 1 and int(s["green"]) == 8
		else "FAIL: %d distinct hashes, %d/8 green" % [int(s["distinct"]),
			int(s["green"])]))
	# the model's own calibration: what the tiers actually draw
	for tn in ["mouse03", "mouse1", "trackpad"]:
		var sx := 0.0
		var ss := 0.0
		var tx := 0.0
		var tn_ := 0
		var jh := {}
		for i in 300:
			var hn := HN.new(tn, "cal", i)
			sx += hn.offset.x * hn.offset.x + hn.offset.y * hn.offset.y
			ss += (hn.speed - 1.0) * (hn.speed - 1.0)
			jh[hn.jit] = int(jh.get(hn.jit, 0)) + 1
			for t in 100:
				var e: Vector2 = hn.tick() - hn.offset
				tx += e.x * e.x + e.y * e.y
				tn_ += 1
		var hn0 := HN.new(tn, "cal", 0)
		print("  %-9s set: %s" % [tn, hn0.describe()])
		print("            300 draws: offset sd %.1f mm/axis, speed sd %.1f%%, tremor sd %.1f mm/axis, j %s" % [
			sqrt(sx / 600.0) * 1000.0, sqrt(ss / 300.0) * 100.0,
			sqrt(tx / float(tn_) / 2.0) * 1000.0, str(jh)])
	# is the press shift honoured? press == cue + j, both signs
	var ok := 0
	var n := 0
	for jj in [-3, -1, 1, 3]:
		for i in 3:
			var r := one(st, float(c["lead"]), c, "null", "jchk", i, jj)
			n += 1
			if int(r["g0"]) >= 0 and int(r["press"]) == int(r["g0"]) + jj:
				ok += 1
	print("  press shift honoured (press tick == cue tick + j) on %d/%d throws, j in -3..+3" % [ok, n])

# ----------------------------------------------------------------- TIERS ---
func run_tiers(st: Dictionary, c: Dictionary) -> void:
	print("")
	print("SKILL / CHANCE AT THE WINNER - the same intention, N %d throws per tier." % N)
	print("  chance = 1 - max(P, 1-P): the rate the same intention disagrees with")
	print("  itself. distinct = distinct final state hashes (1 = no noise at all).")
	for tn in ["null", "mouse03", "mouse1", "trackpad"]:
		var s := sample(st, c, tn, "tier", N if tn != "null" else 8)
		print(row("%s  %s" % [tn, HN.new(tn, "x", 0).describe()], s)
			+ "  chance %.2f" % chance(float(s["p"])))
	print("  -- one noise at a time, trackpad magnitudes (33 mm / 5% / +/-3) --")
	for tn in ["off_only", "trem_only", "speed_only", "jit_only"]:
		var s := sample(st, c, tn, "part", N)
		print(row(tn, s) + "  chance %.2f" % chance(float(s["p"])))

# ---------------------------------------------------------------- LADDER ---
# a near-miss walked back to the winner, N throws per rung under LADDER_TIER
func ladder_axis(st: Dictionary, c: Dictionary, axis: String,
		steps: Array) -> void:
	var ps: Array[float] = []
	var lines: Array[String] = []
	for v in steps:
		var cc := c.duplicate()
		var label := ""
		if axis == "a1":
			cc["a1"] = float(c["a1"]) + float(v)
			label = "a1 %+.2f rad (%+.0f mm)" % [float(v), float(v) * 1150.0]
		elif axis == "sd":
			cc["sd"] = maxi(1, roundi(int(c["sd"]) * (1.0 + float(v))))
			label = "duration %+.0f%% (sd %d)" % [float(v) * 100.0, int(cc["sd"])]
		elif axis == "lead":
			cc["lead"] = float(c["lead"]) + float(v)
			label = "stance %+.1f m (lead %.1f)" % [float(v), float(cc["lead"])]
		var d := one(st, float(cc["lead"]), cc, "null", "det", 0)
		var s := sample(st, cc, LADDER_TIER, "ladder|%s|%s" % [axis, str(v)], N)
		ps.append(float(s["p"]))
		lines.append(row(label, s) + "  det %s" % ("G" if bool(d["green"])
			else ("c" if bool(d["caught"]) else ".")))
	for l in lines:
		print(l)
	var mono := true
	var worst := 0.0
	for i in range(1, ps.size()):
		if ps[i] > ps[i - 1] + 1e-9:
			mono = false
			worst = maxf(worst, ps[i] - ps[i - 1])
	print("  -> %s" % ("MONOTONE: every step toward the winner raises or keeps P"
		if mono else "NON-MONOTONE: a further miss beat a nearer one by up to %.2f" % worst))

func run_ladder(st: Dictionary, c: Dictionary) -> void:
	print("")
	print("LEARNABILITY - a near-miss walked back to the winner, N %d throws per" % N)
	print("rung under tier %s (%s)." % [LADDER_TIER, HN.new(LADDER_TIER, "x", 0).describe()])
	print("'det' is the rung's verdict with NO noise: G green, c caught only, . miss.")
	print("  stroke angle a1 (the aim), + direction:")
	ladder_axis(st, c, "a1", [0.0, 0.10, 0.20, 0.30, 0.40])
	print("  stroke angle a1, - direction:")
	ladder_axis(st, c, "a1", [0.0, -0.10, -0.20, -0.30, -0.40])
	print("  stroke duration:")
	ladder_axis(st, c, "sd", [0.0, 0.20, 0.40, 0.60])
	print("  stance (further from the beam):")
	ladder_axis(st, c, "lead", [0.0, 0.30, 0.60, 0.90])
	print("  stance (nearer the beam):")
	ladder_axis(st, c, "lead", [0.0, -0.30, -0.60, -0.90])

# ------------------------------------------------------------------ EDGE ---
# the deterministic edge of the a1 basin, then P(green) across it under
# LADDER_TIER, in mm of hand; and the press-timing edge in ticks with the same
# cursor noise on and the press shift FIXED per column.
func run_edge(st: Dictionary, c: Dictionary) -> void:
	print("")
	print("BASIN EDGE - how sharp is the cliff a hand has to stand near?")
	for sgn in [1.0, -1.0]:
		var map := ""
		var edge := -1.0
		var i := 0
		var miss := 0
		while i <= 160 and miss < 6:
			var cc := c.duplicate()
			cc["a1"] = float(c["a1"]) + sgn * float(i) * 0.005
			var g := bool(one(st, float(c["lead"]), cc, "null", "edge", 0)["green"])
			map += "#" if g else "."
			if not g:
				miss += 1
				if edge < 0.0:
					edge = float(i) * 0.005
			else:
				miss = 0
			i += 1
		print("  a1 %s: deterministic map out from the winner, 0.005 rad = 5.75 mm of hand per cell" % (
			"+" if sgn > 0 else "-"))
		print("    %s" % map)
		if edge < 0.0:
			print("    no edge inside %.2f rad" % (float(i) * 0.005))
			continue
		print("    first miss at %+.3f rad = %+.0f mm of hand" % [sgn * edge,
			sgn * edge * 1150.0])
		var ps: Array[float] = []
		var lab := "    mm:"
		var pl := "    P: "
		for q in range(-8, 9):
			var cc := c.duplicate()
			cc["a1"] = float(c["a1"]) + sgn * (edge + float(q) * 0.005)
			var s := sample(st, cc, LADDER_TIER, "edge|%s|%d" % [str(sgn), q], N)
			ps.append(float(s["p"]))
			lab += "%5d" % roundi(float(q) * 5.75)
			pl += "%5.2f" % float(s["p"])
		print("    %s P(green) at mm past the deterministic edge, N %d each:" % [LADDER_TIER, N])
		print(lab)
		print(pl)
		print("    0.9 -> 0.1 width: %s" % width_09_01(ps, 5.75, "mm"))
	print("  press timing: hand closed at cue + j ticks (17 ms each), %s cursor noise on, N %d each" % [LADDER_TIER, N])
	var lab2 := "    j:  "
	var pd := "    det:"
	var pl2 := "    P:  "
	var ps2: Array[float] = []
	for jj in range(-8, 9):
		var s := sample(st, c, LADDER_TIER, "tedge|%d" % jj, N, jj)
		var d := one(st, float(c["lead"]), c, "null", "det", 0, jj)
		ps2.append(float(s["p"]))
		lab2 += "%5d" % jj
		pl2 += "%5.2f" % float(s["p"])
		pd += "%5s" % ("#" if bool(d["green"]) else ".")
	print(lab2)
	print(pd)
	print(pl2)
	print("    0.9 -> 0.1 width: %s" % width_09_01(ps2, 1.0, "ticks"))

func width_09_01(ps: Array[float], cell: float, unit: String) -> String:
	# both flanks: from the last cell >= 0.9 to the first cell <= 0.1 going
	# right, and from the first cell >= 0.9 to the last cell <= 0.1 going left
	var out: Array[String] = []
	var hi := -1
	for i in ps.size():
		if ps[i] >= 0.9:
			hi = i
	var lo := -1
	if hi >= 0:
		for i in range(hi + 1, ps.size()):
			if ps[i] <= 0.1:
				lo = i
				break
	if hi >= 0 and lo >= 0:
		out.append("right flank %.1f %s (cells %d..%d)" % [float(lo - hi) * cell, unit, hi, lo])
	var hi2 := -1
	for i in ps.size():
		if ps[i] >= 0.9:
			hi2 = i
			break
	var lo2 := -1
	if hi2 >= 0:
		for i in range(hi2 - 1, -1, -1):
			if ps[i] <= 0.1:
				lo2 = i
				break
	if hi2 >= 0 and lo2 >= 0:
		out.append("left flank %.1f %s (cells %d..%d)" % [float(hi2 - lo2) * cell, unit, lo2, hi2])
	if out.is_empty():
		return "no 0.9 -> 0.1 crossing in range (min %.2f max %.2f)" % [ps.min(), ps.max()]
	return "; ".join(out)

# ------------------------------------------------------------------- run ---
func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var mode := String(args[0]) if args.size() > 0 else "all"
	if args.size() > 1:
		N = int(args[1])
	var sts: Array = []
	for i in range(2, args.size()):
		sts.append(String(args[i]))
	if sts.is_empty():
		sts = ["beam", "thin"]
	print("learn_probe  mode %s  N %d  stations %s  (the sim has no RNG; the hand model is seeded per (tag, sample))" % [
		mode, N, str(sts)])
	if mode == "time":
		var st := station("beam")
		var c := {"a0": PI * 0.85, "a1": -PI * 0.30, "sd": 9, "pull": false,
			"w": 120, "lead": 2.0}
		for tn in ["null", "mouse1"]:
			var t0 := Time.get_ticks_msec()
			for i in 10:
				one(st, 2.0, c, tn, "time", i)
			print("  10 throws %s: %d ms" % [tn, Time.get_ticks_msec() - t0])
		quit(0)
		return
	for sn in sts:
		var st := station(sn)
		print("")
		print("==== %s ====" % String(st["name"]))
		var t0 := Time.get_ticks_msec()
		var c := find_winner(st)
		if c.is_empty():
			print("  no green stroke in the 108-cell search")
			continue
		print("  winner: %s   (search %d ms)" % [cstr(c), Time.get_ticks_msec() - t0])
		if mode == "null" or mode == "all":
			run_null(st, c)
		if mode == "tiers" or mode == "all":
			run_tiers(st, c)
		if mode == "ladder" or mode == "all":
			run_ladder(st, c)
		if mode == "edge" or mode == "all":
			run_edge(st, c)
		print("  [%s done in %d s]" % [sn, (Time.get_ticks_msec() - t0) / 1000])
	for lv in sims:
		sims[lv].free()
	quit(0)
