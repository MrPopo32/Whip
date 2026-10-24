extends RefCounted
## THE DOOR UP - the bench for MOVE 4 (a door beam over a gap, launched UP onto
## a ledge). Everything is thrown, pumped and released through step_tick; no
## state is hand-laid. new_sim() never enters the tree; save_enabled = false.
##
## ORIGIN: the F0 lip corner. x = 0 is the lip face, y = 0 is the F0 floor.
## Y IS DOWN IN THE SIM (GRAV +y). Every number this bench PRINTS is in "up"
## metres (h > 0 = above F0) unless it says "y".
##
## THE WORLD (ground chain, air on the left as you walk it):
##   left wall x = -12   |  F0 floor y = 0, x -12..0  |  lip face x = 0 down to
##   the pit floor y = +D |  pit floor x 0..G         |  ledge face x = G up to
##   y = -h               |  LEDGE top y = -h, x G..G+3 (3 m wide)
##   far face x = G+3 down to y = +D (the ledge is a step, not a shelf against a
##   wall: overshoot falls off the far side, and that is a failure)
##   far floor x G+3..G+12 at y = +D, seal.
##   Fillets 0.35 m at the two convex lips (0,0) and (G,-h) and (G+3,-h), as
##   every shipped lip.
##   Door beam (1.4, -2.2) r 0.11 - every shipped door.
const TL := preload("res://tests/tapelib.gd")
const PUMP := preload("res://tests/bot_pump.gd")
const HN := preload("res://tests/hand_noise.gd")

const DOOR := Vector2(1.4, -2.2)
const DOOR_R := 0.11
const LEDGE_W := 3.0

# route_bot / lab_throw's 36-stroke grid, three leads outside it (the lead is
# where you stand). 36 x leads = the standing-throw search.
const A0S := [0.85, 1.10]
const A1S := [-0.42, -0.30, -0.18]
const SDS := [5, 9, 14]

static func grid36() -> Array:
	var g: Array = []
	for a0 in A0S:
		for a1 in A1S:
			for sd in SDS:
				for pull in [false, true]:
					g.append({"a0": PI * float(a0), "a1": PI * float(a1),
						"sd": sd, "pull": pull, "w": 120,
						"name": "a0 %.2fpi a1 %+.2fpi sd %d %s" % [a0, a1, sd,
							"pull" if pull else "push"]})
	return g

## Build the world into a fresh sim. extra: Array of [Vector2 pos, r] anchors
## appended AFTER the door (door is always k = 0 when door = true).
## far = "step" (drop off the ledge's far side) or "wall" (a riser at G+3).
static func make(G: float, h: float, D := 3.0, door := true, extra: Array = [],
		far := "step", spawn_x := -3.0) -> Node2D:
	var m: Node2D = TL.new_sim()
	m.save_enabled = false
	m.t_a.clear(); m.t_b.clear()
	m.t_arc_c.clear(); m.t_arc_r.clear(); m.t_arc_ang.clear()
	var pts: Array = [Vector2(-12.0, -25.0), Vector2(-12.0, 0.0),
		Vector2(0.0, 0.0), Vector2(0.0, D), Vector2(G, D), Vector2(G, -h),
		Vector2(G + LEDGE_W, -h)]
	if far == "wall":
		pts.append(Vector2(G + LEDGE_W, -h - 25.0))
	else:
		pts.append(Vector2(G + LEDGE_W, D))
		pts.append(Vector2(G + LEDGE_W + 9.0, D))
		pts.append(Vector2(G + LEDGE_W + 9.0, -25.0))
	for i in range(pts.size() - 1):
		m.t_a.append(pts[i]); m.t_b.append(pts[i + 1])
	var ok1: bool = m._fillet(Vector2(0.0, 0.0), 0.35)
	var ok2: bool = m._fillet(Vector2(G, -h), 0.35)
	var ok3 := true
	if far != "wall":
		ok3 = m._fillet(Vector2(G + LEDGE_W, -h), 0.35)
	assert(ok1 and ok2 and ok3)
	m._finish_terrain()
	m._clear_anchor_tables()
	if door:
		m._add_anchor(DOOR, DOOR_R, 0, "DOOR")
	for e: Array in extra:
		m._add_anchor(e[0], float(e[1]), 0, "X")
	if m.a_pos.size() == 0:
		m._add_anchor(Vector2(-900.0, -900.0), 0.1, 0, "NONE")
	m._av_size()
	m.spawn = Vector2(spawn_x, -m.BODY_R)
	m.goal_x = 999.0
	m._reset()
	return m

# ------------------------------------------------------------ the stance --
## Put the body on a floor at x (floor top y = fy), whip laid back by holding
## the hand at a0 for 90 ticks (lab_throw.stand_at / climb bench idiom).
static func stand(m: Node2D, x: float, fy: float, a0: float) -> void:
	m.teleport(Vector2(x, fy - m.BODY_R))
	for t in 90:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)

## One standing throw at anchor k, with a hand-noise model. mirror = throw
## toward -x (angles reflected). Two-pass press shift for the noise's timing
## term (climb bench idiom). never_grip = the must-report-nothing control.
static func throw(m: Node2D, k: int, c: Dictionary, hn: RefCounted,
		mirror := false, never_grip := false, dpress := 0,
		off := Vector2.ZERO) -> Dictionary:
	var w := int(c["w"])
	var shift: int = int(hn.jit) + dpress
	var s0: Dictionary = m.snapshot()
	var hs0: Dictionary = hn.save_state()
	var r1 := _pass(m, k, c, hn, -1, mirror, never_grip, off)
	if shift != 0 and int(r1["g0"]) >= 0:
		m.restore(s0)
		hn.restore_state(hs0)
		var r2 := _pass(m, k, c, hn, maxi(0, int(r1["g0"]) + shift), mirror,
			never_grip, off)
		r2["g0"] = r1["g0"]
		return r2
	return r1

static func _ang(a: float, mirror: bool) -> float:
	return PI - a if mirror else a

static func _pass(m: Node2D, k: int, c: Dictionary, hn: RefCounted, press: int,
		mirror: bool, never_grip: bool, off: Vector2) -> Dictionary:
	var w := int(c["w"])
	var grip := false
	var closes := 0
	var g0 := -1
	var caught := false
	var et := -1
	for t in w + 130:
		var te := float(t - w) / float(hn.speed) if t >= w else -1.0
		var ang := float(c["a0"])
		var amp := 1.0
		if t >= w:
			if te < float(c["sd"]):
				ang = float(c["a1"])
			elif bool(c["pull"]) and te < float(c["sd"]) + 10.0:
				ang = float(c["a0"]); amp = 0.7
			else:
				ang = float(c["a1"])
		var a := _ang(ang, mirror)
		var o: Vector2 = off if t >= w else Vector2.ZERO
		var tgt: Vector2 = m.body_pos + Vector2(cos(a), sin(a)) * m.REACH * amp \
			+ hn.tick() + o
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var fire := false
		if press >= 0 and closes == 0:
			fire = t >= press
		else:
			fire = absf(float(m.a_theta[k])) >= 2.6
		if never_grip:
			fire = false
		if not grip and fire and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	var lock := false
	var tether := -1.0
	if caught:
		tether = float(m.a_freelen[k])
		for t in 55:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		lock = float(m.a_freelen[k]) >= 0.0 and int(m.a_locked[k]) == 1
	return {"caught": caught, "lock": lock, "et": et, "g0": g0,
		"tether": tether, "hash": m.state_hash(), "grounded": m.grounded}

## route_bot.haul_off: hand shut, cursor out at the anchor, until airborne.
static func haul(m: Node2D, k: int, cap := 240) -> int:
	var t := 0
	while t < cap and m.grounded and float(m.a_freelen[k]) >= 0.0:
		var d: Vector2 = (Vector2(m.a_pos[k]) - m.body_pos).normalized()
		m.step_tick(m.body_pos + d * m.REACH, true)
		t += 1
	return t

# ------------------------------------------------------------ the swing --
## True body angle about the beam (deg from straight down, + = +x side).
static func body_deg(m: Node2D, k: int) -> float:
	var p: Vector2 = m.a_pos[k]
	return rad_to_deg(atan2(m.body_pos.x - p.x, m.body_pos.y - p.y))

## Pump with bot_pump's servo (target deg, <= 0 flat out). dir = +1 means the
## launch goes to +x. Stops at the first BACK APEX (the body turning from
## moving -dir to moving +dir on the -dir side) after the last COMPLETED
## +dir-side half-swing peaked >= want (deg), or after max_half half-swings,
## or cap ticks. Returns the record; the sim is left AT that back apex.
## hn: its tremor+offset is added to the pump cursor (the pump is a hand too).
static func pump_to(m: Node2D, k: int, target: float, want: float, dir: float,
		hn: RefCounted, max_half := 30, cap := 2400) -> Dictionary:
	var prev: Vector2 = m.body_pos
	var th_prev := body_deg(m, k) * dir
	var om_prev := 0.0
	var sgn := 0.0
	var pk := 0.0
	var last_pk_f := 0.0      # last completed +dir half-swing peak
	var last_pk_b := 0.0      # last completed -dir half-swing peak
	var half := 0
	var ground := 0
	var over := false
	var th_u := th_prev
	for t in cap:
		if float(m.a_freelen[k]) < 0.0:
			return {"ok": false, "why": "lost the beam pumping", "t": t,
				"amp_f": last_pk_f, "amp_b": last_pk_b, "half": half,
				"ground": ground}
		var th := body_deg(m, k) * dir
		var d := th - th_prev
		if d > 180.0: d -= 360.0
		elif d < -180.0: d += 360.0
		th_u += d
		if absf(th_u) > 180.0:
			over = true
		var om := d
		pk = maxf(pk, absf(th))
		var sg: float = signf(th)
		if sg != 0.0 and sg != sgn:
			if sgn > 0.0:
				last_pk_f = pk
				half += 1
			elif sgn < 0.0:
				last_pk_b = pk
				half += 1
			sgn = sg
			pk = 0.0
		# back apex: on the -dir side, angular velocity turns from - to +
		var ready := last_pk_f >= want or half >= max_half or over
		if ready and th < 0.0 and om_prev < 0.0 and om >= 0.0 and t > 2:
			return {"ok": true, "t": t, "amp_f": last_pk_f, "amp_b": last_pk_b,
				"half": half, "ground": ground, "prev": prev, "over": over,
				"th": th}
		if ready and over and t > 2:
			# circulating: no back apex exists. Release sweep starts at the
			# bottom on the way round instead.
			if th_prev < 0.0 and th >= 0.0 and om > 0.0:
				return {"ok": true, "t": t, "amp_f": 180.0, "amp_b": 180.0,
					"half": half, "ground": ground, "prev": prev, "over": true,
					"th": th}
		om_prev = om
		th_prev = th
		if m.grounded:
			ground += 1
		var cur: Vector2 = PUMP.pump_cursor(m, k, prev, target) + hn.tick()
		prev = m.body_pos
		m.step_tick(cur, true)
	return {"ok": false, "why": "never reached the release swing", "t": cap,
		"amp_f": last_pk_f, "amp_b": last_pk_b, "half": half, "ground": ground}

## Keep pumping n more ticks (same servo), then OPEN THE HAND and fly with the
## cursor parked on the body. Classify where it ends. Returns the outcome.
static func release_after(m: Node2D, k: int, target: float, n: int,
		prev0: Vector2, hn: RefCounted, G: float, h: float, D: float,
		fly := 360) -> Dictionary:
	var prev := prev0
	for t in n:
		if float(m.a_freelen[k]) < 0.0:
			break
		var cur: Vector2 = PUMP.pump_cursor(m, k, prev, target) + hn.tick()
		prev = m.body_pos
		m.step_tick(cur, true)
	var v: Vector2 = (m.body_pos - prev) * 60.0
	var rel_deg := body_deg(m, k)
	var rel_pos: Vector2 = m.body_pos
	var still := 0
	var maxup: float = -m.body_pos.y
	var t_end := fly
	for t in fly:
		m.step_tick(m.body_pos, false)
		maxup = maxf(maxup, -m.body_pos.y)
		var sp: float = (m.body_pos - m.body_prv).length() / m.SDT
		if m.grounded and sp < 0.25:
			still += 1
		else:
			still = 0
		if still >= 30:
			t_end = t
			break
	var out := classify(m, G, h, D)
	# STOP: it must still be there 120 ticks later, hand open
	if out["where"] == "LEDGE":
		for t in 120:
			m.step_tick(m.body_pos, false)
		var o2 := classify(m, G, h, D)
		if o2["where"] != "LEDGE":
			out["where"] = "SLID:" + String(o2["where"])
	out["v"] = v.length()
	out["vang"] = rad_to_deg(atan2(-v.y, v.x))
	out["rel_deg"] = rel_deg
	out["rel_pos"] = rel_pos
	out["maxup"] = maxup - m.BODY_R    # feet height reached, up metres
	out["t_end"] = t_end
	out["still"] = still >= 30
	return out

static func classify(m: Node2D, G: float, h: float, D: float) -> Dictionary:
	var b: Vector2 = m.body_pos
	var feet_up: float = -(b.y + m.BODY_R)
	var where := "AIR"
	if m.grounded or true:
		if b.x < 0.0 and absf(feet_up) < 0.25:
			where = "F0"
		elif b.x >= G - 0.05 and b.x <= G + LEDGE_W + 0.05 \
				and absf(feet_up - h) < 0.25:
			where = "LEDGE"
		elif b.x > 0.0 and b.x < G and absf(feet_up + D) < 0.3:
			where = "PIT"
		elif b.x > G + LEDGE_W and absf(feet_up + D) < 0.3:
			where = "FAR"
		elif b.y > D + 1.0:
			where = "OUT"
	return {"where": where, "x": b.x, "up": feet_up, "grounded": m.grounded}

# ------------------------------------------------ one pump, many releases --
## Ballistic forecast of the BODY CENTRE from p with v (prefilter only - the
## real flight is always simulated). Returns the x where it comes DOWN through
## the ledge-top line y = -h - BODY_R, or NAN if it never gets that high.
static func ballistic_land(p: Vector2, v: Vector2, h: float, br: float) -> float:
	var ytop := -h - br
	var above := p.y <= ytop
	for i in range(1, 240):
		var t := float(i) / 60.0
		var q := p + v * t + Vector2(0.0, 5.0 * t * t)
		var vy := v.y + 10.0 * t
		if q.y <= ytop:
			above = true
		elif above and vy > 0.0:
			return q.x
	return NAN

## The flight after the hand opens, cursor parked on the body. early = stop as
## soon as the outcome is decided (below the ledge top and outside its span,
## descending). Classifies; a LEDGE landing must also still be there after a
## further `stay` ticks, hand open.
static func fly(m: Node2D, G: float, h: float, D: float, early := true,
		cap := 360, stay := 90) -> Dictionary:
	var still := 0
	var maxup: float = -m.body_pos.y - m.BODY_R
	var prev: Vector2 = m.body_pos
	var t_end := cap
	var why := ""
	for t in cap:
		prev = m.body_pos
		m.step_tick(m.body_pos, false)
		var b: Vector2 = m.body_pos
		maxup = maxf(maxup, -b.y - m.BODY_R)
		var sp: float = (b - prev).length() * 60.0
		if m.grounded and sp < 0.25:
			still += 1
		else:
			still = 0
		if still >= 20:
			t_end = t
			break
		if early and b.y > prev.y and b.y > -h + 0.3:
			if b.x < G - 0.4 or b.x > G + LEDGE_W + 0.4:
				why = "early"
				t_end = t
				break
	var out := classify(m, G, h, D)
	if why == "early":
		# decided but not landed: name it by the side it fell on
		out["where"] = "PIT" if m.body_pos.x < G else "FAR"
	if String(out["where"]) == "LEDGE":
		for t in stay:
			m.step_tick(m.body_pos, false)
		var o2 := classify(m, G, h, D)
		if String(o2["where"]) != "LEDGE":
			out["where"] = "SLID-" + String(o2["where"])
		out["x_final"] = m.body_pos.x
	out["maxup"] = maxup
	out["t_end"] = t_end
	return out

static func code(w: String) -> String:
	match w:
		"LEDGE": return "L"
		"PIT": return "p"
		"FAR": return "f"
		"F0": return "0"
		"AIR": return "a"
	if w.begins_with("SLID"):
		return "s"
	return "?"
