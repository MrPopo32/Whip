extends SceneTree
## Arithmetic self-check on the terraced level: every beam must be catchable
## from the tier you throw from (<= ~2.4 m) and, if it is a door, launchable
## over the tier below (> ~3.2 m of air). Catches design mistakes before a
## human wastes a session on them.

func _floor_at(m: Node2D, x: float) -> float:
	var best := 99.0
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		if absf(B.x - A.x) < 0.01:
			continue
		if x < minf(A.x, B.x) - 0.001 or x > maxf(A.x, B.x) + 0.001:
			continue
		var t := (x - A.x) / (B.x - A.x)
		best = minf(best, A.y + (B.y - A.y) * t)
	return best

func _initialize() -> void:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	print("beam        floor just BEFORE   height   floor just AFTER   air below   role")
	for k in m.a_pos.size():
		var p: Vector2 = m.a_pos[k]
		var fb := _floor_at(m, p.x - 2.0)
		var fa := _floor_at(m, p.x + 2.0)
		var h_throw: float = fb - p.y
		var air: float = fa - p.y
		var role := "?"
		if h_throw <= 2.45 and air > 3.2:
			role = "DOOR  (catch cold + launch)"
		elif h_throw <= 2.45:
			role = "school (catch cold only)"
		elif h_throw > 3.5:
			role = "FAST  (swing-only)"
		else:
			role = "*** NEITHER - unusable ***"
		print("(%5.1f,%5.1f)     %5.1f          %5.2f      %5.1f          %5.2f    %s"
			% [p.x, p.y, fb, h_throw, fa, air, role])
	print("")
	print("goal_x = %.1f, floor there = %.1f" % [m.goal_x, _floor_at(m, m.goal_x)])
	# every tier must let you crawl FORWARD to its door without climbing
	print("")
	print("terrain, left to right (a climb in the travel direction would strand you):")
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		if absf(B.x - A.x) < 0.01:
			var dir := "DOWN (fall, fine)" if B.y > A.y else "UP (climb - check)"
			print("  x=%5.1f  vertical %5.1f -> %5.1f   %s" % [A.x, A.y, B.y, dir])
	m.free()
	quit(0)
