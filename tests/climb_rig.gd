extends SceneTree
## CLIMB RIG CHECK (scratch for the launch footprint): a thrown lock on a door
## beam, then the lip taken away -> open air. Prints the catch and what the
## bot_pump servo does with each amplitude target. Timing too.
const TL := preload("res://tests/tapelib.gd")
const PUMP := preload("res://tests/bot_pump.gd")

static func door_world(m: Node2D) -> void:
	m.t_a.clear(); m.t_b.clear()
	m.t_arc_c.clear(); m.t_arc_r.clear(); m.t_arc_ang.clear()
	m.t_a.append(Vector2(-30.0, 2.2)); m.t_b.append(Vector2(-1.4, 2.2))
	m.t_a.append(Vector2(-1.4, 2.2)); m.t_b.append(Vector2(-1.4, 30.0))
	m._fillet(Vector2(-1.4, 2.2), 0.35)
	m._finish_terrain()
	m._clear_anchor_tables()
	m._add_anchor(Vector2.ZERO, 0.11, 0, "B")
	m._av_size()
	m.spawn = Vector2(-3.4, 2.2 - 0.28)
	m.goal_x = 999.0
	m._reset()

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var m: Node2D = TL.new_sim()
	door_world(m)
	for t in 60:
		m.step_tick(m.body_pos, false)
	print("standing at ", m.body_pos, " grounded ", m.grounded)
	var plan: Dictionary = TL.plan_capture(m, 0, "lock")
	print("plan ", plan.get("lead"), " r ", plan.get("r"))
	var ok: bool = TL.do_capture(m, 0, plan)
	print("capture ", ok, " tick ", m.tick_count, " ms ", Time.get_ticks_msec() - t0)
	for t in 90:
		m.step_tick(m.body_pos, true)
	print("after hold: freelen %.2f locked %d body %s grounded %s pin %d" % [
		m.a_freelen[0], m.a_locked[0], str(m.body_pos), str(m.grounded), m.a_pinidx[0]])
	quit(0)
