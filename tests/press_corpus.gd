extends SceneTree
## HOW OFTEN DOES THE PRESS WINDOW BITE?
## Large corpus of throws. For each, one ungripped baseline run gives the
## qualifying mask; the shipped gate then makes the press outcome EXACTLY
## predictable - a press at tick tp catches iff some tick in [tp, tp+14]
## qualifies (verified tick-for-tick against real gripped re-runs in
## tests/press_sweep.gd, seven throws, zero mismatches).
## Everything is reported relative to t_touch: the tick the rope first lands
## on the beam, which is the only thing the player can actually see.

const RUN := 210
const GW := 15   # GRIP_WINDOW

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

func _baseline(c: Array) -> Dictionary:
	var m := _rig(c[0], c[1], c[2])
	var qual := PackedInt32Array()
	var t_touch := -1
	var t_hook := -1
	for t in RUN:
		m.step_tick(_tgt(m, t, c), false)
		qual.append(1 if (absf(m.a_theta[0]) >= m.th_part
			and m.a_lockidx[0] >= m.pin_min_idx) else 0)
		var ctr: Vector2 = m.a_pos[0]
		var n := 0
		var lft := false
		var rgt := false
		for i in m.NP:
			if (m.pos[i] - ctr).length() - m.a_r[0] - m.p_rad[i] < 0.015:
				n += 1
				if m.pos[i].x < ctr.x: lft = true
				else: rgt = true
		if t_touch < 0 and n >= 1:
			t_touch = t
		if t_hook < 0 and n >= 3 and lft and rgt:
			t_hook = t
	m.free()
	return {"qual": qual, "t_touch": t_touch, "t_hook": t_hook}

func _press(c: Array, tp: int) -> int:
	# -1 nothing, 0 partial, 1 lock
	var m := _rig(c[0], c[1], c[2])
	var eng := -1
	var verdict := -1
	for t in RUN:
		m.step_tick(_tgt(m, t, c), t >= tp)
		if eng < 0 and m.a_freelen[0] >= 0.0:
			eng = t
		if eng >= 0 and m.a_locked[0] >= 0 and verdict < 0:
			verdict = m.a_locked[0]
	m.free()
	if eng < 0:
		return -1
	return maxi(verdict, 0)

func _ms(t: int) -> int:
	return int(round(t * 1000.0 / 60.0))

func _initialize() -> void:
	print("PRESS WINDOW CORPUS.  GRIP_WINDOW = 15 ticks, FORWARD ONLY.")
	print("catchable = some press tick engages.  hole = a dead press tick with")
	print("catching press ticks on BOTH sides of it.")
	print("")
	print("  r   dx   dy   a1  |touch hook  q0 | first  last  ticks holes maxhole"
		+ " | press vs hook (ms)")
	var n_throw := 0
	var n_catch := 0
	var n_holed := 0
	var holesum := 0
	var maxhole_all := 0
	var early_ms := []
	var late_ms := []
	var hole_ms := []
	var rt_out := {9: [0, 0, 0], 12: [0, 0, 0], 15: [0, 0, 0], 18: [0, 0, 0]}
	var cfgs := []
	for r in [0.22, 0.20, 0.11, 0.10]:
		for dy in [2.0, 2.2, 2.4, 2.6]:
			for dx in [1.4, 1.7, 2.0, 2.3, 2.6]:
				for a1 in [-0.42, -0.34]:
					cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI, 9, true])
	for c in cfgs:
		var b := _baseline(c)
		var qual: PackedInt32Array = b["qual"]
		var t_hook: int = b["t_hook"]
		var any := false
		for t in RUN:
			if qual[t] == 1:
				any = true
				break
		if not any or t_hook < 0:
			continue
		n_throw += 1
		# exact press outcome from the mask
		var catches := PackedInt32Array()
		catches.resize(RUN)
		for tp in RUN:
			var ok := 0
			for u in range(tp, mini(tp + GW, RUN)):
				if qual[u] == 1:
					ok = 1
					break
			catches[tp] = ok
		var first := -1
		var last := -1
		var nt := 0
		var q0 := -1
		for t in RUN:
			if qual[t] == 1 and q0 < 0:
				q0 = t
			if catches[t] == 1:
				if first < 0:
					first = t
				last = t
				nt += 1
		var holes := 0
		var maxhole := 0
		var run_h := 0
		for t in range(first, last + 1):
			if catches[t] == 0:
				holes += 1
				run_h += 1
				maxhole = maxi(maxhole, run_h)
			else:
				run_h = 0
		n_catch += 1
		if holes > 0:
			n_holed += 1
			hole_ms.append(_ms(maxhole))
		holesum += holes
		maxhole_all = maxi(maxhole_all, maxhole)
		early_ms.append(_ms(first - t_hook))
		late_ms.append(_ms(last - t_hook))
		print("%.2f %4.1f %4.1f %5.2f | %4d %4d %4d | %4d %5d %5d %5d %6d | %+5d .. %+5d"
			% [c[2], c[0], c[1], c[4] / PI, b["t_touch"], t_hook, q0,
			first, last, nt, holes, maxhole,
			_ms(first - t_hook), _ms(last - t_hook)])
		for rt in [9, 12, 15, 18]:
			var tp2: int = t_hook + rt
			if tp2 >= RUN:
				continue
			var res: int = _press(c, tp2)
			rt_out[rt][res + 1] += 1
	print("")
	print("throws that can catch at all: %d" % n_catch)
	print("of those, throws with a DEAD press tick inside the window: %d (%.0f%%)"
		% [n_holed, 100.0 * n_holed / maxf(n_catch, 1)])
	print("longest dead run anywhere: %d ticks (%d ms)" % [maxhole_all, _ms(maxhole_all)])
	hole_ms.sort()
	print("dead-run lengths (ms): ", hole_ms)
	early_ms.sort()
	late_ms.sort()
	print("")
	print("PRESS WINDOW MEASURED FROM THE MOMENT THE ROPE VISIBLY HOOKS THE BEAM")
	print("  earliest catching press (ms vs hook): min %d  median %d  max %d"
		% [early_ms[0], early_ms[early_ms.size() / 2], early_ms[-1]])
	print("  latest   catching press (ms vs hook): min %d  median %d  max %d"
		% [late_ms[0], late_ms[late_ms.size() / 2], late_ms[-1]])
	print("")
	print("A HUMAN WHO PRESSES WHEN THEY SEE THE HOOK, PLUS REACTION TIME:")
	print("  reaction    NOTHING   partial    LOCK")
	for rt in [9, 12, 15, 18]:
		var a: Array = rt_out[rt]
		print("   %3d ms      %4d      %4d     %4d" % [_ms(rt), a[0], a[1], a[2]])
	quit(0)
