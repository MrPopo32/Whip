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
const MAIN := preload("res://main.gd")
const LIB := preload("res://tests/crag_lib.gd")

const SHIPPED_FP := 8896234646103814336
const SHIPPED_HASH := 2762505307938286422
const TMP := "user://crag_gate_tmp.save"

var fail: Array[String] = []

func new_sim(lvl: String) -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = lvl
	m.setup_sim()
	m.save_enabled = false
	return m

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
	var m := new_sim("")
	for t in 900:
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		var grip := false
		if t < 90:
			tgt = b + Vector2(0.5, -0.5)
		elif t < 280:
			var ph := float(t - 90) * 0.11
			tgt = b + Vector2(cos(ph), sin(ph)) * 1.1
		elif t < 340:
			tgt = b + Vector2(-1.05, -0.35)
		elif t < 352:
			tgt = b + Vector2(1.05, -0.45)
		elif t < 600:
			tgt = b + Vector2(0.8, -0.8); grip = t > 420
		else:
			var p2 := float(t) * 0.05
			tgt = b + Vector2(cos(p2), -0.6); grip = true
		m.step_tick(tgt, grip)
	var h: int = m.state_hash()
	if h != SHIPPED_HASH:
		fail.append("C1 golden hash %d != %d - the sim's BEHAVIOUR moved" % [h, SHIPPED_HASH])
	else:
		print("  C1 ok: shipped fp %d, golden hash %d, 0 arcs, 0 backdrop polygons, CAM_VOLS, slot user://run.save"
			% [SHIPPED_FP, h])
	m.free()

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
	var dir := DirAccess.open("res://tapes")
	if dir == null:
		fail.append("C2 no tapes/ directory")
		return
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".tape"):
			continue
		var t := MAIN.tape_load("res://tapes/" + f)
		if not bool(t.get("ok", false)):
			fail.append("C2 %s unreadable: %s" % [f, str(t.get("err", ""))])
			continue
		n += 1
		if int(t["lvl"]) != SHIPPED_FP:
			fail.append("C2 %s names level %d, not the shipped %d"
				% [f, int(t["lvl"]), SHIPPED_FP])
		if int(t["lvl"]) == crag_fp:
			fail.append("C2 %s would replay into the CRAG" % f)
	if n != 6:
		fail.append("C2 found %d tapes, expected 6" % n)
	elif fail.is_empty():
		print("  C2 ok: 6 tapes, all still naming %d; the crag is %d (%d features)"
			% [SHIPPED_FP, crag_fp, na])

# --------------------------------------------------------------------- C3 ---
func c3() -> void:
	var d := new_sim("")
	var c := new_sim("crag")
	if c.save_path != "user://run_crag.save":
		fail.append("C3 the crag writes %s" % c.save_path)
	if d.save_path == c.save_path:
		fail.append("C3 both levels write %s" % d.save_path)
	d.body_pos = Vector2(3.0, -1.0)
	if not d.save_to(TMP):
		fail.append("C3 could not write the temp save")
	var r_wrong: int = c.load_from(TMP)
	c.save_to(TMP)
	var d2 := new_sim("")
	var r_wrong2: int = d2.load_from(TMP)
	var c2 := new_sim("crag")
	var r_right: int = c2.load_from(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + ".tmp"))
	if r_wrong != -1:
		fail.append("C3 a crag session ACCEPTED a traverse save (load_from -> %d)" % r_wrong)
	if r_wrong2 != -1:
		fail.append("C3 a traverse session ACCEPTED a crag save (load_from -> %d)" % r_wrong2)
	if r_right != 1:
		fail.append("C3 a crag save was refused by its OWN level (load_from -> %d)" % r_right)
	if fail.is_empty():
		print("  C3 ok: slots user://run.save / user://run_crag.save; cross-load -1 both ways, own-load 1")
	d.free(); d2.free(); c.free(); c2.free()

# --------------------------------------------------------------------- C4 ---
# THE AIR REGION IS DERIVED FROM THE TERRAIN. The segments are chained back
# into loops through their shared vertices - through the fillet, where one
# has been cut, by intersecting the two lines - and the one open chain is
# the ground, closed far above the sky; every closed chain is an island.
# Air is inside the ground's polygon and outside every island's. A normal
# is right when a point 2 mm along it is in the air and 2 mm against it is
# not, and the checker has to score 0 on the reversed walk or it is not a
# checker (lab_gate L3's rule).
func chain_loops(ta: PackedVector2Array, tb: PackedVector2Array) -> Array:
	var out: Array = []
	var cur := PackedVector2Array()
	var n := ta.size()
	var start := 0
	for s in n:
		var A := ta[s]
		var B := tb[s]
		if cur.is_empty():
			cur.append(A)
			start = s
		cur.append(B)
		var joined := false
		if s + 1 < n:
			joined = _join(cur, A, B, ta[s + 1], tb[s + 1], false)
		if not joined:
			var closed := _join(cur, A, B, ta[start], tb[start], true)
			out.append({"pts": cur, "closed": closed})
			cur = PackedVector2Array()
	return out

func _join(cur: PackedVector2Array, A: Vector2, B: Vector2, A2: Vector2,
		B2: Vector2, closing: bool) -> bool:
	if B.distance_to(A2) < 0.000001:
		return true
	var d1 := (B - A).normalized()
	var d2 := (B2 - A2).normalized()
	var den := d1.cross(d2)
	if absf(den) < 0.000000001:
		return false
	var t := (A2 - A).cross(d2) / den
	var v := A + d1 * t
	if v.distance_to(B) < 1.0 and v.distance_to(A2) < 1.0:
		cur[cur.size() - 1] = v
		if closing:
			cur[0] = v
		return true
	return false

var air_outer := PackedVector2Array()
var air_islands: Array = []

func in_air(q: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(q, air_outer):
		return false
	for isl: PackedVector2Array in air_islands:
		if Geometry2D.is_point_in_polygon(q, isl):
			return false
	return true

func normals_score(ta: PackedVector2Array, tb: PackedVector2Array) -> int:
	var ok := 0
	for i in ta.size():
		var n := Vector2((tb[i] - ta[i]).y, -(tb[i] - ta[i]).x).normalized()
		var mid := (ta[i] + tb[i]) * 0.5
		if in_air(mid + n * 0.002) and not in_air(mid - n * 0.002):
			ok += 1
	return ok

func c4() -> void:
	var m := new_sim("crag")
	var loops := chain_loops(m.t_a, m.t_b)
	air_islands = []
	var opens := 0
	for l: Dictionary in loops:
		if bool(l["closed"]):
			air_islands.append(l["pts"])
		else:
			opens += 1
			air_outer = (l["pts"] as PackedVector2Array).duplicate()
			air_outer.append(Vector2(air_outer[air_outer.size() - 1].x, -1000.0))
			air_outer.append(Vector2(air_outer[0].x, -1000.0))
	if opens != 1:
		fail.append("C4 expected one open ground chain, found %d" % opens)
		m.free()
		return
	var good := normals_score(m.t_a, m.t_b)
	var ra := PackedVector2Array()
	var rb := PackedVector2Array()
	for i in range(m.t_a.size() - 1, -1, -1):
		ra.append(m.t_b[i])
		rb.append(m.t_a[i])
	var bad := normals_score(ra, rb)
	if good != m.t_a.size():
		fail.append("C4 %d of %d crag normals point into the air" % [good, m.t_a.size()])
	elif bad != 0:
		fail.append("C4 the normal checker scores %d on a REVERSED winding - it cannot fail, so it cannot pass" % bad)
	else:
		print("  C4 ok: 1 ground chain + %d islands enclose the air; %d/%d normals into it; reversed winding scores 0/%d"
			% [air_islands.size(), good, m.t_a.size(), m.t_a.size()])
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
	# (c) an arc is not catchable: wind the chain 1.5 turns round the lip's
	# fillet with the body hanging under it, close the hand every tick that
	# GRIP_WINDOW allows, and require that nothing engages and no winding is
	# measured anywhere
	var c0: Vector2 = m.t_arc_c[0]
	var rr: float = m.t_arc_r[0] + 0.04
	for i in m.NP:
		var s: float = m.cum_len[i]
		var q: Vector2
		if s < 1.5:
			q = c0 + Vector2(0.0, 1.5 - s + rr)
		elif s < 1.5 + 1.5 * TAU * rr:
			var a: float = PI * 0.5 + (s - 1.5) / rr
			q = c0 + Vector2(cos(a), sin(a)) * rr
		else:
			q = c0 + Vector2(0.4, s - 1.5 - 1.5 * TAU * rr)
		m.pos[i] = q; m.prv[i] = q
	m.body_pos = c0 + Vector2(0.0, 2.2); m.body_prv = m.body_pos
	m.clear_anchors()
	var eng := 0
	var thmax := 0.0
	for t in 120:
		m.step_tick(m.body_pos, (t / 10) % 2 == 0)
		for k in m.a_pos.size():
			if float(m.a_freelen[k]) >= 0.0:
				eng += 1
			thmax = maxf(thmax, absf(float(m.a_theta[k])))
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
	var nfeat: int = m.a_pos.size()
	m.free()
	var locked := 0
	print("  C6 every feature, crawled to and thrown at (first lock of the 108-stroke grid):")
	for k in nfeat:
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = LIB.search(k, "wrap")
		if not r.has("m"):
			r = LIB.search(k, "touch")
		if not r.has("m"):
			r = LIB.search(k, "wrap", false, true)
		if not r.has("m"):
			r = LIB.search(k, "touch", false, true)
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		if r.has("m"):
			var mm: Node2D = r["m"]
			locked += 1
			print("     k%-2d %-14s LOCK  stroke %3d of the grid  tether %.2f m  catch at tick %3d, feet %s  crawl %.1f s  (%.0f s)"
				% [k, names[k], int(r["att"]), float(r["tether"]), int(r["et"]),
				"on the floor" if bool(r["egnd"]) else "off it",
				int(r["crawl_t"]) / 60.0, dt])
			print("          %s" % String(r["how"]))
			mm.free()
		else:
			fail.append("C6 k%d %s: no lock in %d strokes (caught %d) %s"
				% [k, names[k], int(r["att"]), int(r["caught"]), str(r.get("err", ""))])
			print("     k%-2d %-14s NO LOCK in %d strokes, caught %d  (%.0f s) %s"
				% [k, names[k], int(r["att"]), int(r["caught"]), dt, str(r.get("err", ""))])
	if locked == nfeat:
		print("  C6 ok: %d of %d features locked from a crawled-to standing spot" % [locked, nfeat])

# --------------------------------------------------------------------- C7 ---
func c7() -> void:
	var m := new_sim("crag")
	var x0: float = m.body_pos.x
	var t := 0
	var last := -1e9
	var stalls := 0
	while t < 60 * 400 and not m.finished:
		m.step_tick(LIB.gait_cursor(m, t, 1.0), false)
		t += 1
		if t % 600 == 0:
			if m.body_pos.x - last < 0.3:
				stalls += 1
				if stalls >= 3:
					break
			else:
				stalls = 0
			last = m.body_pos.x
	if not m.finished:
		fail.append("C7 the crag is not walkable: %.1f s of gait moved the body from %.2f to (%.2f, %.2f), goal at %.1f"
			% [t / 60.0, x0, m.body_pos.x, m.body_pos.y, m.goal_x])
	elif m.falls != 0:
		fail.append("C7 the walk tripped the out-of-world net %d times" % m.falls)
	else:
		print("  C7 ok: hand open, the gait walks spawn (%.1f) to the flag (%.1f, y %.1f) in %.1f s, 0 out-of-world"
			% [x0, m.body_pos.x, m.body_pos.y, t / 60.0])
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
	d.free()
	var c := new_sim("crag")
	var loops := chain_loops(c.t_a, c.t_b)
	var fin := 0
	var tot := 0
	var worst := 0.0
	# every island segment: finite, and no more than half the island's extent
	var s0 := 0
	for l: Dictionary in loops:
		var pts: PackedVector2Array = l["pts"]
		var nseg: int = pts.size() - 1
		if bool(l["closed"]):
			var lo := Vector2(1e9, 1e9)
			var hi := Vector2(-1e9, -1e9)
			for q in pts:
				lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
				hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
			var half := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
			for s in range(s0, s0 + nseg):
				tot += 1
				if not is_inf(c.t_deep[s]):
					fin += 1
					worst = maxf(worst, c.t_deep[s] - half)
		s0 += nseg
	if fin != tot or worst > 0.000001:
		fail.append("C8 %d of %d island segments finite, worst overreach %.3f m" % [fin, tot, worst])
	else:
		print("  C8 ok: rescue depth INF behind all %d shipped segments; finite (<= half the island) behind all %d island segments" % [inf_d, tot])
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
