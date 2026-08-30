extends SceneTree
## catch_subtick.gd - IS THE CATCH BLIND BETWEEN TICKS?
##
## The winding angle is measured once per 60 Hz tick while a thrown tip is
## moving at 20-80 m/s, so a wrap that peaks between two ticks would never be
## sampled above th_part and could never engage - a silent false negative that
## no amount of player timing could fix. main_sub.gd re-measures every substep
## (960 Hz, read-only) so the two samplings can be compared on the same throws.
##
## Also reported: the size of the tick-to-tick jump in theta right through the
## engage threshold. A big jump means the threshold is being crossed in one
## sample, which is where a between-ticks peak would hide.

const NT := 115

func _rig(dx: float, h: float, r: float) -> Node2D:
	var m: Node2D = load("res://tests/jb/main_sub.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -h)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

func _target(m: Node2D, t: int, s: Array) -> Vector2:
	var a0: float = s[3]
	var a1: float = s[4]
	var sd: int = s[5]
	var fin: int = s[6]
	var b: Vector2 = m.body_pos
	if t < 30:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return b + Vector2(cos(a1), sin(a1)) * m.REACH
	if fin == 2 and t < 30 + sd + 8:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
	return b + Vector2(cos(a1), sin(a1)) * m.REACH

func _strokes() -> Array:
	var out: Array = []
	for beam in [[0.22, 2.2], [0.11, 2.2], [0.11, 2.6]]:
		for dx in [1.8, 2.5]:
			for a0 in [PI * 0.85, PI * 1.10]:
				for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
					for sd in [5, 9, 14]:
						for fin in [0, 2]:
							out.append([dx, beam[1], beam[0], a0, a1, sd, fin])
	return out

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var strokes := _strokes()
	var n_tick_good := 0        # qualifies on the 60 Hz sampling
	var n_sub_good := 0         # qualifies on the 960 Hz sampling
	var hidden := 0             # qualifies ONLY between ticks: invisible to the game
	var jump_max := 0.0
	var jump_sum := 0.0
	var jump_n := 0
	var extra_qual := 0         # substep-qualifying ticks the tick sampler missed
	var tick_qual_t := 0
	for s in strokes:
		var m := _rig(s[0], s[1], s[2])
		var tq := false
		var sq := false
		var prev := 0.0
		var crossed := false
		for t in NT:
			m.step_tick(_target(m, t, s), false)
			var th: float = absf(m.a_theta[0])
			var q_tick: bool = th >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx
			if q_tick:
				tq = true
				tick_qual_t += 1
			if bool(m.sub_qual):
				sq = true
				if not q_tick:
					extra_qual += 1
			# how far does theta move in ONE tick right through the threshold?
			if not crossed and prev < m.th_part and th >= m.th_part:
				crossed = true
				var j: float = th - prev
				jump_max = maxf(jump_max, j)
				jump_sum += j
				jump_n += 1
			prev = th
		m.free()
		if tq:
			n_tick_good += 1
		if sq:
			n_sub_good += 1
		if sq and not tq:
			hidden += 1
	print("=== SUB-TICK SAMPLING ========================================")
	print("%d strokes." % strokes.size())
	print("qualify on the shipped 60 Hz sampling:   %d" % n_tick_good)
	print("qualify on 960 Hz substep sampling:      %d" % n_sub_good)
	print("qualify ONLY between ticks (invisible):  %d" % hidden)
	print("")
	print("ticks where the geometry qualified at 960 Hz but not at 60 Hz: %d" % extra_qual)
	print("(against %d ticks where the 60 Hz sampler saw it qualify)" % tick_qual_t)
	if jump_n > 0:
		print("")
		print("theta jump across the engage threshold in a single tick:")
		print("  mean %.2f rad, worst %.2f rad, over %d crossings" % [
			jump_sum / jump_n, jump_max, jump_n])
		print("  (th_part is %.1f rad, so a jump of that size is the sampler)" % 3.4)
	print("")
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
