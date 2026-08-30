extends SceneTree
## The whole calling convention for tests/bot_pump.gd, in one loop.
## Proves the policy is callable from another script exactly as documented.
##   godot --headless --path . -s res://tests/pump_use.gd

const PUMP := preload("res://tests/bot_pump.gd")

func _initialize() -> void:
	# hang on an isolated beam: 2.0 m of rope, a 0.10 m beam, 1.3 turns wound
	# on, released 8 degrees off vertical
	var m: Node2D = PUMP.rig(2.0, 0.10, 1.3, deg_to_rad(8.0))
	for t in 30:
		m.step_tick(m.body_pos, true)          # settle: the wrap catches here
	print("locked=%d  tether=%.2f m" % [m.a_locked[0], m.a_freelen[0]])
	print("   t     swing   est   phase  radius   vt      (target 60 deg)")

	var prev: Vector2 = m.body_pos             # THE ONLY STATE THE POLICY NEEDS
	var peak := 0.0
	for t in 900:
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 60.0)   # servo to 60 deg
		prev = m.body_pos
		m.step_tick(cur, true)                 # the grip stays CLOSED while hanging
		var s := PUMP.swing_state(m, 0, prev)
		peak = maxf(peak, absf(atan2(m.body_pos.x - m.a_pos[0].x,
			m.body_pos.y - m.a_pos[0].y)))
		if t % 150 == 149:
			print("  %4d  %6.1f %6.1f  %+5.2f  %5.2f m  %5.2f m/s"
				% [t + 1, rad_to_deg(peak), rad_to_deg(float(s["amp"])),
				   s["phase"], s["radius"],
				   absf(float(s["omega"]) * float(s["radius"]))])
			peak = 0.0
	m.free()
	quit(0)
