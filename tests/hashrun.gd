extends SceneTree
## Prints a state hash after a fixed scripted session. Two builds that agree
## here are bit-identical in behaviour, which is how an optimisation proves it
## optimised nothing but the cost.
func _initialize() -> void:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	for t in 900:
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		var grip := false
		if t < 90:
			tgt = b + Vector2(0.5, -0.5)
		elif t < 280:
			var ph := float(t - 90) * 0.11
			tgt = b + Vector2(cos(ph), sin(ph)) * 1.1
		elif t < 340:
			tgt = b + Vector2(-1.05, -0.35)
		elif t < 352:
			tgt = b + Vector2(1.05, -0.45)
		elif t < 600:
			tgt = b + Vector2(0.8, -0.8); grip = t > 420
		else:
			var p2 := float(t) * 0.05
			tgt = b + Vector2(cos(p2), -0.6); grip = true
		m.step_tick(tgt, grip)
	print("hash %d   body %.9f %.9f" % [m.state_hash(), m.body_pos.x, m.body_pos.y])
	m.free()
	quit(0)
