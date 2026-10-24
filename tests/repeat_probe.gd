extends SceneTree
## REPEATABILITY: ONE INTENTION, A HUNDRED TIMES.
##
## The sim has no RNG, so "the same throw" always gives the same bytes. But a
## HAND never gives the same throw twice, and the question the player asked -
## "how much is skill vs rng, how much control does the user actually have" -
## is a question about the same INTENTION, not the same bytes. So: take a
## stroke that really wins, replay it N times through a model of a human hand
## (offset, tremor, speed, press timing - see class Hand below), and read the
## outcome distribution.
##
##   P(lock) ~ 1.0 at every tier a trackpad can reach   -> the whip repeats.
##   P(lock) ~ 0.5, flat across tiers                    -> decided below the
##                                                          hand's resolution.
##   P(lock) that FALLS as the tier RISES               -> a skill with a
##                                                          precision demand;
##                                                          the knee is the
##                                                          number that matters.
##
## THE SIM HAS NO RNG. THIS PROBE DOES. Every draw is from a
## RandomNumberGenerator seeded from (stroke key, sample index), so any sample
## in any table re-runs to the bit. With every sigma at zero the model is the
## identity and N replays must give ONE state hash: that null runs before
## every table (mode "replay" prints it as its first line).
##
## THE NOISE MODEL (the same definitions as tests/hand_noise.gd, embedded here
## so this probe does not race a file another probe is still writing):
##   OFFSET  one Gaussian vector per throw, sigma S in x and y independently,
##           added to every cursor of the throw: where you put your hand.
##   TREMOR  a per-tick AR(1) with pole exp(-2 pi 5Hz dt), innovation scaled
##           so the STATIONARY sd is S, started from that distribution, added
##           to the cursor every tick: how still you hold it.
##   SPEED   one Gaussian per throw, sd 5%, clamped 0.8..1.2, scaling the
##           stroke's duration (stroke + pull ticks, not the windup).
##   PRESS   one uniform integer per throw in [-J, +J] ticks, added to the
##           tick the hand shuts. The shut tick is CUE + j, where CUE is the
##           first tick THIS replay's wrap reads >= 2.6 rad (route_bot's
##           trigger): a negative j rewinds to the start-of-tick state j ticks
##           earlier (a ring of snapshots, sim + hand), so an early press is
##           causal and bit-exact. After the press, route_bot's re-arm policy
##           applies unchanged: if the 15-tick window lapses with nothing
##           caught the hand opens and shuts again on the cue, at most 4 times.
##
## THE PIXEL. main.gd's control is 1 / PPM_INPUT = 16.67 mm of hand per
## PHYSICAL px (README: 1.66667 m per 100 px; the "138 px" there is the reach
## circle's DIAMETER, 2 x 1.15 m). The brief that commissioned this probe wrote
## "1 px = 8.3 mm", which is that diameter read as a radius. Tiers are
## therefore given in MILLIMETRES, and both readings are covered:
##     2.5 mm   = 0.3 px at the brief's scale (a good mouse)
##     8.3 mm   = 1 px at the brief's scale  = 0.5 px measured
##    16.7 mm   = 2 px at the brief's scale  = 1 px measured ("trackpad")
##    33.3 mm   = 2 px MEASURED
##
## HOLD. After a catch the cursor parks on the body and the hand stays shut
## for 180 ticks (3 s); for the standing stations the floor is removed first
## (tests/lab_throw.gd hold_test: on a 2.2 m beam a hang measured with the
## floor in is a hang measured ON the floor). HELD = a_freelen >= 0 at +180,
## GREEN = _holds() there (a_locked == 1 and engaged).
##
##   godot --headless --path . -s res://tests/repeat_probe.gd -- <mode> ...
##     search   <station> <outdir>                the 108-grid, 3 distinct winners
##     replay   <station> <idx> <N> <outdir>      the tables for winner idx
##     leapscan <outdir>                          which swings reach FAST 7
##     leapsearch <outdir>                        3 distinct winning leaps
##     leapreplay <idx> <N> <outdir>              the tables for leap idx
##   stations: beam (lab k0 r0.22)  thin (lab k1 r0.11)  door (traverse k3)
##             fast (traverse k7, from a swing on door k3)
const MAIN := preload("res://main.gd")
const TL := preload("res://tests/tapelib.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const PUMP := preload("res://tests/bot_pump.gd")

const M_PER_PX := 1.0 / 60.0          # main.gd PPM_INPUT: the measured pixel
const TREMOR_HZ := 5.0
const CUE_RAD := 2.6                  # route_bot's grip trigger
const WINDUP := 120
const SETTLE := 90
const HOLD := 180

# ------------------------------------------------------------ the hand ----
class Hand:
	var rng := RandomNumberGenerator.new()
	var off := Vector2.ZERO           # m
	var speed := 1.0
	var jit := 0
	var trem := Vector2.ZERO          # m
	var alpha := 0.0
	var innov := 0.0
	var sig_mm := 0.0
	var jmax := 0

	func _init(key: String, sample: int, pos_mm: float, jit_ticks: int,
			speed_sd: float, off_on := true, trem_on := true) -> void:
		sig_mm = pos_mm
		jmax = jit_ticks
		rng.seed = int(("%s#%d" % [key, sample]).hash()) * 2654435761 + sample
		var s := pos_mm * 0.001
		# fixed draw order: off.x off.y speed jit trem0.x trem0.y, then the
		# tremor's two draws per tick
		var ox := rng.randfn(0.0, 1.0)
		var oy := rng.randfn(0.0, 1.0)
		off = Vector2(ox, oy) * s if (off_on and s > 0.0) else Vector2.ZERO
		var sp := rng.randfn(0.0, 1.0)
		speed = clampf(1.0 + sp * speed_sd, 0.8, 1.2) if speed_sd > 0.0 else 1.0
		jit = rng.randi_range(-jit_ticks, jit_ticks) if jit_ticks > 0 else 0
		alpha = exp(-TAU * TREMOR_HZ / 60.0)
		var ts := s if trem_on else 0.0
		innov = ts * sqrt(1.0 - alpha * alpha)
		var tx := rng.randfn(0.0, 1.0)
		var ty := rng.randfn(0.0, 1.0)
		trem = Vector2(tx, ty) * ts if ts > 0.0 else Vector2.ZERO

	func tick() -> Vector2:
		if innov > 0.0:
			trem = trem * alpha + Vector2(rng.randfn(0.0, 1.0),
				rng.randfn(0.0, 1.0)) * innov
		return off + trem

	func save() -> Dictionary:
		return {"st": rng.state, "tr": trem}

	func load(d: Dictionary) -> void:
		rng.state = int(d["st"])
		trem = d["tr"]

# a cell of the table: what is switched on, and how big
func cell(name: String, pos_mm: float, jit: int, speed_sd := 0.05,
		off_on := true, trem_on := true) -> Dictionary:
	return {"name": name, "pos": pos_mm, "jit": jit, "speed": speed_sd,
		"off": off_on, "trem": trem_on}

func hand_for(c: Dictionary, key: String, i: int) -> Hand:
	return Hand.new(key, i, float(c["pos"]), int(c["jit"]),
		float(c["speed"]), bool(c["off"]), bool(c["trem"]))

# THE CELLS. The diagonal of the brief's 3x3 (position tier x timing tier),
# its two off-diagonal extremes, and the measured-pixel trackpad on top; then
# the trackpad tier one noise at a time, for attribution.
func main_cells() -> Array:
	return [
		cell("null        0.0mm  +-0", 0.0, 0, 0.0),
		cell("mouse       2.5mm  +-1", 2.5, 1),
		cell("mouse       2.5mm  +-3", 2.5, 3),
		cell("1px(brief)  8.3mm  +-2", 8.3, 2),
		cell("trackpad   16.7mm  +-1", 16.7, 1),
		cell("trackpad   16.7mm  +-3", 16.7, 3),
		cell("2px(meas)  33.3mm  +-3", 33.3, 3),
	]

func part_cells() -> Array:
	return [
		cell("part: offset only 33mm", 33.3, 0, 0.0, true, false),
		cell("part: tremor only 33mm", 33.3, 0, 0.0, false, true),
		cell("part: press only  +-3 ", 0.0, 3, 0.0),
		cell("part: speed only  5%  ", 0.0, 0, 0.05),
	]

# ------------------------------------------------------------- stations ----
func station(name: String) -> Dictionary:
	match name:
		"beam":
			return {"name": "BEAM r0.22 (lab k0, 2.2 m)", "level": "lab", "k": 0}
		"thin":
			return {"name": "THIN r0.11 (lab k1, 2.2 m)", "level": "lab", "k": 1}
		"door":
			return {"name": "DOOR r0.11 (traverse k3, 2.2 m over home tier)",
				"level": "", "k": 3}
	return {}

func new_sim(level: String) -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = level
	m.setup_sim()
	m.save_enabled = false            # belt and braces: _ready never fires
	return m

# the stance: teleport onto the floor `lead` m before the anchor, settle 90
# ticks with the hand BACK at the windup angle (lab_throw's stand_at, and the
# measured reason for it), no noise. The snapshot of this is the state every
# replay of the intention starts from.
func stance(m: Node2D, k: int, lead: float, a0: float) -> Dictionary:
	var x := float(m.a_pos[k].x) - lead
	m.teleport(Vector2(x, TL.floor_y(m, x) - m.BODY_R))
	for t in SETTLE:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
	return m.snapshot()

func strip_floor(m: Node2D) -> void:
	m.t_a = PackedVector2Array()
	m.t_b = PackedVector2Array()
	m.t_n = PackedVector2Array()
	m.t_lo = PackedVector2Array()
	m.t_hi = PackedVector2Array()
	m.t_deep = PackedFloat32Array()
	m.world_bottom = 1.0e9

# ------------------------------------------------------------ one throw ----
# From the stance snapshot: windup, stroke, follow-through, with the hand's
# error on every cursor and the press at cue + j. Then the hold.
func throw_noisy(m: Node2D, snap: Dictionary, k: int, c: Dictionary,
		h: Hand, strip: bool) -> Dictionary:
	m.restore(snap)
	var a0 := float(c["a0"])
	var a1 := float(c["a1"])
	var pull := bool(c["pull"])
	var sd := maxi(1, roundi(int(c["sd"]) * h.speed))
	var pw := maxi(1, roundi(10.0 * h.speed))
	var T := WINDUP + 130
	var ring: Array = []
	var t := 0
	var g0 := -1
	var press := -1
	var grip := false
	var closes := 0
	var caught := false
	var et := -1
	var th_c := 0.0
	while t < T:
		if g0 < 0 and h.jit < 0:
			ring.push_back({"s": m.snapshot(), "h": h.save(), "t": t})
			if ring.size() > -h.jit + 1:
				ring.pop_front()
		var cue := absf(float(m.a_theta[k])) >= CUE_RAD \
			and float(m.a_freelen[k]) < 0.0
		if g0 < 0 and cue:
			g0 = t
			if h.jit < 0:
				var e: Dictionary = ring[0]
				m.restore(e["s"])
				h.load(e["h"])
				t = int(e["t"])
				ring.clear()
				cue = false
			press = maxi(g0 + h.jit, 0)
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
		var ang := a0
		var amp := 1.0
		if t < WINDUP:
			ang = a0
		elif t < WINDUP + sd:
			ang = a1
		elif pull and t < WINDUP + sd + pw:
			ang = a0
			amp = 0.7
		else:
			ang = a1
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(ang), sin(ang)) * m.REACH * amp + h.tick()
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			th_c = absf(float(m.a_theta[k]))
			break
		t += 1
	var hash: int = m.state_hash()
	var r := {"caught": caught, "et": et, "th": th_c, "g0": g0, "press": press,
		"j": h.jit, "closes": closes, "speed": h.speed, "off": h.off,
		"hash": hash, "cls": -1, "cls_t": -1, "lost_t": -1, "held": false,
		"green": false, "gnd": 0}
	if not caught:
		r["why"] = "miss"
		return r
	hold_out(m, k, r, strip)
	return r

func hold_out(m: Node2D, k: int, r: Dictionary, strip: bool) -> void:
	if strip:
		strip_floor(m)
	for t in HOLD:
		m.step_tick(m.body_pos, true)
		if m.grounded:
			r["gnd"] = int(r["gnd"]) + 1
		if int(r["cls"]) < 0 and int(m.a_locked[k]) >= 0 \
				and float(m.a_freelen[k]) >= 0.0:
			r["cls"] = int(m.a_locked[k])
			r["cls_t"] = t
		if float(m.a_freelen[k]) < 0.0:
			r["lost_t"] = t
			break
	r["held"] = float(m.a_freelen[k]) >= 0.0
	r["green"] = bool(m._holds(k))
	if bool(r["green"]):
		r["why"] = "win"
	elif int(r["cls"]) == 0:
		r["why"] = "partial"
	elif int(r["cls"]) == 1:
		r["why"] = "demoted"
	else:
		r["why"] = "unclassified"

# --------------------------------------------------------------- search ----
const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]

func null_hand() -> Hand:
	return Hand.new("null", 0, 0.0, 0, 0.0)

func cstr(c: Dictionary) -> String:
	return "lead %.1f a0 %.3f a1 %.3f sd %d pull %s" % [float(c["lead"]),
		float(c["a0"]), float(c["a1"]), int(c["sd"]), str(bool(c["pull"]))]

func do_search(sname: String, outdir: String) -> void:
	var st := station(sname)
	var m := new_sim(String(st["level"]))
	var k := int(st["k"])
	var strip := true
	print("")
	print("SEARCH %s: the 108-cell grid (3 leads x 6 angle pairs x 3 sd x pull)," % st["name"])
	print("cue-driven grip, no noise; each catch held 180 ticks with the floor out.")
	var att := 0
	var caught := 0
	var locked := 0
	var green := 0
	var wins: Array = []
	for lead in [1.6, 2.0, 2.4]:
		for gi in GRID.size():
			var ang: Array = GRID[gi]
			for sd in [9, 14, 5]:
				for pull in [false, true]:
					var c := {"lead": lead, "a0": ang[0], "a1": ang[1], "sd": sd,
						"pull": pull, "gi": gi}
					var snap := stance(m, k, lead, float(c["a0"]))
					var r := throw_noisy(m, snap, k, c, null_hand(), strip)
					att += 1
					if bool(r["caught"]):
						caught += 1
						if int(r["cls"]) == 1:
							locked += 1
						if bool(r["green"]):
							green += 1
							c["g0"] = int(r["g0"])
							c["th"] = float(r["th"])
							c["hash"] = str(int(r["hash"]))
							wins.append(c)
	print("  att %d caught %d locked %d green@180 %d" % [att, caught, locked, green])
	# THREE DISTINCT WINNERS: different angle pairs first (a different cursor
	# path), then different stroke length, then different stance.
	var pick: Array = []
	for pass_ in 3:
		for w in wins:
			if pick.size() >= 3:
				break
			var ok := true
			for p in pick:
				if pass_ == 0 and int(p["gi"]) == int(w["gi"]):
					ok = false
				elif pass_ == 1 and int(p["gi"]) == int(w["gi"]) \
						and int(p["sd"]) == int(w["sd"]):
					ok = false
				elif pass_ == 2 and cstr(p) == cstr(w):
					ok = false
			if ok:
				pick.append(w)
	for i in pick.size():
		var w: Dictionary = pick[i]
		print("  winner %d: %s   cue@%d  theta@catch %.2f" % [i, cstr(w),
			int(w["g0"]), float(w["th"])])
	var f := FileAccess.open("%s/winners_%s.json" % [outdir, sname],
		FileAccess.WRITE)
	f.store_string(JSON.stringify({"station": sname, "att": att,
		"caught": caught, "locked": locked, "green": green, "wins": pick,
		"all": wins.size()}))
	f.close()
	m.free()

# --------------------------------------------------------------- replay ----
func wilson(kk: int, n: int) -> String:
	if n == 0:
		return "-"
	var z := 1.96
	var p := float(kk) / float(n)
	var d := 1.0 + z * z / n
	var cc := (p + z * z / (2.0 * n)) / d
	var hh := z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / d
	return "%.2f-%.2f" % [maxf(0.0, cc - hh), minf(1.0, cc + hh)]

func summarise(rs: Array) -> Dictionary:
	var n := rs.size()
	var s := {"n": n, "caught": 0, "locked": 0, "green": 0, "held": 0,
		"miss": 0, "partial": 0, "demoted": 0, "unclassified": 0,
		"first_press": 0, "distinct": 0, "th_mean": 0.0, "th_sd": 0.0,
		"never_launched": 0, "snag": 0, "grounded": 0, "win_grounded": 0, "win": 0}
	var hs := {}
	var ths: Array[float] = []
	for r in rs:
		if bool(r["caught"]):
			s["caught"] = int(s["caught"]) + 1
			ths.append(float(r["th"]))
			if int(r["closes"]) == 1:
				s["first_press"] = int(s["first_press"]) + 1
		if int(r["cls"]) == 1:
			s["locked"] = int(s["locked"]) + 1
		if bool(r["green"]):
			s["green"] = int(s["green"]) + 1
		if bool(r["held"]):
			s["held"] = int(s["held"]) + 1
		var w := String(r["why"])
		if s.has(w):
			s[w] = int(s[w]) + 1
		hs[int(r["hash"])] = true
	s["distinct"] = hs.size()
	if ths.size() > 0:
		var mu := 0.0
		for v in ths:
			mu += v
		mu /= ths.size()
		var va := 0.0
		for v in ths:
			va += (v - mu) * (v - mu)
		s["th_mean"] = mu
		s["th_sd"] = sqrt(va / maxf(1.0, ths.size() - 1.0))
	return s

func row(label: String, s: Dictionary) -> String:
	return "  %-24s n %3d | caught %3d lock %3d GREEN@3s %3d  P %.2f [%s] | miss %3d partial %3d demoted %3d | theta %.2f+-%.2f | 1st-press %3d hashes %3d" % [
		label, int(s["n"]), int(s["caught"]), int(s["locked"]), int(s["green"]),
		float(s["green"]) / maxf(1.0, float(s["n"])),
		wilson(int(s["green"]), int(s["n"])), int(s["miss"]), int(s["partial"]),
		int(s["demoted"]), float(s["th_mean"]), float(s["th_sd"]),
		int(s["first_press"]), int(s["distinct"])]

func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}

func do_replay(sname: String, idx: int, N: int, outdir: String) -> void:
	var st := station(sname)
	var wj := load_json("%s/winners_%s.json" % [outdir, sname])
	var wins: Array = wj.get("wins", [])
	if idx >= wins.size():
		print("no winner %d for %s" % [idx, sname])
		return
	var c: Dictionary = wins[idx]
	var k := int(st["k"])
	var m := new_sim(String(st["level"]))
	var snap := stance(m, k, float(c["lead"]), float(c["a0"]))
	var key := "%s/%d" % [sname, idx]
	print("")
	print("REPLAY %s  winner %d: %s" % [st["name"], idx, cstr(c)])
	# THE NULL: 8 samples at all-zero sigmas -> one hash, and the search's own
	# verdict (its hash is the winner's hash at the catch tick)
	var nul: Array = []
	for i in 8:
		nul.append(throw_noisy(m, snap, k, c, Hand.new(key, i, 0.0, 0, 0.0),
			true))
	var sn := summarise(nul)
	var same_as_search := str(int(nul[0]["hash"])) == String(c["hash"])
	print("  NULL x8: distinct hashes %d, green %d/8, hash == search's %s  -> %s" % [
		int(sn["distinct"]), int(sn["green"]), str(same_as_search),
		"PASS" if int(sn["distinct"]) == 1 and int(sn["green"]) == 8
			and same_as_search else "FAIL"])
	# press-shift check: press == cue + j for both signs, no other noise
	var okj := 0
	var nj := 0
	for jj in [-3, -2, -1, 1, 2, 3]:
		var h := Hand.new(key + "/j", jj + 10, 0.0, 0, 0.0)
		h.jit = jj
		var r := throw_noisy(m, snap, k, c, h, true)
		nj += 1
		if int(r["g0"]) >= 0 and int(r["press"]) == int(r["g0"]) + jj:
			okj += 1
	print("  press shift honoured (press == cue + j) %d/%d, j in -3..+3 excl 0" % [okj, nj])
	var out := {"station": sname, "idx": idx, "stroke": c, "N": N,
		"null_distinct": int(sn["distinct"]), "null_green": int(sn["green"]),
		"cells": []}
	print("  cell                     n     | outcomes                                     | losses                       | wrap at catch  | presses/hashes")
	for cc in main_cells() + part_cells():
		var n := N if float(cc["pos"]) > 0.0 or int(cc["jit"]) > 0 \
			or float(cc["speed"]) > 0.0 else 8
		if String(cc["name"]).begins_with("part"):
			n = maxi(20, N / 2)
		var rs: Array = []
		for i in n:
			rs.append(throw_noisy(m, snap, k, c, hand_for(cc, key + "/"
				+ String(cc["name"]), i), true))
		var s := summarise(rs)
		s["cell"] = cc
		# where the lost ones diverged, by press offset, for the reading
		var byj := {}
		for r in rs:
			var jk := str(int(r["j"]))
			if not byj.has(jk):
				byj[jk] = [0, 0]
			byj[jk][0] += 1
			if bool(r["green"]):
				byj[jk][1] += 1
		s["byj"] = byj
		print(row(String(cc["name"]), s))
		out["cells"].append(s)
	var f := FileAccess.open("%s/replay_%s_%d.json" % [outdir, sname, idx],
		FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	m.free()

# ----------------------------------------------------------------- leap ----
# THE ONLY NON-STANDING THROW. The intention is bot_leap's policy: pump on
# door 3 until the swing peaks past `amp`, open the hand at `rel` degrees on
# the way up, stroke `s0` ticks later at `aim`, shut on the wrap reading.
# The hand's error rides on every cursor (pump included); the press is
# cue + j with the same rewind ring; the release stays the policy's own
# closed-loop reading of the swing (a player lets go on what he sees).

func leap_hang(kind: String, hang: float, th0: float, thrown: Dictionary) -> Node2D:
	# kind "wound": bot_leap's rig_level (the bench start). kind "thrown": a
	# real throw at the door from the tier, then hauled off the lip (route_bot's
	# haul_off), then held shut - the state a player is actually in.
	var m := new_sim("")
	if kind == "wound":
		LEAP._wind_on(m, 3, hang, 1.8, deg_to_rad(th0))
		for t in 30:
			m.step_tick(m.body_pos, true)
		return m
	var snap := stance(m, 3, float(thrown["lead"]), float(thrown["a0"]))
	var r := throw_noisy(m, snap, 3, thrown, null_hand(), false)
	if not bool(r["green"]):
		m.free()
		return null
	return m

func leap_noisy(m: Node2D, snap: Dictionary, pol: Dictionary, h: Hand) -> Dictionary:
	m.restore(snap)
	var ka := 3
	var kb := 7
	var pp := pol.duplicate()
	pp["sd"] = maxi(1, roundi(int(pol["sd"]) * h.speed))
	pp["grip_arm"] = 999.0            # the policy never grips: the grip is ours
	pp["grip_at"] = -1
	var st := LEAP.leap_begin(m, ka, kb, pp)
	var prev: Vector2 = m.body_pos
	var ring: Array = []
	var t := 0
	var g0 := -1
	var press := -1
	var grip := false
	var closes := 0
	var caught := false
	var et := -1
	var th_c := 0.0
	var snag := -1
	var guard := 0
	while guard < 3000:
		guard += 1
		var ph := String(st["phase"])
		if ph == "hang" or ph == "fail":
			break
		if ph == "fly" and g0 < 0 and h.jit < 0:
			ring.push_back({"s": m.snapshot(), "h": h.save(), "t": t,
				"st": st.duplicate(true), "prev": prev})
			if ring.size() > -h.jit + 1:
				ring.pop_front()
		var cue := ph == "fly" and absf(float(m.a_theta[kb])) >= CUE_RAD \
			and float(m.a_freelen[kb]) < 0.0
		if g0 < 0 and cue:
			g0 = t
			if h.jit < 0:
				var e: Dictionary = ring[0]
				m.restore(e["s"])
				h.load(e["h"])
				t = int(e["t"])
				st = e["st"]
				prev = e["prev"]
				ring.clear()
				cue = false
			press = maxi(g0 + h.jit, 0)
		var cg: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		if String(st["phase"]) == "hang":
			break
		var cur: Vector2 = cg[0] + h.tick()
		if String(st["phase"]) == "pump":
			grip = true
		else:
			if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
					and float(m.a_freelen[kb]) < 0.0:
				grip = false
			if int(st["rel_t"]) == t and closes == 0:
				grip = false          # the launch tick itself
			if not grip and float(m.a_freelen[kb]) < 0.0:
				if closes == 0 and press >= 0 and t >= press:
					grip = true
					closes = 1
				elif closes > 0 and closes < 4 and cue:
					grip = true
					closes += 1
			if closes == 0 and press < 0:
				grip = false
		m.step_tick(cur, grip)
		t += 1
		if float(m.a_freelen[kb]) >= 0.0:
			caught = true
			et = t
			th_c = absf(float(m.a_theta[kb]))
			st["phase"] = "hang"
			break
		for j in m.a_pos.size():
			if j != ka and j != kb and float(m.a_freelen[j]) >= 0.0:
				snag = j
		if snag >= 0:
			break
	var r := {"caught": caught, "et": et, "th": th_c, "g0": g0, "press": press,
		"j": h.jit, "closes": closes, "speed": h.speed, "off": h.off,
		"hash": m.state_hash(), "cls": -1, "cls_t": -1, "lost_t": -1,
		"held": false, "green": false, "gnd": 0, "rel_t": int(st["rel_t"]),
		"throw_t": int(st["throw_t"]), "fly": int(st["f"]),
		"amp": float(st["rel_amp"]), "min_d": float(st["min_d"]),
		"snag": snag, "launched": int(st["rel_t"]) >= 0}
	if not caught:
		if snag >= 0:
			r["why"] = "snag"
		elif int(st["rel_t"]) < 0:
			r["why"] = "never_launched"
		elif int(st["ground_t"]) > 0:
			r["why"] = "grounded"
		else:
			r["why"] = "miss"
		return r
	hold_out(m, kb, r, false)
	if bool(r["green"]) and int(r["gnd"]) > 0:
		r["why"] = "win_grounded"
	return r

func leap_pol(hang: float, rel: float, aim: float, lead: int) -> Dictionary:
	var p: Dictionary = LEAP.default_policy()
	p["amp_max"] = 250.0
	p["max_half"] = 22
	p["rel"] = rel
	p["aim"] = aim
	p["lead"] = lead
	p["hang"] = hang
	return p

func do_leapscan(outdir: String) -> void:
	print("")
	print("LEAPSCAN: door 3 (21.4,-2.2) -> fast 7 (27.2,-1.5), 5.84 m along, 0.7 m up.")
	print("Start = bot_leap rig_level on door 3 (wound 1.8 turns, tilted th0),")
	print("30 ticks shut. Policy = bot_leap defaults with route_bot's amp_max 250.")
	print("  hang th0  rel  aim  lead | launched fly  amp  min_d | caught cls green why")
	var found: Array = []
	for hang in [1.2, 1.6, 2.0, 2.4]:
		for rel in [-1.0, 25.0, 45.0]:
			for aim in [-0.5, -0.8]:
				for lead in [38]:
					var m := leap_hang("wound", hang, 6.0, {})
					if float(m.a_freelen[3]) < 0.0:
						print("  %.1f  6  the start wrap did not take" % hang)
						m.free()
						continue
					var snap: Dictionary = m.snapshot()
					var pol := leap_pol(hang, rel, aim, lead)
					var r := leap_noisy(m, snap, pol, null_hand())
					print("  %.1f  6  %4.0f %4.1f  %2d  |  %5s   %3d %4.0f %5.2f | %5s %2d %5s %s" % [
						hang, rel, aim, lead, str(bool(r["launched"])),
						int(r["fly"]), float(r["amp"]), float(r["min_d"]),
						str(bool(r["caught"])), int(r["cls"]),
						str(bool(r["green"])), String(r["why"])])
					if bool(r["green"]):
						found.append({"hang": hang, "th0": 6.0, "rel": rel,
							"aim": aim, "lead": lead, "kind": "wound"})
					m.free()
	var f := FileAccess.open("%s/leapscan.json" % outdir, FileAccess.WRITE)
	f.store_string(JSON.stringify({"found": found}))
	f.close()
	print("  %d green leaps" % found.size())

func do_leapsearch(outdir: String) -> void:
	# widen around what leapscan found, and pick 3 distinct (different rel or
	# aim or start hang)
	print("")
	print("LEAPSEARCH: door 3 -> fast 7 from a wound start on door 3.")
	var wins: Array = []
	for hang in [1.2, 1.6, 2.0, 2.4, 2.8]:
		for th0 in [6.0, 11.0]:
			for rel in [-1.0, 20.0, 25.0, 30.0, 35.0, 45.0]:
				for aim in [-0.3, -0.5, -0.8]:
					var m := leap_hang("wound", hang, th0, {})
					if float(m.a_freelen[3]) < 0.0:
						m.free()
						continue
					var snap: Dictionary = m.snapshot()
					var pol := leap_pol(hang, rel, aim, 38)
					var r := leap_noisy(m, snap, pol, null_hand())
					if bool(r["green"]):
						print("  GREEN hang %.1f th0 %.0f rel %.0f aim %.1f  fly %d amp %.0f th %.2f" % [
							hang, th0, rel, aim, int(r["fly"]), float(r["amp"]),
							float(r["th"])])
						wins.append({"hang": hang, "th0": th0, "rel": rel,
							"aim": aim, "lead": 38, "kind": "wound",
							"g0": int(r["g0"]), "th": float(r["th"]),
							"hash": str(int(r["hash"]))})
					m.free()
	var pick: Array = []
	for w in wins:
		if pick.size() >= 3:
			break
		var ok := true
		for p in pick:
			if float(p["rel"]) == float(w["rel"]) and float(p["aim"]) == float(w["aim"]):
				ok = false
			if float(p["hang"]) == float(w["hang"]) and float(p["th0"]) == float(w["th0"]):
				ok = false
		if ok:
			pick.append(w)
	if pick.size() < 3:
		for w in wins:
			if pick.size() >= 3:
				break
			if not pick.has(w):
				pick.append(w)
	print("  %d green of the grid; picked %d" % [wins.size(), pick.size()])
	var f := FileAccess.open("%s/winners_fast.json" % outdir, FileAccess.WRITE)
	f.store_string(JSON.stringify({"wins": pick, "all": wins.size()}))
	f.close()

func do_leapreplay(idx: int, N: int, outdir: String) -> void:
	var wj := load_json("%s/winners_fast.json" % outdir)
	var wins: Array = wj.get("wins", [])
	if idx >= wins.size():
		print("no leap winner %d" % idx)
		return
	var w: Dictionary = wins[idx]
	var m := leap_hang("wound", float(w["hang"]), float(w["th0"]), {})
	var snap: Dictionary = m.snapshot()
	var pol := leap_pol(float(w["hang"]), float(w["rel"]), float(w["aim"]),
		int(w["lead"]))
	var key := "fast/%d" % idx
	print("")
	print("LEAPREPLAY fast 7 from a swing on door 3, winner %d: hang %.1f th0 %.0f rel %.0f aim %.1f" % [
		idx, float(w["hang"]), float(w["th0"]), float(w["rel"]), float(w["aim"])])
	var nul: Array = []
	for i in 8:
		nul.append(leap_noisy(m, snap, pol, Hand.new(key, i, 0.0, 0, 0.0)))
	var sn := summarise(nul)
	var same := str(int(nul[0]["hash"])) == String(w["hash"])
	print("  NULL x8: distinct hashes %d, green %d/8, hash == search's %s -> %s" % [
		int(sn["distinct"]), int(sn["green"]), str(same),
		"PASS" if int(sn["distinct"]) == 1 and int(sn["green"]) == 8 and same
		else "FAIL"])
	var okj := 0
	var nj := 0
	for jj in [-3, -2, -1, 1, 2, 3]:
		var h := Hand.new(key + "/j", jj + 10, 0.0, 0, 0.0)
		h.jit = jj
		var r := leap_noisy(m, snap, pol, h)
		nj += 1
		if int(r["g0"]) >= 0 and int(r["press"]) == int(r["g0"]) + jj:
			okj += 1
	print("  press shift honoured %d/%d" % [okj, nj])
	var out := {"station": "fast", "idx": idx, "leap": w, "N": N, "cells": []}
	print("  cell                     n     | outcomes                                     | losses                       | wrap at catch  | presses/hashes")
	for cc in main_cells() + part_cells():
		var n := N if float(cc["pos"]) > 0.0 or int(cc["jit"]) > 0 \
			or float(cc["speed"]) > 0.0 else 8
		if String(cc["name"]).begins_with("part"):
			n = maxi(20, N / 2)
		var rs: Array = []
		for i in n:
			rs.append(leap_noisy(m, snap, pol, hand_for(cc, key + "/"
				+ String(cc["name"]), i)))
		var s := summarise(rs)
		s["cell"] = cc
		var nl := 0
		var sg := 0
		var gr := 0
		for r in rs:
			var wy := String(r["why"])
			if wy == "never_launched":
				nl += 1
			elif wy == "snag":
				sg += 1
			elif wy == "grounded":
				gr += 1
		s["never_launched"] = nl
		s["snag"] = sg
		s["grounded"] = gr
		print(row(String(cc["name"]), s) + " | nolaunch %d snag %d ground %d" % [nl, sg, gr])
		out["cells"].append(s)
	var f := FileAccess.open("%s/replay_fast_%d.json" % [outdir, idx],
		FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	m.free()

# ----------------------------------------------------------------- main ----
func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var mode := String(args[0]) if args.size() > 0 else ""
	var t0 := Time.get_ticks_msec()
	match mode:
		"search":
			do_search(String(args[1]), String(args[2]))
		"replay":
			do_replay(String(args[1]), int(args[2]), int(args[3]), String(args[4]))
		"leapscan":
			do_leapscan(String(args[1]))
		"leapsearch":
			do_leapsearch(String(args[1]))
		"leapreplay":
			do_leapreplay(int(args[1]), int(args[2]), String(args[3]))
		_:
			print("modes: search <station> <outdir> | replay <station> <idx> <N> <outdir> | leapscan <outdir> | leapsearch <outdir> | leapreplay <idx> <N> <outdir>")
	print("  [%.0f s]" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
