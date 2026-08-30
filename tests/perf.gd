extends SceneTree
## How expensive is one simulation tick? The sim is pure arithmetic in
## GDScript, so this is the number that decides whether it survives on a
## phone, where the interpreter runs several times slower than on desktop.

func _initialize() -> void:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	# warm up
	for t in 60:
		m.step_tick(m.body_pos + Vector2(0.5, -0.9), false)
	var cases := [["free flail (no wrap)", false], ["gripped, wrapped", true]]
	for c in cases:
		var t0 := Time.get_ticks_usec()
		var n := 1200
		for t in n:
			var ph := float(t) * 0.05
			m.step_tick(m.body_pos + Vector2(cos(ph), sin(ph)) * m.REACH, c[1])
		var us: float = float(Time.get_ticks_usec() - t0) / float(n)
		print("%-22s  %6.0f us/tick   %4.1f%% of a 16.7 ms frame   headroom x%.1f"
			% [c[0], us, us / 16667.0 * 100.0, 16667.0 / maxf(us, 1.0)])
	print("")
	print("beams in level: %d, chain particles: %d, substeps/tick: %d"
		% [m.a_pos.size(), m.NP, m.SUB])
	m.free()
	quit(0)
