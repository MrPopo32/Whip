extends SceneTree
## What does a shorter arm buy? You hang tether + arm + body below the beam,
## so the arm sets how much air a swing needs. Sweeps arm length against beam
## height and reports whether a swing can actually develop, or whether the
## ground cuts the arc off and you just stand there.

func _rig(arm: float, beam_h: float, tether_target: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.arm_max = arm
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))   # flat floor
	m.t_n.append(Vector2(0, -1))
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -beam_h); m.a_r[0] = 0.16
	# hang the body from a wrap with roughly the requested tether
	var c: Vector2 = m.a_pos[0]
	var rr: float = m.a_r[0] + 0.04
	var turns := 1.5
	var rise: float = tether_target - rr
	var wl: float = turns * TAU * rr
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + Vector2(0.0, tether_target - s)
		elif s < rise + wl:
			var a: float = PI / 2.0 + (s - rise) / rr
			p = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = PI / 2.0 + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			p = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, s - rise - wl)
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + Vector2(0.0, tether_target + 0.6)
	m.body_prv = m.body_pos
	return m

func _run(arm: float, beam_h: float, tether: float) -> Array:
	var m := _rig(arm, beam_h, tether)
	for t in 60:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free(); return [-1.0, 0.0, 0.0]
	var c: Vector2 = m.a_pos[0]
	var flen: float = m.a_freelen[0]
	# resonant pump: drive the hand across the swing at the pendulum period
	var period: float = TAU * sqrt(maxf(flen + arm, 0.3) / 10.0)
	var peak := 0.0
	var grounded_ticks := 0
	for t in 1200:
		var ph: float = float(t) / 60.0 / period * TAU
		var tgt: Vector2 = m.body_pos + Vector2(cos(ph), -0.55).normalized() * m.REACH
		m.step_tick(tgt, true)
		var d: Vector2 = m.body_pos - c
		peak = maxf(peak, rad_to_deg(absf(atan2(d.x, d.y))))
		if m.grounded:
			grounded_ticks += 1
	var hang: float = m.body_pos.y - c.y
	m.free()
	return [flen, peak, float(grounded_ticks) / 1200.0, hang]

func _initialize() -> void:
	print("hang depth = tether + arm + body(0.28). If that exceeds the beam")
	print("height, the floor cuts the arc off and no swing can develop.")
	print("")
	print("beam h  arm    tether  peak swing  ground%  launchable?")
	for beam_h in [2.2, 2.8, 3.2]:
		for arm in [1.30, 1.15, 1.00, 0.85]:
			var r := _run(arm, beam_h, 1.6)
			if r[0] < 0.0:
				print("%4.1f   %.2f    (wrap did not hold)" % [beam_h, arm]); continue
			var ok: String = "YES" if r[1] > 45.0 else "no"
			print("%4.1f   %.2f   %5.2f    %6.1f deg   %4.0f%%     %s"
				% [beam_h, arm, r[0], r[1], r[2] * 100.0, ok])
		print("")
	quit(0)
