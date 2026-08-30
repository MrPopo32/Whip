extends SceneTree
## THE PROOF, END TO END.
##
## The offline sweep scored candidates on trajectories where the grip is never
## closed, so nothing engages and the physics is identical for every candidate.
## That is the right way to SEARCH, but it is not proof about the shipped loop:
## the moment a catch fires the trajectory diverges.  So this runs the patched
## build for real - hand closing, wraps engaging, bodies hanging - and audits
## every tick against the oracle on the build's OWN trajectories.
##
##   FALSE POSITIVE  a catch engaged on a tick the oracle calls NOT wrapped.
##   FALSE NEGATIVE  the oracle calls the rope wrapped, the press is live
##                   (hand closed within GRIP_WINDOW, anchor armed, nothing
##                   engaged, a lock index exists) and no catch fired.
##
## Four press times per throw, so the audit covers early, on-time and late
## presses rather than one lucky instant.

const ORC := preload("res://tests/orc_lib.gd")
const RUN := 210
const BUILD := "res://tests/main_wrap.gd"

func _rig(dx: float, dy: float, r: float) -> Node2D:
	var m: Node2D = load(BUILD).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in range(m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -dy)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R)
	m.body_prv = m.body_pos
	for i in range(m.pos.size()):
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

var fp := 0
var fn := 0
var fp_ex: Array = []
var fn_ex: Array = []
var theta_err := 0.0
var caught := 0
var pressed := 0
var dead_by_rt := [0, 0, 0, 0]
var phantom_by_rt := [0, 0, 0, 0]
var n_by_rt := [0, 0, 0, 0]

func _one(c: Array, press: int, ri: int, count_press: bool) -> void:
	var m := _rig(c[0], c[1], c[2])
	var cen: Vector2 = m.a_pos[0]
	var r: float = m.a_r[0]
	var was_eng := false
	var got := false
	var phantom := false
	for t in range(RUN):
		var grip: bool = t >= press
		m.step_tick(_tgt(m, t, c), grip)
		var mm: Dictionary = ORC.measure(m.pos, m.p_rad, cen, r)
		var pin: bool = m._pinch(0)
		var wrapped: bool = (float(mm["A"]) >= m.th_part and bool(mm["near"])) or pin
		# 1. the measurement itself must BE the oracle quantity
		var want: float = (float(mm["A"]) if float(mm["mind"]) < r + m.wrap_near
			else 0.0)
		theta_err = maxf(theta_err, absf(absf(m.a_theta[0]) - want))
		var eng: bool = m.a_freelen[0] >= 0.0
		# 2. false positive: it engaged on a tick that is not wrapped
		if eng and not was_eng:
			got = true
			if not wrapped:
				phantom = true
				fp += 1
				if fp_ex.size() < 4:
					fp_ex.append([c[2], c[0], c[1], t, mm["A"], pin])
		# 3. false negative: the press was live on a wrapped tick and nothing
		#    took. a_armed and the grip window are input rules, not measurement
		#    rules, so a tick only counts if the press really was live.
		if (not eng) and (not was_eng) and wrapped and m.taut \
				and m.tick_count - m.grip_edge <= m.GRIP_WINDOW \
				and m.a_armed[0] == 1 and m.a_lockidx[0] >= m.pin_min_idx:
			fn += 1
			if fn_ex.size() < 4:
				fn_ex.append([c[2], c[0], c[1], t, mm["A"], pin])
		was_eng = eng
	m.free()
	if got:
		caught += 1
	pressed += 1
	if count_press:
		n_by_rt[ri] += 1
		if not got:
			dead_by_rt[ri] += 1
		if phantom:
			phantom_by_rt[ri] += 1

func _initialize() -> void:
	var cfgs := []
	for r in [0.10, 0.11, 0.14, 0.16, 0.20, 0.24]:
		for dy in [2.0, 2.2, 2.4]:
			for dx in [1.5, 1.8, 2.1, 2.4]:
				for a1 in [-0.34, -0.26]:
					for hold in [9, 14]:
						for fl in [true, false]:
							cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI, hold, fl])
	var t0 := Time.get_ticks_msec()
	# pass 1: find the visible cue and whether the throw ever wraps at all,
	# with the hand open (this is the open-loop trajectory)
	var cue := PackedInt32Array()
	var hook := PackedInt32Array()
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		var cen: Vector2 = m.a_pos[0]
		var r: float = m.a_r[0]
		var cu := -1
		var hk := 0
		for t in range(RUN):
			m.step_tick(_tgt(m, t, c), false)
			var mm: Dictionary = ORC.measure(m.pos, m.p_rad, cen, r)
			if cu < 0 and int(mm["nc15"]) >= 3 and bool(mm["straddle"]):
				cu = t
			if (float(mm["A"]) >= m.th_part and bool(mm["near"])) or m._pinch(0):
				hk = 1
		m.free()
		cue.append(cu)
		hook.append(hk)
	print("pass 1 done (%.0f s): %d of %d throws ever wrap"
		% [(Time.get_ticks_msec() - t0) / 1000.0, hook.count(1), cfgs.size()])

	# pass 2: press for real, four reaction times
	for ci in range(cfgs.size()):
		var c: Array = cfgs[ci]
		for ri in range(4):
			var rt: int = [9, 12, 15, 18][ri]
			var p: int = (cue[ci] + rt) if cue[ci] >= 0 else (40 + 15 * ri)
			if p >= RUN:
				continue
			_one(c, p, ri, cue[ci] >= 0 and hook[ci] == 1)
		if ci % 96 == 0:
			print("  ... %d/%d  (%.0f s)"
				% [ci, cfgs.size(), (Time.get_ticks_msec() - t0) / 1000.0])

	print("")
	print("=================================================================")
	print("CLOSED-LOOP AUDIT of %s" % BUILD)
	print("  runs audited                                   %d" % pressed)
	print("  ticks audited                                  %d" % (pressed * RUN))
	print("")
	print("  worst disagreement between the build's a_theta")
	print("  and the oracle's taut wrap angle               %.9f rad" % theta_err)
	print("")
	print("  FALSE POSITIVES  (a catch fired on a rope the")
	print("                    oracle says is not wrapped)  %d" % fp)
	print("  FALSE NEGATIVES  (a live press on a wrapped")
	print("                    rope that took nothing)      %d" % fn)
	for e in fp_ex:
		print("     FP: r=%.2f at (%.1f,-%.1f) tick %d  A=%.2f pinch=%s"
			% [e[0], e[1], e[2], e[3], e[4], str(e[5])])
	for e in fn_ex:
		print("     FN: r=%.2f at (%.1f,-%.1f) tick %d  A=%.2f pinch=%s"
			% [e[0], e[1], e[2], e[3], e[4], str(e[5])])
	print("")
	print("  player press, measured in the real loop:")
	print("   reaction | presses | caught nothing | caught a rope that was NOT wrapped")
	for ri in range(4):
		print("    %3d ms  |  %4d   |     %4d       |    %d"
			% [int(round([9, 12, 15, 18][ri] * 1000.0 / 60.0)), n_by_rt[ri],
			dead_by_rt[ri], phantom_by_rt[ri]])
	print("=================================================================")
	quit(0)
