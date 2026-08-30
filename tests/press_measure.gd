extends SceneTree
## IS THERE A NON-CHATTERING MEASURE THAT ADMITS EXACTLY THE SAME THROWS?
##
## a_theta sums the turn of segments with BOTH ends inside the 4 mm contact
## shell. Measured: it is a segment counter times a constant (0.85-0.90 rad
## per segment at r=0.20, 1.47-1.55 at r=0.10), and that count swings by +-3
## on a rope that never leaves the beam.
##
## CANDIDATE (th_c): the winding of the chain BETWEEN its first and its last
## vertex inside the SAME 4 mm shell. Identical contact evidence, no widened
## tolerance - but it does not collapse when an intermediate vertex lifts off
## by a millimetre, because only the two ends of the wrapped stretch matter.
## A straight chain across a beam still scores ~0 (one contact vertex).
##
## The test that matters: sweep the threshold on th_c and find the value at
## which the set of throws that can EVER catch is exactly the shipped set.
## That is a like-for-like swap - no throw gains a catch, none loses one.

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

## winding of the chain between its first and last vertex inside the SAME
## contact shell a_theta uses. No widened tolerance.
func _thc(m: Node2D) -> float:
	var ctr: Vector2 = m.a_pos[0]
	var R: float = m.a_r[0]
	var lo := -1
	var hi := -1
	for i in m.NP:
		if (m.pos[i] - ctr).length() < R + m.p_rad[i] + m.wrap_shell:
			if lo < 0:
				lo = i
			hi = i
	if lo < 0 or hi <= lo:
		return 0.0
	var w := 0.0
	for i in range(lo, hi):
		w += (m.pos[i] - ctr).angle_to(m.pos[i + 1] - ctr)
	return absf(w)

func _ms(t: int) -> int:
	return int(round(t * 1000.0 / 60.0))

func _initialize() -> void:
	var cfgs := []
	for r in [0.22, 0.20, 0.11, 0.10]:
		for dy in [2.0, 2.2, 2.4, 2.6]:
			for dx in [1.4, 1.7, 2.0, 2.3, 2.6]:
				for a1 in [-0.42, -0.34, -0.22]:
					cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI, 9, true])
	var data := []
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		var th := PackedFloat32Array()
		var thc := PackedFloat32Array()
		var lidx := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			th.append(absf(m.a_theta[0]))
			thc.append(_thc(m))
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
		var tp_: float = m.th_part
		m.free()
		data.append({"th": th, "thc": thc, "lidx": lidx, "hook": t_hook,
			"part": tp_, "r": c[2]})
	# shipped acceptance
	var accept_old := []
	var n_old := 0
	for d in data:
		var th: PackedFloat32Array = d["th"]
		var lidx: PackedInt32Array = d["lidx"]
		var ok := false
		for t in RUN:
			if th[t] >= float(d["part"]) and lidx[t] == 1:
				ok = true
				break
		accept_old.append(ok)
		if ok:
			n_old += 1
	print("shipped rule accepts %d of %d throws" % [n_old, data.size()])
	print("")
	print("threshold on th_c | accepted | gained | lost | dead ticks | NOTHING at hook+RT")
	print("      rad         |          |        |      |            | 150 200 250 300 ms")
	for xi in range(0, 26):
		var X: float = 3.0 + xi * 0.2
		var acc := 0
		var gained := 0
		var lost := 0
		var deadt := 0
		var rtb := [0, 0, 0, 0]
		var nc := 0
		for di in data.size():
			var d: Dictionary = data[di]
			var thc: PackedFloat32Array = d["thc"]
			var lidx: PackedInt32Array = d["lidx"]
			var qual := PackedInt32Array(); qual.resize(RUN)
			var ok := false
			for t in RUN:
				qual[t] = 1 if (thc[t] >= X and lidx[t] == 1) else 0
				if qual[t] == 1:
					ok = true
			if ok:
				acc += 1
			if ok and not accept_old[di]:
				gained += 1
			if accept_old[di] and not ok:
				lost += 1
			if not ok or int(d["hook"]) < 0:
				continue
			nc += 1
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
			for t in range(f, l + 1):
				if cs[t] == 0:
					deadt += 1
			for ri in range(4):
				var tp2: int = int(d["hook"]) + [9, 12, 15, 18][ri]
				if tp2 < RUN and cs[tp2] == 0:
					rtb[ri] += 1
		print("     %5.2f        |   %4d   |  %4d  | %4d |    %5d   | %3d %3d %3d %3d"
			% [X, acc, gained, lost, deadt, rtb[0], rtb[1], rtb[2], rtb[3]])
	quit(0)
