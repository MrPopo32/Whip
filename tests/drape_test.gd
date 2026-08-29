extends SceneTree
## A DRAPE is not a wrap. A chain simply lying across a beam covers the top
## half of it - a half turn, pi = 3.14 rad. If that reaches the catch
## threshold, then touching a beam IS catching it, and no skill is involved.

func _initialize() -> void:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()          # open air
	var k := 0
	m.a_r[k] = 0.20
	m.a_pos[k] = Vector2(0.0, -40.0)
	var c: Vector2 = m.a_pos[k]
	var r: float = m.a_r[k] + 0.035
	# lay the chain limply over the top of the beam: half the whip down each
	# side, no winding, no speed - exactly what a lazy flail leaves behind
	var half: float = m.cum_len[m.NP - 1] * 0.5
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < half - r * PI * 0.5:
			p = c + Vector2(-r, -(half - r * PI * 0.5 - s))
		elif s < half + r * PI * 0.5:
			var a: float = PI + (s - (half - r * PI * 0.5)) / r
			p = c + Vector2(cos(a), sin(a)) * r
		else:
			p = c + Vector2(r, s - (half + r * PI * 0.5))
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + Vector2(-r, -(half - r * PI * 0.5) - 1.3)
	m.body_prv = m.body_pos
	print("th_part (catch) = %.2f   th_full (lock) = %.2f   half turn = %.2f"
		% [m.th_part, m.th_full, PI])
	var caught := false
	for t in 120:
		m.step_tick(m.body_pos, true)          # gripping, as a player often is
		if t < 6 or t % 20 == 0:
			print("  t%3d  theta=%.2f  engaged=%s  locked=%d"
				% [t, absf(m.a_theta[k]), str(m.a_freelen[k] >= 0.0), m.a_locked[k]])
		if m.a_freelen[k] >= 0.0:
			caught = true
	print("")
	if caught:
		print(">>> A LIMP DRAPE CATCHES. Touching a beam is catching it.")
	else:
		print(">>> ok: a drape does not catch")
	m.free()
	quit(0)
