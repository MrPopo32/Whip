extends SceneTree
## SKILL OR CHANCE, PART 1b: DOES WALKING TOWARD THE WINNER RAISE THE ODDS?
##
## A skill has a gradient: a near-miss that is corrected toward the winning
## stroke should lock MORE often, every step of the way, under the same hand
## noise. A lottery has none. This takes a known winning stroke (found by
## tests/skill_probe.gd's 108-cell search, passed on the command line so no
## search is repeated) and walks ONE parameter at a time from well outside the
## aim basin back to the winner, N noisy throws per rung under one tier of
## tests/hand_noise.gd. Two ladders: the stroke angle a1 (the aim, in rad;
## 0.05 rad = 58 mm of cursor at the 1.15 m reach) and the stance (lead, in m).
##
## Throw machinery is tests/skill_probe.gd's, line for line. THE SIM HAS NO
## RNG; THE PROBE DOES, seeded per (tag, sample). Tier "null" is run once per
## rung (the noise-free verdict, 'det' column) and 3 times at the winner; the
## three must give one hash - the instrument's null.
##
##   godot --headless --path . -s res://tests/skill_ladder.gd -- <station> <wrap|touch> <lead> <a0> <a1> <sd> <pull 0|1> <N> <tier> <out.json>
const MAIN := preload("res://main.gd")
const HN := preload("res://tests/hand_noise.gd")

const D_A1 := [-0.60, -0.45, -0.35, -0.28, -0.22, -0.17, -0.12, -0.08, -0.04,
	0.0, 0.04, 0.08, 0.12, 0.17, 0.22, 0.28, 0.35, 0.45, 0.60]
const D_LEAD := [-0.80, -0.60, -0.45, -0.30, -0.20, -0.10, 0.0, 0.10, 0.20,
	0.30, 0.45, 0.60, 0.80]

var m: Node2D
var stances := {}
var pristine := {}                    # every stance is built from the sim as
                                      # new_lab() made it (lab_throw's stand_at),
                                      # never from where the last throw left
                                      # the rope - see tests/skill_cell.gd

func new_lab() -> Node2D:
	var s: Node2D = MAIN.new()
	s.external_drive = true
	s.level_id = "lab"
	s.setup_sim()
	s.save_enabled = false
	return s

func stance(k: int, lead: float, a0: float) -> void:
	var key := "%.4f/%.4f" % [lead, a0]
	if not stances.has(key):
		m.restore(pristine)
		m.teleport(Vector2(float(m.a_pos[k].x) - lead, -m.BODY_R))
		for t in 90:
			m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
		stances[key] = m.snapshot()
	m.restore(stances[key])

func touching(k: int) -> bool:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

func cue(k: int, policy: String) -> bool:
	return absf(float(m.a_theta[k])) >= 2.6 if policy == "wrap" else touching(k)

func aim(t: int, c: Dictionary, s: float) -> Array:
	var w := int(c["w"])
	if t < w:
		return [float(c["a0"]), 1.0]
	var te := float(t - w) / s
	if te < float(c["sd"]):
		return [float(c["a1"]), 1.0]
	if bool(c["pull"]) and te < float(c["sd"]) + 10.0:
		return [float(c["a0"]), 0.7]
	return [float(c["a1"]), 1.0]

func throw(k: int, c: Dictionary, policy: String, hn: RefCounted) -> Dictionary:
	var w := int(c["w"])
	var r := _pass(k, c, policy, hn, w, -1)
	# no second pass when the whip caught inside the windup (a stance too
	# close to the beam): there is no windup-end snapshot to rewind to
	if hn.jit != 0 and int(r["g0"]) >= 0 and not (r["snap_w"] as Dictionary).is_empty():
		m.restore(r["snap_w"])
		hn.restore_state(r["hn_w"])
		var r2 := _pass(k, c, policy, hn, w, maxi(w, int(r["g0"]) + hn.jit))
		r2["g0"] = r["g0"]
		r2.erase("snap_w")
		r2.erase("hn_w")
		return r2
	r.erase("snap_w")
	r.erase("hn_w")
	return r

func _pass(k: int, c: Dictionary, policy: String, hn: RefCounted, w: int,
		press: int) -> Dictionary:
	var grip := false
	var closes := 0
	var g0 := -1
	var caught := false
	var et := -1
	var out := {"snap_w": {}, "hn_w": {}}
	var t0 := 0
	if press >= 0:
		t0 = w
	for t in range(t0, w + 130):
		if t == w and press < 0:
			out["snap_w"] = m.snapshot()
			out["hn_w"] = hn.save_state()
		var av := aim(t, c, hn.speed)
		var tgt: Vector2 = m.body_pos + Vector2(cos(float(av[0])),
			sin(float(av[0]))) * m.REACH * float(av[1]) + hn.tick()
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var fire := false
		if press >= 0 and closes == 0:
			fire = t >= press
		else:
			fire = cue(k, policy)
		if not grip and fire and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
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
	out["caught"] = caught
	out["green"] = green
	out["et"] = et
	out["g0"] = g0
	out["hash"] = m.state_hash()
	return out

func one(k: int, c: Dictionary, policy: String, tier: String, tag: String,
		s: int) -> Dictionary:
	stance(k, float(c["lead"]), float(c["a0"]))
	var hn: RefCounted = HN.new(tier, tag, s)
	return throw(k, c, policy, hn)

func rung(k: int, c: Dictionary, policy: String, tier: String, tag: String,
		n: int) -> Dictionary:
	var det := one(k, c, policy, "null", tag, 0)
	var caught := 0
	var green := 0
	for s in n:
		var r := one(k, c, policy, tier, tag, s)
		if bool(r["caught"]):
			caught += 1
		if bool(r["green"]):
			green += 1
	return {"det_caught": bool(det["caught"]), "det_green": bool(det["green"]),
		"det_hash": int(det["hash"]), "n": n, "caught": caught, "green": green}

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var k := int(args[0])
	var policy := String(args[1])
	var w0 := {"lead": float(args[2]), "a0": float(args[3]), "a1": float(args[4]),
		"sd": int(args[5]), "pull": int(args[6]) == 1, "w": 120}
	var N := int(args[7])
	var tier := String(args[8])
	var outp := String(args[9])
	m = new_lab()
	pristine = m.snapshot()
	var name := String(m.a_name[k])
	print("")
	print("LADDER  station %d %s  cue %s  winner L%.2f a0 %.3f a1 %.3f sd %d %s  N %d  tier %s = %s"
		% [k, name, policy, float(w0["lead"]), float(w0["a0"]), float(w0["a1"]),
		int(w0["sd"]), "pull" if bool(w0["pull"]) else "nopull", N, tier,
		HN.new(tier, "x", 0).describe()])
	# the null at the winner: three noise-free throws, one hash
	var nh := {}
	for s in 3:
		nh[int(one(k, w0, policy, "null", "ladder-null", s)["hash"])] = true
	print("  NULL: 3 noise-free throws of the winner -> %d distinct hash(es)" % nh.size())
	var report := {"station": k, "name": name, "policy": policy, "winner": w0,
		"N": N, "tier": tier, "null_hashes": nh.size(), "a1": [], "lead": []}
	print("")
	print("  A1 LADDER (the aim): d rad   d mm of cursor   det   caught  green  P(green)")
	for d in D_A1:
		var c := w0.duplicate()
		c["a1"] = float(w0["a1"]) + float(d)
		var r := rung(k, c, policy, tier, "%s/a1/%.3f" % [name, float(d)], N)
		r["d"] = d
		report["a1"].append(r)
		print("    %+5.2f   %+6.0f   %-2s   %3d  %3d   %5.2f" % [float(d),
			float(d) * m.REACH * 1000.0,
			"G" if bool(r["det_green"]) else ("c" if bool(r["det_caught"]) else "."),
			int(r["caught"]), int(r["green"]), float(r["green"]) / N])
	print("")
	print("  LEAD LADDER (the stance): d m     det   caught  green  P(green)")
	for d in D_LEAD:
		var c := w0.duplicate()
		c["lead"] = float(w0["lead"]) + float(d)
		var r := rung(k, c, policy, tier, "%s/lead/%.3f" % [name, float(d)], N)
		r["d"] = d
		report["lead"].append(r)
		print("    %+5.2f   %-2s   %3d  %3d   %5.2f" % [float(d),
			"G" if bool(r["det_green"]) else ("c" if bool(r["det_caught"]) else "."),
			int(r["caught"]), int(r["green"]), float(r["green"]) / N])
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	m.free()
	quit(0)
