extends SceneTree
## THE BUDGET COST OF THE DRAG, on a clean two-beam bench: beam A in open air
## with 4.5 m under it, beam B 7.8 m along and 3.0 m down (the fast line's own
## spacing), floor stepped to match, and nothing else in the world to snag.
## Same release tick, two forks, and the whole timeline for each.

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

const GAP := 7.8
const DROP := 3.0

func rig() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for k in range(2, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0); m.a_r[0] = 0.10
	m.a_pos[1] = Vector2(GAP, -40.0 + DROP); m.a_r[1] = 0.10
	# two tiers, each 4.5 m under its own beam
	var pts: Array[Vector2] = [Vector2(-30.0, -35.5), Vector2(GAP - 1.0, -35.5),
		Vector2(GAP - 1.0, -35.5 + DROP), Vector2(40.0, -35.5 + DROP)]
	for i in range(pts.size() - 1):
		m.t_a.append(pts[i]); m.t_b.append(pts[i + 1])
	for i in m.t_a.size():
		var ab: Vector2 = m.t_b[i] - m.t_a[i]
		m.t_n.append(Vector2(ab.y, -ab.x).normalized())
	return m

func wind(m: Node2D, hang: float) -> void:
	LEAP._wind_on(m, 0, hang, 1.8, deg_to_rad(6.0))

func contacts(m: Node2D, k: int) -> int:
	var c: Vector2 = m.a_pos[k]
	var n := 0
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[k] - m.p_rad[i] < 0.005:
			n += 1
	return n

func snap1(hang: float, rel: float) -> Dictionary:
	var m := rig(); wind(m, hang)
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
				"teth": float(m.a_freelen[0]), "wrap": absf(float(m.a_theta[0])),
				"amp": last_pk}
			m.free(); return d
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	m.free(); return {}

func fly(hang: float, e: Dictionary, kill: bool, close_at: int) -> Dictionary:
	var m := rig(); wind(m, hang)
	LEAP.load_state(m, e["snap"])
	if kill:
		m.a_pos[0] = Vector2(0.0, 900.0); m.a_r[0] = 0.001
		m.a_freelen[0] = -1.0; m.a_pinidx[0] = -1; m.a_locked[0] = -1
	var B: Vector2 = m.a_pos[1]
	var v: Vector2 = (m.body_pos - Vector2(e["prev"])) * 60.0
	var tmin := 0; var dmin := 1e9
	for i in 240:
		var tt: float = float(i) / 60.0
		var q: Vector2 = m.body_pos + v * tt + Vector2(0.0, 5.0 * tt * tt)
		if q.distance_to(B) < dmin: dmin = q.distance_to(B); tmin = i
	var s0: int = clampi(tmin - 38, 4, 18)
	var wnd: Vector2 = (B - m.body_pos).normalized().rotated(PI)
	var aim := Vector2.ZERO
	var drag := -1; var qual := -1; var ground := -1; var caught := -1
	var dnear := 1e9
	for f in 200:
		if f == s0:
			aim = (B - m.body_pos).normalized().rotated(-0.5)
		var dirv: Vector2 = wnd if f < s0 else aim
		var grip: bool = close_at >= 0 and f >= close_at and f < close_at + 15
		m.step_tick(m.body_pos + dirv * m.REACH, grip)
		if not kill and contacts(m, 0) > 0: drag = f
		if qual < 0 and absf(float(m.a_theta[1])) >= float(m.th_part): qual = f
		dnear = minf(dnear, m.body_pos.distance_to(B))
		if m.grounded and ground < 0: ground = f
		if caught < 0 and m.a_freelen[1] >= 0.0: caught = f
		if caught >= 0 and f > caught + 60: break
		if ground >= 0 and close_at < 0 and f > ground + 4: break
		if ground >= 0 and f > ground + 12: break
	var held: bool = m.a_freelen[1] >= 0.0
	var lk: int = int(m.a_locked[1])
	m.free()
	return {"drag": drag, "qual": qual, "ground": ground, "caught": caught,
		"held": held, "lk": lk, "s0": s0, "dnear": dnear}

func line(hang: float, rel: float, kill: bool) -> void:
	var e := snap1(hang, rel)
	if e.is_empty():
		print("   %.1f  %3.0f   (no release)" % [hang, rel]); return
	var base := fly(hang, e, kill, -1)
	var good: Array = []
	var f := 0
	while f < 140:
		var q := fly(hang, e, kill, f)
		if bool(q["held"]):
			good.append(f)
		f += 3
	var lo := -1; var hi := -1
	if not good.is_empty():
		lo = int(good[0]); hi = int(good[good.size() - 1])
	print("   %.2f %3.0f %5.2f  %s  %6s %5d  %6s  %6.2f  %6s   %s"
		% [float(e["teth"]), rel, float(e["wrap"]),
		   "FREE" if kill else "REAL",
		   ("t=%d" % int(base["drag"])) if int(base["drag"]) >= 0 else "-",
		   int(base["s0"]),
		   ("t=%d" % int(base["qual"])) if int(base["qual"]) >= 0 else "never",
		   float(base["dnear"]),
		   ("t=%d" % int(base["ground"])) if int(base["ground"]) >= 0 else ">200",
		   ("t=%d..%d (%d of %d sampled)" % [lo, hi, good.size(), 47]) if lo >= 0 else "NEVER TAKES"])

func _initialize() -> void:
	print("CLEAN TWO-BEAM BENCH: beam B is %.1f m along and %.1f m down, each beam"
		% [GAP, DROP])
	print("with 4.5 m of air. Nothing else in the world. Ticks are from the")
	print("instant the hand opens. 'press' = every tick a press actually takes B.")
	print("")
	print("   teth rel  wrap  fork  dragto  stroke   B wraps  closest  lands   press window")
	for hang in [2.0, 2.4, 2.8]:
		for rel in [12.0, 24.0, 40.0]:
			line(hang, rel, false)
			line(hang, rel, true)
		print("")
	quit(0)
