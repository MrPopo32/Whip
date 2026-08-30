extends SceneTree
## FOUR RULES, ONE CORPUS, ONE ACCEPTANCE TEST.
## Hard filter: a rule may not make ANY throw catchable that the shipped rule
## refuses. Anything that gains a throw is rejected outright, whatever it does
## for the false negatives.
##   A  shipped: instantaneous a_theta >= th_part, forward-only 250 ms window
##   B  A + the window also looks 250 ms BACK, voided the moment the wrap
##      would have released (th < th_rel with no self-pinch)
##   C  contact-span measure th_c in the catch gate, SAME th_part, same window
##   D  C + B
## th_c = winding of the chain between its FIRST and LAST vertex inside the
## same 4 mm contact shell a_theta already uses. Same evidence, same threshold.

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

func _eval(d: Dictionary, use_c: bool, back: bool, part: float,
		th_rel: float) -> Dictionary:
	var src: PackedFloat32Array = d["thc"] if use_c else d["th"]
	var lidx: PackedInt32Array = d["lidx"]
	var pin: PackedInt32Array = d["pin"]
	var qual := PackedInt32Array(); qual.resize(RUN)
	var ok := false
	for t in RUN:
		qual[t] = 1 if (src[t] >= part and lidx[t] == 1) else 0
		if qual[t] == 1:
			ok = true
	if not ok:
		return {"ok": false}
	var cs := PackedInt32Array(); cs.resize(RUN)
	var qlast := -999
	for tp in RUN:
		var o := 0
		for u in range(tp, mini(tp + GW, RUN)):
			if qual[u] == 1:
				o = 1
				break
		if src[tp] < th_rel and pin[tp] == 0:
			qlast = -999
		if qual[tp] == 1:
			qlast = tp
		var b: int = 1 if (back and qlast >= 0 and tp - qlast <= GW
			and lidx[tp] == 1) else 0
		cs[tp] = 1 if (o == 1 or b == 1) else 0
	var f := -1
	var l := -1
	for t in RUN:
		if cs[t] == 1:
			if f < 0: f = t
			l = t
	var dead := 0
	var runh := 0
	var mx := 0
	for t in range(f, l + 1):
		if cs[t] == 0:
			dead += 1; runh += 1; mx = maxi(mx, runh)
		else:
			runh = 0
	return {"ok": true, "cs": cs, "dead": dead, "max": mx, "f": f, "l": l}

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
		var thc := PackedFloat32Array()
		var lidx := PackedInt32Array()
		var pin := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			th.append(absf(m.a_theta[0]))
			thc.append(_thc(m))
			lidx.append(1 if m.a_lockidx[0] >= m.pin_min_idx else 0)
			pin.append(1 if m._pinch(0) else 0)
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
		data.append({"th": th, "thc": thc, "lidx": lidx, "pin": pin, "hook": t_hook})
	var names := ["A shipped", "B window looks back", "C span measure",
		"D span measure + look back"]
	var usec := [false, false, true, true]
	var uback := [false, true, false, true]
	var acc := [0, 0, 0, 0]
	var dead := [0, 0, 0, 0]
	var holed := [0, 0, 0, 0]
	var mx := [0, 0, 0, 0]
	var rtb := [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
	var gained := [0, 0, 0, 0]
	var lost := [0, 0, 0, 0]
	var nhook := 0
	var base_ok := []
	for di in data.size():
		var a := _eval(data[di], false, false, part, th_rel)
		base_ok.append(bool(a["ok"]))
	for di in data.size():
		var d: Dictionary = data[di]
		var counted: bool = int(d["hook"]) >= 0 and bool(base_ok[di])
		if counted:
			nhook += 1
		for vi in 4:
			var r := _eval(d, usec[vi], uback[vi], part, th_rel)
			if not bool(r["ok"]):
				if base_ok[di]:
					lost[vi] += 1
				continue
			acc[vi] += 1
			if not base_ok[di]:
				gained[vi] += 1
				continue
			if not counted:
				continue
			dead[vi] += int(r["dead"])
			if int(r["dead"]) > 0:
				holed[vi] += 1
			mx[vi] = maxi(mx[vi], int(r["max"]))
			var cs: PackedInt32Array = r["cs"]
			for ri in 4:
				var tp2: int = int(d["hook"]) + [9, 12, 15, 18][ri]
				if tp2 < RUN and cs[tp2] == 0:
					rtb[vi][ri] += 1
	print("corpus %d throws; shipped rule accepts %d; %d of those have a visible hook"
		% [data.size(), acc[0], nhook])
	print("")
	print("rule                         accepts gained lost | dead  holed longest | NOTHING at hook+reaction")
	print("                                                 | ticks       dead ms | 150ms 200ms 250ms 300ms")
	for vi in 4:
		print("%-28s %5d %6d %4d | %5d %5d %8d | %4d  %4d  %4d  %4d"
			% [names[vi], acc[vi], gained[vi], lost[vi], dead[vi], holed[vi],
			_ms(mx[vi]), rtb[vi][0], rtb[vi][1], rtb[vi][2], rtb[vi][3]])
	print("")
	print("NOTHING as %% of the %d throws that can be caught and are visible:" % nhook)
	for vi in 4:
		print("%-28s  %2.0f%%   %2.0f%%   %2.0f%%   %2.0f%%"
			% [names[vi], 100.0 * rtb[vi][0] / nhook, 100.0 * rtb[vi][1] / nhook,
			100.0 * rtb[vi][2] / nhook, 100.0 * rtb[vi][3] / nhook])
	# show the mechanism on the throw the report quotes
	print("")
	print("MECHANISM, school beam med r=0.20 at (2.0,-2.2), ticks 106-140:")
	var m2 := _rig(2.0, 2.2, 0.20)
	var cc := [2.0, 2.2, 0.20, 0.85 * PI, -0.42 * PI, 9, true]
	var s1 := ""
	var s2 := ""
	for t in 141:
		m2.step_tick(_tgt(m2, t, cc), false)
		if t < 106:
			continue
		s1 += "%.1f " % absf(m2.a_theta[0])
		s2 += "%.1f " % _thc(m2)
	print("  a_theta: ", s1)
	print("  th_c   : ", s2)
	m2.free()
	quit(0)
