extends SceneTree
## THE PRESS WINDOW, by brute force. Fly one leg with the hand OPEN throughout,
## then replay it once per tick, closing the hand on that tick and only that
## tick, and record whether the far beam takes. The set of ticks that work IS
## the press window - not a threshold crossing, the actual thing the player has
## to hit.

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

func new_level() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	return m

func snap1(ka: int, kb: int, hang: float, rel: float) -> Dictionary:
	var m := new_level()
	LEAP._wind_on(m, ka, hang, 1.8, deg_to_rad(6.0))
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[ka] < 0.0:
		m.free(); return {}
	var dir: float = signf(float(m.a_pos[kb].x) - float(m.a_pos[ka].x))
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var last_pk := 0.0; var half := 0; var sgn := 0.0
	for t in 2400:
		if m.a_freelen[ka] < 0.0: break
		var s := PUMP.swing_state(m, ka, prev)
		var th: float = rad_to_deg(float(s["theta"])) * dir
		var om: float = float(s["omega"]) * dir
		pk = maxf(pk, absf(th))
		var sg: float = signf(th)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0:
				last_pk = pk; half += 1
			sgn = sg; pk = 0.0
		if (last_pk >= 55.0 or half >= 22) and om > 0.0 and th >= rel:
			var d := {"snap": LEAP.save_state(m), "prev": prev,
				"teth": float(m.a_freelen[ka]), "wrap": absf(float(m.a_theta[ka])),
				"amp": last_pk}
			m.free(); return d
		var cur: Vector2 = PUMP.pump_cursor(m, ka, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	m.free(); return {}

func try_close(ka: int, kb: int, hang: float, e: Dictionary, close_at: int) -> Array:
	var m := new_level()
	LEAP._wind_on(m, ka, hang, 1.8, deg_to_rad(6.0))
	LEAP.load_state(m, e["snap"])
	var B: Vector2 = m.a_pos[kb]
	var v: Vector2 = (m.body_pos - Vector2(e["prev"])) * 60.0
	var tmin := 0; var dmin := 1e9
	for i in 240:
		var tt: float = float(i) / 60.0
		var q: Vector2 = m.body_pos + v * tt + Vector2(0.0, 5.0 * tt * tt)
		if q.distance_to(B) < dmin: dmin = q.distance_to(B); tmin = i
	var s0: int = clampi(tmin - 38, 4, 18)
	var wind: Vector2 = (B - m.body_pos).normalized().rotated(PI)
	var aim := Vector2.ZERO
	var theta_at := 0.0
	var caught := -1
	var ground := -1
	for f in 200:
		if f == s0:
			aim = (B - m.body_pos).normalized().rotated(-0.5)
		var dirv: Vector2 = wind if f < s0 else aim
		var grip: bool = close_at >= 0 and f >= close_at and f < close_at + 15
		if f == close_at:
			theta_at = absf(float(m.a_theta[kb]))
		m.step_tick(m.body_pos + dirv * m.REACH, grip)
		if caught < 0 and m.a_freelen[kb] >= 0.0:
			caught = f
		if m.grounded and ground < 0:
			ground = f
		if caught >= 0 and f > caught + 60: break
		if ground >= 0 and close_at < 0: break
		if ground >= 0 and f > ground + 10: break
	var held: bool = m.a_freelen[kb] >= 0.0
	var lk: int = int(m.a_locked[kb])
	m.free()
	return [held, lk, caught, ground, theta_at]

func run(ka: int, kb: int, hang: float, rel: float) -> void:
	var e := snap1(ka, kb, hang, rel)
	if e.is_empty():
		print("  A%d->A%d hang %.1f rel %.0f: no release" % [ka, kb, hang, rel]); return
	var base := try_close(ka, kb, hang, e, -1)
	var air: int = int(base[3])
	var good: Array = []
	var locks: Array = []
	for f in range(0, 130):
		var q := try_close(ka, kb, hang, e, f)
		if bool(q[0]):
			good.append(f)
			if int(q[1]) == 1:
				locks.append(f)
	var runs: Array = []
	var s := -1; var p := -999
	for f in good:
		if int(f) != p + 1:
			if s >= 0: runs.append([s, p])
			s = int(f)
		p = int(f)
	if s >= 0: runs.append([s, p])
	var txt: Array = []
	for r in runs:
		txt.append("t=%d..%d (%d ticks)" % [r[0], r[1], r[1] - r[0] + 1])
	print("  A%d -> A%d, hang %.1f m (tether %.2f, wrap %.2f rad), release at %.0f deg"
		% [ka, kb, hang, float(e["teth"]), float(e["wrap"]), rel])
	print("     hand-open flight lands at t=%s. Press windows that take A%d: %s"
		% [("%d" % air) if air >= 0 else ">200", kb,
		   ", ".join(PackedStringArray(txt)) if not txt.is_empty() else "NONE"])
	print("     of those, %d ticks give a LOCK; %d give a partial"
		% [locks.size(), good.size() - locks.size()])

func _initialize() -> void:
	print("THE PRESS WINDOW - every tick on which closing the hand actually takes")
	print("the far beam. GRIP_WINDOW is 15 ticks, so one press is honoured for 15.")
	print("")
	run(7, 8, 2.4, 16.0)
	run(7, 8, 2.4, 24.0)
	run(7, 8, 2.0, 16.0)
	run(8, 9, 2.0, 28.0)
	quit(0)
