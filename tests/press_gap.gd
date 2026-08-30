extends SceneTree
## Why does the qualifying train have HOLES?
## For a throw that definitely wraps, dump every tick across the hole:
##   th      = a_theta as shipped (segments with BOTH ends inside the tight
##             contact shell a_r + p_rad + wrap_shell)
##   nsh     = how many segments passed that shell gate this tick
##   th_bnd  = the same winding sum with the contact gate removed (band only) -
##             i.e. how wound the rope GEOMETRICALLY is, contact or not
##   touch   = chain vertices within 1.5 cm of the beam surface
##   clr     = clearance of the closest wrapped vertex above the surface (mm);
##             negative means pressed into it
##   span    = does the wrapped stretch reach BOTH sides of the beam (a hook)
##   pin     = _pinch()
## If th collapses while th_bnd / touch / span hold steady, the rope never let
## go: the hole is the contact gate chattering, not the wrap coming undone.

const RUN := 200

func _rig(dx: float, dy: float, r: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -dy)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R)
	m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p
		m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

func _tgt(m: Node2D, t: int, c: Array) -> Vector2:
	var a0: float = c[3]
	var a1: float = c[4]
	var sd: int = c[5]
	var pull: bool = c[6]
	if t < 30:
		return m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH
	if pull and t < 30 + sd + 10:
		return m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
	return m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH

func _dump(name: String, c: Array, lo: int, hi: int) -> void:
	var m := _rig(c[0], c[1], c[2])
	print("")
	print("=== %s  r=%.2f at (%.1f,-%.1f)  th_part=%.2f ==="
		% [name, c[2], c[0], c[1], m.th_part])
	print("tick   th    nsh  th_bnd  touch  clr(mm)  span  pin  gate")
	for t in RUN:
		m.step_tick(_tgt(m, t, c), false)
		if t < lo or t > hi:
			continue
		var ctr: Vector2 = m.a_pos[0]
		var R: float = m.a_r[0]
		var band: float = R + 0.35
		var th_bnd := 0.0
		var nsh := 0
		for i in range(m.NP - 1):
			var v0: Vector2 = m.pos[i] - ctr
			var v1: Vector2 = m.pos[i + 1] - ctr
			if v0.length() < band and v1.length() < band:
				th_bnd += v0.angle_to(v1)
				if v0.length() < R + m.p_rad[i] + m.wrap_shell \
						and v1.length() < R + m.p_rad[i + 1] + m.wrap_shell:
					nsh += 1
		var touch := 0
		var clr := 9.9
		var lft := false
		var rgt := false
		var up := false
		var dn := false
		for i in m.NP:
			var d: float = (m.pos[i] - ctr).length() - R - m.p_rad[i]
			if d < 0.015:
				touch += 1
				var rel: Vector2 = m.pos[i] - ctr
				if rel.x < 0.0: lft = true
				else: rgt = true
				if rel.y < 0.0: up = true
				else: dn = true
			if (m.pos[i] - ctr).length() < band:
				clr = minf(clr, d)
		var span: String = "BOTH" if ((lft and rgt) or (up and dn)) else "one "
		var gate: String = "QUALIFY" if (absf(m.a_theta[0]) >= m.th_part
			and m.a_lockidx[0] >= m.pin_min_idx) else "-"
		print("%4d  %5.2f  %3d  %6.2f  %5d  %7.1f  %s  %s  %s"
			% [t, absf(m.a_theta[0]), nsh, absf(th_bnd), touch, clr * 1000.0,
			span, ("PIN" if m._pinch(0) else " . "), gate])
	m.free()

func _initialize() -> void:
	print("DIAGNOSING THE HOLES IN THE QUALIFYING TRAIN")
	_dump("school beam med (hole at 117-120)",
		[2.0, 2.2, 0.20, 0.85 * PI, -0.42 * PI, 9, true], 104, 140)
	_dump("school beam fat (hole at 112)",
		[2.0, 2.2, 0.22, 0.85 * PI, -0.42 * PI, 9, true], 104, 140)
	_dump("fast beam high (hole at 107-108)",
		[2.0, 2.6, 0.10, 0.85 * PI, -0.42 * PI, 9, true], 100, 132)
	quit(0)
