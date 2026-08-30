extends SceneTree
## One leg, printed. A7 -> A8 on the real level, REAL vs FREE dismount, with the
## body's actual position each tick, so the budget table can be believed.

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const KA := 7
const KB := 8

func new_level() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	return m

func contacts(m: Node2D, k: int) -> int:
	var c: Vector2 = m.a_pos[k]
	var n := 0
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[k] - m.p_rad[i] < 0.005:
			n += 1
	return n

func snap1(hang: float, rel: float) -> Dictionary:
	var m := new_level()
	LEAP._wind_on(m, KA, hang, 1.8, deg_to_rad(6.0))
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[KA] < 0.0:
		m.free(); return {}
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var last_pk := 0.0; var half := 0; var sgn := 0.0
	for t in 2400:
		if m.a_freelen[KA] < 0.0: break
		var s := PUMP.swing_state(m, KA, prev)
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
				"teth": float(m.a_freelen[KA]), "pin": int(m.a_pinidx[KA]),
				"wrap": absf(float(m.a_theta[KA])), "amp": last_pk}
			m.free(); return d
		var cur: Vector2 = PUMP.pump_cursor(m, KA, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	m.free(); return {}

func run(hang: float, rel: float) -> void:
	var e := snap1(hang, rel)
	if e.is_empty():
		print("  (no release at hang %.1f rel %.0f)" % [hang, rel]); return
	print("  hang %.1f m, release at %.0f deg off a %.0f deg swing." % [hang, rel, float(e["amp"])])
	print("  tether %.2f m, pin idx %d, wrap %.2f rad at the instant the hand opens."
		% [float(e["teth"]), int(e["pin"]), float(e["wrap"])])
	var A := new_level(); LEAP._wind_on(A, KA, hang, 1.8, deg_to_rad(6.0))
	LEAP.load_state(A, e["snap"])
	var B := new_level(); LEAP._wind_on(B, KA, hang, 1.8, deg_to_rad(6.0))
	LEAP.load_state(B, e["snap"])
	B.a_pos[KA] = Vector2(0.0, 900.0); B.a_r[KA] = 0.001
	B.a_freelen[KA] = -1.0; B.a_pinidx[KA] = -1; B.a_locked[KA] = -1
	var pol: Dictionary = LEAP.default_policy()
	pol["amp_max"] = 250.0; pol["max_half"] = 22
	var sa := LEAP.leap_begin(A, KA, KB, pol); sa["phase"] = "fly"; sa["rel_t"] = 0
	var sb := LEAP.leap_begin(B, KA, KB, pol); sb["phase"] = "fly"; sb["rel_t"] = 0
	var PA: Vector2 = A.a_pos[KA]
	var PB: Vector2 = A.a_pos[KB]
	for st in [sa, sb]:
		var mm: Node2D = A if st == sa else B
		var v: Vector2 = (mm.body_pos - Vector2(e["prev"])) * 60.0
		var tmin := 0; var dmin := 1e9
		for i in 240:
			var tt: float = float(i) / 60.0
			var q: Vector2 = mm.body_pos + v * tt + Vector2(0.0, 5.0 * tt * tt)
			if q.distance_to(PB) < dmin: dmin = q.distance_to(PB); tmin = i
		st["s0"] = clampi(tmin - 38, 4, 18)
		st["wind"] = (PB - mm.body_pos).normalized().rotated(PI)
	print("    t  | REAL: body x,y   d(A7)  d(A8)  spd  cont  th8  grip | FREE: body x,y   d(A7) d(A8)  spd  th8 grip")
	var pa: Vector2 = A.body_pos
	var pb: Vector2 = B.body_pos
	for f in range(1, 111):
		var ca: Array = LEAP.leap_step(A, sa, pa)
		var cb: Array = LEAP.leap_step(B, sb, pb)
		pa = A.body_pos; pb = B.body_pos
		A.step_tick(ca[0], ca[1])
		B.step_tick(cb[0], cb[1])
		if f % 5 != 0 and f > 6:
			continue
		print("   %3d | %6.2f %6.2f  %5.2f  %5.2f %5.2f  %3d %5.2f  %s | %6.2f %6.2f  %5.2f %5.2f %5.2f %5.2f  %s"
			% [f, A.body_pos.x, A.body_pos.y, A.body_pos.distance_to(PA),
			   A.body_pos.distance_to(PB), (A.body_pos - pa).length() * 60.0,
			   contacts(A, KA), absf(float(A.a_theta[KB])), "G" if ca[1] else ".",
			   B.body_pos.x, B.body_pos.y, B.body_pos.distance_to(PA),
			   B.body_pos.distance_to(PB), (B.body_pos - pb).length() * 60.0,
			   absf(float(B.a_theta[KB])), "G" if cb[1] else "."])
	print("   REAL end: on A8 = %s (locked %d, tether %.2f), body x %.2f, grounded %s"
		% [str(A.a_freelen[KB] >= 0.0), int(A.a_locked[KB]), float(A.a_freelen[KB]),
		   A.body_pos.x, str(A.grounded)])
	print("   FREE end: on A8 = %s (locked %d, tether %.2f), body x %.2f, grounded %s"
		% [str(B.a_freelen[KB] >= 0.0), int(B.a_locked[KB]), float(B.a_freelen[KB]),
		   B.body_pos.x, str(B.grounded)])
	A.free(); B.free()
	print("")

func _initialize() -> void:
	print("A7 (27.2,-1.5) -> A8 (35.0,1.5). 7.8 m along, 3.0 m down, 8.36 m apart.")
	print("Whip is 5.25 m; arm reach 1.15 m. The body must get within ~6.4 m of A8.")
	print("")
	run(2.4, 24.0)
	run(2.4, 40.0)
	run(1.6, 24.0)
	quit(0)
