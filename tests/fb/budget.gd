extends SceneTree
## THE FLOW BUDGET of one beam-to-beam cycle, measured on the REAL level.
## A7 (27.2, -1.5) -> A8 (35.0, 1.5): the fast line's own 7.8 m gap, 4.5 m of
## air under each beam.
##
## The cycle, in the order the player lives it:
##   pump on A7 -> OPEN the hand (t = 0) -> the drag -> the stroke -> the wave
##   runs out to A8 -> the wrap forms -> the press window -> CLOSE the hand.
## Everything below is in ticks at 60 Hz; the airtime is the whole budget and
## every other number is a withdrawal from it.
##
## Each row is run twice from the identical release tick:
##   REAL  the shipped build
##   FREE  the same release with beam A7 removed on the release tick, i.e. the
##         dismount the player thinks they are asking for.

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

func snaps(hang: float, rels: Array) -> Array:
	var m := new_level()
	LEAP._wind_on(m, KA, hang, 1.8, deg_to_rad(6.0))
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[KA] < 0.0:
		m.free(); return []
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var last_pk := 0.0; var half := 0; var sgn := 0.0
	var got := {}
	var out: Array = []
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
		if (last_pk >= 55.0 or half >= 22) and om > 0.0:
			for rel in rels:
				if th >= float(rel) and not got.has(rel):
					got[rel] = true
					out.append({"snap": LEAP.save_state(m), "prev": prev,
						"rel": float(rel), "amp": last_pk,
						"teth": float(m.a_freelen[KA]),
						"pin": int(m.a_pinidx[KA]),
						"wrap": absf(float(m.a_theta[KA]))})
		if got.size() == rels.size(): break
		if t > 1200 and out.is_empty(): break
		var cur: Vector2 = PUMP.pump_cursor(m, KA, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	m.free()
	return out

func fly(e: Dictionary, hang: float, kill: bool) -> Dictionary:
	var m := new_level()
	LEAP._wind_on(m, KA, hang, 1.8, deg_to_rad(6.0))
	LEAP.load_state(m, e["snap"])
	if kill:
		m.a_pos[KA] = Vector2(0.0, 900.0); m.a_r[KA] = 0.001
		m.a_freelen[KA] = -1.0; m.a_pinidx[KA] = -1; m.a_locked[KA] = -1
	var p: Dictionary = LEAP.default_policy()
	p["amp_max"] = 250.0
	p["max_half"] = 22
	var st := LEAP.leap_begin(m, KA, KB, p)
	st["phase"] = "fly"
	st["rel_t"] = 0
	st["f"] = 0
	var v: Vector2 = (m.body_pos - Vector2(e["prev"])) * 60.0
	var B: Vector2 = m.a_pos[KB]
	var tmin := 0; var dmin := 1e9
	for i in 240:
		var tt: float = float(i) / 60.0
		var q: Vector2 = m.body_pos + v * tt + Vector2(0.0, 0.5 * 10.0 * tt * tt)
		var dd: float = q.distance_to(B)
		if dd < dmin: dmin = dd; tmin = i
	st["s0"] = clampi(tmin - int(p["lead"]), int(p["s0_min"]), int(p["s0_max"]))
	var u: Vector2 = (B - m.body_pos).normalized()
	st["wind"] = u.rotated(PI)
	var prev: Vector2 = m.body_pos
	# ---- timeline recorders ----
	var drag_end := -1        # last tick the chain still touched A7
	var stroke_t: int = int(st["s0"])
	var tip_t := -1           # tip first within 0.5 m of A8
	var arm_t := -1           # theta_B first >= grip_arm (2.6)
	var qual_t := -1          # theta_B first >= th_part (3.4) or a pinch
	var win := 0              # ticks in the first unbroken qualifying window
	var win_run := 0
	var ground_t := -1
	var caught_t := -1
	var v_at := {}
	var vfree := v.length()
	for f in 200:
		var cg: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		m.step_tick(cg[0], cg[1])
		if not kill and contacts(m, KA) > 0:
			drag_end = f
		var thb: float = absf(float(m.a_theta[KB]))
		if tip_t < 0 and m.pos[m.NP - 1].distance_to(B) < 0.5:
			tip_t = f
		if arm_t < 0 and thb >= 2.6:
			arm_t = f
		var q: bool = thb >= float(m.th_part)
		if q:
			if qual_t < 0: qual_t = f
			win_run += 1
			win = maxi(win, win_run)
		else:
			win_run = 0
		if f in [8, 16, 24, 32, 40, 56]:
			v_at[f] = (m.body_pos - prev).length() * 60.0
		if m.grounded and ground_t < 0:
			ground_t = f
		if m.a_freelen[KB] >= 0.0 and caught_t < 0:
			caught_t = f
		if ground_t >= 0 and f > ground_t + 20:
			break
	var dclose: float = 1e9
	m.free()
	return {"v0": vfree, "drag_end": drag_end, "stroke": stroke_t,
		"tip": tip_t, "arm": arm_t, "qual": qual_t, "win": win,
		"ground": ground_t, "caught": caught_t, "v": v_at}

func _initialize() -> void:
	print("THE FLOW BUDGET, A7 -> A8 on the real level (7.8 m gap, 4.5 m of air).")
	print("All figures in TICKS at 60 Hz. 'airtime' is the whole budget: release")
	print("to the feet touching the tier below.")
	print("")
	for hang in [1.6, 2.0, 2.4, 2.8, 3.2]:
		var ss := snaps(hang, [16.0, 24.0, 32.0, 40.0, 52.0])
		if ss.is_empty():
			print("  hang %.1f m: never pumped to a release" % hang)
			continue
		print("  == start hang %.1f m  (tether %.2f m, pin %d, wrap %.2f rad) =="
			% [hang, float(ss[0]["teth"]), int(ss[0]["pin"]), float(ss[0]["wrap"])])
		print("    rel  amp   fork  |v0|   drag ends  stroke  tip@A8  wrap>=2.6  wrap>=3.4  press win  airtime  CAUGHT")
		for e in ss:
			for kill in [false, true]:
				var r := fly(e, hang, kill)
				print("    %3.0f  %3.0f   %s  %5.2f    %6s   %5d   %6s    %7s    %7s     %5d    %6s   %s"
					% [float(e["rel"]), float(e["amp"]),
					   "FREE" if kill else "REAL", float(r["v0"]),
					   ("t=%d" % int(r["drag_end"])) if int(r["drag_end"]) >= 0 else "-",
					   int(r["stroke"]),
					   ("t=%d" % int(r["tip"])) if int(r["tip"]) >= 0 else "never",
					   ("t=%d" % int(r["arm"])) if int(r["arm"]) >= 0 else "never",
					   ("t=%d" % int(r["qual"])) if int(r["qual"]) >= 0 else "never",
					   int(r["win"]),
					   ("t=%d" % int(r["ground"])) if int(r["ground"]) >= 0 else ">200",
					   ("t=%d" % int(r["caught"])) if int(r["caught"]) >= 0 else "no"])
		print("")
	quit(0)
