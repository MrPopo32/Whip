extends SceneTree
## THE CRAG'S GATES, modelled on tests/lab_gate.gd: the level exists without
## touching the traverse or the lab, its rock is wound the right way round,
## its arcs cannot hold, and every feature on it is REACHED - by a searched
## throw from a body that crawled to the spot - and the whole thing is walked.
##
##   godot --headless --path . -s res://tests/crag_gate.gd [-- quick]
##
##  C1 the shipped level is byte-identical: fingerprint, golden hash, no arcs,
##     no backdrop, the traverse's camera table
##  C2 all 6 tapes still name the shipped level; the crag names neither it
##     nor the lab
##  C3 the crag has its own save slot and refuses the traverse's save (and
##     the traverse refuses the crag's); it accepts its own
##  C4 every crag normal - ground and island - points into the air region
##     the loops enclose; the reversed winding scores 0
##  C5 arcs: the fillet is tangent and leaves the normals alone; a rope laid
##     over a filleted lip slides off; an arc never enters a_pos and a rope
##     wound round one is never caught
##  C6 every feature locks from a searched throw after a crawl-in
##     (minutes; skipped by -- quick)
##  C7 the crag is crawlable end to end with the hand open
##  C8 the rescue depth is finite behind every island face and INF behind
##     every face of the shipped level
##
## C2, C3, C4, C6, C7 and C8's island half are the generic level checks, taken
## from tests/level_lib.gd so that this gate, lab_gate and level_gate (any
## level, by name) measure with one piece of code. C1, C5's bench and C8's
## shipped half are the crag's own.
const MAIN := preload("res://main.gd")
const LIB := preload("res://tests/crag_lib.gd")
const LLIB := preload("res://tests/level_lib.gd")

const SHIPPED_FP := 8896234646103814336
const SHIPPED_HASH := 2762505307938286422
const TMP := "user://crag_gate_tmp.save"

var fail: Array[String] = []

func new_sim(lvl: String) -> Node2D:
	return LLIB.new_sim(lvl)

# --------------------------------------------------------------------- C1 ---
func c1() -> void:
	var d := new_sim("")
	if d.level_fingerprint() != SHIPPED_FP:
		fail.append("C1 shipped level_fingerprint %d != %d"
			% [d.level_fingerprint(), SHIPPED_FP])
	if d.t_a.size() != 11 or d.a_pos.size() != 11:
		fail.append("C1 shipped level has %d segments / %d anchors, want 11/11"
			% [d.t_a.size(), d.a_pos.size()])
	if d.t_arc_c.size() != 0:
		fail.append("C1 the shipped level grew %d arcs" % d.t_arc_c.size())
	if d.bd_poly.size() != 0:
		fail.append("C1 the shipped level grew a backdrop (%d polygons)" % d.bd_poly.size())
	if d.cam_vols != MAIN.CAM_VOLS:
		fail.append("C1 the shipped level's camera table moved")
	if d.save_path != "user://run.save":
		fail.append("C1 shipped save slot moved to %s" % d.save_path)
	d.free()
	var h: int = LLIB.golden_hash()
	if h != SHIPPED_HASH:
		fail.append("C1 golden hash %d != %d - the sim's BEHAVIOUR moved" % [h, SHIPPED_HASH])
	else:
		print("  C1 ok: shipped fp %d, golden hash %d, 0 arcs, 0 backdrop polygons, CAM_VOLS, slot user://run.save"
			% [SHIPPED_FP, h])

# --------------------------------------------------------------------- C2 ---
func c2() -> void:
	var c := new_sim("crag")
	var crag_fp: int = c.level_fingerprint()
	var na: int = c.a_pos.size()
	c.free()
	var l := new_sim("lab")
	var lab_fp: int = l.level_fingerprint()
	l.free()
	if crag_fp == SHIPPED_FP or crag_fp == lab_fp:
		fail.append("C2 the crag fingerprints the same as another level")
	elif LLIB.tapes_check(crag_fp, "the CRAG", "C2", fail):
		print("  C2 ok: 6 tapes, all still naming %d; the crag is %d (%d features)"
			% [SHIPPED_FP, crag_fp, na])

# --------------------------------------------------------------------- C3 ---
func c3() -> void:
	LLIB.slot_check("crag", "user://run_crag.save", "C3", fail, TMP)

# --------------------------------------------------------------------- C4 ---
# THE AIR REGION IS DERIVED FROM THE TERRAIN (level_lib.normals_check): the
# segments are chained back into loops through their shared vertices -
# through the fillet, where one has been cut, by intersecting the two lines -
# and the one open chain is the ground, closed far above the sky; every
# closed chain is an island. Air is inside the ground's polygon and outside
# every island's. A normal is right when a point 2 mm along it is in the air
# and 2 mm against it is not, and the checker has to score 0 on the reversed
# walk or it is not a checker (lab_gate L3's rule).
func c4() -> void:
	var m := new_sim("crag")
	LLIB.normals_check(m, "C4", fail)
	m.free()

# --------------------------------------------------------------------- C5 ---
func c5() -> void:
	# (a) the geometry, on a bench: a 90 degree lip and a 106.7 degree spike
	var m := new_sim("")
	m.t_a = PackedVector2Array(); m.t_b = PackedVector2Array()
	m.t_arc_c = PackedVector2Array(); m.t_arc_r = PackedFloat32Array()
	m.t_arc_ang = PackedVector2Array()
	var pts := [Vector2(-10, 0), Vector2(10, 0), Vector2(10, 3), Vector2(30, 3),
		Vector2(36, 0), Vector2(43, -5.196152), Vector2(50, 0)]
	for i in range(pts.size() - 1):
		if i == 3:
			continue                        # a gap: two separate chains
		m.t_a.append(pts[i]); m.t_b.append(pts[i + 1])
	var before: PackedVector2Array = m.t_a.duplicate()
	var n_anch: int = m.a_pos.size()
	var f1: bool = m._fillet(Vector2(10, 0), 0.4)
	var f2: bool = m._fillet(Vector2(10, 3), 0.4)          # concave: must refuse
	var f3: bool = m._fillet(Vector2(43, -5.196152), 0.5)
	m._finish_terrain()
	if not f1 or f2 or not f3:
		fail.append("C5 fillet accepted/refused wrongly: lip %s concave %s spike %s"
			% [str(f1), str(f2), str(f3)])
	if m.a_pos.size() != n_anch:
		fail.append("C5 filleting changed a_pos.size() %d -> %d" % [n_anch, m.a_pos.size()])
	if m.t_arc_c.size() != 2:
		fail.append("C5 expected 2 arcs, got %d" % m.t_arc_c.size())
	else:
		# tangency: the centre is exactly r from both adjacent lines, the
		# tangent points are the new endpoints, and the directions (so the
		# normals) are unchanged
		var worst := 0.0
		for pair: Array in [[0, 0, 1, 0.4], [1, 3, 4, 0.5]]:
			var j: int = pair[0]
			var si: int = pair[1]
			var sj: int = pair[2]
			var r: float = pair[3]
			var c: Vector2 = m.t_arc_c[j]
			for s: int in [si, sj]:
				var n: Vector2 = m.t_n[s]
				var dist: float = absf((c - m.t_a[s]).dot(n))
				worst = maxf(worst, absf(dist - r))
				var tp: Vector2 = c + n * r
				var endd: float = minf(tp.distance_to(m.t_a[s]), tp.distance_to(m.t_b[s]))
				worst = maxf(worst, endd)
				var d_old: Vector2 = (before[s] - (pts[s + 1] if s < 3 else pts[s + 2])).normalized()
				var d_new: Vector2 = (m.t_a[s] - m.t_b[s]).normalized()
				worst = maxf(worst, d_old.distance_to(d_new))
		# the 90 degree lip is shortened by exactly r
		worst = maxf(worst, absf(m.t_b[0].distance_to(Vector2(10, 0)) - 0.4))
		worst = maxf(worst, absf(m.t_a[1].distance_to(Vector2(10, 0)) - 0.4))
		if worst > 0.00001:
			fail.append("C5 fillet geometry off by %.2e" % worst)
	# (b) A ROPE OVER THE FILLETED LIP SLIDES OFF, hand open. The handle is
	# laid at the lip with the rest of the chain hanging down the face, the
	# body 0.6 m back (inside the arm's 1.15 m, so the tether cannot yank -
	# a first version laid the handle 4 m off and measured a 90 m/s yank),
	# and the cursor is parked ON the handle so the spring pulls nothing:
	# what moves the chain is its own weight. Smooth means no snag: the whole
	# chain ends past the lip with nothing engaged, nothing measured, and the
	# fastest particle in the chain never once reaching CRACK_SPEED.
	m.body_pos = Vector2(9.3, -0.28); m.body_prv = m.body_pos
	for i in m.NP:
		var s: float = m.cum_len[i]
		var q: Vector2 = Vector2(9.7 + s, -0.05) if s < 0.3 			else Vector2(10.05, -0.05 + (s - 0.3))
		m.pos[i] = q; m.prv[i] = q
	m.clear_anchors()
	var vmax := 0.0
	var eng_b := 0
	var th_b := 0.0
	for t in 300:
		m.step_tick(m.pos[0], false)
		for i in m.NP:
			vmax = maxf(vmax, (m.pos[i] - m.prv[i]).length() / m.SDT)
		for k in m.a_pos.size():
			if float(m.a_freelen[k]) >= 0.0:
				eng_b += 1
			th_b = maxf(th_b, absf(float(m.a_theta[k])))
	var on_lip := 0
	for i in m.NP:
		if m.pos[i].x < 9.55 or m.pos[i].y < 0.35:
			on_lip += 1
	var tip_y: float = m.pos[m.NP - 1].y
	if on_lip != 0 or vmax >= m.CRACK_SPEED or eng_b != 0 or th_b > 0.0:
		fail.append("C5 the rope did not slide off the filleted lip cleanly: %d particles not past it, tip peak %.1f m/s, %d engaged ticks, theta %.2f"
			% [on_lip, vmax, eng_b, th_b])
	# (c) an arc is not catchable: wind the chain 1.5 turns round a lip's
	# fillet with the body hanging under it, close the hand every tick that
	# GRIP_WINDOW allows, and require that nothing engages and no winding is
	# measured anywhere (level_lib.arc_bench, which level_gate A runs on
	# every level)
	var ab := LLIB.arc_bench()
	var eng: int = ab["eng"]
	var thmax: float = ab["thmax"]
	if eng != 0 or thmax > 0.0:
		fail.append("C5 a rope wound on an ARC engaged %d anchor-ticks / measured %.2f rad - an arc is in the catch machinery" % [eng, thmax])
	# (d) on the crag itself: arcs exist, and no anchor is one
	var c := new_sim("crag")
	var na: int = c.a_pos.size()
	var narc: int = c.t_arc_c.size()
	var overlap := 0
	for j in narc:
		for k in na:
			if c.t_arc_c[j].distance_to(c.a_pos[k]) < c.t_arc_r[j] + c.a_r[k]:
				overlap += 1
	if narc == 0:
		fail.append("C5 the crag has no arcs")
	if overlap != 0:
		fail.append("C5 %d arcs overlap an anchor" % overlap)
	if fail.is_empty():
		print("  C5 ok: fillet tangent to both lines (<1e-5), 90 deg lip shortened by r, concave refused, a_pos unchanged; a laid rope slid off (tip y %.2f, peak %.1f m/s); 1.5 turns on an arc engaged nothing (theta %.2f); crag has %d arcs, %d anchors, 0 overlapping"
			% [tip_y, vmax, thmax, narc, na])
	m.free(); c.free()

# --------------------------------------------------------------------- C6 ---
func c6() -> void:
	var m := new_sim("crag")
	var names := LIB.feat_names(m)
	m.free()
	LLIB.reach_check("crag", names, "C6", fail)

# --------------------------------------------------------------------- C7 ---
func c7() -> void:
	var m := new_sim("crag")
	LLIB.walk_check(m, "C7", fail)
	m.free()

# --------------------------------------------------------------------- C8 ---
func c8() -> void:
	var d := new_sim("")
	var inf_d := 0
	for s in d.t_a.size():
		if is_inf(d.t_deep[s]):
			inf_d += 1
	if inf_d != d.t_a.size():
		fail.append("C8 %d of %d shipped segments have a FINITE rescue depth - the rescue there is no longer unbounded" % [d.t_a.size() - inf_d, d.t_a.size()])
	else:
		print("  C8 ok: rescue depth INF behind all %d shipped segments" % inf_d)
	d.free()
	# every island segment: finite, and no more than half the island's extent
	var c := new_sim("crag")
	LLIB.rescue_check(c, "C8", fail)
	c.free()

func _initialize() -> void:
	var quick := OS.get_cmdline_user_args().has("quick")
	c1(); c2(); c3(); c4(); c5(); c8(); c7()
	if not quick:
		c6()
	if fail.is_empty():
		print("PASS  crag gates C1-C8%s" % (" (C6 skipped: quick)" if quick else ""))
		quit(0)
		return
	for f in fail:
		print("FAIL  %s" % f)
	quit(1)
