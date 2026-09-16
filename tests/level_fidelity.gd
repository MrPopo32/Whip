extends SceneTree
## THE PROOF OF FIDELITY: a level drawn as a scene is the SAME WORLD as the
## level written by hand, to the bit, or the scene loader cannot carry a tape
## or a save. Every check here is an equality of arrays, not a fingerprint
## that happens to agree.
##
##   godot --headless --path . -s res://tests/level_fidelity.gd
##
##  F1 res://levels/crag.tscn, the committed export, loaded through the scene
##     loader, fingerprints 1132405890178884573 - the hardcoded crag's number -
##     and every element of every array it produces is bit-identical to the
##     hardcoded build's: terrain, normals, boxes, rescue depths, arcs,
##     anchors, spawn, goal, world_bottom, camera table, backdrop
##  F2 the exporter itself round-trips: the crag and the lab exported afresh
##     to a scratch scene and loaded back compare the same way (the lab is the
##     one with jam flags, captions and an authored camera table)
##  F3 the derived camera table is the authored one: level_default_vols on the
##     shipped ground chains reproduces CAM_VOLS and CRAG_VOLS element for
##     element
##  F4 the number that decided the schema: how many of the hardcoded crag's
##     post-fillet segment endpoints are OFF the 0.01 m grid in float32 (so a
##     scene that stored segments instead of corners could not have carried
##     them), and how many raw float32 values the .tscn text format keeps
##     bit-exact (all of them - Godot 4.7 prints shortest-round-trip digits)
##  F5 the loader's rulings, on scratch scenes built here: a Ground and an
##     island drawn the wrong way round load to the same fingerprint as the
##     right way round with every normal into the air; no Spawn is refused; a
##     fillet marker off its vertex is refused; a zero-length segment is
##     refused; a name with no scene is refused - each with a message that
##     names the mistake, and none of them builds a playable world
const MAIN := preload("res://main.gd")
const LIB := preload("res://tests/level_lib.gd")
const EXP := preload("res://tests/level_export.gd")

const CRAG_FP := 1132405890178884573
const LAB_FP := 3497417229650881203
const TMP := "user://level_fidelity_%s.tscn"

var fail: Array[String] = []

# ------------------------------------------------------------ comparing --
func bits32(v: float) -> String:
	return PackedFloat32Array([v]).to_byte_array().hex_encode()

func cmp_v2(what: String, name: String, A: PackedVector2Array, B: PackedVector2Array) -> int:
	if A.size() != B.size():
		fail.append("%s %s: %d vs %d elements" % [what, name, A.size(), B.size()])
		return 1
	for i in A.size():
		if A[i].x != B[i].x or A[i].y != B[i].y:
			fail.append("%s %s[%d]: (%.9f, %.9f) vs (%.9f, %.9f)"
				% [what, name, i, A[i].x, A[i].y, B[i].x, B[i].y])
			return 1
	return 0

func cmp_f(what: String, name: String, A: PackedFloat32Array, B: PackedFloat32Array) -> int:
	if A.size() != B.size():
		fail.append("%s %s: %d vs %d elements" % [what, name, A.size(), B.size()])
		return 1
	for i in A.size():
		if A[i] != B[i] and not (is_inf(A[i]) and is_inf(B[i])):
			fail.append("%s %s[%d]: %.9f vs %.9f" % [what, name, i, A[i], B[i]])
			return 1
	return 0

func cmp_i(what: String, name: String, A: PackedInt32Array, B: PackedInt32Array) -> int:
	if A != B:
		fail.append("%s %s differ: %s vs %s" % [what, name, str(A), str(B)])
		return 1
	return 0

func compare(h: Node2D, s: Node2D, what: String) -> int:
	# h is the hardcoded build, s the scene build. Every array _build_* fills,
	# and everything _finish_terrain derives from them.
	var bad := 0
	if int(h.level_fingerprint()) != int(s.level_fingerprint()):
		fail.append("%s fingerprint %d vs %d" % [what, h.level_fingerprint(), s.level_fingerprint()])
		bad += 1
	bad += cmp_v2(what, "t_a", h.t_a, s.t_a)
	bad += cmp_v2(what, "t_b", h.t_b, s.t_b)
	bad += cmp_v2(what, "t_n", h.t_n, s.t_n)
	bad += cmp_v2(what, "t_lo", h.t_lo, s.t_lo)
	bad += cmp_v2(what, "t_hi", h.t_hi, s.t_hi)
	bad += cmp_f(what, "t_deep", h.t_deep, s.t_deep)
	bad += cmp_v2(what, "t_arc_c", h.t_arc_c, s.t_arc_c)
	bad += cmp_f(what, "t_arc_r", h.t_arc_r, s.t_arc_r)
	bad += cmp_v2(what, "t_arc_ang", h.t_arc_ang, s.t_arc_ang)
	bad += cmp_v2(what, "a_pos", h.a_pos, s.a_pos)
	bad += cmp_f(what, "a_r", h.a_r, s.a_r)
	bad += cmp_i(what, "a_jam", h.a_jam, s.a_jam)
	if h.a_name != s.a_name:
		fail.append("%s a_name differ: %s vs %s" % [what, str(h.a_name), str(s.a_name)])
		bad += 1
	if h.spawn.x != s.spawn.x or h.spawn.y != s.spawn.y:
		fail.append("%s spawn (%.9f, %.9f) vs (%.9f, %.9f)" % [what, h.spawn.x, h.spawn.y, s.spawn.x, s.spawn.y])
		bad += 1
	for nm: String in ["goal_x", "goal_y", "world_bottom"]:
		if float(h.get(nm)) != float(s.get(nm)):
			fail.append("%s %s %.9f vs %.9f" % [what, nm, float(h.get(nm)), float(s.get(nm))])
			bad += 1
	if not EXP.same_vols(h.cam_vols, s.cam_vols):
		fail.append("%s camera table differs: %s vs %s" % [what, str(h.cam_vols), str(s.cam_vols)])
		bad += 1
	if h.bd_poly.size() != s.bd_poly.size():
		fail.append("%s backdrop: %d vs %d polygons" % [what, h.bd_poly.size(), s.bd_poly.size()])
		bad += 1
	else:
		for j in h.bd_poly.size():
			bad += cmp_v2(what, "bd_poly[%d]" % j, h.bd_poly[j], s.bd_poly[j])
			if h.bd_col[j] != s.bd_col[j]:
				fail.append("%s bd_col[%d] %s vs %s" % [what, j, str(h.bd_col[j]), str(s.bd_col[j])])
				bad += 1
	return bad

func summary(m: Node2D) -> String:
	return "%d segments, %d arcs, %d anchors, %d camera volumes, %d backdrop polygons" % [
		m.t_a.size(), m.t_arc_c.size(), m.a_pos.size(), m.cam_vols.size(), m.bd_poly.size()]

# --------------------------------------------------------------------- F1 ---
func f1() -> void:
	var h := LIB.new_sim("crag")
	var s := LIB.new_sim("crag.tscn")
	if String(s.level_err) != "":
		fail.append("F1 res://levels/crag.tscn was refused: %s" % String(s.level_err))
	elif int(h.level_fingerprint()) != CRAG_FP:
		fail.append("F1 the HARDCODED crag fingerprints %d, not %d - the crag moved, re-export it" % [h.level_fingerprint(), CRAG_FP])
	elif compare(h, s, "F1") == 0:
		print("  F1 ok: res://levels/crag.tscn fingerprints %d, the hardcoded crag's; %s, all bit-identical"
			% [s.level_fingerprint(), summary(s)])
	h.free(); s.free()

# --------------------------------------------------------------------- F2 ---
func f2() -> void:
	for lvl: String in ["crag", "lab"]:
		var tmp := TMP % lvl
		var ok: bool = EXP.export_level(lvl, tmp)
		if not ok:
			fail.append("F2 exporting %s to %s failed" % [lvl, tmp])
			continue
		var h := LIB.new_sim(lvl)
		var s := LIB.new_sim(tmp)
		if String(s.level_err) != "":
			fail.append("F2 %s: the export was refused by the loader: %s" % [lvl, String(s.level_err)])
		elif compare(h, s, "F2 " + lvl) == 0:
			print("  F2 ok: %s exported afresh and loaded back: fingerprint %d, %s, all bit-identical%s"
				% [lvl, s.level_fingerprint(), summary(s),
				"; jam flags and captions carried" if lvl == "lab" else ""])
		h.free(); s.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

# --------------------------------------------------------------------- F3 ---
func f3() -> void:
	var ok := true
	for lvl: String in ["", "crag"]:
		var m := LIB.new_sim(lvl)
		# the ground is the LONGEST open chain: the traverse's left wall is a
		# separate segment appended after its floor polyline, so its build
		# walks back into two open chains
		var loops := LIB.chain_loops(m.t_a, m.t_b)
		var g := PackedVector2Array()
		for l: Dictionary in loops:
			if not bool(l["closed"]) and (l["pts"] as PackedVector2Array).size() > g.size():
				g = l["pts"]
		var want: Array = MAIN.CAM_VOLS if lvl == "" else MAIN.CRAG_VOLS
		var got: Array = MAIN.level_default_vols(g)
		if not EXP.same_vols(want, got):
			ok = false
			fail.append("F3 %s: derived table %s != authored %s" % ["traverse" if lvl == "" else lvl, str(got), str(want)])
		m.free()
	if ok:
		print("  F3 ok: level_default_vols reproduces CAM_VOLS (5 volumes) and CRAG_VOLS (10) element for element: boundary = lip - 1.0 m, floor y, zoom 1.0")

# --------------------------------------------------------------------- F4 ---
func f4() -> void:
	var m := LIB.new_sim("crag")
	var off := 0
	var ex := ""
	var vals := PackedFloat32Array()
	for i in m.t_a.size():
		for v: float in [m.t_a[i].x, m.t_a[i].y, m.t_b[i].x, m.t_b[i].y]:
			vals.append(v)
			var qv := PackedFloat32Array([roundf(v * 100.0) / 100.0])[0]
			if qv != v:
				off += 1
				if ex == "":
					ex = "%.9f (nearest grid value %.9f, %s)" % [v, qv, "segment %d" % i]
	# and the text format, on those very values: written as a Line2D and read
	# back through ResourceLoader, how many come back bit-identical
	var pts := PackedVector2Array()
	for j in range(0, vals.size() - 1, 2):
		pts.append(Vector2(vals[j], vals[j + 1]))
	var root := Node2D.new()
	var l := Line2D.new()
	l.name = "L"
	l.points = pts
	root.add_child(l)
	l.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var tmp := TMP % "raw"
	ResourceSaver.save(ps, tmp)
	root.free()
	var ps2: PackedScene = ResourceLoader.load(tmp, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var r2: Node = ps2.instantiate()
	var back: PackedVector2Array = (r2.get_node("L") as Line2D).points
	var same := 0
	for j in pts.size():
		if bits32(pts[j].x) == bits32(back[j].x) and bits32(pts[j].y) == bits32(back[j].y):
			same += 1
	r2.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	if same != pts.size():
		fail.append("F4 the .tscn text kept only %d of %d raw float32 pairs bit-exact" % [same, pts.size()])
	else:
		print("  F4 ok: %d of %d post-fillet endpoint coordinates of the crag are OFF the 0.01 m grid in float32 (e.g. %s) - which is why the scene stores corners and radii and re-cuts the fillets; the .tscn text kept %d of %d raw float32 pairs bit-exact"
			% [off, vals.size(), ex, same, pts.size()])
	m.free()

# --------------------------------------------------------------------- F5 ---
# scratch scenes, built here with bare nodes (no scripts: the loader's
# defaults) so the rulings are about the loader and not about the editor
func scene(ground: PackedVector2Array, islands: Array, anchors: Array,
		spawn: Variant, extra: Callable) -> String:
	var root := Node2D.new()
	root.name = "Level"
	var g := Line2D.new()
	g.name = "Ground"
	g.points = EXP.px_arr(ground)
	root.add_child(g)
	var isl := Node2D.new()
	isl.name = "Islands"
	root.add_child(isl)
	for p: PackedVector2Array in islands:
		var l := Line2D.new()
		l.name = "I%d" % isl.get_child_count()
		l.points = EXP.px_arr(p)
		l.closed = true
		isl.add_child(l)
	var an := Node2D.new()
	an.name = "Anchors"
	root.add_child(an)
	for a: Vector2 in anchors:
		var mk := Marker2D.new()
		mk.name = "A%d" % an.get_child_count()
		mk.position = a * 60.0
		an.add_child(mk)
	if spawn != null:
		var sp := Marker2D.new()
		sp.name = "Spawn"
		sp.position = (spawn as Vector2) * 60.0
		root.add_child(sp)
	extra.call(root)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var tmp := TMP % ("f5_%d" % Time.get_ticks_usec())
	ResourceSaver.save(ps, tmp)
	root.free()
	return tmp

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)

func f5() -> void:
	var ground := PackedVector2Array([Vector2(-8, -6), Vector2(-8, 0), Vector2(6, 0),
		Vector2(6, 3), Vector2(14, 3), Vector2(14, -2)])
	var lump := PackedVector2Array([Vector2(7.0, 1.54), Vector2(7.8, 1.54),
		Vector2(7.8, 2.14), Vector2(7.0, 2.14)])                # solid inside
	var anchors: Array = [Vector2(-2.0, -2.2), Vector2(7.4, 0.8)]
	var nothing := func(_r: Node) -> void: pass
	# (a) the right way round, and both polylines reversed
	var p_ok := scene(ground, [lump], anchors, Vector2(-5, -1), nothing)
	var rg := ground.duplicate()
	rg.reverse()
	var rl := lump.duplicate()
	rl.reverse()
	var p_rev := scene(rg, [rl], anchors, Vector2(-5, -1), nothing)
	var a := LIB.new_sim(p_ok)
	var b := LIB.new_sim(p_rev)
	var loops := LIB.chain_loops(a.t_a, a.t_b)
	var air := LIB.air_of(loops)
	var good_a := LIB.normals_score(air, a.t_a, a.t_b)
	var good_b := LIB.normals_score(air, b.t_a, b.t_b)
	if String(a.level_err) != "" or String(b.level_err) != "":
		fail.append("F5 a plain scene was refused: %s / %s" % [String(a.level_err), String(b.level_err)])
	elif int(a.level_fingerprint()) != int(b.level_fingerprint()) or compare(a, b, "F5 reversed") != 0:
		fail.append("F5 the reversed scene loads to a different world (fp %d vs %d)" % [a.level_fingerprint(), b.level_fingerprint()])
	elif good_a != a.t_a.size() or good_b != b.t_a.size():
		fail.append("F5 normals into the air: %d/%d forward, %d/%d reversed" % [good_a, a.t_a.size(), good_b, b.t_a.size()])
	elif a.t_arc_c.size() != 5:
		fail.append("F5 expected 5 arcs (1 lip at 0.35 + 4 lump corners at 0.10), got %d" % a.t_arc_c.size())
	elif a.a_pos.size() != 2 or float(a.a_r[0]) != PackedFloat32Array([0.12])[0]:
		fail.append("F5 bare Marker2D anchors: %d, r %.3f (want 2 at 0.12)" % [a.a_pos.size(), float(a.a_r[0])])
	elif a.cam_vols.size() != 2 or float(a.cam_vols[0][1]) != 5.0:
		fail.append("F5 derived camera table %s (want 2 volumes, boundary at 5.0)" % str(a.cam_vols))
	else:
		var vols := PackedStringArray()
		for v: Array in a.cam_vols:
			vols.append("x %.0f..%.0f y %.0f" % [float(v[0]), float(v[1]), float(v[2])])
		print("  F5 ok: Ground and a lump drawn backwards load to fingerprint %d, the same as forwards, with %d/%d normals into the air, 5 arcs, 2 default anchors at r 0.12, camera [%s]"
			% [b.level_fingerprint(), good_b, b.t_a.size(), ", ".join(vols)])
	a.free(); b.free()
	# (b) no Spawn, (c) a fillet marker off its vertex, (d) a zero-length
	# segment, (e) no such scene: refused, with the mistake named
	var refusals: Array = [
		["no Spawn", scene(ground, [lump], anchors, null, nothing), "Spawn"],
		["a fillet marker 0.50 m off its vertex",
			scene(ground, [lump], anchors, Vector2(-5, -1), func(r: Node) -> void:
				var mk := Marker2D.new()
				# A fillet marker IS a Marker2D carrying whip_fillet.gd: the loader now
				# refuses any other child of a terrain node by name (a bare marker or a
				# sprite there used to be read as a fillet of radius 0 and move the
				# fingerprint), so this fixture carries the script a real one carries.
				mk.set_script(preload("res://levels/whip_fillet.gd"))
				mk.name = "F"
				mk.position = Vector2(6.5, 0.0) * 60.0
				r.get_node("Ground").add_child(mk)), "drag it onto"],
		["a zero-length segment", scene(PackedVector2Array([Vector2(-8, -6),
			Vector2(-8, 0), Vector2(-8, 0), Vector2(6, 0)]), [], anchors,
			Vector2(-5, -1), nothing), "same place"],
		["no such scene", "nope", "does not exist"],
	]
	var ok := 0
	for r: Array in refusals:
		var m := LIB.new_sim(String(r[1]))
		var err := String(m.level_err)
		if err == "":
			fail.append("F5 %s was NOT refused" % String(r[0]))
		elif not err.contains(String(r[2])):
			fail.append("F5 %s: refused, but the message does not name it: %s" % [String(r[0]), err])
		elif m.t_a.size() != 0 or m.a_pos.size() != 0:
			fail.append("F5 %s: refused but left %d segments / %d anchors to play" % [String(r[0]), m.t_a.size(), m.a_pos.size()])
		else:
			ok += 1
			print("     refused %-38s -> %s" % [r[0], err.substr(0, 110)])
		m.free()
	if ok == refusals.size():
		print("  F5 ok: %d bad scenes refused, each naming the mistake, none of them playable" % ok)
	for p: String in [p_ok, p_rev]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for r: Array in refusals:
		if String(r[1]).begins_with("user://"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(r[1])))

func _initialize() -> void:
	f1(); f2(); f3(); f4(); f5()
	if fail.is_empty():
		print("PASS  level fidelity F1-F5: res://levels/crag.tscn is the crag, fingerprint %d" % CRAG_FP)
		quit(0)
		return
	for f in fail:
		print("FAIL  %s" % f)
	quit(1)
