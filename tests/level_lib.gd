extends RefCounted
## THE LEVEL KIT: the checks a level has to pass whoever built it, written
## once and called by tests/level_gate.gd (any level, by name),
## tests/lab_gate.gd and tests/crag_gate.gd (the two hardcoded levels, which
## keep their own numbered lines and their own level-specific gates on top),
## and tests/level_export.gd / level_fidelity.gd (which need the loop walker).
## Every checker here prints one "<tag> ok: ..." line with the numbers it
## measured, or appends a "<tag> ..." failure, so a wrapper only decides the
## tag and the order.
const MAIN := preload("res://main.gd")
const CRAG := preload("res://tests/crag_lib.gd")

const SHIPPED_FP := 8896234646103814336
const SHIPPED_HASH := 2762505307938286422

static func new_sim(lvl: String) -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = lvl
	m.setup_sim()             # FIRST: it re-derives save_path from the level
	m.save_enabled = false    # and no gate writes any slot
	return m

# ------------------------------------------------------------ the golden --
# hashrun.gd's own scripted session, inline, so a gate stands alone.
static func golden_hash() -> int:
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
	m.free()
	return h

# -------------------------------------------------------------- names --
# What to call each anchor in a report: the crag's vocabulary table, a scene's
# node names, else the caption, else k<i>.
static func anchor_names(lvl: String, m: Node2D) -> Array[String]:
	var out: Array[String] = []
	if lvl == "crag":
		return CRAG.feat_names(m)
	if not MAIN.level_is_builtin(lvl):
		var ps: PackedScene = load(MAIN.level_scene_path(lvl))
		if ps != null:
			var root: Node = ps.instantiate()
			var an := root.get_node_or_null("Anchors")
			if an != null:
				for c in an.get_children():
					if c is Node2D:
						out.append(String(c.name))
			root.free()
	for k in m.a_pos.size():
		if k >= out.size():
			out.append(String(m.a_name[k]) if String(m.a_name[k]) != "" else "k%d" % k)
	return out

# ---------------------------------------------- loops and the air region --
# THE AIR REGION IS DERIVED FROM THE TERRAIN (crag_gate C4's method). The
# segments are chained back into loops through their shared vertices -
# through a fillet, where one has been cut, by intersecting the two lines -
# and the one open chain is the ground, closed far above the sky; every
# closed chain is an island. Air is inside the ground's polygon and outside
# every island's. A normal is right when a point 2 mm along it is in the air
# and 2 mm against it is not, and the checker has to score 0 on the reversed
# walk or it is not a checker (lab_gate L3's rule).
static func chain_loops(ta: PackedVector2Array, tb: PackedVector2Array) -> Array:
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
			out.append({"pts": cur, "closed": closed, "s0": start, "s1": s})
			cur = PackedVector2Array()
	return out

static func _join(cur: PackedVector2Array, A: Vector2, B: Vector2, A2: Vector2,
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

static func air_of(loops: Array) -> Dictionary:
	var outer := PackedVector2Array()
	var islands: Array = []
	var opens := 0
	for l: Dictionary in loops:
		if bool(l["closed"]):
			islands.append(l["pts"])
		else:
			opens += 1
			outer = (l["pts"] as PackedVector2Array).duplicate()
			outer.append(Vector2(outer[outer.size() - 1].x, -1000.0))
			outer.append(Vector2(outer[0].x, -1000.0))
	return {"outer": outer, "islands": islands, "opens": opens}

static func in_air(air: Dictionary, q: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(q, air["outer"]):
		return false
	for isl: PackedVector2Array in air["islands"]:
		if Geometry2D.is_point_in_polygon(q, isl):
			return false
	return true

static func normals_score(air: Dictionary, ta: PackedVector2Array,
		tb: PackedVector2Array) -> int:
	var ok := 0
	for i in ta.size():
		var n := Vector2((tb[i] - ta[i]).y, -(tb[i] - ta[i]).x).normalized()
		var mid := (ta[i] + tb[i]) * 0.5
		if in_air(air, mid + n * 0.002) and not in_air(air, mid - n * 0.002):
			ok += 1
	return ok

static func normals_check(m: Node2D, tag: String, fail: Array) -> void:
	var loops := chain_loops(m.t_a, m.t_b)
	var air := air_of(loops)
	if int(air["opens"]) != 1:
		fail.append("%s expected one open ground chain, found %d" % [tag, int(air["opens"])])
		return
	var good := normals_score(air, m.t_a, m.t_b)
	var ra := PackedVector2Array()
	var rb := PackedVector2Array()
	for i in range(m.t_a.size() - 1, -1, -1):
		ra.append(m.t_b[i])
		rb.append(m.t_a[i])
	var bad := normals_score(air, ra, rb)
	var ni: int = (air["islands"] as Array).size()
	if good != m.t_a.size():
		# name the first wrong one: that is what a developer needs
		var first := -1
		for i in m.t_a.size():
			var n: Vector2 = m.t_n[i]
			var mid: Vector2 = (m.t_a[i] + m.t_b[i]) * 0.5
			if not (in_air(air, mid + n * 0.002) and not in_air(air, mid - n * 0.002)):
				first = i
				break
		fail.append("%s %d of %d normals point into the air; first wrong is segment %d (%.2f,%.2f)-(%.2f,%.2f)"
			% [tag, good, m.t_a.size(), first, m.t_a[first].x, m.t_a[first].y,
			m.t_b[first].x, m.t_b[first].y])
	elif bad != 0:
		fail.append("%s the normal checker scores %d on a REVERSED winding - it cannot fail, so it cannot pass" % [tag, bad])
	else:
		print("  %s ok: 1 ground chain + %d islands enclose the air; %d/%d normals into it; reversed winding scores 0/%d"
			% [tag, ni, good, m.t_a.size(), m.t_a.size()])

# --------------------------------------------------------------- tapes --
# Every committed tape names the shipped traverse and none names THIS level.
static func tapes_check(fp: int, what: String, tag: String, fail: Array) -> bool:
	var dir := DirAccess.open("res://tapes")
	if dir == null:
		fail.append("%s no tapes/ directory" % tag)
		return false
	var n := 0
	var bad := 0
	for f in dir.get_files():
		if not f.ends_with(".tape"):
			continue
		var t := MAIN.tape_load("res://tapes/" + f)
		if not bool(t.get("ok", false)):
			fail.append("%s %s unreadable: %s" % [tag, f, str(t.get("err", ""))])
			bad += 1
			continue
		n += 1
		if int(t["lvl"]) != SHIPPED_FP:
			fail.append("%s %s names level %d, not the shipped %d" % [tag, f, int(t["lvl"]), SHIPPED_FP])
			bad += 1
		if int(t["lvl"]) == fp:
			fail.append("%s %s would replay into %s" % [tag, f, what])
			bad += 1
	if n != 6:
		fail.append("%s found %d tapes, expected 6" % [tag, n])
		return false
	return bad == 0

# ---------------------------------------------------------------- slot --
# The level's own slot, the traverse's save refused by it, its save refused
# by the traverse, its own save accepted - the refusal proves nothing if
# nothing is ever accepted.
static func slot_check(lvl: String, want: String, tag: String, fail: Array,
		tmp: String) -> void:
	var d := new_sim("")
	var l := new_sim(lvl)
	var slot: String = l.save_path
	if want != "" and slot != want:
		fail.append("%s the level writes %s, want %s" % [tag, slot, want])
	if d.save_path == slot:
		fail.append("%s both levels write %s" % [tag, slot])
	d.body_pos = Vector2(3.0, -1.0)
	if not d.save_to(tmp):
		fail.append("%s could not write the temp save" % tag)
	var r_wrong: int = l.load_from(tmp)
	l.save_to(tmp)
	var d2 := new_sim("")
	var r_wrong2: int = d2.load_from(tmp)
	var l2 := new_sim(lvl)
	var r_right: int = l2.load_from(tmp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp + ".tmp"))
	if r_wrong != -1:
		fail.append("%s the level ACCEPTED a traverse save (load_from -> %d)" % [tag, r_wrong])
	if r_wrong2 != -1:
		fail.append("%s a traverse session ACCEPTED the level's save (load_from -> %d)" % [tag, r_wrong2])
	if r_right != 1:
		fail.append("%s the level's save was refused by its OWN level (load_from -> %d)" % [tag, r_right])
	if r_wrong == -1 and r_wrong2 == -1 and r_right == 1 and d.save_path != slot \
			and (want == "" or slot == want):
		print("  %s ok: slots user://run.save / %s; cross-load -1 both ways, own-load 1" % [tag, slot])
	d.free(); d2.free(); l.free(); l2.free()

# ---------------------------------------------------------------- walk --
# Crawlable end to end with the hand open: to the flag, or, on a bench with
# no flag, to within a metre of the far wall. The gait is
# tests/ground_probe.gd's winner, taken from crag_lib rather than restated.
static func walk_check(m: Node2D, tag: String, fail: Array) -> void:
	var x0: float = m.body_pos.x
	var right := -1e9
	for i in m.t_a.size():
		right = maxf(right, maxf(m.t_a[i].x, m.t_b[i].x))
	var bench: bool = m.goal_x >= 900.0
	var t := 0
	var last := -1e9
	var stalls := 0
	while t < 60 * 400:
		if bench and m.body_pos.x >= right - 1.0:
			break
		if not bench and m.finished:
			break
		m.step_tick(CRAG.gait_cursor(m, t, 1.0), false)
		t += 1
		if t % 600 == 0:
			if m.body_pos.x - last < 0.3:
				stalls += 1
				if stalls >= 3:
					break
			else:
				stalls = 0
			last = m.body_pos.x
	var got: bool = (m.body_pos.x >= right - 1.0) if bench else m.finished
	if not got:
		fail.append("%s not walkable: %.1f s of gait moved the body from %.2f to (%.2f, %.2f), %s"
			% [tag, t / 60.0, x0, m.body_pos.x, m.body_pos.y,
			("wall at %.1f" % right) if bench else ("goal at %.1f" % m.goal_x)])
	elif m.falls != 0:
		fail.append("%s the walk tripped the out-of-world net %d times" % [tag, m.falls])
	elif bench:
		print("  %s ok: hand open, the gait walks spawn (%.1f) to x %.2f (wall at %.1f) in %.1f s, 0 out-of-world"
			% [tag, x0, m.body_pos.x, right, t / 60.0])
	else:
		print("  %s ok: hand open, the gait walks spawn (%.1f) to the flag (%.1f, y %.1f) in %.1f s, 0 out-of-world"
			% [tag, x0, m.body_pos.x, m.body_pos.y, t / 60.0])

# --------------------------------------------------------------- reach --
# Every anchor LOCKS from a searched throw after a crawl-in (crag_gate C6).
# Minutes per level; the wrappers skip it under -- quick.
static func reach_check(lvl: String, names: Array[String], tag: String,
		fail: Array) -> int:
	var m := new_sim(lvl)
	var na: int = m.a_pos.size()
	m.free()
	var locked := 0
	print("  %s every anchor, crawled to and thrown at (first lock of the 108-stroke grid):" % tag)
	for k in na:
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = CRAG.search(k, "wrap", false, false, lvl)
		if not r.has("m"):
			r = CRAG.search(k, "touch", false, false, lvl)
		if not r.has("m"):
			r = CRAG.search(k, "wrap", false, true, lvl)
		if not r.has("m"):
			r = CRAG.search(k, "touch", false, true, lvl)
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		if r.has("m"):
			var mm: Node2D = r["m"]
			locked += 1
			print("     k%-2d %-16s LOCK  stroke %3d of the grid  tether %.2f m  catch at tick %3d, feet %s  crawl %.1f s  (%.0f s)"
				% [k, names[k], int(r["att"]), float(r["tether"]), int(r["et"]),
				"on the floor" if bool(r["egnd"]) else "off it",
				int(r["crawl_t"]) / 60.0, dt])
			print("          %s" % String(r["how"]))
			mm.free()
		else:
			fail.append("%s k%d %s: no lock in %d strokes (caught %d) %s"
				% [tag, k, names[k], int(r["att"]), int(r["caught"]), str(r.get("err", ""))])
			print("     k%-2d %-16s NO LOCK in %d strokes, caught %d  (%.0f s) %s"
				% [k, names[k], int(r["att"]), int(r["caught"]), dt, str(r.get("err", ""))])
	if locked == na:
		print("  %s ok: %d of %d anchors locked from a crawled-to standing spot" % [tag, locked, na])
	return locked

# --------------------------------------------------------- rescue depth --
# Finite, and no more than half the island's extent, behind every island
# segment (crag_gate C8's island half; the shipped-INF half is the crag
# gate's own, because it is about the traverse).
static func rescue_check(m: Node2D, tag: String, fail: Array) -> void:
	var loops := chain_loops(m.t_a, m.t_b)
	var fin := 0
	var tot := 0
	var worst := 0.0
	for l: Dictionary in loops:
		if not bool(l["closed"]):
			continue
		var pts: PackedVector2Array = l["pts"]
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for q in pts:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var half := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
		for s in range(int(l["s0"]), int(l["s1"]) + 1):
			tot += 1
			if not is_inf(m.t_deep[s]):
				fin += 1
				worst = maxf(worst, m.t_deep[s] - half)
	if fin != tot or worst > 0.000001:
		fail.append("%s %d of %d island segments have a finite rescue depth, worst overreach %.3f m" % [tag, fin, tot, worst])
	else:
		print("  %s ok: rescue depth finite (<= half the island) behind all %d island segments" % [tag, tot])

# ---------------------------------------------------------------- arcs --
# An arc is never an anchor. On a bench: wind the chain 1.5 turns round a
# filleted lip with the body hanging under it, close the hand every tick
# GRIP_WINDOW allows, and require that nothing engages and no winding is
# measured (crag_gate C5 c). On the level: no arc overlaps an anchor, and
# the anchor count is the scene's.
static func arc_bench() -> Dictionary:
	var m := new_sim("")
	m.t_a = PackedVector2Array(); m.t_b = PackedVector2Array()
	m.t_arc_c = PackedVector2Array(); m.t_arc_r = PackedFloat32Array()
	m.t_arc_ang = PackedVector2Array()
	var pts := [Vector2(-10, 0), Vector2(10, 0), Vector2(10, 3), Vector2(30, 3)]
	for i in range(pts.size() - 1):
		m.t_a.append(pts[i]); m.t_b.append(pts[i + 1])
	m._fillet(Vector2(10, 0), 0.4)
	m._finish_terrain()
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
	m.free()
	return {"eng": eng, "thmax": thmax}

static func arcs_check(m: Node2D, tag: String, fail: Array) -> void:
	var n0 := fail.size()
	var b := arc_bench()
	if int(b["eng"]) != 0 or float(b["thmax"]) > 0.0:
		fail.append("%s a rope wound on an ARC engaged %d anchor-ticks / measured %.2f rad - an arc is in the catch machinery"
			% [tag, int(b["eng"]), float(b["thmax"])])
	var overlap := 0
	for j in m.t_arc_c.size():
		for k in m.a_pos.size():
			if m.t_arc_c[j].distance_to(m.a_pos[k]) < m.t_arc_r[j] + m.a_r[k]:
				overlap += 1
	if overlap != 0:
		fail.append("%s %d arcs overlap an anchor" % [tag, overlap])
	if fail.size() == n0:
		print("  %s ok: 1.5 turns on an arc engaged nothing (theta %.2f); the level has %d arcs, %d anchors, 0 overlapping"
			% [tag, float(b["thmax"]), m.t_arc_c.size(), m.a_pos.size()])

# ---------------------------------------------------- the contract table --
# Not a gate: the numbers the README's level contract is written in, read
# off this level so the developer can see where he stands against them.
static func contract_report(m: Node2D, names: Array[String]) -> void:
	print("  the contract, per anchor (throw from 2.0 m of lead; ceilings: cold catch <= ~2.4 m up, launch needs > ~3.2 m of air under, 6.5 m keeps anchors out of each other's reach):")
	for k in m.a_pos.size():
		var ax: float = m.a_pos[k].x
		var ay: float = m.a_pos[k].y
		var dir := -1.0 if ax < m.spawn.x else 1.0
		var stand := ax - dir * 2.0
		var fy := CRAG.floor_y(m, stand)
		var far := CRAG.floor_y(m, ax + dir * 1.0)
		var near := 1e9
		var nk := -1
		for j in m.a_pos.size():
			if j != k and m.a_pos[k].distance_to(m.a_pos[j]) < near:
				near = m.a_pos[k].distance_to(m.a_pos[j])
				nk = j
		var notes := PackedStringArray()
		if fy < -1e8:
			notes.append("NO FLOOR under the standing spot")
		elif fy - ay > 2.4:
			notes.append("above the cold-catch ceiling")
		if far > -1e8 and far - ay <= 3.2:
			notes.append("not launchable: %.1f m of air under it" % (far - ay))
		if near < 6.5:
			notes.append("within reach of k%d" % nk)
		print("     k%-2d %-16s (%6.2f,%6.2f) r %.2f  %4.2f m over the floor at y %5.1f, %4.1f m of air past it, nearest anchor %.2f m  %s"
			% [k, names[k], ax, ay, m.a_r[k], (fy - ay) if fy > -1e8 else 0.0, fy,
			(far - ay) if far > -1e8 else 0.0, near, "  ".join(notes)])

static func vols_report(m: Node2D, derived: bool) -> void:
	print("  camera table (%s), %d volumes:" % ["derived from the floors" if derived else "authored", m.cam_vols.size()])
	for v: Array in m.cam_vols:
		print("     x %6.1f .. %6.1f   floor y %5.1f   zoom %.2f" % [float(v[0]), float(v[1]), float(v[2]), float(v[3])])
