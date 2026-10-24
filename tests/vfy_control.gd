extends SceneTree
## ADVERSARIAL REPRODUCTION of the "control" probe (tests/skill_cell.gd,
## tests/skill_ladder.gd, tests/hand_noise.gd). Written from the brief's spec,
## not copied: own noise model (class Hand, below), own seeds, own stance
## build, own press-shift mechanism. THE SIM HAS NO RNG; THIS PROBE DOES.
##
## Throw protocol is lab_throw.gd's standing throw (stand_at + throw_once):
## fresh lab, teleport to (anchor.x - lead, -BODY_R), 90 ticks with the hand
## held at a0 and NO noise (the stance), then the throw: w ticks of windup at
## a0, sd ticks at a1, (pull: 10 ticks at a0 amp 0.7), then a1 held, 130 ticks
## after the windup at most; cue-driven grip ("wrap" |a_theta| >= 2.6, "touch"
## contact band), re-arming up to 4 closes; 55 ticks held after the catch;
## green = m._holds(k).
##
## NOISE (per the brief, one draw order, seeded per (tag, tier, stroke, sample)):
##   OFFSET   one Gaussian Vector2 per throw, sd off_px * (1/60 m), x,y indep.
##   TREMOR   per-tick: white Gaussian through a one-pole low-pass at 5 Hz
##            (pole a = exp(-2 pi 5 / 60)); innovation sd chosen so the
##            stationary sd is trem_px * (1/60 m). Started from stationarity.
##   SPEED    one Gaussian scalar per throw, sd 5 %, clamped [0.8, 1.2],
##            multiplies the durations of the stroke phases after the windup.
##   TIMING   one integer per throw, uniform in [-jit, +jit] ticks, added to
##            the tick of the FIRST close. Implemented as: pass A finds the
##            cue tick g0 with the noise stream; the sim and the noise are
##            restored to the end-of-windup snapshot and pass B forces the
##            first close at max(w, g0 + jit), re-arms cue-driven after.
## Noise is added to the cursor from t = 0 of the throw (windup included).
##
##   godot --headless --path . -s res://tests/vfy_control.gd -- cell   <k> <wrap|touch> <lead> <a0> <a1> <sd> <pull> <N> <tier> <tag>
##   godot --headless --path . -s res://tests/vfy_control.gd -- ladder <k> <wrap|touch> <lead> <a0> <a1> <sd> <pull> <N> <tier> <tag>
##   godot --headless --path . -s res://tests/vfy_control.gd -- null   <k> <wrap|touch> <lead> <a0> <a1> <sd> <pull> <N>
const MAIN := preload("res://main.gd")

const M_PER_PX := 1.0 / 60.0    # main.gd PPM_INPUT = 60 px per metre of mouse
const TIERS := {
	"null":     [0.0, 0.0, 0.00, 0],
	"mouse03":  [0.3, 0.3, 0.05, 1],
	"mouse1":   [1.0, 1.0, 0.05, 2],
	"trackpad": [2.0, 2.0, 0.05, 3],
	"off_only": [2.0, 0.0, 0.00, 0],
	"trem_only":[0.0, 2.0, 0.00, 0],
	"jit_only": [0.0, 0.0, 0.00, 3],
}

class Hand:
	var rng := RandomNumberGenerator.new()
	var off := Vector2.ZERO
	var speed := 1.0
	var jit := 0
	var trem := Vector2.ZERO
	var a := 0.0
	var inn := 0.0
	var trem_sd := 0.0
	func _init(tier: Array, seed_str: String) -> void:
		# own seed: 64-bit FNV-1a over the seed string
		var h: int = -3750763034362895579   # FNV offset basis (as int64)
		for b in seed_str.to_utf8_buffer():
			h = (h ^ int(b)) * 1099511628211
		rng.seed = h
		var off_sd := float(tier[0]) * M_PER_PX
		trem_sd = float(tier[1]) * M_PER_PX
		var sp_sd := float(tier[2])
		var jmax := int(tier[3])
		# fixed draw order
		off = Vector2(rng.randfn(), rng.randfn()) * off_sd
		speed = clampf(1.0 + rng.randfn() * sp_sd, 0.8, 1.2)
		jit = rng.randi_range(-jmax, jmax) if jmax > 0 else 0
		a = exp(-2.0 * PI * 5.0 / 60.0)
		inn = trem_sd * sqrt(1.0 - a * a)
		trem = Vector2(rng.randfn(), rng.randfn()) * trem_sd
	func step() -> Vector2:
		trem = trem * a + Vector2(rng.randfn(), rng.randfn()) * inn
		return off + trem
	func save() -> Array:
		return [rng.state, trem]
	func load(s: Array) -> void:
		rng.state = int(s[0])
		trem = s[1]

var m: Node2D
var stance_snap := {}
var stance_key := ""

func new_lab() -> Node2D:
	var s: Node2D = MAIN.new()
	s.external_drive = true
	s.level_id = "lab"
	s.setup_sim()
	s.save_enabled = false
	return s

func stand(k: int, lead: float, a0: float) -> void:
	# a stance is ALWAYS lab_throw's: a fresh lab, teleport, 90 ticks at a0.
	# Built once per (k, lead, a0) from a fresh sim and snapshotted; the rig
	# self-check (mode null) confirms restore(stance) == fresh build by hash.
	var key := "%d/%.5f/%.6f" % [k, lead, a0]
	if key != stance_key:
		if m != null:
			m.free()
		m = new_lab()
		m.teleport(Vector2(float(m.a_pos[k].x) - lead, -m.BODY_R))
		for t in 90:
			m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
		stance_snap = m.snapshot()
		stance_key = key
	else:
		m.restore(stance_snap)

func touching(k: int) -> bool:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

func target(t: int, c: Dictionary, sp: float) -> Vector2:
	var w := int(c["w"])
	var ang := float(c["a0"])
	var amp := 1.0
	if t >= w:
		var te := float(t - w)
		var d1 := float(c["sd"]) * sp
		if te < d1:
			ang = float(c["a1"])
		elif bool(c["pull"]) and te < d1 + 10.0 * sp:
			ang = float(c["a0"]); amp = 0.7
		else:
			ang = float(c["a1"])
	return m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp

func run_pass(k: int, c: Dictionary, policy: String, h: Hand, from: int,
		press: int, want_snap: bool) -> Dictionary:
	var w := int(c["w"])
	var grip := false
	var closes := 0
	var g0 := -1
	var caught := false
	var et := -1
	var peak := -1.0
	var tip := Vector2.ZERO
	var snap := {}
	var hsave := []
	for t in range(from, w + 130):
		if want_snap and t == w:
			snap = m.snapshot()
			hsave = h.save()
		var tgt := target(t, c, h.speed) + h.step()
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var cue := false
		if press >= 0 and closes == 0:
			cue = t >= press
		else:
			cue = absf(float(m.a_theta[k])) >= 2.6 if policy == "wrap" else touching(k)
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
		if t >= w and float(m.tip_speed) > peak:
			peak = float(m.tip_speed)
			tip = m.pos[m.NP - 1]
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	var green := false
	if caught:
		for t in 55:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		green = bool(m._holds(k))
	return {"caught": caught, "green": green, "et": et, "g0": g0, "tip": tip,
		"hash": m.state_hash(), "snap": snap, "hsave": hsave, "jit": h.jit}

func throw(k: int, c: Dictionary, policy: String, h: Hand) -> Dictionary:
	var w := int(c["w"])
	var r := run_pass(k, c, policy, h, 0, -1, h.jit != 0)
	if h.jit != 0 and int(r["g0"]) >= w and not (r["snap"] as Dictionary).is_empty():
		m.restore(r["snap"])
		h.load(r["hsave"])
		var r2 := run_pass(k, c, policy, h, w, maxi(w, int(r["g0"]) + h.jit), false)
		r2["g0"] = r["g0"]
		return r2
	return r

func cell(k: int, c: Dictionary, policy: String, N: int, tier_name: String,
		tag: String, label: String) -> Dictionary:
	var tier: Array = TIERS[tier_name]
	var caught := 0
	var green := 0
	var line := ""
	var hashes := {}
	var tips: Array = []
	var ets: Array = []
	for s in N:
		stand(k, float(c["lead"]), float(c["a0"]))
		var h := Hand.new(tier, "vfy|%s|%s|%s|%d" % [tag, tier_name, label, s])
		var r := throw(k, c, policy, h)
		if bool(r["caught"]):
			caught += 1
			ets.append(int(r["et"]))
		if bool(r["green"]):
			green += 1
		line += "G" if bool(r["green"]) else ("c" if bool(r["caught"]) else ".")
		hashes[int(r["hash"])] = true
		tips.append(r["tip"])
	var mu := Vector2.ZERO
	for tp in tips:
		mu += tp
	mu /= maxi(1, tips.size())
	var ss := 0.0
	for tp in tips:
		ss += (tp - mu).length_squared()
	var et_mu := 0.0
	for e in ets:
		et_mu += float(e)
	et_mu /= maxi(1, ets.size())
	var et_ss := 0.0
	for e in ets:
		et_ss += (float(e) - et_mu) * (float(e) - et_mu)
	return {"caught": caught, "green": green, "P": float(green) / N,
		"line": line, "hashes": hashes.size(),
		"tip_rms": sqrt(ss / maxi(1, tips.size())),
		"et_sd": sqrt(et_ss / maxi(1, ets.size() - 1)) if ets.size() > 1 else 0.0}

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var mode := String(args[0])
	var k := int(args[1])
	var policy := String(args[2])
	var c := {"lead": float(args[3]), "a0": float(args[4]), "a1": float(args[5]),
		"sd": int(args[6]), "pull": int(args[7]) == 1, "w": 120}
	var N := int(args[8])
	var t0 := Time.get_ticks_msec()
	if mode == "null":
		# THE INSTRUMENT'S NULL. (a) N throws under the all-zero tier -> one
		# hash. (b) the snapshotted stance equals a fresh stand_at build.
		var r := cell(k, c, policy, N, "null", "null", "null")
		print("NULL k%d %s L%.2f a0 %.6f a1 %.6f sd %d %s: %d throws all-zero sigmas -> %d distinct hash(es), verdict %s"
			% [k, policy, float(c["lead"]), float(c["a0"]), float(c["a1"]),
			int(c["sd"]), "pull" if bool(c["pull"]) else "nopull", N,
			int(r["hashes"]), r["line"]])
		# (b) fresh build, no snapshot
		var h1 := 0
		for rep in 2:
			var f := new_lab()
			f.teleport(Vector2(float(f.a_pos[k].x) - float(c["lead"]), -f.BODY_R))
			for t in 90:
				f.step_tick(f.body_pos + Vector2(cos(float(c["a0"])), sin(float(c["a0"]))) * f.REACH, false)
			var keep := m
			m = f
			var rr := throw(k, c, policy, Hand.new(TIERS["null"], "x"))
			m = keep
			f.free()
			print("  fresh-build throw %d hash %d green %s" % [rep, int(rr["hash"]), str(rr["green"])])
			h1 = int(rr["hash"])
		stand(k, float(c["lead"]), float(c["a0"]))
		var rs := throw(k, c, policy, Hand.new(TIERS["null"], "x"))
		print("  restored-stance throw hash %d  equals fresh: %s" % [int(rs["hash"]), str(int(rs["hash"]) == h1)])
	elif mode == "cell":
		var tier_name := String(args[9])
		var tag := String(args[10])
		var r := cell(k, c, policy, N, tier_name, tag, "cell")
		print("VFY CELL k%d %s L%.2f a0 %.6f a1 %.6f sd %d %s tier %s tag %s N %d: caught %d green %d P %.2f tip rms %.3f m catch-tick sd %.1f hashes %d  %s"
			% [k, policy, float(c["lead"]), float(c["a0"]), float(c["a1"]),
			int(c["sd"]), "pull" if bool(c["pull"]) else "nopull", tier_name, tag,
			N, int(r["caught"]), int(r["green"]), float(r["P"]),
			float(r["tip_rms"]), float(r["et_sd"]), int(r["hashes"]), r["line"]])
	elif mode == "ladder":
		var tier_name := String(args[9])
		var tag := String(args[10])
		var D: Array = [-0.60, -0.45, -0.35, -0.28, -0.22, -0.17, -0.12, -0.08,
			-0.04, 0.0, 0.04, 0.08, 0.12, 0.17, 0.22, 0.28, 0.35, 0.45, 0.60]
		if args.size() > 11:
			D = []
			for s in String(args[11]).split(","):
				D.append(float(s))
		print("VFY LADDER k%d %s L%.2f a0 %.6f a1 %.6f sd %d %s tier %s N %d"
			% [k, policy, float(c["lead"]), float(c["a0"]), float(c["a1"]),
			int(c["sd"]), "pull" if bool(c["pull"]) else "nopull", tier_name, N])
		print("   d rad   d mm   det  caught green  P")
		for d in D:
			var cc := c.duplicate()
			cc["a1"] = float(c["a1"]) + float(d)
			stand(k, float(c["lead"]), float(c["a0"]))
			var dr := throw(k, cc, policy, Hand.new(TIERS["null"], "det"))
			var det := "G" if bool(dr["green"]) else ("c" if bool(dr["caught"]) else ".")
			var r := cell(k, cc, policy, N, tier_name, tag, "d%.2f" % float(d))
			print("  %+.2f  %+5.0f   %s   %3d  %3d  %.2f  %s" % [float(d),
				float(d) * 1.15 * 1000.0, det, int(r["caught"]), int(r["green"]),
				float(r["P"]), r["line"]])
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if m != null:
		m.free()
	quit(0)
