extends SceneTree
## WHICH RULE ACTUALLY CLOSES THE DEAD PRESSES, AND WHAT DOES IT LET IN?
##
## One ungripped baseline per throw records everything every candidate rule
## reads. Rules are then evaluated exactly (the predictor was verified
## tick-for-tick against real gripped re-runs in tests/press_sweep.gd).
##
## TRUTH MEASURE for the audit, independent of the shipped one:
##   th_hug = winding of the maximal CONTIGUOUS run of chain that hugs the
##   beam within HUG of the surface. Unlike a_theta it does not care which
##   layer a strand rides on, and unlike a raw band sum it cannot pick up a
##   straight chain passing nearby, because the run has to stay in contact.
## Every rule is audited on the press ticks it newly allows: what was the rope
## really doing at that instant?

const RUN := 210
const GW := 15
const HUG := 0.08

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

func _hug(m: Node2D) -> float:
	var ctr: Vector2 = m.a_pos[0]
	var R: float = m.a_r[0]
	var i0 := -1
	var best := 1e9
	for i in m.NP:
		var d: float = (m.pos[i] - ctr).length() - R - m.p_rad[i]
		if d < best:
			best = d
			i0 = i
	if best > HUG:
		return 0.0
	var lo := i0
	var hi := i0
	while lo > 0 and (m.pos[lo - 1] - ctr).length() - R - m.p_rad[lo - 1] < HUG:
		lo -= 1
	while hi < m.NP - 1 and (m.pos[hi + 1] - ctr).length() - R - m.p_rad[hi + 1] < HUG:
		hi += 1
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
	# names, backward cap in ticks, void rule: 0 = th<th_rel & no pinch, 1 = contact lost
	var variants := [
		["shipped (forward only)", 0, 0],
		["symmetric +-250 ms", GW, 0],
		["back 250 ms, void on contact loss", GW, 1],
		["back 500 ms, void on contact loss", 30, 1],
		["back 1000 ms, void on contact loss", 60, 1],
	]
	var nv := variants.size()
	var dead := []
	var holed := []
	var maxhole := []
	var rt_bad := []
	var newmin_hug := []
	var newmin_touch := []
	var new_span_bad := []
	var new_count := []
	for v in nv:
		dead.append(0); holed.append(0); maxhole.append(0)
		rt_bad.append([0, 0, 0, 0])
		newmin_hug.append(99.0); newmin_touch.append(99); new_span_bad.append(0)
		new_count.append(0)
	var n_ok := 0
	var n_bad_throw := 0
	var bad_maxhug := []
	var bad_maxth := []
	var good_hug_at_q0 := []
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		var th := PackedFloat32Array()
		var hug := PackedFloat32Array()
		var qual := PackedInt32Array()
		var pin := PackedInt32Array()
		var lidx := PackedInt32Array()
		var touch := PackedInt32Array()
		var span := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			var x: float = absf(m.a_theta[0])
			th.append(x)
			hug.append(_hug(m))
			qual.append(1 if (x >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx) else 0)
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
			touch.append(n)
			span.append(1 if (lft and rgt) else 0)
			if t_hook < 0 and n >= 3 and lft and rgt:
				t_hook = t
		var th_rel: float = m.th_rel
		m.free()
		var anyq := false
		var q0 := -1
		for t in RUN:
			if qual[t] == 1:
				anyq = true
				q0 = t
				break
		if not anyq:
			n_bad_throw += 1
			var mh := 0.0
			var mt := 0.0
			for t in RUN:
				mh = maxf(mh, hug[t])
				mt = maxf(mt, th[t])
			bad_maxhug.append(mh)
			bad_maxth.append(mt)
			continue
		if t_hook < 0:
			continue
		n_ok += 1
		good_hug_at_q0.append(hug[q0])
		# shipped catch set (also the reference for "newly allowed")
		var base := PackedInt32Array(); base.resize(RUN)
		for tp in RUN:
			var o := 0
			for u in range(tp, mini(tp + GW, RUN)):
				if qual[u] == 1:
					o = 1
					break
			base[tp] = o
		for vi in nv:
			var cap: int = variants[vi][1]
			var vrule: int = variants[vi][2]
			var cs := PackedInt32Array(); cs.resize(RUN)
			var qlast := -999
			for tp in RUN:
				var voided: bool = (th[tp] < th_rel and pin[tp] == 0) if vrule == 0 \
					else (touch[tp] == 0)
				if voided:
					qlast = -999
				if qual[tp] == 1:
					qlast = tp
				var back: int = 1 if (cap > 0 and qlast >= 0 and tp - qlast <= cap
					and lidx[tp] == 1) else 0
				cs[tp] = 1 if (base[tp] == 1 or back == 1) else 0
				if cs[tp] == 1 and base[tp] == 0:
					new_count[vi] += 1
					newmin_hug[vi] = minf(newmin_hug[vi], hug[tp])
					newmin_touch[vi] = mini(newmin_touch[vi], touch[tp])
					if span[tp] == 0:
						new_span_bad[vi] += 1
			var f := -1
			var l := -1
			for t in RUN:
				if cs[t] == 1:
					if f < 0: f = t
					l = t
			var h := 0
			var runh := 0
			for t in range(f, l + 1):
				if cs[t] == 0:
					h += 1; runh += 1
					maxhole[vi] = maxi(maxhole[vi], runh)
				else:
					runh = 0
			dead[vi] += h
			if h > 0:
				holed[vi] += 1
			for ri in range(4):
				var tp2: int = t_hook + [9, 12, 15, 18][ri]
				if tp2 < RUN and cs[tp2] == 0:
					rt_bad[vi][ri] += 1
	print("corpus: %d catchable throws, %d throws that can never catch" % [n_ok, n_bad_throw])
	print("")
	print("rule                                 dead   throws  longest | NOTHING at hook+RT")
	print("                                    ticks    holed  dead ms | 150  200  250  300 ms")
	for vi in nv:
		print("%-34s %5d    %5d %8d | %3d  %3d  %3d  %3d"
			% [variants[vi][0], dead[vi], holed[vi], _ms(maxhole[vi]),
			rt_bad[vi][0], rt_bad[vi][1], rt_bad[vi][2], rt_bad[vi][3]])
	print("")
	print("NOTHING rates as %% of %d catchable throws:" % n_ok)
	for vi in nv:
		print("%-34s  %2.0f%%  %2.0f%%  %2.0f%%  %2.0f%%"
			% [variants[vi][0],
			100.0 * rt_bad[vi][0] / n_ok, 100.0 * rt_bad[vi][1] / n_ok,
			100.0 * rt_bad[vi][2] / n_ok, 100.0 * rt_bad[vi][3] / n_ok])
	print("")
	print("AUDIT - what is the rope doing at the press ticks each rule NEWLY allows?")
	print("rule                                newly   min true   min pts   presses with")
	print("                                  allowed   wrap rad  touching   rope on ONE side")
	for vi in nv:
		if new_count[vi] == 0:
			print("%-34s        0         -         -        -" % variants[vi][0])
			continue
		print("%-34s %8d %10.2f %9d %8d"
			% [variants[vi][0], new_count[vi], newmin_hug[vi], newmin_touch[vi],
			new_span_bad[vi]])
	print("")
	bad_maxhug.sort()
	bad_maxth.sort()
	good_hug_at_q0.sort()
	print("TRUTH-MEASURE SANITY (th_hug, hug band %.0f mm):" % (HUG * 1000.0))
	print("  throws the shipped rule refuses: PEAK true wrap  min %.2f  median %.2f  max %.2f rad"
		% [bad_maxhug[0], bad_maxhug[bad_maxhug.size() / 2], bad_maxhug[-1]])
	print("  (their peak a_theta:             min %.2f  median %.2f  max %.2f rad)"
		% [bad_maxth[0], bad_maxth[bad_maxth.size() / 2], bad_maxth[-1]])
	print("  throws it accepts: true wrap AT the qualifying tick  min %.2f  median %.2f rad"
		% [good_hug_at_q0[0], good_hug_at_q0[good_hug_at_q0.size() / 2]])
	quit(0)
