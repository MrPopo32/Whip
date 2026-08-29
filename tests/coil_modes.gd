extends SceneTree
## Compare the three coil modes on the exact behaviour the player reported:
## catch a beam, then keep stirring the hand. Measures how much whip ends up
## coiled, and - critically - whether stirring HAULS YOU UP for free, which
## would make mode 1 a winch (a banned second verb).

func _run(mode: int) -> Array:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.coil_mode = mode
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))
	m.t_n.append(Vector2(0, -1))
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(2.4, -2.2); m.a_r[0] = 0.20
	m.body_pos = Vector2(0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	var grip := false
	var start_y := 0.0
	var high := 99.0
	var flen0 := -1.0
	var peak_contact := 0
	var peak_speed := 0.0
	var spd_sum := 0.0
	var spd_n := 0
	for t in 500:
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		if t < 25:
			tgt = b + Vector2(-1.05, -0.35)
		elif t < 38:
			tgt = b + Vector2(1.0, -0.55)
		else:
			var ph := float(t - 38) * 0.10
			tgt = b + Vector2(cos(ph), sin(ph)) * m.REACH
		if not grip and absf(m.a_theta[0]) >= m.th_part:
			grip = true
			start_y = m.body_pos.y
			flen0 = m.a_freelen[0]
		m.step_tick(tgt, grip)
		if grip:
			high = minf(high, m.body_pos.y)
			var sp: float = (m.body_pos - m.body_prv).length() * 960.0
			peak_speed = maxf(peak_speed, sp)
			spd_sum += sp
			spd_n += 1
		var n := 0
		for i in m.pos.size():
			if (m.pos[i] - m.a_pos[0]).length() < m.a_r[0] + m.p_rad[i] + 0.05:
				n += 1
		peak_contact = maxi(peak_contact, n)
	var climbed: float = start_y - high
	var res := [peak_contact, climbed, flen0, m.a_freelen[0], m.body_pos.y - start_y, peak_speed, spd_sum / maxf(float(spd_n), 1.0)]
	m.free()
	return res

func _initialize() -> void:
	print("catch a beam, then keep stirring the hand (what the player does)")
	print("mode  peak coiled  climbed  tether end   net height   PEAK body   mean body")
	print("                                                       speed m/s   speed m/s")
	for mode in [0, 1, 3]:
		var r := _run(mode)
		print(" %d      %2d/26      %5.2f m      %5.2f      %+5.2f m     %6.1f     %6.2f"
			% [mode, r[0], r[1], r[3], -r[4], r[5], r[6]])
	print("")
	print("")
	print("'climbed' = free altitude won by stirring (large in mode 1 = winch).")
	print("PEAK/mean body speed is the thrash meter: a hanging swing runs a few m/s.")
	quit(0)
