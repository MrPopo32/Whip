extends SceneTree
## Whip a beam from close range and watch the coil grow. A real wrap is two or
## three turns and then stops. If theta and the contact population climb without
## bound until the whole whip is on the beam, that is the bug.

func _rig(bx: float, by: float, amu: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.anchor_mu = amu
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))
	m.t_n.append(Vector2(0, -1))
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)            # park every other beam
	m.a_pos[0] = Vector2(bx, by); m.a_r[0] = 0.20
	m.body_pos = Vector2(0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	return m

func _contacts(m: Node2D) -> Array:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	var lo := 99
	var hi := -1
	for i in m.pos.size():
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + 0.05:
			n += 1
			lo = mini(lo, i)
			hi = maxi(hi, i)
	return [n, lo, hi]

func _run(bx: float, by: float, keep_stirring: bool, amu: float) -> Array:
	var m := _rig(bx, by, amu)
	var grip := false
	var peak_contact := 0
	var peak_theta := 0.0
	for t in 500:
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		if t < 25:
			tgt = b + Vector2(-1.05, -0.35)
		elif t < 38:
			tgt = b + Vector2(1.0, -0.55)
		elif keep_stirring:
			# the player keeps moving the mouse, as players do
			var ph := float(t - 38) * 0.10
			tgt = b + Vector2(cos(ph), sin(ph)) * m.REACH
		else:
			tgt = b + Vector2(0.35, -1.05)
		if not grip and absf(m.a_theta[0]) >= m.th_part:
			grip = true
		m.step_tick(tgt, grip)
		var c := _contacts(m)
		peak_contact = maxi(peak_contact, c[0])
		peak_theta = maxf(peak_theta, absf(m.a_theta[0]))
	var fin := _contacts(m)
	var res := [peak_contact, peak_theta, fin[0], fin[1] if fin[1] < 99 else -1, fin[2]]
	m.free()
	return res

func _initialize() -> void:
	print("is the runaway coil driven by FRICTION, or purely by winding geometry?")
	print("(hand kept stirring in all rows, beam 2.4 m ahead)")
	print("anchor_mu   peak inContact   peak turns   final inContact")
	for amu in [0.40, 0.20, 0.05, 0.01]:
		var r := _run(2.4, -2.2, true, amu)
		print("   %.2f          %2d/26          %5.2f          %2d/26"
			% [amu, r[0], r[1] / TAU, r[2]])
	quit(0)
