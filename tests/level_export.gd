extends SceneTree
## EXPORT A HARDCODED LEVEL TO A SCENE, in the schema main.gd's loader reads
## (main.gd, "SCENE LEVELS"). Builds the level the way the game does, walks
## its segments back into the polylines they came from (through every fillet,
## by intersecting the two shortened lines, then onto the 0.01 m grid the
## loader uses), and writes Ground, Islands, Anchors, Spawn, Goal, Backdrop -
## and a Camera node only if the derived table would differ from the level's.
## Then it loads what it wrote back through the loader and prints both
## fingerprints, so the export is checked the moment it is made.
## tests/level_fidelity.gd is the standing gate on the committed file.
##
##   godot --headless --path . -s res://tests/level_export.gd -- level=crag out=res://levels/crag.tscn
const MAIN := preload("res://main.gd")
const LIB := preload("res://tests/level_lib.gd")
const PPM := 60.0
const TERRAIN_COL := Color(0.32, 0.35, 0.42)     # _draw's terrain colour

# The crag's own labels, in its anchor and island order (main.gd _build_crag),
# so the scene reads like the README's table rather than like a dump.
const CRAG_ANCHORS := ["H0_HORN", "H1_STALACTITE", "H2_WINDOW", "D0_HORN",
	"D1_STALACTITE", "D2_WINDOW", "D3_BRANCH", "D4_KNOB", "D5_HORN",
	"D6_STALACTITE", "D7_WINDOW", "D8_BRANCH"]
const CRAG_ISLANDS := ["H1_brow", "H0_shelf", "D0_shelf", "D1_brow", "D4_lump",
	"D5_shelf", "D6_brow", "D3_rib", "D8_rib", "H2_hood", "D2_hood", "D7_hood"]
const CRAG_PAINT := ["far_cliff", "D4_pillar", "H1_spike", "D1_spike",
	"D6_spike", "H1_curtain", "D1_curtain", "D6_curtain", "H0_buttress",
	"D0_buttress", "D5_buttress", "D3_curtain", "D8_curtain", "D2_curtain",
	"D7_curtain", "H2_curtain", "near_rock"]
const HUD := {
	"crag": "THE WHIP - THE CRAG   (--level crag.tscn)   a gorge, nine drops, the rock decides which throws survive\nSPACE / LMB = CLOSE YOUR HAND on the rope. A wrap only takes in the moment you close it,\nand only holds while you hold. OPEN your hand and you leave the anchor that instant.\nRock cannot be wrapped - only the anchors hold. Green ring = it holds. Amber = it betrays.",
	"lab": "THE WHIP - THE LAB   (--level lab.tscn)   flat ground, four stations, walk the length of it\nSPACE / LMB = CLOSE YOUR HAND. A wrap only takes in the moment you close it.\nBEAM and THIN BEAM are ordinary: you have to throw a CROSSING onto them.\nJAM (pale collar) makes the crossing for you - it takes from angles a wrap will not.\nBoth let go the instant you open your hand. Green ring = it holds. Amber = it betrays.",
}

static func q(v: float, step: float) -> float:
	var inv := roundf(1.0 / step)
	return roundf(v * inv) / inv

static func qv(v: Vector2) -> Vector2:
	return Vector2(q(v.x, 0.01), q(v.y, 0.01))

static func px(v: Vector2) -> Vector2:
	return v * PPM

static func px_arr(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		out.append(px(v))
	return out

static func convex(p: PackedVector2Array, i: int, closed: bool) -> bool:
	# the same test _fillet applies: d1 x d2 > 0 with the air on the left
	var n := p.size()
	if not closed and (i == 0 or i == n - 1):
		return false
	var d1 := (p[i] - p[(i - 1 + n) % n]).normalized()
	var d2 := (p[(i + 1) % n] - p[i]).normalized()
	return d1.cross(d2) > 0.000001

static func common(rs: Array) -> float:
	# the most frequent radius, 0 if there are none
	if rs.is_empty():
		return 0.0
	var count := {}
	for r: float in rs:
		count[r] = int(count.get(r, 0)) + 1
	var best := 0.0
	var bn := -1
	for r: float in count:
		if int(count[r]) > bn:
			bn = int(count[r])
			best = r
	return best

static func same_vols(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		for j in 4:
			if float(a[i][j]) != float(b[i][j]):
				return false
	return true

static func export_level(lvl: String, out: String) -> bool:
	var m := LIB.new_sim(lvl)
	if String(m.level_err) != "":
		print("cannot export: %s" % String(m.level_err))
		m.free()
		return false
	# ---- the polylines, recovered and put on the grid
	var loops := LIB.chain_loops(m.t_a, m.t_b)
	var ground := PackedVector2Array()
	var islands: Array = []
	var opens := 0
	var polys: Array = []                  # every loop, in order, quantised
	for l: Dictionary in loops:
		var p: PackedVector2Array = (l["pts"] as PackedVector2Array).duplicate()
		for i in p.size():
			p[i] = qv(p[i])
		if bool(l["closed"]):
			if p.size() > 1 and p[p.size() - 1] == p[0]:
				p.remove_at(p.size() - 1)
			islands.append(p)
		else:
			opens += 1
			ground = p
		polys.append({"pts": p, "closed": bool(l["closed"])})
	if opens != 1:
		print("cannot export: %d open chains, the schema has one Ground" % opens)
		m.free()
		return false
	# ---- which vertex each arc rounds, and at what radius
	var vr: Array = []                      # per loop: {vertex index: r}
	for lp: Dictionary in polys:
		vr.append({})
	for j in m.t_arc_c.size():
		var c: Vector2 = m.t_arc_c[j]
		var bl := -1
		var bi := -1
		var bd := 1e9
		for li in polys.size():
			var p: PackedVector2Array = polys[li]["pts"]
			for i in p.size():
				var d := c.distance_to(p[i])
				if d < bd:
					bd = d
					bl = li
					bi = i
		vr[bl][bi] = q(m.t_arc_r[j], 0.001)
	var g_rs: Array = []
	var i_rs: Array = []
	for li in polys.size():
		for i: int in vr[li]:
			if bool(polys[li]["closed"]):
				i_rs.append(float(vr[li][i]))
			else:
				g_rs.append(float(vr[li][i]))
	var fg := common(g_rs)
	var fi := common(i_rs)
	# ---- the scene
	var root := Node2D.new()
	root.name = "Level"
	root.set_script(load("res://levels/whip_level.gd"))
	root.set("fillet_ground", fg)
	root.set("fillet_island", fi)
	root.set("hud", String(HUD.get(lvl, "")))
	var overrides := 0
	var isl_node := Node2D.new()
	isl_node.name = "Islands"
	var li := 0
	for lp: Dictionary in polys:
		var p: PackedVector2Array = lp["pts"]
		var closed: bool = lp["closed"]
		var line := Line2D.new()
		if closed:
			var ii := islands.find(p)
			line.name = CRAG_ISLANDS[ii] if lvl == "crag" and ii < CRAG_ISLANDS.size() \
				else "Island%d" % ii
		else:
			line.name = "Ground"
		line.set_script(load("res://levels/whip_terrain.gd"))
		line.points = px_arr(p)
		line.closed = closed
		line.width = 6.0
		line.default_color = TERRAIN_COL
		if closed:
			isl_node.add_child(line)
		else:
			root.add_child(line)
		# per-vertex overrides: a convex corner whose radius is not the role's
		# default (or that has no arc while the default is not 0)
		var dflt := fi if closed else fg
		for i in p.size():
			if not convex(p, i, closed):
				continue
			var r: float = float(vr[li].get(i, 0.0))
			if r != dflt:
				var mk := Marker2D.new()
				mk.name = "fillet_%d" % i
				mk.set_script(load("res://levels/whip_fillet.gd"))
				mk.position = px(p[i])
				mk.set("radius", r)
				line.add_child(mk)
				overrides += 1
		li += 1
	root.add_child(isl_node)
	# ---- anchors
	var an := Node2D.new()
	an.name = "Anchors"
	root.add_child(an)
	for k in m.a_pos.size():
		var mk := Marker2D.new()
		var cap := String(m.a_name[k])
		if lvl == "crag" and k < CRAG_ANCHORS.size():
			mk.name = CRAG_ANCHORS[k]
		elif cap != "":
			mk.name = "A%d_%s" % [k, cap.replace(" ", "_")]
		else:
			mk.name = "A%d" % k
		mk.set_script(load("res://levels/whip_anchor.gd"))
		mk.position = px(m.a_pos[k])
		mk.set("radius", q(m.a_r[k], 0.001))
		mk.set("jam", int(m.a_jam[k]) == 1)
		mk.set("caption", cap)
		an.add_child(mk)
	var sp := Marker2D.new()
	sp.name = "Spawn"
	sp.position = px(m.spawn)
	root.add_child(sp)
	if float(m.goal_x) < 900.0:
		var gl := Marker2D.new()
		gl.name = "Goal"
		gl.position = px(Vector2(m.goal_x, m.goal_y))
		root.add_child(gl)
	# ---- camera: only if the derived table is not the level's
	var derived: Array = MAIN.level_default_vols(ground)
	var cam_written := false
	if not same_vols(derived, m.cam_vols):
		var cn := Node2D.new()
		cn.name = "Camera"
		root.add_child(cn)
		for vi in m.cam_vols.size():
			var v: Array = m.cam_vols[vi]
			var line := Line2D.new()
			line.name = "V%d" % vi
			line.set_script(load("res://levels/whip_camvol.gd"))
			line.points = PackedVector2Array([px(Vector2(float(v[0]), float(v[2]))),
				px(Vector2(float(v[1]), float(v[2])))])
			line.width = 2.0
			line.default_color = Color(0.9, 0.6, 0.2, 0.6)
			line.set("zoom", float(v[3]))
			cn.add_child(line)
		cam_written = true
	# ---- backdrop
	if m.bd_poly.size() > 0:
		var bn := Node2D.new()
		bn.name = "Backdrop"
		root.add_child(bn)
		for j in m.bd_poly.size():
			var pg := Polygon2D.new()
			if lvl == "crag" and j < CRAG_PAINT.size():
				pg.name = CRAG_PAINT[j]
			elif lvl == "crag" and j - CRAG_PAINT.size() < CRAG_ISLANDS.size():
				pg.name = CRAG_ISLANDS[j - CRAG_PAINT.size()] + "_fill"
			else:
				pg.name = "Paint%d" % j
			var poly: PackedVector2Array = (m.bd_poly[j] as PackedVector2Array).duplicate()
			for i in poly.size():
				poly[i] = px(qv(poly[i]))
			pg.polygon = poly
			pg.color = m.bd_col[j]
			bn.add_child(pg)
	# every node must be owned by the root to be packed
	_own(root, root)
	var ps := PackedScene.new()
	var e1 := ps.pack(root)
	var e2 := ResourceSaver.save(ps, out)
	root.free()
	if e1 != OK or e2 != OK:
		print("cannot write %s: pack %d save %d" % [out, e1, e2])
		m.free()
		return false
	print("wrote %s: Ground %d pts, %d islands, %d anchors, %d backdrop polygons, fillet_ground %.2f fillet_island %.2f, %d per-vertex overrides, camera %s"
		% [out, ground.size(), islands.size(), m.a_pos.size(), m.bd_poly.size(),
		fg, fi, overrides, "written (%d volumes)" % m.cam_vols.size() if cam_written
		else "derived (matches the level's %d volumes)" % m.cam_vols.size()])
	# ---- and read it straight back through the loader
	var s := LIB.new_sim(out)
	var ok: bool = String(s.level_err) == "" \
		and int(s.level_fingerprint()) == int(m.level_fingerprint())
	print("fingerprint hardcoded %d, scene %d -> %s" % [m.level_fingerprint(),
		s.level_fingerprint(), "IDENTICAL" if ok else "DIFFERENT" + (
		" (%s)" % String(s.level_err) if String(s.level_err) != "" else "")])
	s.free()
	m.free()
	return ok

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)

func _initialize() -> void:
	var lvl := "crag"
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			lvl = a.substr(6)
		if a.begins_with("out="):
			out = a.substr(4)
	if out == "":
		out = "res://levels/%s.tscn" % (lvl if lvl != "" else "traverse")
	var ok := export_level(lvl, out)
	quit(0 if ok else 1)
