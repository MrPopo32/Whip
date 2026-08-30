extends SceneTree
## How EARNED is a catch? Fires a fixed grid of blind strokes at one beam and
## reports the fraction that lock. 100% = the beam catches itself (the "noodle
## that instantly wraps" complaint); near 0% = impossible. We want a rate low
## enough that a lock is a thing you did, not a thing that happened.

func _b() -> String:
	var e := OS.get_environment("WHIP_BUILD")
	return e if e != "" else "res://main.gd"

func _one(tp: float, h: float, a0: float, a1: float, sd: int) -> Array:
	var m: Node2D = load(_b()).new()
	m.external_drive = true
	m.taper = tp
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))
	m.t_n.append(Vector2(0, -1))
	m.a_pos.clear(); m.a_r.clear(); m.a_theta.clear(); m.a_lockidx.clear()
	m.a_freelen.clear(); m.a_half.clear(); m.a_pinidx.clear(); m.a_pinpt.clear()
	m.a_paytick.clear(); m.a_locked.clear(); m.a_armed.clear(); m.a_pend.clear()
	m.a_ength.clear(); m.a_pin0.clear()
	m.a_pos.append(Vector2(2.2, -h)); m.a_r.append(0.22)
	m.a_theta.append(0.0); m.a_lockidx.append(-1); m.a_freelen.append(-1.0)
	m.a_half.append(0); m.a_pinidx.append(-1); m.a_pinpt.append(Vector2.ZERO)
	m.a_paytick.append(0); m.a_locked.append(-1); m.a_armed.append(1)
	m.a_pend.append(0); m.a_ength.append(0.0); m.a_pin0.append(-1)
	m.body_pos = Vector2(0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	var grip := false
	var locked := false
	var caught := false
	for t in 130:
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		if t < 30:
			tgt = b + Vector2(cos(a0), sin(a0)) * m.REACH
		elif t < 30 + sd:
			tgt = b + Vector2(cos(a1), sin(a1)) * m.REACH
		else:
			tgt = b + Vector2(cos(a1), sin(a1)) * m.REACH
		if not grip and absf(m.a_theta[0]) >= m.th_part:
			grip = true
		m.step_tick(tgt, grip)
		if m.a_freelen[0] >= 0.0:
			caught = true
		if m.a_locked[0] == 1:
			locked = true
	m.free()
	return [locked, caught]

func _rate(tp: float, h: float) -> Array:
	var locks := 0
	var catches := 0
	var n := 0
	for a0 in [PI * 0.85, PI * 1.10]:
		for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
			for sd in [5, 9, 14]:
				var r := _one(tp, h, a0, a1, sd)
				n += 1
				if r[0]:
					locks += 1
				if r[1]:
					catches += 1
	return [100.0 * locks / n, 100.0 * catches / n, n]

func _initialize() -> void:
	print("BUILD: " + _b())
	print("lock rate over %d blind strokes (100%% = catches itself)" % 18)
	print("beam height sweep at taper 26:1")
	print("height   lock%  catch%")
	for tp in [26.0]:
		var line := ""
		for h in [2.0, 2.2, 2.4]:
			var r := _rate(tp, h)
			print("%.2f m    %5.1f  %5.1f" % [h, r[0], r[1]])
		print(line)
	quit(0)
