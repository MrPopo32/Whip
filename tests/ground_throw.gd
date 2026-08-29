extends SceneTree
## The player's actual complaint: standing on the ground, how high can one
## stroke throw the tip? The airborne bench flatters the whip - on the ground
## the chain drags, and drag is paid out of the stroke.

func _throw(tp: float, mu: float) -> Array:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.taper = tp
	m.ground_mu = mu
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))
	m.a_pos.clear(); m.a_r.clear(); m.a_theta.clear(); m.a_lockidx.clear()
	m.a_freelen.clear(); m.a_half.clear(); m.a_pinidx.clear(); m.a_pinpt.clear()
	m.a_paytick.clear(); m.a_locked.clear(); m.a_armed.clear(); m.a_pend.clear()
	m.a_ength.clear()
	m.body_pos = Vector2(0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	var high := 0.0        # highest the TIP gets above ground
	var tipmax := 0.0
	for t in 200:
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		if t < 40:
			tgt = b + Vector2(-1.0, -0.4)        # settle, whip trails behind
		elif t < 52:
			tgt = b + Vector2(1.05, -0.5)        # the stroke: sweep up-forward
		else:
			tgt = b + Vector2(0.4, -1.05)        # follow through, hold high
		m.step_tick(tgt, false)
		high = maxf(high, -m.pos[m.NP - 1].y)
		tipmax = maxf(tipmax, m.tip_speed)
	m.free()
	return [high, tipmax]

func _initialize() -> void:
	print("ONE stroke from standing. Beam height to clear = 2.5 m + wrap.")
	print("taper   mu=0.30        mu=0.15        mu=0.05")
	for tp in [22.0, 35.0, 50.0, 70.0]:
		var line := "%5.0f:1" % tp
		for mu in [0.30, 0.15, 0.05]:
			var r := _throw(tp, mu)
			line += "  %5.2f m/%3.0f  " % [r[0], r[1]]
		print(line)
	quit(0)
