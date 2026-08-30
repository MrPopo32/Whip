extends SceneTree
## HOW FAR CAN ONE DISMOUNT ACTUALLY THROW YOU? The number that decides beam
## spacing. Release off a pumped swing on an isolated beam with 4.5 m of air
## under it (fast-line geometry) and measure the horizontal distance the body
## covers before its feet touch the tier below.
##
##   REAL   the shipped build, hand doing the leap's own windup+stroke
##   STRIP  the shipped build, hand hauled straight away from the beam (the
##          technique that fb/hand.gd found strips the coil fastest)
##   FREE   the same release with the beam removed on the release tick
##
## Also reported: the wave transit time, i.e. how long the whip needs between a
## hand movement and the tip answering it.

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

func _contacts(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[0] - m.p_rad[i] < 0.005:
			n += 1
	return n

func _snaps(hang: float, r: float, rels: Array) -> Array:
	var m := PUMP.rig(hang, r, 1.8, deg_to_rad(6.0), 4.5)
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free(); return []
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var last_pk := 0.0; var half := 0; var sgn := 0.0
	var got := {}
	var out: Array = []
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
		if (last_pk >= 55.0 or half >= 22) and om > 0.0:
			for rel in rels:
				if th >= float(rel) and not got.has(rel):
					got[rel] = true
					out.append({"snap": LEAP.save_state(m), "prev": prev,
						"rel": float(rel), "amp": last_pk,
						"teth": float(m.a_freelen[0]),
						"pin": int(m.a_pinidx[0]),
						"wrap": absf(float(m.a_theta[0]))})
		if got.size() == rels.size(): break
		if t > 1200 and out.is_empty(): break
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	m.free()
	return out

func _reach(hang: float, r: float, e: Dictionary, mode: String) -> Array:
	var m := PUMP.rig(hang, r, 1.8, deg_to_rad(6.0), 4.5)
	LEAP.load_state(m, e["snap"])
	if mode == "free":
		m.a_pos[0] = Vector2(0.0, 900.0); m.a_r[0] = 0.001
		m.a_freelen[0] = -1.0; m.a_pinidx[0] = -1; m.a_locked[0] = -1
	var beam := Vector2(0.0, -40.0)
	var x0: float = m.body_pos.x
	var v0: Vector2 = (m.body_pos - Vector2(e["prev"])) * 60.0
	var fwd: Vector2 = v0.normalized()
	var away: Vector2 = (m.body_pos - beam).normalized()
	var target: Vector2 = m.body_pos + fwd * 8.0
	var maxdx := 0.0
	var land := -1
	var landx := 0.0
	var clear_at := -1
	var run := 0
	for t in range(1, 241):
		var cur: Vector2 = m.body_pos
		if mode == "strip":
			cur = m.body_pos + away * m.REACH
		elif mode == "real" or mode == "free":
			if t <= 14:
				cur = m.body_pos - fwd * m.REACH
			else:
				cur = m.body_pos + (target - m.body_pos).normalized().rotated(-0.5) * m.REACH
		m.step_tick(cur, false)
		if mode != "free":
			if _contacts(m) == 0:
				run += 1
				if run >= 5 and clear_at < 0: clear_at = t - 4
			else:
				run = 0
		if land < 0:
			maxdx = maxf(maxdx, absf(m.body_pos.x - x0))
			if m.grounded:
				land = t
				landx = absf(m.body_pos.x - x0)
	if land < 0:
		landx = maxdx
	return [landx, maxdx, land, clear_at]

func _wave() -> void:
	# WAVE TRANSIT: hold the body still, flick the hand, time the tip's answer.
	print("WAVE TRANSIT - how long after a hand movement the tip answers.")
	print("   flick     handle peak   tip peak   transit")
	for flick in [6, 10, 16]:
		var m: Node2D = load("res://main.gd").new()
		m.external_drive = true
		m.setup_sim()
		m.teleport(Vector2(0, -30))
		for t in 90:
			m.body_prv = m.body_pos
			m.step_tick(m.body_pos + Vector2(0.9, -0.5), false)
		var hp := -1; var tp := -1
		var hbest := 0.0; var tbest := 0.0
		var prev_h: Vector2 = m.pos[0]
		for t in 120:
			m.body_prv = m.body_pos
			var tgt: Vector2 = m.body_pos + (Vector2(-1.0, -0.5) if t < flick
				else Vector2(-0.2, -0.9))
			prev_h = m.pos[0]
			m.step_tick(tgt, false)
			var hv: float = (m.pos[0] - prev_h).length() * 60.0
			if hv > hbest: hbest = hv; hp = t
			if m.tip_speed > tbest: tbest = m.tip_speed; tp = t
		print("   %2d tk    t=%3d %5.1f    t=%3d %5.1f   %d ticks (%.0f ms)"
			% [flick, hp, hbest, tp, tbest, tp - hp, (tp - hp) * 1000.0 / 60.0])
		m.free()
	print("")

func _initialize() -> void:
	_wave()
	print("REACH: horizontal metres covered from the release point before landing")
	print("on the tier 4.5 m below. Beam spacing can be no wider than the body can")
	print("carry the whip's own 5.25 m of reach.")
	print("")
	print("   tether  r     rel  amp  wrap   REAL reach  STRIP reach  FREE reach   drag cost   clear")
	for hang in [1.6, 2.0, 2.4, 2.8, 3.2]:
		for r in [0.10, 0.22]:
			var ss := _snaps(hang, r, [16.0, 24.0, 32.0, 40.0, 52.0])
			for e in ss:
				var A := _reach(hang, r, e, "real")
				var S := _reach(hang, r, e, "strip")
				var F := _reach(hang, r, e, "free")
				var best: float = maxf(A[0], S[0])
				print("   %5.2f  %.2f  %3.0f  %3.0f  %5.2f    %5.2f m      %5.2f m     %5.2f m    %+5.2f m   %s"
					% [float(e["teth"]), r, float(e["rel"]), float(e["amp"]),
					   float(e["wrap"]), A[0], S[0], F[0], best - F[0],
					   ("t=%d" % int(A[3])) if int(A[3]) >= 0 else "never"])
	quit(0)
