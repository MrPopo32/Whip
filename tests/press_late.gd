extends SceneTree
## The biggest bucket of failed presses is "too late": the window had already
## shut by the time a human could press. Is that honest - the rope really left
## the beam - or is it the measure declaring a release on a rope that is still
## hooked? Dump the state at the instant of the failed press.

const RUN := 210
const GW := 15

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

func _initialize() -> void:
	var cfgs := []
	for r in [0.22, 0.20, 0.11, 0.10]:
		for dy in [2.0, 2.2, 2.4, 2.6]:
			for dx in [1.4, 1.7, 2.0, 2.3, 2.6]:
				for a1 in [-0.42, -0.34, -0.22]:
					cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI, 9, true])
	var gone := 0
	var still := 0
	var shut_ms := []
	print("throws where a press at hook+200 ms is TOO LATE - state at that instant:")
	print("  r   dx   dy   a1 | window shut  | touching  both   a_theta  self  band")
	print("                   | at hook+ ms  |    pts    sides    rad    pinch  wind")
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		var th := PackedFloat32Array()
		var lidx := PackedInt32Array()
		var tch := PackedInt32Array()
		var spn := PackedInt32Array()
		var pin := PackedInt32Array()
		var bnd := PackedFloat32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			th.append(absf(m.a_theta[0]))
			lidx.append(1 if m.a_lockidx[0] >= m.pin_min_idx else 0)
			pin.append(1 if m._pinch(0) else 0)
			var ctr: Vector2 = m.a_pos[0]
			var R: float = m.a_r[0]
			var n := 0
			var lft := false
			var rgt := false
			for i in m.NP:
				if (m.pos[i] - ctr).length() - R - m.p_rad[i] < 0.015:
					n += 1
					if m.pos[i].x < ctr.x: lft = true
					else: rgt = true
			tch.append(n)
			spn.append(1 if (lft and rgt) else 0)
			var band: float = R + 0.35
			var w := 0.0
			for i in range(m.NP - 1):
				var v0: Vector2 = m.pos[i] - ctr
				var v1: Vector2 = m.pos[i + 1] - ctr
				if v0.length() < band and v1.length() < band:
					w += v0.angle_to(v1)
			bnd.append(absf(w))
			if t_hook < 0 and n >= 3 and lft and rgt:
				t_hook = t
		var part: float = m.th_part
		m.free()
		var qual := PackedInt32Array(); qual.resize(RUN)
		var any := false
		for t in RUN:
			qual[t] = 1 if (th[t] >= part and lidx[t] == 1) else 0
			if qual[t] == 1:
				any = true
		if not any or t_hook < 0:
			continue
		var cs := PackedInt32Array(); cs.resize(RUN)
		for tp in RUN:
			var o := 0
			for u in range(tp, mini(tp + GW, RUN)):
				if qual[u] == 1:
					o = 1
					break
			cs[tp] = o
		var l := -1
		for t in RUN:
			if cs[t] == 1:
				l = t
		var tp2: int = t_hook + 12
		if tp2 >= RUN or cs[tp2] == 1 or tp2 <= l:
			continue
		shut_ms.append(int(round((l - t_hook) * 1000.0 / 60.0)))
		if tch[tp2] <= 1:
			gone += 1
		else:
			still += 1
		print("%.2f %4.1f %4.1f %5.2f |   %+5d      |   %4d    %s   %5.2f   %s  %5.2f"
			% [c[2], c[0], c[1], c[4] / PI,
			int(round((l - t_hook) * 1000.0 / 60.0)),
			tch[tp2], ("yes " if spn[tp2] == 1 else "no  "), th[tp2],
			("YES " if pin[tp2] == 1 else " -  "), bnd[tp2]])
	shut_ms.sort()
	print("")
	print("%d such throws. At the failed press the rope had LEFT the beam"
		% (gone + still))
	print("(0 or 1 contact points) on %d of them, and was STILL ON IT on %d."
		% [gone, still])
	if shut_ms.size() > 0:
		print("the window shut this long after the rope visibly hooked the beam:")
		print("  min %d ms, median %d ms, max %d ms"
			% [shut_ms[0], shut_ms[shut_ms.size() / 2], shut_ms[-1]])
	quit(0)
