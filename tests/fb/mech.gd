extends SceneTree
## WHAT holds you after you let go? Three forks from the same release tick:
##   A  the real build
##   D  identical, but anchor_mu set to 0 at the release tick (frictionless beam)
##   B  identical, but the beam removed entirely
## If D looks like B, the leash is CAPSTAN FRICTION. If D looks like A, the
## leash is the GEOMETRY of a wound rope that has to unspool before it is free.

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
		mode: String, n: int) -> Array:
	var m := PUMP.rig(hang, r, turns, deg_to_rad(6.0), 4.5)
	LEAP.load_state(m, e["snap"])
	if mode == "kill":
		m.a_pos[0] = Vector2(0.0, 900.0); m.a_r[0] = 0.001
		m.a_freelen[0] = -1.0; m.a_pinidx[0] = -1; m.a_locked[0] = -1
	elif mode == "nomu":
		m.anchor_mu = 0.0
	elif mode == "nomu_nogrnd":
		m.anchor_mu = 0.0
		m.ground_mu = 0.0
	var beam := Vector2(0.0, -40.0)
	var maxd := 0.0
	var minv := 1e9
	var minv_t := -1
	var clear_at := -1
	var run := 0
	var pb: Vector2 = m.body_pos
	var out: Array = []
	for t in range(1, n + 1):
		pb = m.body_pos
		m.step_tick(m.body_pos, false)
		var v: float = (m.body_pos - pb).length() * 60.0
		var d: float = m.body_pos.distance_to(beam)
		maxd = maxf(maxd, d)
		if t <= 60 and v < minv:
			minv = v; minv_t = t
		if mode != "kill":
			if _contacts(m) == 0:
				run += 1
				if run >= 5 and clear_at < 0:
					clear_at = t - 4
			else:
				run = 0
		out.append(d)
	var d40: float = out[mini(39, out.size() - 1)]
	var d60: float = out[mini(59, out.size() - 1)]
	m.free()
	return [d40, d60, maxd, minv, minv_t, clear_at]

func _initialize() -> void:
	print("WHAT IS THE LEASH? A = real, D = same beam with zero contact friction,")
	print("B = beam removed. Distances are body-to-beam, metres.")
	print("")
	print("   config                     fork    d@+40t  d@+60t   max d   slowest speed (tick)  chain clear at")
	for cfg in [[2.4, 0.10, 1.8, 24.0], [1.6, 0.10, 1.8, 24.0],
			[3.2, 0.10, 1.8, 24.0], [2.0, 0.22, 1.8, 24.0]]:
		var e := _snap(cfg[0], cfg[1], cfg[2], cfg[3])
		if e.is_empty():
			print("   %.1f m / r %.2f            (no release)" % [cfg[0], cfg[1]])
			continue
		for mode in ["real", "nomu", "kill"]:
			var q := _fly(cfg[0], cfg[1], cfg[2], e, mode, 90)
			var lab := "A real" if mode == "real" else ("D mu=0" if mode == "nomu" else "B gone")
			print("   %.1f m tether, r %.2f, %.1f rad  %s  %6.2f  %6.2f  %6.2f   %5.2f m/s at t=%2d    %s"
				% [float(e["teth"]), cfg[1], float(e["th"]), lab,
				   q[0], q[1], q[2], q[3], q[4],
				   ("t=%d" % int(q[5])) if int(q[5]) >= 0 else "never (90t)"])
		print("")
	quit(0)
