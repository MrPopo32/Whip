extends SceneTree
## The whole calling convention for tests/bot_leap.gd, in one loop: one leap
## across the level's real fast line, beam A6 (27.2,-1.5) to A8 (35.0,-1.5),
## 7.8 m apart and 4.5 m over the floor, with every other beam in the level
## present. Proves the policy is callable from another script as documented.
##   godot --headless --path . -s res://tests/leap_use.gd

const LEAP := preload("res://tests/bot_leap.gd")

func _initialize() -> void:
	# hang on beam 6: 2.8 m of rope with 1.8 turns wound on, 6 degrees off
	# vertical, then settle so the wrap takes
	var m: Node2D = LEAP.rig_level(6, 2.8, 1.8, deg_to_rad(6.0))
	for t in 30:
		m.step_tick(m.body_pos, true)
	print("on A6: locked=%d  tether=%.2f m" % [m.a_locked[6], m.a_freelen[6]])

	var st: Dictionary = LEAP.leap_begin(m, 6, 8)   # from beam 6, to beam 8
	var prev: Vector2 = m.body_pos                  # THE ONLY STATE YOU KEEP
	var phase := ""
	while st["phase"] != "hang" and st["phase"] != "fail":
		var cg: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		m.step_tick(cg[0], cg[1])                   # cursor in metres, grip bool
		if st["phase"] != phase:
			phase = st["phase"]
			print("  tick %4d  -> %s%s" % [st["t"], phase,
				"   (the hand opens: this is the launch)" if phase == "fly" else ""])

	if st["phase"] == "fail":
		print("missed - the body is on the floor between two recovery beams")
		m.free(); quit(1); return
	print("caught A8 after %d ticks in the air: tether %.2f m"
		% [st["f"], m.a_freelen[8]])
	print("  stroke fired %d ticks after the launch, hand shut at %d, %d shut(s)"
		% [st["throw_t"], st["grip_t"], st["closes"]])
	# hang on for two seconds, hand closed, cursor parked. The wrap is still
	# PENDING at the moment it takes - main.gd judges partial-vs-locked from
	# settled geometry over the next 30 ticks - so the verdict is read here.
	for t in 120:
		var cg2: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		m.step_tick(cg2[0], cg2[1])
	print("2 s later: still on A8 = %s, %s, ground contacts during the leap = %d"
		% [str(m.a_freelen[8] >= 0.0),
		   "LOCKED (green)" if m.a_locked[8] == 1 else "partial (amber)",
		   st["ground_t"]])
	m.free()
	quit(0)
