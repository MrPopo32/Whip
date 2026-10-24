extends SceneTree
const TL := preload("res://tests/tapelib.gd")
const RIG := preload("res://tests/climb_rig.gd")
func _initialize() -> void:
	var m: Node2D = TL.new_sim()
	var t0 := Time.get_ticks_usec()
	for t in 300:
		m.step_tick(m.body_pos + Vector2(0.5, -0.5), t > 150)
	print("traverse 300 ticks: %.0f us/tick" % ((Time.get_ticks_usec() - t0) / 300.0))
	RIG.door_world(m)
	t0 = Time.get_ticks_usec()
	for t in 300:
		m.step_tick(m.body_pos + Vector2(0.5, -0.5), t > 150)
	print("door world 300 ticks: %.0f us/tick" % ((Time.get_ticks_usec() - t0) / 300.0))
	quit(0)
