extends SceneTree
## Side check found while chasing the drag: main.gd's out-of-world safety net is
## `if body_pos.y > 6.0`, but the level's own floor descends to y=12. Does
## standing on the level's later tiers trip it?
func _initialize() -> void:
	print("tier floors in _build_level: 0, 3, 6, 9, 12   (safety net fires at body y > 6.0)")
	print("  place the body on a tier, step 10 ticks, hand open, cursor on the body:")
	print("   tier floor   body y start | falls | body after | teleported?")
	for fy in [0.0, 3.0, 6.0, 9.0, 12.0]:
		var m: Node2D = load("res://main.gd").new()
		m.external_drive = true
		m.setup_sim()
		var x := 25.0
		if fy == 6.0: x = 35.0
		elif fy == 9.0: x = 44.0
		elif fy == 12.0: x = 55.0
		elif fy == 3.0: x = 25.0
		m.teleport(Vector2(x, fy - m.BODY_R - 0.01))
		var y0: float = m.body_pos.y
		for t in 10:
			m.step_tick(m.body_pos, false)
		print("   %5.1f       %8.2f     |  %3d  | (%6.2f,%6.2f) | %s"
			% [fy, y0, m.falls, m.body_pos.x, m.body_pos.y,
			   "YES - reset to spawn" if m.falls > 0 else "no"])
		m.free()
	quit(0)
