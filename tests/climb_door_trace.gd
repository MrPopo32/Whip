extends SceneTree
## Trace of the swing on the door after catch A (F0 lead 1.8, grid36 #24):
## angle, radius, speed, velocity, every 4 ticks. Diagnostic only.
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")
func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var T := 0.0 if a.size() < 1 else float(a[0])
	var n := 400 if a.size() < 2 else int(a[1])
	var li := 24 if a.size() < 3 else int(a[2])
	var lead := 1.8 if a.size() < 4 else float(a[3])
	var m: Node2D = DL.make(8.0, 0.0)
	var c: Dictionary = DL.grid36()[li]
	DL.stand(m, DL.DOOR.x - lead, 0.0, float(c["a0"]))
	var r: Dictionary = DL.throw(m, 0, c, HN.new("null", "t", 0))
	print("lock ", r["lock"], " tether ", r["tether"], " body ", m.body_pos)
	var prev: Vector2 = m.body_pos
	for t in n:
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, T)
		prev = m.body_pos
		m.step_tick(cur, true)
		var v: Vector2 = (m.body_pos - prev) * 60.0
		var rv: Vector2 = m.body_pos - Vector2(m.a_pos[0])
		if t % 4 == 0:
			print("t %3d deg %+5.0f R %.2f  body (%+.2f, %+.2f up) v %.1f (%+.1f, %+.1f up) free %.2f pin %d" % [t,
				DL.body_deg(m, 0), rv.length(), m.body_pos.x, -m.body_pos.y, v.length(), v.x, -v.y,
				float(m.a_freelen[0]), int(m.a_pinidx[0])])
	quit(0)
