extends SceneTree
## WHY DOES a_theta FALL WHILE THE WRAP TIGHTENS?
## a_theta counts only segments with BOTH ends inside a_r + p_rad + wrap_shell,
## i.e. rope touching the BARE beam. Once the rope crosses its own standing
## part, the outer strand rides a rope-diameter out and stops counting. So:
##   n1 = vertices on the bare beam (inside the shipped shell)
##   n2 = vertices NOT on the bare beam but within a rope diameter of a vertex
##        that is - i.e. riding on a strand already wrapped
##   per = a_theta / n1seg, the angle one counted segment is worth
## If n1 falls while n1+n2 holds or rises, the rope is not unwinding: it is
## winding onto itself, and the measure is blind to the second layer.

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
	if t < 30:
		return m.body_pos + Vector2(cos(c[3]), sin(c[3])) * m.REACH
	if t < 30 + int(c[5]):
		return m.body_pos + Vector2(cos(c[4]), sin(c[4])) * m.REACH
	if bool(c[6]) and t < 30 + int(c[5]) + 10:
		return m.body_pos + Vector2(cos(c[3]), sin(c[3])) * m.REACH * 0.7
	return m.body_pos + Vector2(cos(c[4]), sin(c[4])) * m.REACH

func _dump(name: String, c: Array, lo: int, hi: int) -> void:
	var m := _rig(c[0], c[1], c[2])
	print("")
	print("=== %s  r=%.2f at (%.1f,-%.1f) ===" % [name, c[2], c[0], c[1]])
	print("tick   a_theta  n1  n2  n1+n2  rad/seg  gate")
	for t in RUN:
		m.step_tick(_tgt(m, t, c), false)
		if t < lo or t > hi:
			continue
		var ctr: Vector2 = m.a_pos[0]
		var R: float = m.a_r[0]
		var on1 := []
		var n1 := 0
		for i in m.NP:
			var d: float = (m.pos[i] - ctr).length()
			if d < R + m.p_rad[i] + m.wrap_shell:
				n1 += 1
				on1.append(i)
		var n2 := 0
		for i in m.NP:
			var d: float = (m.pos[i] - ctr).length()
			if d >= R + m.p_rad[i] + m.wrap_shell:
				for j in on1:
					if absi(i - int(j)) > 1 and m.pos[i].distance_to(m.pos[j]) \
							< m.p_rad[i] + m.p_rad[j] + 0.02:
						n2 += 1
						break
		var nseg := 0
		for i in range(m.NP - 1):
			var d0: float = (m.pos[i] - ctr).length()
			var d1: float = (m.pos[i + 1] - ctr).length()
			if d0 < R + m.p_rad[i] + m.wrap_shell and d1 < R + m.p_rad[i + 1] + m.wrap_shell:
				nseg += 1
		var per: float = absf(m.a_theta[0]) / maxf(nseg, 1)
		print("%4d   %6.2f  %3d %3d %6d  %7.2f  %s"
			% [t, absf(m.a_theta[0]), n1, n2, n1 + n2, per,
			"QUALIFY" if (absf(m.a_theta[0]) >= m.th_part
				and m.a_lockidx[0] >= m.pin_min_idx) else "-"])
	m.free()

func _initialize() -> void:
	print("SECOND-LAYER BLINDNESS IN THE WINDING MEASURE")
	_dump("school beam med - the 18-tick dead stretch",
		[2.0, 2.2, 0.20, 0.85 * PI, -0.42 * PI, 9, true], 106, 140)
	_dump("fast beam thin - the 16-tick dead stretch",
		[2.0, 2.6, 0.10, 0.85 * PI, -0.42 * PI, 9, true], 104, 130)
	quit(0)
