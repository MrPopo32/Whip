extends SceneTree
## Tick-by-tick: what happens to the body in the 1.5 s after the hand opens.
## Same A/B counterfactual as fb/drag.gd, but printed as a timeline, so the
## question "is it a drag or is it a leash" can be answered by looking at
## whether the body's distance from the beam PLATEAUS (leash) or merely grows
## slowly (drag).

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

func _contacts(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[0] - m.p_rad[i] < 0.005:
			n += 1
	return n

# arc length of chain from the handle to the last particle still touching
func _spooled(m: Node2D) -> float:
	var c: Vector2 = m.a_pos[0]
	var hi := -1
	var lo := 99
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[0] - m.p_rad[i] < 0.02:
			hi = maxi(hi, i)
			lo = mini(lo, i)
	if hi < 0:
		return 0.0
	return float(m.cum_len[hi]) - float(m.cum_len[lo])

func _snap(hang: float, r: float, turns: float, drop: float, rel: float) -> Dictionary:
	var m := PUMP.rig(hang, r, turns, deg_to_rad(6.0), drop)
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free(); return {}
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var last_pk := 0.0; var half := 0; var sgn := 0.0
	for t in 2400:
		if m.a_freelen[0] < 0.0:
			break
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
				"th": absf(float(m.a_theta[0])), "spool": _spooled(m),
				"amp": last_pk}
			m.free()
			return d
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 95.0)
		prev = m.body_pos
		step2(m, cur, true)
	m.free()
	return {}

func step2(m: Node2D, c: Vector2, g: bool) -> void:
	m.step_tick(c, g)

func _run(hang: float, r: float, turns: float, rel: float, n: int) -> void:
	var e := _snap(hang, r, turns, 4.5, rel)
	if e.is_empty():
		print("   (no release)"); return
	print("   tether %.2f m, pin idx %d, wrap %.2f rad, %.2f m of chain on the beam, swing amp %.0f deg"
		% [float(e["teth"]), int(e["pin"]), float(e["th"]), float(e["spool"]),
		   float(e["amp"])])
	var A := PUMP.rig(hang, r, turns, deg_to_rad(6.0), 4.5)
	LEAP.load_state(A, e["snap"])
	var B := PUMP.rig(hang, r, turns, deg_to_rad(6.0), 4.5)
	LEAP.load_state(B, e["snap"])
	B.a_pos[0] = Vector2(0.0, 900.0); B.a_r[0] = 0.001
	B.a_freelen[0] = -1.0; B.a_pinidx[0] = -1; B.a_locked[0] = -1
	var beam := Vector2(0.0, -40.0)
	print("    t   contact  spooled |  A: dist   speed   v_radial  |  B: dist  speed | A-B speed  A-B dist")
	var pa: Vector2 = A.body_pos
	var pb: Vector2 = B.body_pos
	for t in range(1, n + 1):
		pa = A.body_pos; pb = B.body_pos
		A.step_tick(A.body_pos, false)
		B.step_tick(B.body_pos, false)
		var va: Vector2 = (A.body_pos - pa) * 60.0
		var vb: Vector2 = (B.body_pos - pb) * 60.0
		var da: float = A.body_pos.distance_to(beam)
		var db: float = B.body_pos.distance_to(beam)
		var rh: Vector2 = (A.body_pos - beam).normalized()
		if t <= 12 or t % 4 == 0:
			print("   %3d   %4d    %5.2f  |  %6.2f  %6.2f   %+6.2f    |  %6.2f  %5.2f |  %+6.2f    %+6.2f"
				% [t, _contacts(A), _spooled(A), da, va.length(), va.dot(rh),
				   db, vb.length(), va.length() - vb.length(), da - db])
	print("")

func _initialize() -> void:
	print("THE DISMOUNT, TICK BY TICK.  v_radial > 0 = moving away from the beam;")
	print("v_radial < 0 = being pulled BACK toward it.")
	print("")
	print("A) the leapable catch: 2.4 m tether, r 0.10, released at 24 deg")
	_run(2.4, 0.10, 1.8, 24.0, 72)
	print("B) the short greedy catch: 1.6 m tether, r 0.10, released at 24 deg")
	_run(1.6, 0.10, 1.8, 24.0, 72)
	print("C) the long catch: 3.2 m tether, r 0.10, released at 24 deg")
	_run(3.2, 0.10, 1.8, 24.0, 72)
	quit(0)
