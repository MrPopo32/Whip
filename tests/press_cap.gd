extends SceneTree
## Two loose ends.
## (1) Does the backward reach have to be capped at 250 ms? The honesty guard
##     is the VOID rule (the latch dies the moment the wrap would have
##     released), not the cap. Sweep the cap, audit what each one lets in.
## (2) Verify the anticipation ceiling directly: press early and HOLD, real
##     gripped runs, no mask arithmetic.

const RUN := 210
const GW := 15

func _rig(dx: float, dy: float, r: float, src: String) -> Node2D:
	var m: Node2D = load(src).new()
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

func _ms(t: int) -> int:
	return int(round(t * 1000.0 / 60.0))

func _initialize() -> void:
	# ---------- (2) anticipation ceiling, real gripped runs ----------
	print("ANTICIPATION CEILING - press at tick P and HOLD the button down.")
	print("(the wrap on this throw first qualifies at tick 107)")
	var cc := [2.0, 2.2, 0.20, 0.85 * PI, -0.42 * PI, 9, true]
	for P in [0, 30, 60, 80, 88, 90, 92, 93, 95, 100]:
		var m := _rig(cc[0], cc[1], cc[2], "res://main.gd")
		var eng := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, cc), t >= P)
			if eng < 0 and m.a_freelen[0] >= 0.0:
				eng = t
		m.free()
		print("  press at %3d, held for the whole throw -> %s"
			% [P, ("caught at tick %d" % eng) if eng >= 0 else "NOTHING, ever"])
	# ---------- (1) how far back may the look reach ----------
	var cfgs := []
	for r in [0.22, 0.20, 0.11, 0.10]:
		for dy in [2.0, 2.2, 2.4, 2.6]:
			for dx in [1.4, 1.7, 2.0, 2.3, 2.6]:
				for a1 in [-0.42, -0.34, -0.22]:
					cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI, 9, true])
	var caps := [0, 15, 30, 45, 90]
	var nv := caps.size()
	var dead := []
	var holed := []
	var mxh := []
	var rtb := []
	var newn := []
	var newspan := []
	var newmin := []
	for i in nv:
		dead.append(0); holed.append(0); mxh.append(0)
		rtb.append([0, 0, 0, 0]); newn.append(0); newspan.append(0)
		newmin.append(99.0)
	var nhook := 0
	var part := 0.0
	var th_rel := 0.0
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2], "res://main.gd")
		part = m.th_part
		th_rel = m.th_rel
		var th := PackedFloat32Array()
		var lidx := PackedInt32Array()
		var pin := PackedInt32Array()
		var span := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			th.append(absf(m.a_theta[0]))
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
			span.append(1 if (lft and rgt) else 0)
			if t_hook < 0 and n >= 3 and lft and rgt:
				t_hook = t
		m.free()
		var qual := PackedInt32Array(); qual.resize(RUN)
		var any := false
		for t in RUN:
			qual[t] = 1 if (th[t] >= part and lidx[t] == 1) else 0
			if qual[t] == 1:
				any = true
		if not any or t_hook < 0:
			continue
		nhook += 1
		var base := PackedInt32Array(); base.resize(RUN)
		for tp in RUN:
			var o := 0
			for u in range(tp, mini(tp + GW, RUN)):
				if qual[u] == 1:
					o = 1
					break
			base[tp] = o
		for vi in nv:
			var cap: int = caps[vi]
			var cs := PackedInt32Array(); cs.resize(RUN)
			var qlast := -999
			for tp in RUN:
				if th[tp] < th_rel and pin[tp] == 0:
					qlast = -999
				if qual[tp] == 1:
					qlast = tp
				var b: int = 1 if (cap > 0 and qlast >= 0 and tp - qlast <= cap
					and lidx[tp] == 1) else 0
				cs[tp] = 1 if (base[tp] == 1 or b == 1) else 0
				if cs[tp] == 1 and base[tp] == 0:
					newn[vi] += 1
					newmin[vi] = minf(newmin[vi], th[tp])
					if span[tp] == 0:
						newspan[vi] += 1
			var f := -1
			var l := -1
			for t in RUN:
				if cs[t] == 1:
					if f < 0: f = t
					l = t
			var runh := 0
			for t in range(f, l + 1):
				if cs[t] == 0:
					dead[vi] += 1; runh += 1
					mxh[vi] = maxi(mxh[vi], runh)
				else:
					runh = 0
			var hd := false
			for t in range(f, l + 1):
				if cs[t] == 0:
					hd = true
					break
			if hd:
				holed[vi] += 1
			for ri in 4:
				var tp2: int = t_hook + [9, 12, 15, 18][ri]
				if tp2 < RUN and cs[tp2] == 0:
					rtb[vi][ri] += 1
	print("")
	print("HOW FAR BACK MAY THE WINDOW LOOK? (void rule fixed: the latch dies")
	print("the moment the wrap would have released). %d throws." % nhook)
	print("")
	print("back  dead  holed  longest | NOTHING at hook+RT   | newly allowed presses")
	print(" ms  ticks         dead ms | 150 200 250 300 ms   | count  lowest theta  rope one side")
	for vi in nv:
		print("%4d %5d %6d %8d | %3d %3d %3d %3d   | %5d %11.2f %11d"
			% [_ms(caps[vi]), dead[vi], holed[vi], _ms(mxh[vi]),
			rtb[vi][0], rtb[vi][1], rtb[vi][2], rtb[vi][3],
			newn[vi], (newmin[vi] if newn[vi] > 0 else 0.0), newspan[vi]])
	print("")
	print("NOTHING as %% of %d throws:" % nhook)
	for vi in nv:
		print("  back %4d ms:  %2.0f%%  %2.0f%%  %2.0f%%  %2.0f%%"
			% [_ms(caps[vi]), 100.0 * rtb[vi][0] / nhook, 100.0 * rtb[vi][1] / nhook,
			100.0 * rtb[vi][2] / nhook, 100.0 * rtb[vi][3] / nhook])
	quit(0)
