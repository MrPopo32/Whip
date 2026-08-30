extends SceneTree
## catch_alias.gd - WHAT DOES THE SUB-TICK SAMPLING ACTUALLY BUY?
##
## tests/catch_subtick.gd found 3 of 45 physically-wrapping strokes that never
## present a qualifying sample to the 60 Hz gate. Those throws are outside the
## denominator of tests/catch_window.gd by construction - it defines a "good"
## throw with the same 60 Hz sampler the gate uses - so the sweep cannot see
## them at all. This finds them by name and asks whether the 240 Hz engage
## sampling in main_fix2.gd actually catches them, at any press tick.

const NT := 115

func _rig(path: String, dx: float, h: float, r: float) -> Node2D:
	var m: Node2D = load(path).new()
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

func _catches(path: String, s: Array, t_touch: int) -> int:
	var best := 0
	for d in [-12, -9, -6, -3, 0, 3, 6, 9, 12, 15, 18, 21]:
		var m := _rig(path, s[0], s[1], s[2])
		var press := maxi(t_touch + d, 0)
		var out := 0
		for t in NT:
			m.step_tick(_target(m, t, s), t >= press)
			if m.a_freelen[0] >= 0.0:
				out = 1
				if m.a_locked[0] == 1:
					out = 2
					break
				if m.a_locked[0] == 0:
					break
		m.free()
		best = maxi(best, out)
		if best == 2:
			break
	return best

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("strokes that wrap at 960 Hz but never present a qualifying 60 Hz sample")
	print("")
	var found := 0
	var rescued := 0
	var rescued_lock := 0
	for s in _strokes():
		var m := _rig("res://tests/jb/main_sub.gd", s[0], s[1], s[2])
		var tick_q := false
		var sub_q := false
		var maxth := 0.0
		var sub_max := 0.0
		var t_touch := -1
		for t in NT:
			m.step_tick(_target(m, t, s), false)
			var th: float = absf(m.a_theta[0])
			maxth = maxf(maxth, th)
			sub_max = maxf(sub_max, float(m.sub_peak))
			if th >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx:
				tick_q = true
			if bool(m.sub_qual):
				sub_q = true
			if t_touch < 0:
				for i in m.pos.size():
					if m.pos[i].distance_to(m.a_pos[0]) < m.a_r[0] + m.p_rad[i] + m.wrap_shell:
						t_touch = t
						break
		m.free()
		if tick_q or not sub_q or t_touch < 0:
			continue
		found += 1
		var base := _catches("res://main.gd", s, t_touch)
		var fix2 := _catches("res://tests/jb/whip_arrival_subtick.gd", s, t_touch)
		if fix2 > 0:
			rescued += 1
		if fix2 == 2:
			rescued_lock += 1
		var names := ["nothing", "catch+betray", "LOCK"]
		print("  beam r %.2f at %.1f m, lead %.1f m: peak theta %.2f at 60 Hz, %.2f at 960 Hz"
			% [s[2], s[1], s[0], maxth, sub_max])
		print("      shipped rule at any press tick: %s   |   with 240 Hz engage sampling: %s"
			% [names[base], names[fix2]])
	print("")
	print("%d such strokes; the 240 Hz engage sampling makes %d catchable" % [found, rescued])
	print("(%d of them all the way to a LOCK)." % rescued_lock)
	print("")
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
