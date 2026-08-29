extends SceneTree
func _initialize() -> void:
	for turns in [0.5, 0.75, 1.0, 1.25]:
		var main: Node2D = load("res://main.gd").new()
		main.external_drive = true
		main.setup_sim()
		var test = load("res://tests/sim_test.gd")
		var helper = test.new()
		helper._prewrap(main, 0, turns)
		var line := "turns=%.2f theta:" % turns
		for t in 16:
			main.step_tick(main.body_pos, true)
			line += " %.2f" % absf(main.a_theta[0])
		print(line)
		main.free()
	quit(0)
