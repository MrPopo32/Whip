extends SceneTree
## When a human press does NOTHING, why? Three different bugs wear the same
## face on screen:
##   EARLY  the press landed before the window opened - the wrap took longer
##          than 250 ms to arrive, and holding the button does not help
##   HOLE   catching presses exist on BOTH sides of this instant - the wrap
##          was catchable just before and just after, and silently was not now
##   LATE   the press landed after the last catchable instant

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
	var tot := 0
	var res := {}
	for rt in [9, 12, 15, 18]:
		res[rt] = [0, 0, 0, 0]   # catch, early, hole, late
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		var th := PackedFloat32Array()
		var lidx := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			th.append(absf(m.a_theta[0]))
			lidx.append(1 if m.a_lockidx[0] >= m.pin_min_idx else 0)
			var ctr: Vector2 = m.a_pos[0]
			var n := 0
			var lft := false
			var rgt := false
			for i in m.NP:
				if (m.pos[i] - ctr).length() - m.a_r[0] - m.p_rad[i] < 0.015:
					n += 1
					if m.pos[i].x < ctr.x: lft = true
					else: rgt = true
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
		tot += 1
		var cs := PackedInt32Array(); cs.resize(RUN)
		for tp in RUN:
			var o := 0
			for u in range(tp, mini(tp + GW, RUN)):
				if qual[u] == 1:
					o = 1
					break
			cs[tp] = o
		var f := -1
		var l := -1
		for t in RUN:
			if cs[t] == 1:
				if f < 0: f = t
				l = t
		for rt in [9, 12, 15, 18]:
			var tp2: int = t_hook + rt
			if tp2 >= RUN:
				res[rt][3] += 1
				continue
			if cs[tp2] == 1:
				res[rt][0] += 1
			elif tp2 < f:
				res[rt][1] += 1
			elif tp2 > l:
				res[rt][3] += 1
			else:
				res[rt][2] += 1
	print("Player presses when the rope visibly hooks the beam, plus reaction.")
	print("%d catchable throws." % tot)
	print("")
	print("reaction | caught | NOTHING because...")
	print("         |        | too EARLY   in a HOLE   too LATE")
	for rt in [9, 12, 15, 18]:
		var a: Array = res[rt]
		print("  %3d ms |  %4d  |  %4d (%2.0f%%)  %4d (%2.0f%%)  %4d (%2.0f%%)"
			% [int(round(rt * 1000.0 / 60.0)), a[0],
			a[1], 100.0 * a[1] / tot, a[2], 100.0 * a[2] / tot,
			a[3], 100.0 * a[3] / tot])
	quit(0)
