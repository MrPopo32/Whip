extends SceneTree
## Is wrap_shell (4 mm) finer than the standoff the solver actually leaves?
## Measured: wraps with 11-16 chain vertices lying within 15 mm of the beam,
## straddling it, with 3-5 rad of real winding, score a_theta = 0.01 rad.
##
## wrap_shell only enters the MEASUREMENT, never the physics, so one ungripped
## run per throw can be scored at every candidate shell width. The structural
## defence against a fold - a segment needs BOTH ends in the shell - is kept
## exactly as it is at every width.
##
## HARD ACCEPTANCE TEST: a width may not make a single throw catchable that the
## shipped rule refuses. gained must be 0.

const RUN := 210
const GW := 15
const SHELLS := [0.004, 0.006, 0.008, 0.010, 0.012, 0.015, 0.020, 0.030, 0.050]

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

## exactly _measure_wraps, with the shell as a parameter
func _theta(m: Node2D, shell: float) -> float:
	var ctr: Vector2 = m.a_pos[0]
	var R: float = m.a_r[0]
	var band: float = R + 0.35
	var th := 0.0
	for i in range(m.NP - 1):
		var v0: Vector2 = m.pos[i] - ctr
		var v1: Vector2 = m.pos[i + 1] - ctr
		var d0: float = v0.length()
		var d1: float = v1.length()
		if d0 < band and d1 < band:
			if d0 < R + m.p_rad[i] + shell and d1 < R + m.p_rad[i + 1] + shell:
				th += v0.angle_to(v1)
	return absf(th)

func _initialize() -> void:
	var cfgs := []
	for r in [0.22, 0.20, 0.11, 0.10]:
		for dy in [2.0, 2.2, 2.4, 2.6]:
			for dx in [1.4, 1.7, 2.0, 2.3, 2.6]:
				for a1 in [-0.42, -0.34, -0.22]:
					cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI, 9, true])
	var ns := SHELLS.size()
	var data := []
	var part := 0.0
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		part = m.th_part
		var rows := []
		for si in ns:
			rows.append(PackedFloat32Array())
		var lidx := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			for si in ns:
				rows[si].append(_theta(m, SHELLS[si]))
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
		data.append({"rows": rows, "lidx": lidx, "hook": t_hook})
	# shipped acceptance (shell index 0)
	var base_ok := []
	for d in data:
		var rows: Array = d["rows"]
		var th: PackedFloat32Array = rows[0]
		var lidx: PackedInt32Array = d["lidx"]
		var ok := false
		for t in RUN:
			if th[t] >= part and lidx[t] == 1:
				ok = true
				break
		base_ok.append(ok)
	var nbase := 0
	for b in base_ok:
		if b:
			nbase += 1
	print("shipped shell 4 mm accepts %d of %d throws. th_part unchanged at %.2f rad."
		% [nbase, data.size(), part])
	print("")
	print("shell  accepts gained lost | dead  holed longest | NOTHING at hook+reaction")
	print(" mm                        | ticks       dead ms | 150ms 200ms 250ms 300ms")
	for si in ns:
		var acc := 0
		var gained := 0
		var lost := 0
		var deadt := 0
		var holed := 0
		var mxh := 0
		var rtb := [0, 0, 0, 0]
		var nh := 0
		for di in data.size():
			var d: Dictionary = data[di]
			var rows: Array = d["rows"]
			var th: PackedFloat32Array = rows[si]
			var lidx: PackedInt32Array = d["lidx"]
			var qual := PackedInt32Array(); qual.resize(RUN)
			var ok := false
			for t in RUN:
				qual[t] = 1 if (th[t] >= part and lidx[t] == 1) else 0
				if qual[t] == 1:
					ok = true
			if ok:
				acc += 1
			if ok and not bool(base_ok[di]):
				gained += 1
			if bool(base_ok[di]) and not ok:
				lost += 1
			if not ok or not bool(base_ok[di]) or int(d["hook"]) < 0:
				continue
			nh += 1
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
			var runh := 0
			var hd := false
			for t in range(f, l + 1):
				if cs[t] == 0:
					deadt += 1; runh += 1; hd = true
					mxh = maxi(mxh, runh)
				else:
					runh = 0
			if hd:
				holed += 1
			for ri in 4:
				var tp2: int = int(d["hook"]) + [9, 12, 15, 18][ri]
				if tp2 < RUN and cs[tp2] == 0:
					rtb[ri] += 1
		print("%5.1f  %6d %6d %4d | %5d %5d %8d |  %3d   %3d   %3d   %3d"
			% [SHELLS[si] * 1000.0, acc, gained, lost, deadt, holed,
			int(round(mxh * 1000.0 / 60.0)), rtb[0], rtb[1], rtb[2], rtb[3]])
	quit(0)
