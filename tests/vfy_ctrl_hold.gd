extends SceneTree
## VERIFIER COPY of skill_cell.gd with the hold extended: green read at 55 (the original), 90 and 180 ticks of holding.
## ONE CELL OF THE SKILL INSTRUMENT, ON ITS OWN, FOR CROSS-CHECKS.
##
## The same stroke at the same tier, under a NAMED noise tag, N samples: so two
## noise realisations of one intention can be laid side by side, and one
## realisation can be re-run on an intention nudged by microns. Written when
## tests/skill_ladder.gd's winner rung (20/20 at the trackpad tier) disagreed
## with tests/skill_probe.gd's identical cell (20/30): the two differ only in
## the seed tag and in a0/a1 passed as 6-figure decimals instead of PI*1.1 and
## -PI*0.42 (about 2 microns of cursor). Throw machinery is skill_probe's,
## line for line; the sim has no RNG, the probe's noise is seeded per (tag,
## sample). "exact" as a0/a1 uses the PI multiples from lab_throw's grid.
##
##   godot --headless --path . -s res://tests/skill_cell.gd -- <station> <wrap|touch> <lead> <a0|exact> <a1|exact> <sd> <pull> <N> <tier> <tag>
const MAIN := preload("res://main.gd")
const HN := preload("res://tests/hand_noise.gd")

var m: Node2D
var stances := {}
var pristine := {}                    # the sim as new_lab() made it: every
                                      # stance is built from THIS, so a stance
                                      # is lab_throw's stand_at and not "wherever
                                      # the previous throw left the rope". Found
                                      # the hard way: BEAM sd 9 at the trackpad
                                      # tier read 20/30 from a stance built after
                                      # 18 throws and 19/20 from a pristine one.

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
	var peak := -1.0
	var tip := Vector2.ZERO
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
		if t >= w and m.tip_speed > peak:
			peak = m.tip_speed
			tip = m.pos[m.NP - 1]      # the tip where it was at peak speed:
			                           # the positive control's landing point
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	var green := false
	var g90 := false
	var g180 := false
	if caught:
		for t in 180:
			m.step_tick(m.body_pos, true)
			if t == 54:
				green = bool(m._holds(k))
			if t == 89:
				g90 = bool(m._holds(k))
			if float(m.a_freelen[k]) < 0.0:
				break
		g180 = bool(m._holds(k)) and float(m.a_freelen[k]) >= 0.0
	out["g90"] = g90
	out["g180"] = g180
	out["caught"] = caught
	out["green"] = green
	out["et"] = et
	out["g0"] = g0
	out["tip"] = tip
	out["hash"] = m.state_hash()
	return out

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var k := int(args[0])
	var policy := String(args[1])
	var a0 := PI * 1.10 if String(args[3]) == "exact" else float(args[3])
	var a1 := -PI * 0.42 if String(args[4]) == "exact" else float(args[4])
	var c := {"lead": float(args[2]), "a0": a0, "a1": a1, "sd": int(args[5]),
		"pull": int(args[6]) == 1, "w": 120}
	var N := int(args[7])
	var tier := String(args[8])
	var tag := String(args[9])
	# optional: <warm> throws of the same cell under tag "warm" FIRST, in the
	# same process, so a state that survives restore() would show up as a
	# different count from the cold run
	var warm := int(args[10]) if args.size() > 10 else 0
	m = new_lab()
	pristine = m.snapshot()
	# THE NULL: three noise-free throws of this stroke from the pristine stance
	# must give one hash, and that throw's verdict is the 'det' the noisy
	# samples are read against
	var nh := {}
	var det := {}
	for s in 3:
		stance(k, float(c["lead"]), float(c["a0"]))
		det = throw(k, c, policy, HN.new("null", tag, s))
		nh[int(det["hash"])] = true
	print("NULL 3 noise-free throws -> %d distinct hash(es); noise-free verdict %s"
		% [nh.size(), "GREEN" if bool(det["green"]) else ("caught" if bool(det["caught"]) else "miss")])
	if warm > 0:
		var wg := 0
		var wl := ""
		for s in warm:
			stance(k, float(c["lead"]), float(c["a0"]))
			var hw: RefCounted = HN.new(tier, "warm", s)
			var rw := throw(k, c, policy, hw)
			if bool(rw["green"]):
				wg += 1
			wl += "G" if bool(rw["green"]) else ("c" if bool(rw["caught"]) else ".")
		print("WARM %d throws tag warm: green %d  %s" % [warm, wg, wl])
	var caught := 0
	var green := 0
	var g90n := 0
	var g180n := 0
	var line := ""
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var syy := 0.0
	var sd_ref := 0.0
	var hashes := {}
	var ets: Array = []
	for s in N:
		stance(k, float(c["lead"]), float(c["a0"]))
		var hn: RefCounted = HN.new(tier, tag, s)
		var r := throw(k, c, policy, hn)
		if bool(r["caught"]):
			caught += 1
			ets.append(int(r["et"]))
		if bool(r["green"]):
			green += 1
		if bool(r["g90"]):
			g90n += 1
		if bool(r["g180"]):
			g180n += 1
		line += "G" if bool(r["green"]) else ("c" if bool(r["caught"]) else ".")
		var tp: Vector2 = r["tip"]
		sx += tp.x
		sy += tp.y
		sxx += tp.x * tp.x
		syy += tp.y * tp.y
		sd_ref += tp.distance_to(det["tip"])
		hashes[int(r["hash"])] = true
	var vx := maxf(0.0, sxx / N - (sx / N) * (sx / N))
	var vy := maxf(0.0, syy / N - (sy / N) * (sy / N))
	var et_mu := 0.0
	for e in ets:
		et_mu += float(e)
	et_mu /= maxi(1, ets.size())
	var et_ss := 0.0
	for e in ets:
		et_ss += (float(e) - et_mu) * (float(e) - et_mu)
	print("HOLD-LENGTH: green@55 %d  green@90 %d  green@180 %d  of N %d" % [green, g90n, g180n, N])
	print("CELL k%d %s L%.2f a0 %.9f a1 %.9f sd %d %s  tier %s  tag %s  N %d: caught %d green %d P %.2f  tip rms %.3f m  tip |d| %.3f m  catch-tick sd %.1f  hashes %d  %s"
		% [k, policy, float(c["lead"]), a0, a1, int(c["sd"]),
		"pull" if bool(c["pull"]) else "nopull", tier, tag, N, caught, green,
		float(green) / N, sqrt(vx + vy), sd_ref / N,
		sqrt(et_ss / maxi(1, ets.size() - 1)), hashes.size(), line])
	m.free()
	quit(0)
