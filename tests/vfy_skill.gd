extends SceneTree
## INDEPENDENT REPRODUCTION of tests/learn_probe.gd's instrument and of the
## measurement it never finished: ONE intention thrown N times through a noisy
## hand, outcome distribution read. Written from the brief's spec, not copied:
## own noise model (below), own press-shift mechanism (two-pass replay instead
## of snapshot rewind), own seeds. THE SIM HAS NO RNG; THIS PROBE DOES, seeded
## per (tier, tag, sample) so any row re-runs to the bit.
##
##   godot --headless --path . -s res://tests/vfy_skill.gd -- <mode> [N] [beam|thin]
##   modes: null | winner | tiers | ladder | edge | jit
##
## Never enters the tree; save_enabled=false; no user://run*.save.
const MAIN := preload("res://main.gd")
const TL := preload("res://tests/tapelib.gd")

const M_PER_PX := 1.0 / 60.0          # main.gd PPM_INPUT = 60 px/m -> 16.67 mm/px
const DT := 1.0 / 60.0
const TREMOR_HZ := 5.0
const CUE_RAD := 2.6
const SETTLE := 90
const HOLD := 55

# off/trem in physical px, speed as a fraction of stroke duration, jit in ticks
const TIERS := {
	"null":      {"off": 0.0, "trem": 0.0, "speed": 0.0,  "jit": 0},
	"mouse03":   {"off": 0.3, "trem": 0.3, "speed": 0.05, "jit": 1},
	"brief8mm":  {"off": 0.5, "trem": 0.5, "speed": 0.05, "jit": 2},   # the brief's "1 px = 8.3 mm"
	"mouse1":    {"off": 1.0, "trem": 1.0, "speed": 0.05, "jit": 2},
	"trackpad":  {"off": 2.0, "trem": 2.0, "speed": 0.05, "jit": 3},
	"off_only":  {"off": 2.0, "trem": 0.0, "speed": 0.0,  "jit": 0},
	"trem_only": {"off": 0.0, "trem": 2.0, "speed": 0.0,  "jit": 0},
	"speed_only": {"off": 0.0, "trem": 0.0, "speed": 0.05, "jit": 0},
	"jit_only":  {"off": 0.0, "trem": 0.0, "speed": 0.0,  "jit": 3},
}

# ---------------------------------------------------------- the hand ------
class Hand:
	var rng := RandomNumberGenerator.new()
	var offset := Vector2.ZERO   # m
	var speed := 1.0
	var jit := 0
	var trem := Vector2.ZERO     # m
	var alpha := 0.0
	var innov := 0.0
	func _init(tier: Dictionary, key: String) -> void:
		rng.seed = key.hash() ^ 0x5bd1e995
		var off_m := float(tier["off"]) * M_PER_PX
		var trem_m := float(tier["trem"]) * M_PER_PX
		# fixed draw order: offset, speed, jit, tremor seed
		var ox := rng.randfn(0.0, 1.0)
		var oy := rng.randfn(0.0, 1.0)
		offset = Vector2(ox, oy) * off_m
		var sp := rng.randfn(0.0, 1.0)
		speed = clampf(1.0 + sp * float(tier["speed"]), 0.8, 1.2) \
			if float(tier["speed"]) > 0.0 else 1.0
		var J := int(tier["jit"])
		jit = rng.randi_range(-J, J) if J > 0 else 0
		alpha = exp(-2.0 * PI * TREMOR_HZ * DT)
		innov = trem_m * sqrt(1.0 - alpha * alpha)
		trem = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * trem_m
	func tick() -> Vector2:
		if innov > 0.0:
			trem = trem * alpha + Vector2(rng.randfn(0.0, 1.0),
				rng.randfn(0.0, 1.0)) * innov
		return offset + trem

# ---------------------------------------------------------- the bench -----
var N := 40
var sims := {}
var fresh := {}

func sim(level: String) -> Node2D:
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

func station(name: String) -> Dictionary:
	if name == "thin":
		return {"name": "THIN r0.11 (lab k1)", "level": "lab", "k": 1}
	return {"name": "BEAM r0.22 (lab k0)", "level": "lab", "k": 0}

# stroke angle at stroke-tick ts (ticks since the windup began)
func aim(c: Dictionary, ts: int, sd: int, pw: int) -> Array:
	var w := int(c.get("w", 120))
	if ts < w:
		return [float(c["a0"]), 1.0]
	if ts < w + sd:
		return [float(c["a1"]), 1.0]
	if bool(c["pull"]) and ts < w + sd + pw:
		return [float(c["a0"]), 0.7]
	return [float(c["a1"]), 1.0]

# ONE THROW, two passes over the SAME noise stream:
#   pass A: hand never closes; find the first tick >= SETTLE at which the cue
#           (taut wrap >= CUE_RAD, not caught) reads true  -> g0
#   pass B: replay; first close at max(g0 + j, SETTLE); then lab_throw's
#           re-arm rule (re-open when GRIP_WINDOW lapses empty, re-close on
#           the cue, at most 4 closes); on catch, hold 55 ticks at the body.
# A throw with no cue in pass A presses never (nocue).
func throw(st: Dictionary, c: Dictionary, tier: String, key: String,
		jfix: int = 999) -> Dictionary:
	var td: Dictionary = TIERS[tier]
	var k := int(st["k"])
	var lead := float(c["lead"])
	var hA := Hand.new(td, key)
	var j := hA.jit if jfix == 999 else jfix
	var sp := hA.speed
	var sd := maxi(1, roundi(int(c["sd"]) * sp))
	var pw := maxi(1, roundi(10.0 * sp))
	var T := SETTLE + int(c.get("w", 120)) + 130
	# pass A
	var m := sim(String(st["level"]))
	var x := float(m.a_pos[k].x) - lead
	var fy := TL.floor_y(m, x)
	m.teleport(Vector2(x, fy - m.BODY_R))
	var g0 := -1
	for t in T:
		if t >= SETTLE and absf(float(m.a_theta[k])) >= CUE_RAD \
				and float(m.a_freelen[k]) < 0.0:
			g0 = t
			break
		var a: Array = aim(c, t - SETTLE, sd, pw)
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(float(a[0])), sin(float(a[0]))) * m.REACH * float(a[1]) + hA.tick()
		m.step_tick(tgt, false)
		if float(m.a_freelen[k]) >= 0.0:
			break   # caught with the hand open? cannot happen, but be honest
	# pass B
	var hB := Hand.new(td, key)
	m = sim(String(st["level"]))
	m.teleport(Vector2(x, fy - m.BODY_R))
	var press := maxi(g0 + j, SETTLE) if g0 >= 0 else -1
	var grip := false
	var closes := 0
	var caught := false
	var et := -1
	var first_press := -1
	for t in T:
		var cue := absf(float(m.a_theta[k])) >= CUE_RAD \
			and float(m.a_freelen[k]) < 0.0
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		if not grip and float(m.a_freelen[k]) < 0.0:
			if closes == 0 and press >= 0 and t >= press:
				grip = true
				closes = 1
				first_press = t
			elif closes > 0 and closes < 4 and cue:
				grip = true
				closes += 1
		var a: Array = aim(c, t - SETTLE, sd, pw)
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(float(a[0])), sin(float(a[0]))) * m.REACH * float(a[1]) + hB.tick()
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	var held := false
	var green := false
	var locked := -1
	if caught:
		for i in HOLD:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		held = float(m.a_freelen[k]) >= 0.0
		green = bool(m._holds(k))
		locked = int(m.a_locked[k])
	return {"caught": caught, "held": held, "green": green, "locked": locked,
		"g0": g0, "press": first_press, "j": j, "speed": sp, "off": hA.offset,
		"hash": m.state_hash(), "et": et}

func sample(st: Dictionary, c: Dictionary, tier: String, tag: String, n: int,
		jfix: int = 999) -> Dictionary:
	var caught := 0
	var held := 0
	var green := 0
	var nocue := 0
	var hashes := {}
	for i in n:
		var r := throw(st, c, tier, "vfy|%s|%s|%d" % [tier, tag, i], jfix)
		if bool(r["caught"]): caught += 1
		if bool(r["held"]): held += 1
		if bool(r["green"]): green += 1
		if int(r["g0"]) < 0: nocue += 1
		hashes[int(r["hash"])] = true
	return {"n": n, "caught": caught, "held": held, "green": green,
		"nocue": nocue, "distinct": hashes.size(), "p": float(green) / float(n)}

func wilson(k: int, n: int) -> String:
	var z := 1.96
	var p := float(k) / float(n)
	var d := 1.0 + z * z / n
	var cc := (p + z * z / (2.0 * n)) / d
	var h := z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / d
	return "%.2f-%.2f" % [maxf(0.0, cc - h), minf(1.0, cc + h)]

func row(label: String, s: Dictionary) -> String:
	return "  %-30s n %3d  caught %3d  held %3d  GREEN %3d  P %.2f [%s]  nocue %2d  distinct %3d  chance %.2f" % [
		label, int(s["n"]), int(s["caught"]), int(s["held"]), int(s["green"]),
		float(s["p"]), wilson(int(s["green"]), int(s["n"])), int(s["nocue"]),
		int(s["distinct"]), 1.0 - maxf(float(s["p"]), 1.0 - float(s["p"]))]

func describe(tier: String) -> String:
	var t: Dictionary = TIERS[tier]
	return "%s: off %.1fpx=%.1fmm trem %.1fpx=%.1fmm speed %.0f%% jit +/-%d" % [tier,
		float(t["off"]), float(t["off"]) * M_PER_PX * 1000.0,
		float(t["trem"]), float(t["trem"]) * M_PER_PX * 1000.0,
		float(t["speed"]) * 100.0, int(t["jit"])]

const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]

# the probe's stated winners, checked directly (and by the search in mode winner)
func claimed(st_name: String) -> Dictionary:
	if st_name == "thin":
		return {"lead": 1.6, "a0": PI * 0.85, "a1": -PI * 0.42, "sd": 9, "pull": true, "w": 120}
	return {"lead": 1.6, "a0": PI * 1.10, "a1": -PI * 0.42, "sd": 9, "pull": false, "w": 120}

func cstr(c: Dictionary) -> String:
	return "lead %.2f a0 %.3f a1 %.3f sd %d pull %s" % [float(c["lead"]),
		float(c["a0"]), float(c["a1"]), int(c["sd"]), str(bool(c["pull"]))]

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var mode := String(args[0]) if args.size() > 0 else "null"
	if args.size() > 1:
		N = int(args[1])
	var sts: Array = []
	for i in range(2, args.size()):
		sts.append(String(args[i]))
	if sts.is_empty():
		sts = ["beam", "thin"]
	print("vfy_skill mode %s N %d stations %s" % [mode, N, str(sts)])
	for sn in sts:
		var st := station(sn)
		var c := claimed(sn)
		print("")
		print("==== %s   claimed winner: %s ====" % [String(st["name"]), cstr(c)])
		var t0 := Time.get_ticks_msec()
		if mode == "null":
			# NULL 1: 8 replays via restore -> one hash, 8/8 green
			var s := sample(st, c, "null", "null", 8)
			print(row("null x8 (restore idiom)", s))
			# NULL 2: fresh MAIN.new() per throw must give the SAME hash as restore
			var fresh_hashes := {}
			for i in 3:
				sims.clear()   # forces a fresh sim + setup each time (leaks are fine in a probe)
				var r := throw(st, c, "null", "vfy|null|null|0")
				fresh_hashes[int(r["hash"])] = true
			var r0 := throw(st, c, "null", "vfy|null|null|0")
			print("  fresh-sim x3 distinct %d; matches restore-idiom hash: %s" % [
				fresh_hashes.size(), str(fresh_hashes.has(int(r0["hash"])))])
			print("  %s" % ("NULL PASS" if int(s["distinct"]) == 1 and int(s["green"]) == 8
				and fresh_hashes.size() == 1 and fresh_hashes.has(int(r0["hash"])) else "NULL FAIL"))
			# calibration of MY model
			for tn in ["mouse03", "brief8mm", "mouse1", "trackpad"]:
				var sx := 0.0; var ss := 0.0; var tx := 0.0; var tn_ := 0
				var jh := {}
				for i in 300:
					var h := Hand.new(TIERS[tn], "cal|%s|%d" % [tn, i])
					sx += h.offset.length_squared()
					ss += (h.speed - 1.0) * (h.speed - 1.0)
					jh[h.jit] = int(jh.get(h.jit, 0)) + 1
					for t in 100:
						var e: Vector2 = h.tick() - h.offset
						tx += e.length_squared(); tn_ += 1
				print("  cal %-9s offset sd %.1f mm/axis  speed sd %.1f%%  tremor sd %.1f mm/axis  j %s" % [
					tn, sqrt(sx / 600.0) * 1000.0, sqrt(ss / 300.0) * 100.0,
					sqrt(tx / float(tn_) / 2.0) * 1000.0, str(jh)])
			# press shift honoured, both signs
			var ok := 0; var n := 0
			for jj in [-3, -1, 1, 3]:
				for i in 3:
					var r := throw(st, c, "null", "vfy|jchk|%d" % i, jj)
					n += 1
					if int(r["g0"]) >= 0 and int(r["press"]) == int(r["g0"]) + jj:
						ok += 1
					elif i == 0:
						print("    j %+d: g0 %d press %d" % [jj, int(r["g0"]), int(r["press"])])
			print("  press shift honoured %d/%d (j in -3,-1,+1,+3)" % [ok, n])
		elif mode == "winner":
			# the 108-cell search in learn_probe's order (sd 9,14,5) AND in
			# lab_throw's order (sd 5,9,14); first green of each
			for order in [[9, 14, 5], [5, 9, 14]]:
				var found := {}
				var greens := 0
				for lead in [1.6, 2.0, 2.4]:
					for ang: Array in GRID:
						for sd in order:
							for pull in [false, true]:
								var cc := {"lead": lead, "a0": ang[0], "a1": ang[1],
									"sd": sd, "pull": pull, "w": 120}
								if bool(throw(st, cc, "null", "w")["green"]):
									greens += 1
									if found.is_empty():
										found = cc
				print("  order %s: first green %s   (greens %d/108)" % [str(order),
					cstr(found) if not found.is_empty() else "NONE", greens])
		elif mode == "tiers":
			for tn in ["null", "mouse03", "brief8mm", "mouse1", "trackpad"]:
				var s := sample(st, c, tn, "tier", N if tn != "null" else 8)
				print(row(describe(tn), s))
			print("  -- one source at a time, trackpad magnitudes --")
			for tn in ["off_only", "trem_only", "speed_only", "jit_only"]:
				var s := sample(st, c, tn, "part", N)
				print(row(tn, s))
		elif mode == "ladder":
			for sgn in [1.0, -1.0]:
				print("  a1 ladder, %s direction, tier mouse1, N %d:" % ["+" if sgn > 0 else "-", N])
				var ps: Array[float] = []
				for v in [0.0, 0.10, 0.20, 0.30, 0.40]:
					var cc := c.duplicate()
					cc["a1"] = float(c["a1"]) + sgn * v
					var d := throw(st, cc, "null", "det")
					var s := sample(st, cc, "mouse1", "lad|%.2f" % (sgn * v), N)
					ps.append(float(s["p"]))
					print(row("a1 %+.2f rad (%+.0f mm)" % [sgn * v, sgn * v * 1150.0], s)
						+ "  det %s" % ("G" if bool(d["green"]) else ("c" if bool(d["caught"]) else ".")))
				var mono := true
				for i in range(1, ps.size()):
					if ps[i] > ps[i - 1] + 1e-9:
						mono = false
				print("  -> %s" % ("MONOTONE toward winner" if mono else "NON-MONOTONE"))
		elif mode == "edge":
			for sgn in [1.0, -1.0]:
				var map := ""
				var i := 0
				var miss := 0
				while i <= 120 and miss < 6:
					var cc := c.duplicate()
					cc["a1"] = float(c["a1"]) + sgn * float(i) * 0.005
					var g := bool(throw(st, cc, "null", "e")["green"])
					map += "#" if g else "."
					miss = miss + 1 if not g else 0
					i += 1
				print("  a1 %s det map (0.005 rad = 5.75 mm/cell): %s" % ["+" if sgn > 0 else "-", map])
		elif mode == "jit":
			var lab := "  j:   "; var pd := "  det: "; var pl := "  P:   "
			for jj in range(-8, 9):
				var d := throw(st, c, "null", "jd", jj)
				var s := sample(st, c, "mouse1", "tedge|%d" % jj, N, jj)
				lab += "%5d" % jj
				pd += "%5s" % ("#" if bool(d["green"]) else ("c" if bool(d["caught"]) else "."))
				pl += "%5.2f" % float(s["p"])
			print("  press timing j (ticks), det row noise-free, P row mouse1 N %d:" % N)
			print(lab); print(pd); print(pl)
		print("  [%s %s done in %d s]" % [sn, mode, (Time.get_ticks_msec() - t0) / 1000])
	quit(0)
