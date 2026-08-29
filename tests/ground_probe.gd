extends SceneTree
## Can the player make horizontal progress on flat ground with no anchor?
## (ground lash + taut drag). This decides whether fall basins can have
## walk-out ramps or must be escaped by pendulum alone.

func _make() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))
	m.a_pos.clear(); m.a_r.clear(); m.a_theta.clear(); m.a_lockidx.clear()
	m.a_freelen.clear(); m.a_half.clear(); m.a_pinidx.clear(); m.a_pinpt.clear()
	m.a_paytick.clear(); m.a_locked.clear(); m.a_armed.clear(); m.a_pend.clear()
	m.a_ength.clear()
	m.body_pos = Vector2(0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	return m

func _gait(period: int, fwd: float, back: float, taut_frac: float) -> float:
	var m := _make()
	for t in 600:                                  # 10 seconds
		var ph := t % period
		var f := float(ph) / float(period)
		var tgt: Vector2
		var grip := false
		if f < 0.45:
			tgt = m.body_pos + Vector2(cos(back), sin(back)) * m.REACH
		else:
			tgt = m.body_pos + Vector2(cos(fwd), sin(fwd)) * m.REACH
			grip = f > taut_frac
		m.step_tick(tgt, grip)
	var d: float = m.body_pos.x
	m.free()
	return d

func _initialize() -> void:
	print("10 s of scripted lash/drag gait on flat ground -> net x travel (m)")
	var best := -99.0
	var desc := ""
	for period in [24, 36, 50]:
		for back in [PI * 0.9, PI * 1.15]:
			for fwd in [-PI * 0.1, -PI * 0.3, 0.15]:
				for tf in [0.5, 0.75, 1.1]:
					var d := _gait(period, fwd, back, tf)
					if d > best:
						best = d
						desc = "period=%d back=%.2f fwd=%.2f taut@%.2f" % [period, back, fwd, tf]
	print("best net travel: %.2f m over 10 s   (%s)" % [best, desc])
	quit(0)
