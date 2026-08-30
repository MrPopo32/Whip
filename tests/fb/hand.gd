extends SceneTree
## CAN TECHNIQUE STRIP THE COIL? Identical release tick, five things to do with
## the hand for the 40 ticks after it opens. If the drag is the same whatever
## you do, it is a tax. If one of these beats it, it is a skill.
##
##  park    cursor on the body - the hand goes limp (this is what fb/drag.gd did)
##  wind    cursor at full reach BEHIND the direction of flight (leap's windup)
##  yank    cursor at full reach AHEAD, i.e. hauling the standing part away
##  strip   cursor at full reach straight AWAY from the beam
##  stroke  leap's real sequence: wind for s0 ticks, then throw at the far beam

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

func _contacts(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[0] - m.p_rad[i] < 0.005:
			n += 1
	return n

func _snap(hang: float, r: float, turns: float, rel: float) -> Dictionary:
	var m := PUMP.rig(hang, r, turns, deg_to_rad(6.0), 4.5)
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free(); return {}
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var last_pk := 0.0; var half := 0; var sgn := 0.0
	for t in 2400:
		if m.a_freelen[0] < 0.0: break
		var s := PUMP.swing_state(m, 0, prev)
		var th: float = rad_to_deg(float(s["theta"]))
		var om: float = float(s["omega"])
		pk = maxf(pk, absf(th))
		var sg: float = signf(th)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0:
				last_pk = pk; half += 1
			sgn = sg; pk = 0.0
		if (last_pk >= 55.0 or half >= 22) and om > 0.0 and th >= rel:
			var d := {"snap": LEAP.save_state(m), "prev": prev,
				"teth": float(m.a_freelen[0]), "pin": int(m.a_pinidx[0]),
				"th": absf(float(m.a_theta[0])), "amp": last_pk}
			m.free(); return d
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	m.free(); return {}

func _fly(hang: float, r: float, turns: float, e: Dictionary,
		mode: String, kill: bool) -> Array:
	var m := PUMP.rig(hang, r, turns, deg_to_rad(6.0), 4.5)
	LEAP.load_state(m, e["snap"])
	if kill:
		m.a_pos[0] = Vector2(0.0, 900.0); m.a_r[0] = 0.001
		m.a_freelen[0] = -1.0; m.a_pinidx[0] = -1; m.a_locked[0] = -1
	var beam := Vector2(0.0, -40.0)
	var v0: Vector2 = (m.body_pos - Vector2(e["prev"])) * 60.0
	var fwd: Vector2 = v0.normalized()
	var away: Vector2 = (m.body_pos - beam).normalized()
	var target: Vector2 = m.body_pos + fwd * 7.8   # a beam one gap along
	var clear_at := -1
	var run := 0
	var pb: Vector2 = m.body_pos
	var speeds: Array = []
	var ds: Array = []
	for t in range(1, 91):
		var cur: Vector2 = m.body_pos
		match mode:
			"park": cur = m.body_pos
			"wind": cur = m.body_pos - fwd * m.REACH
			"yank": cur = m.body_pos + fwd * m.REACH
			"strip": cur = m.body_pos + away * m.REACH
			"stroke":
				if t <= 14:
					cur = m.body_pos - fwd * m.REACH
				else:
					cur = m.body_pos + (target - m.body_pos).normalized().rotated(-0.5) * m.REACH
		pb = m.body_pos
		m.step_tick(cur, false)
		speeds.append((m.body_pos - pb).length() * 60.0)
		ds.append(m.body_pos.distance_to(beam))
		if not kill:
			if _contacts(m) == 0:
				run += 1
				if run >= 5 and clear_at < 0: clear_at = t - 4
			else:
				run = 0
	var vmin := 1e9
	for i in mini(60, speeds.size()):
		vmin = minf(vmin, float(speeds[i]))
	m.free()
	return [float(ds[39]), float(ds[59]), vmin, clear_at, float(speeds[39])]

func _initialize() -> void:
	print("WHAT THE HAND CAN DO ABOUT THE COIL. Isolated beam, 4.5 m of air.")
	print("d@40/d@60 = body-to-beam distance in metres at those ticks after release.")
	print("'slowest' = the lowest speed the body is dragged down to in the first second.")
	print("")
	for cfg in [[2.4, 0.10, 1.8, 24.0], [1.6, 0.10, 1.8, 24.0], [2.0, 0.22, 1.8, 24.0]]:
		var e := _snap(cfg[0], cfg[1], cfg[2], cfg[3])
		if e.is_empty():
			print("  (no release)"); continue
		print("  tether %.2f m, beam r %.2f, wrap %.2f rad, released at %.0f deg off a %.0f deg swing"
			% [float(e["teth"]), cfg[1], float(e["th"]), cfg[3], float(e["amp"])])
		print("    hand        d@40t   d@60t   slowest   spd@40t   chain clear")
		for mode in ["park", "wind", "yank", "strip", "stroke"]:
			var q := _fly(cfg[0], cfg[1], cfg[2], e, mode, false)
			print("    %-8s   %5.2f   %5.2f    %5.2f     %5.2f     %s"
				% [mode, q[0], q[1], q[2], q[4],
				   ("t=%d" % int(q[3])) if int(q[3]) >= 0 else "never (90t)"])
		for mode in ["park", "stroke"]:
			var q := _fly(cfg[0], cfg[1], cfg[2], e, mode, true)
			print("    %-8s   %5.2f   %5.2f    %5.2f     %5.2f     (beam removed)"
				% [mode + "*", q[0], q[1], q[2], q[4]])
		print("")
	quit(0)
