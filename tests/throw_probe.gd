extends SceneTree
## Reachability probe: can a scripted throw from flat ground actually WRAP an
## anchor at a given offset? Searches a small grid of strokes and reports the
## best wrap achieved. This is the route-bot analog for the throw verb - level
## geometry must sit inside the envelope this measures, not inside arithmetic.

func _make(dx: float, dy: float, r: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))
	m.a_pos.clear(); m.a_r.clear(); m.a_theta.clear(); m.a_lockidx.clear()
	m.a_freelen.clear(); m.a_half.clear(); m.a_pinidx.clear(); m.a_pinpt.clear()
	m.a_paytick.clear(); m.a_locked.clear(); m.a_armed.clear(); m.a_pend.clear()
	m.a_ength.clear()
	m.a_pos.append(Vector2(dx, -dy)); m.a_r.append(r)
	m.a_theta.append(0.0); m.a_lockidx.append(-1); m.a_freelen.append(-1.0)
	m.a_half.append(0); m.a_pinidx.append(-1); m.a_pinpt.append(Vector2.ZERO)
	m.a_paytick.append(0); m.a_locked.append(-1); m.a_armed.append(1)
	m.a_pend.append(0); m.a_ength.append(0.0)
	m.body_pos = Vector2(0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	return m

func _try(dx: float, dy: float, r: float, a0: float, a1: float,
		sd: int, pull: bool) -> Array:
	var m := _make(dx, dy, r)
	var best := 0.0
	var locked := false
	var grip := false
	for t in 150:
		var tgt: Vector2
		if t < 30:
			tgt = m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH
		elif t < 30 + sd:
			tgt = m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH
		elif pull and t < 30 + sd + 10:
			tgt = m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
		else:
			tgt = m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH
		# a skilled player grips the instant the wrap reads as caught
		if not grip and absf(m.a_theta[0]) >= m.th_part:
			grip = true
		m.step_tick(tgt, grip)
		best = maxf(best, absf(m.a_theta[0]))
		if m.a_locked[0] == 1:
			locked = true
	m.free()
	return [best, locked]

func _probe(dx: float, dy: float, r: float) -> Array:
	var best := 0.0
	var locked := false
	for a0 in [PI * 0.85, PI * 1.10]:                    # windup behind
		for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18, -PI * 0.05]:  # stroke up-fwd
			for sd in [5, 9, 14]:
				for pull in [false, true]:
					var res := _try(dx, dy, r, a0, a1, sd, pull)
					best = maxf(best, res[0])
					if res[1]:
						locked = true
	return [best, locked]

func _initialize() -> void:
	print("anchor r=0.20, body on flat ground at origin, handle-relative offsets")
	print("dx    dy   best_theta  locks?   (th_part=2.2  th_full=3.9)")
	for dy in [3.0, 3.5, 4.0, 4.5]:
		for dx in [1.5, 2.5, 3.5]:
			var res := _probe(dx, dy, 0.20)
			print("%.1f  %.1f      %5.2f     %s" % [dx, dy, res[0],
				"LOCK" if res[1] else ("catch" if res[0] >= 2.2 else "-")])
	quit(0)
