extends SceneTree
## The catch gate refuses wraps that have ALREADY CROSSED THEMSELVES.
## Measured in tests/press_late.gd: presses that failed "too late" while
## _pinch() was TRUE and a_theta read 0.14 and 1.64 rad.
##
## _pinch() is the code's own definition of a wrap that can hold - "the only
## thing that can physically hold a body on a beam" - and it is the sole
## criterion for LOCKED. It is far stricter evidence than th_part: it needs an
## actual self-crossing within PINCH_RAD of the beam with 0.75 turns of chain
## between the two strands. Letting it also satisfy the CATCH gate raises the
## evidence bar, it does not lower it.
##
##   A  shipped
##   B  A + window looks back 250 ms
##   E  A + a self-crossing at the beam also qualifies
##   F  E + window looks back 250 ms
## Reported for every rule: throws it newly accepts, and how many of those had
## a genuine self-crossing (i.e. were refused a catch while physically locked).

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
	var data := []
	var part := 0.0
	var th_rel := 0.0
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		part = m.th_part
		th_rel = m.th_rel
		var th := PackedFloat32Array()
		var pin := PackedInt32Array()
		var lidx := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			th.append(absf(m.a_theta[0]))
			pin.append(1 if m._pinch(0) else 0)
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
		m.free()
		data.append({"th": th, "pin": pin, "lidx": lidx, "hook": t_hook})
	var names := ["A shipped", "B look back", "E self-crossing qualifies",
		"F self-crossing + look back"]
	var upin := [false, false, true, true]
	var uback := [false, true, false, true]
	var acc := [0, 0, 0, 0]
	var gained := [0, 0, 0, 0]
	var gained_pin := [0, 0, 0, 0]
	var dead := [0, 0, 0, 0]
	var holed := [0, 0, 0, 0]
	var mxh := [0, 0, 0, 0]
	var rtb := [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
	var base_ok := []
	var nh := 0
	for d in data:
		var th: PackedFloat32Array = d["th"]
		var lidx: PackedInt32Array = d["lidx"]
		var ok := false
		for t in RUN:
			if th[t] >= part and lidx[t] == 1:
				ok = true
				break
		base_ok.append(ok)
	for di in data.size():
		var d: Dictionary = data[di]
		var th: PackedFloat32Array = d["th"]
		var pin: PackedInt32Array = d["pin"]
		var lidx: PackedInt32Array = d["lidx"]
		if bool(base_ok[di]) and int(d["hook"]) >= 0:
			nh += 1
		for vi in 4:
			var qual := PackedInt32Array(); qual.resize(RUN)
			var ok := false
			for t in RUN:
				var q: bool = (th[t] >= part or (upin[vi] and pin[t] == 1)) \
					and lidx[t] == 1
				qual[t] = 1 if q else 0
				if q:
					ok = true
			if not ok:
				continue
			acc[vi] += 1
			if not bool(base_ok[di]):
				gained[vi] += 1
				var anyp := false
				for t in RUN:
					if pin[t] == 1:
						anyp = true
						break
				if anyp:
					gained_pin[vi] += 1
				continue
			if int(d["hook"]) < 0:
				continue
			var cs := PackedInt32Array(); cs.resize(RUN)
			var qlast := -999
			for tp in RUN:
				var o := 0
				for u in range(tp, mini(tp + GW, RUN)):
					if qual[u] == 1:
						o = 1
						break
				if th[tp] < th_rel and pin[tp] == 0:
					qlast = -999
				if qual[tp] == 1:
					qlast = tp
				var b: int = 1 if (uback[vi] and qlast >= 0 and tp - qlast <= GW
					and lidx[tp] == 1) else 0
				cs[tp] = 1 if (o == 1 or b == 1) else 0
			var f := -1
			var l := -1
			for t in RUN:
				if cs[t] == 1:
					if f < 0: f = t
					l = t
			var runh := 0
			var hd := false
			for t in range(f, l + 1):
				if cs[t] == 0:
					dead[vi] += 1; runh += 1; hd = true
					mxh[vi] = maxi(mxh[vi], runh)
				else:
					runh = 0
			if hd:
				holed[vi] += 1
			for ri in 4:
				var tp2: int = int(d["hook"]) + [9, 12, 15, 18][ri]
				if tp2 < RUN and cs[tp2] == 0:
					rtb[vi][ri] += 1
	print("240 throws; shipped accepts %d; %d of those are visible" % [acc[0], nh])
	print("")
	print("rule                          accepts gained (of which | dead  holed longest | NOTHING at hook+reaction")
	print("                                       had a real self-| ticks       dead ms | 150   200   250   300 ms")
	print("                                       crossing)       |")
	for vi in 4:
		print("%-29s %5d %6d %8d      | %5d %5d %8d | %3d   %3d   %3d   %3d"
			% [names[vi], acc[vi], gained[vi], gained_pin[vi], dead[vi], holed[vi],
			int(round(mxh[vi] * 1000.0 / 60.0)),
			rtb[vi][0], rtb[vi][1], rtb[vi][2], rtb[vi][3]])
	print("")
	print("NOTHING as %% of the %d visible catchable throws:" % nh)
	for vi in 4:
		print("%-29s  %2.0f%%   %2.0f%%   %2.0f%%   %2.0f%%"
			% [names[vi], 100.0 * rtb[vi][0] / nh, 100.0 * rtb[vi][1] / nh,
			100.0 * rtb[vi][2] / nh, 100.0 * rtb[vi][3] / nh])
	quit(0)
