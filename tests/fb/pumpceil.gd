extends SceneTree
## THE OTHER HALF OF THE CYCLE: can you build a swing worth leaving on?
## The route bot's dominant failure on this level is "NEVER LAUNCHED - the swing
## never reached a release angle", which is a PUMP failure, not a dismount one.
## This measures the ceiling directly: wind onto a beam at a given tether and
## pump for 20 s.

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

func new_level() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	return m

func run(k: int, hang: float) -> void:
	var m := new_level()
	LEAP._wind_on(m, k, hang, 1.8, deg_to_rad(6.0))
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[k] < 0.0:
		print("      hang %.1f m: the wrap did not even hold" % hang)
		m.free(); return
	var teth: float = float(m.a_freelen[k])
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var best := 0.0
	var sgn := 0.0
	var gnd := 0
	var lost := -1
	for t in 1200:
		if m.a_freelen[k] < 0.0:
			lost = t; break
		var s := PUMP.swing_state(m, k, prev)
		var th: float = rad_to_deg(float(s["theta"]))
		pk = maxf(pk, absf(th))
		var sg: float = signf(th)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0: best = maxf(best, pk)
			sgn = sg; pk = 0.0
		if m.grounded: gnd += 1
		var cur: Vector2 = PUMP.pump_cursor(m, k, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	print("      hang %.1f -> tether %.2f m: peak swing %5.1f deg, feet on the floor %4d of 1200 ticks%s"
		% [hang, teth, best, gnd,
		   ("  (wrap lost at t=%d)" % lost) if lost >= 0 else ""])
	m.free()

func _initialize() -> void:
	var m := new_level()
	print("PUMP CEILING per beam. bot_leap wants a 70 deg half-swing before it will")
	print("launch (55 on a low beam); under ~20 deg there is no leap at all.")
	print("")
	for k in [0, 2, 3, 4, 7, 8]:
		var fy := 99.0
		for s in m.t_a.size():
			var A: Vector2 = m.t_a[s]; var B: Vector2 = m.t_b[s]
			if absf(B.x - A.x) < 0.01: continue
			if float(m.a_pos[k].x) < minf(A.x, B.x) or float(m.a_pos[k].x) > maxf(A.x, B.x): continue
			fy = minf(fy, A.y)
		print("   A%d at (%.1f, %.1f), r %.2f, %.1f m of air under it:"
			% [k, float(m.a_pos[k].x), float(m.a_pos[k].y), float(m.a_r[k]),
			   fy - float(m.a_pos[k].y)])
		for hang in [1.2, 1.6, 2.0, 2.4, 2.8, 3.2]:
			run(k, hang)
		print("")
	m.free()
	quit(0)
