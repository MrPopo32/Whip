extends SceneTree
## What the pump servo actually does to the TRUE swing about A: the peak |theta|
## of every completed half-swing, signed by side, for each target. Plus the
## cost of a tick, a snapshot and a restore on this machine.
const SW := preload("res://tests/climb_swing_lib.gd")
const PUMP := preload("res://tests/bot_pump.gd")

func _initialize() -> void:
	var b = SW.new(0.10)
	var m: Node2D = b.m
	var s0: Dictionary = m.snapshot()
	var t0 := Time.get_ticks_usec()
	for i in 200:
		m.step_tick(m.body_pos, true)
	var t1 := Time.get_ticks_usec()
	var sn: Dictionary
	for i in 50:
		sn = m.snapshot()
	var t2 := Time.get_ticks_usec()
	for i in 50:
		m.restore(sn)
	var t3 := Time.get_ticks_usec()
	print("tick %.2f ms  snapshot %.2f ms  restore %.2f ms" % [(t1 - t0) / 200000.0, (t2 - t1) / 50000.0, (t3 - t2) / 50000.0])
	var args := Array(OS.get_cmdline_user_args())
	var targets := [90.0, 120.0, 150.0, 0.0]
	if args.size() > 0:
		targets = []
		for a in args: targets.append(float(a))
	for tg in targets:
		m.restore(s0)
		var prev: Vector2 = m.body_pos
		var pk := 0.0
		var sgn := 0.0
		var line := ""
		var th_u := SW.true_theta(m)
		var pr := th_u
		var over := -1
		for t in 2400:
			var raw: float = SW.true_theta(m)
			var d := raw - pr
			if d > PI: d -= TAU
			elif d < -PI: d += TAU
			pr = raw
			th_u += d
			if absf(th_u) > PI and over < 0:
				over = t
			var thd := rad_to_deg(raw)
			pk = maxf(pk, absf(thd))
			var sg := signf(thd)
			if sg != 0.0 and sg != sgn:
				if sgn != 0.0:
					line += " %+.0f" % (pk * sgn)
				sgn = sg
				pk = 0.0
			var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, tg)
			prev = m.body_pos
			m.step_tick(cur, true)
			if m.a_freelen[0] < 0.0:
				line += " LOST@%d" % t
				break
		print("target %3.0f: over@%d tether %.2f pin %d locked %d |%s" % [tg, over, m.a_freelen[0], m.a_pinidx[0], m.a_locked[0], line])
	b.free_sim()
	quit(0)
