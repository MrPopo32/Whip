extends SceneTree
## main.gd's world-fall safety net fires at body_pos.y > 6.0. The level's own
## tiers 3 and 4 are at y = 9.0 and y = 12.0. Does standing on them teleport
## the player back to the spawn?
func _initialize() -> void:
	for spot in [[24.0, "tier 1 (y=3)"], [34.0, "tier 2 (y=6)"],
			[44.0, "tier 3 (y=9)"], [55.0, "tier 4 (y=12), the run-out to the flag"]]:
		var m: Node2D = load("res://main.gd").new()
		m.external_drive = true
		m.setup_sim()
		var fy := 0.0
		for s in m.t_a.size():
			var A: Vector2 = m.t_a[s]
			var B: Vector2 = m.t_b[s]
			if absf(B.x - A.x) < 0.01: continue
			if float(spot[0]) < minf(A.x, B.x) or float(spot[0]) > maxf(A.x, B.x): continue
			fy = maxf(fy, A.y)
		m.teleport(Vector2(float(spot[0]), fy - 1.0))
		var f0: int = m.falls
		for t in 60:
			m.step_tick(m.body_pos, false)
		print("  stand at x=%.0f on %s -> after 1 s the body is at (%.1f, %.1f), falls %+d %s"
			% [float(spot[0]), str(spot[1]), m.body_pos.x, m.body_pos.y,
			   m.falls - f0,
			   "  <-- TELEPORTED TO SPAWN" if m.body_pos.x < 0.0 else ""])
		m.free()
	print("")
	print("  goal_x = 58.0 sits on tier 4 (y = 12.0). The safety net is y > 6.0.")
	quit(0)
