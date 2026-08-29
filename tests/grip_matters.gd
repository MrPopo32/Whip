extends SceneTree
## Does releasing the grip actually cost you anything?
## Engage a full wrap while TAUT, then let go of Space and see whether the body
## still hangs. If it hangs, SLACK is silently load-bearing and the grip button
## has no purpose - which is exactly what the player reported.

func _initialize() -> void:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	var helper = load("res://tests/sim_test.gd").new()
	helper._prewrap(m, 0, 1.1)
	var c: Vector2 = m.a_pos[0]
	# 40 ticks gripped: engage and lock
	for t in 40:
		m.step_tick(m.body_pos, true)
	var y_taut: float = m.body_pos.y - c.y
	print("after 40 ticks GRIPPED : hanging %.2f m below the beam, locked=%d"
		% [y_taut, m.a_locked[0]])
	# now release the grip entirely and keep simulating
	for t in 180:
		m.step_tick(m.body_pos, false)
	var y_slack: float = m.body_pos.y - c.y
	print("after 3 s with grip RELEASED: %.2f m below the beam (engaged=%s)"
		% [y_slack, str(m.a_freelen[0] >= 0.0)])
	var fell := y_slack - y_taut
	print("")
	if fell < 1.0:
		print(">>> SLACK IS LOAD-BEARING: the body only dropped %.2f m in 3 s." % fell)
		print(">>> The grip button is doing nothing to keep you up - there is no")
		print(">>> reason for the player to ever press it while hanging.")
	else:
		print(">>> ok: releasing the grip dropped the body %.2f m" % fell)
	m.free()
	quit(0)
