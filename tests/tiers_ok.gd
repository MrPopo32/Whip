extends SceneTree
## Can you simply STAND on every tier without the out-of-world net firing?
## The net was a hardcoded y > 6.0 while the terraced level runs down to y=12,
## so the last two tiers teleported you to spawn on contact.
func _initialize() -> void:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	print("world_bottom = %.1f (deepest terrain + 4)" % m.world_bottom)
	print("stand at x   floor y   survived 90 ticks?")
	for x in [0.0, 10.0, 25.0, 35.0, 44.0, 55.0]:
		var fy := 1e9
		for s in m.t_a.size():
			var A: Vector2 = m.t_a[s]
			var B: Vector2 = m.t_b[s]
			if absf(B.x - A.x) < 0.01: continue
			if x < minf(A.x, B.x) or x > maxf(A.x, B.x): continue
			var t: float = (x - A.x) / (B.x - A.x)
			fy = minf(fy, A.y + (B.y - A.y) * t)
		m.teleport(Vector2(x, fy - m.BODY_R - 0.1))
		m.falls = 0
		for t in 90:
			m.step_tick(m.body_pos + Vector2(0.3, -0.6), false)
		var ok: bool = m.falls == 0 and absf(m.body_pos.x - x) < 3.0
		print("   %5.1f     %5.1f    %s" % [x, fy, "yes" if ok else "NO - teleported away"])
	m.free()
	quit(0)
