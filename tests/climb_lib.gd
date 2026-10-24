extends RefCounted
## CLIMB LIB - the launch-footprint rig (MOVE 2: "max jump").
##
## FRAME. The beam is at the ORIGIN, r 0.11 (a door beam). The THROWING FLOOR is
## y = F0 = +2.2 (Y IS DOWN), so a height h "above the floor you came from" is
## sim y = F0 - h. The beam is at h = +2.2.
##
## THE HANG IS THROWN, NOT LAID. The body stands on a real floor at y = F0 that
## ends in a 0.35 m-filleted lip at x = -1.4 (the shipped door geometry), throws
## route_bot's plan_throw grid stroke at the beam, shuts the hand on the wrap
## reading (tapelib.try_throw, unchanged) and holds 90 ticks: the catch hauls it
## off the lip. THEN THE FLOOR IS TAKEN AWAY - the brief's open air, no terrain
## anywhere - and the hang settles 120 ticks with the hand shut. Two catches:
##   S  lead 1.8 m, stroke 18 (a0 1.10pi a1 -0.42pi sd 5)          tether 1.63 m
##   L  lead 2.9 m, stroke 21 (a0 1.10pi a1 -0.42pi sd 9 pull)     tether 2.60 m
## both found by tests/climb_catch.gd (every stroke of the grid at 7 leads).
##
## THE PUMP is bot_pump.pump_cursor, the servo, unchanged. It servos on an
## energy estimate that runs optimistic (bot_leap's note), so pump_to() wraps it
## in an outer loop that nudges the TARGET it hands the servo until the TRUE
## amplitude - peak |theta| of each completed half-swing - sits at A.
##
## THE RELEASE is the hand opening the tick after the body crosses a chosen
## angle theta_rel about the beam in a chosen direction of travel (or at a dead
## point, "apex"), shifted by `jit` ticks. The flight is the hand open with the
## cursor parked on the body (plus tremor under noise).

const TL := preload("res://tests/tapelib.gd")
const PUMP := preload("res://tests/bot_pump.gd")
const NOISE := preload("res://tests/hand_noise.gd")

const F0 := 2.2
const LIP_X := -1.4
const BEAM_R := 0.11
const CATCH := {
	"S": {"lead": 1.8, "c": {"a0": PI * 1.10, "a1": -PI * 0.42, "sd": 5,
		"pull": false, "w": 120}},
	"L": {"lead": 2.9, "c": {"a0": PI * 1.10, "a1": -PI * 0.42, "sd": 9,
		"pull": true, "w": 120}},
}

# ------------------------------------------------------------------ worlds --
static func _clear_terrain(m: Node2D) -> void:
	m.t_a.clear(); m.t_b.clear()
	m.t_arc_c.clear(); m.t_arc_r.clear(); m.t_arc_ang.clear()

static func door_world(m: Node2D, lead: float) -> void:
	_clear_terrain(m)
	m.t_a.append(Vector2(-30.0, F0)); m.t_b.append(Vector2(LIP_X, F0))
	m.t_a.append(Vector2(LIP_X, F0)); m.t_b.append(Vector2(LIP_X, 30.0))
	m._fillet(Vector2(LIP_X, F0), 0.35)
	m._finish_terrain()
	m._clear_anchor_tables()
	m._add_anchor(Vector2.ZERO, BEAM_R, 0, "B")
	m._av_size()
	m.spawn = Vector2(-lead, F0 - 0.28)
	m.goal_x = 999.0
	m._reset()

static func open_air(m: Node2D) -> void:
	_clear_terrain(m)
	m._finish_terrain()
	m.world_bottom = 1.0e5

## A PILLAR: the ledge you land on. Top at height h above the throwing floor,
## near edge (lip) at |x| = x0 on the side `dir` (+1 = +x), width w, faces
## running 12 m down - a cliff step with a drop behind it. Both top corners
## are filleted at 0.35 m, the scene loader's ground default (a lip).
static func pillar(m: Node2D, x0: float, h: float, w: float, dir: int,
		door := false) -> void:
	_clear_terrain(m)
	if door:
		_door_floor(m)
	var yl := F0 - h
	var xa := x0 if dir > 0 else -(x0 + w)
	var xb := xa + w
	var yb := yl + 12.0
	# wound solid-inside: top L->R (air up), right face down, bottom R->L,
	# left face up
	var P := [Vector2(xa, yl), Vector2(xb, yl), Vector2(xb, yb), Vector2(xa, yb)]
	for i in 4:
		m.t_a.append(P[i]); m.t_b.append(P[(i + 1) % 4])
	m._fillet(Vector2(xa, yl), 0.35)
	m._fillet(Vector2(xb, yl), 0.35)
	if door:
		m._fillet(Vector2(LIP_X, F0), 0.35)
	m._finish_terrain()
	m.world_bottom = 1.0e5

## THE DOOR KEPT: the throwing floor and its lip left standing in the swing.
static func _door_floor(m: Node2D) -> void:
	m.t_a.append(Vector2(-30.0, F0)); m.t_b.append(Vector2(LIP_X, F0))
	m.t_a.append(Vector2(LIP_X, F0)); m.t_b.append(Vector2(LIP_X, 30.0))

static func door_only(m: Node2D) -> void:
	_clear_terrain(m)
	_door_floor(m)
	m._fillet(Vector2(LIP_X, F0), 0.35)
	m._finish_terrain()
	m.world_bottom = 1.0e5

# ---------------------------------------------------------------- the hang --
static func make_hang(which: String) -> Dictionary:
	var cfg: Dictionary = CATCH[which]
	var m: Node2D = TL.new_sim()
	door_world(m, float(cfg["lead"]))
	for t in 60:
		m.step_tick(m.body_pos, false)
	var r: Dictionary = TL.try_throw(m, 0, cfg["c"])
	var ok := bool(r["caught"]) and int(r["locked"]) == 1 and bool(r["held"])
	open_air(m)
	for t in 120:
		m.step_tick(m.body_pos, true)
	ok = ok and float(m.a_freelen[0]) >= 0.0 and int(m.a_locked[0]) == 1
	return {"m": m, "ok": ok, "tether": float(m.a_freelen[0]),
		"locked": int(m.a_locked[0]), "pin": int(m.a_pinidx[0]),
		"body": m.body_pos, "throw": r}

# ------------------------------------------------------------ swing reading --
static func theta_of(p: Vector2) -> float:
	return atan2(p.x, p.y)             # beam at the origin; 0 = straight down

static func wrapd(a: float) -> float:
	return wrapf(a, -PI, PI)

## Half-swing peak tracker on the TRUE body angle about the beam.
class Swing:
	var prev := 0.0
	var pk := 0.0
	var peaks: Array = []            # deg, completed half-swings
	var bdir: Array = []             # direction at each bottom crossing
	var n := 0
	func start(th: float) -> void:
		prev = th
		pk = absf(th)
	func feed(th: float) -> void:
		var d := wrapf(th - prev, -PI, PI)
		# a bottom crossing: sign flips while both are in the lower half
		if signf(th) != signf(prev) and absf(th) < PI * 0.5 \
				and absf(prev) < PI * 0.5:
			peaks.append(rad_to_deg(pk))
			bdir.append(signf(d))
			pk = 0.0
		pk = maxf(pk, absf(th))
		prev = th
		n += 1
	func circulating() -> bool:
		# two bottom crossings in a row in the same direction = went round
		var k := bdir.size()
		return k >= 2 and bdir[k - 1] == bdir[k - 2]
	func last(k: int) -> Array:
		return peaks.slice(maxi(peaks.size() - k, 0))

## One tick of the servo with an optional noise model on the cursor.
static func pump_tick(m: Node2D, prev: Vector2, target: float, hn: Variant) -> void:
	var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, target)
	if hn != null:
		cur += hn.tick()
	m.step_tick(cur, true)

## Servo to a TRUE amplitude A (deg). A >= 180 = over the top: pump flat out
## until the body circulates, then hold (the servo's gain is zero at PI).
## Returns {ok, ticks, target, peaks, prev} and leaves m at the settle tick.
static func pump_to(m: Node2D, A: float, hn: Variant = null, cap := 3000,
		loose := false) -> Dictionary:
	# REFUSE A BODY THAT IS NOT HANGING. The first null (mode=nograb) caught
	# this passing on nothing: a stroke thrown with the hand open had left 20
	# rad of rope on the beam, the servo's closed hand made the catch itself,
	# and the pump "settled". A pump is only a pump on a wrap that exists.
	if float(m.a_freelen[0]) < 0.0 or int(m.a_locked[0]) != 1:
		return {"ok": false, "why": "not hanging on a lock", "ticks": 0,
			"target": 0.0, "peaks": [], "prev": m.body_pos}
	var sw := Swing.new()
	sw.start(theta_of(m.body_pos))
	var prev: Vector2 = m.body_pos
	var target := 0.0 if A >= 180.0 else A
	var tol := maxf(6.0, 0.05 * A)
	var last_adj := 0
	var circ_t := -1
	for t in cap:
		var pb: Vector2 = m.body_pos
		pump_tick(m, prev, target, hn)
		prev = pb
		if float(m.a_freelen[0]) < 0.0:
			return {"ok": false, "why": "wrap lost", "ticks": t, "target": target,
				"peaks": sw.peaks, "prev": prev}
		sw.feed(theta_of(m.body_pos))
		if A >= 180.0:
			if sw.circulating():
				if circ_t < 0:
					circ_t = t
					target = 180.0
				elif t - circ_t > 90 and sw.circulating():
					return {"ok": true, "ticks": t, "target": target,
						"peaks": sw.peaks, "prev": prev, "circ": true}
			continue
		var np := sw.peaks.size()
		# LOOSE: a swing the servo cannot hold (over ~110 deg the rope goes
		# slack at the top and every half-swing is different) is taken the
		# first time a completed half-swing peaks inside the band, after 6
		if loose and np >= 6 and absf(float(sw.peaks[np - 1]) - A) <= tol 				and not sw.circulating():
			return {"ok": true, "ticks": t, "target": target, "loose": true,
				"peaks": sw.peaks, "prev": prev, "circ": false}
		if np >= 3 and np != last_adj:
			var l2: Array = sw.last(2)
			if absf(float(l2[0]) - A) <= tol and absf(float(l2[1]) - A) <= tol \
					and not sw.circulating():
				return {"ok": true, "ticks": t, "target": target,
					"peaks": sw.peaks, "prev": prev, "circ": false}
			# the outer loop: every 4 half-swings, move the servo's target by
			# the true shortfall (or excess) of the last three
			if np % 4 == 0:
				var l3: Array = sw.last(3)
				var mean := (float(l3[0]) + float(l3[1]) + float(l3[2])) / 3.0
				var spread := absf(float(l3[2]) - float(l3[0]))
				if spread < 8.0 and absf(mean - A) > tol:
					target = clampf(target + 0.8 * (A - mean), 10.0, 179.0)
				last_adj = np
	return {"ok": false, "why": "never settled", "ticks": cap, "target": target,
		"peaks": sw.peaks, "prev": prev}

# ---------------------------------------------------------------- release --
## Continue the servo from the current state until the body crosses theta_rel
## (deg) moving in direction dir (+1 = theta increasing), or the dead point
## (spec "apex" with dir = the side), then open the hand `jit` ticks later
## (jit < 0: earlier, via a ring of snapshots). Returns the release record and
## leaves m on the tick the hand opened (grip false has been applied once).
static func release(m: Node2D, prev0: Vector2, target: float, th_rel: float,
		dir: int, apex: bool, jit: int, hn: Variant, max_t := 420) -> Dictionary:
	var prev: Vector2 = prev0
	var ring: Array = []
	var pre: PackedVector2Array = PackedVector2Array()
	var thp := theta_of(m.body_pos)
	var omp := 0.0
	var sw := Swing.new()
	sw.start(thp)
	var tr := deg_to_rad(th_rel)
	var hit := -1
	for t in max_t:
		if jit < 0:
			ring.append({"s": m.snapshot(), "prev": prev,
				"hn": hn.save_state() if hn != null else {}})
			if ring.size() > -jit + 1:
				ring.pop_front()
		var pb: Vector2 = m.body_pos
		pump_tick(m, prev, target, hn)
		prev = pb
		pre.append(m.body_pos)
		if float(m.a_freelen[0]) < 0.0:
			return {"ok": false, "why": "wrap lost"}
		if m.grounded:
			return {"ok": false, "why": "hit terrain during swing", "t": t}
		var th := theta_of(m.body_pos)
		sw.feed(th)
		var om := wrapd(th - thp)
		var crossed := false
		if t >= 2:
			if apex:
				crossed = (dir > 0 and th > 0.0 and omp > 0.0 and om <= 0.0) \
					or (dir < 0 and th < 0.0 and omp < 0.0 and om >= 0.0)
			else:
				var d0 := wrapd(thp - tr)
				var d1 := wrapd(th - tr)
				crossed = absf(d1 - d0) < PI * 0.5 and (
					(dir > 0 and d0 < 0.0 and d1 >= 0.0) or
					(dir < 0 and d0 > 0.0 and d1 <= 0.0))
		thp = th
		omp = om
		if crossed:
			hit = t
			break
	if hit < 0:
		return {"ok": false, "why": "never crossed", "amp": sw.peaks}
	if jit > 0:
		for j in jit:
			var pb2: Vector2 = m.body_pos
			pump_tick(m, prev, target, hn)
			prev = pb2
			pre.append(m.body_pos)
			if float(m.a_freelen[0]) < 0.0 or m.grounded:
				return {"ok": false, "why": "lost during jit"}
	elif jit < 0:
		var back: Dictionary = ring[0]
		m.restore(back["s"])
		prev = back["prev"]
		if hn != null:
			hn.restore_state(back["hn"])
	var v: Vector2 = (m.body_pos - prev) * 60.0
	var rec := {"ok": true, "t": hit + jit, "pos": m.body_pos, "vel": v,
		"theta": rad_to_deg(theta_of(m.body_pos)), "speed": v.length(),
		"amp": sw.peaks.duplicate(), "pre": pre}
	# OPEN THE HAND
	var cur: Vector2 = m.body_pos
	if hn != null:
		cur += hn.tick()
	m.step_tick(cur, false)
	rec["off"] = float(m.a_freelen[0]) < 0.0
	return rec

## The flight with the hand open. Records the body per tick. With stop = true
## it runs until 120 ticks after the first ground contact.
static func fly(m: Node2D, hn: Variant, max_t := 300, y_stop := F0 + 2.0,
		stop := false) -> Dictionary:
	var tr := PackedVector2Array()
	tr.append(m.body_pos)
	var first := -1
	var g60 := {}
	var g120 := {}
	var air_after := 0
	var max_air_after := 0
	for t in max_t:
		var cur: Vector2 = m.body_pos
		if hn != null:
			cur += hn.tick()
		var pb: Vector2 = m.body_pos
		m.step_tick(cur, false)
		tr.append(m.body_pos)
		if stop:
			if m.grounded and first < 0:
				first = t
			if first >= 0:
				if not m.grounded:
					air_after += 1
					max_air_after = maxi(max_air_after, air_after)
				else:
					air_after = 0
				var v: float = (m.body_pos - pb).length() * 60.0
				if t == first + 60:
					g60 = {"g": m.grounded, "p": m.body_pos, "v": v}
				if t == first + 120:
					g120 = {"g": m.grounded, "p": m.body_pos, "v": v}
					break
		if not stop and m.body_pos.y > y_stop and m.body_pos.y > pb.y:
			break
		if stop and first < 0 and m.body_pos.y > F0 + 6.0:
			break
	return {"traj": tr, "first": first, "g60": g60, "g120": g120,
		"max_air_after": max_air_after}

## THE VERDICT on a stop run, against pillar (x0, h, w, dir).
static func verdict(f: Dictionary, x0: float, h: float, w: float, dir: int) -> String:
	if int(f["first"]) < 0:
		return "MISS"
	var yl := F0 - h
	var xa := x0 if dir > 0 else -(x0 + w)
	var xb := xa + w
	var tr: PackedVector2Array = f["traj"]
	var p0: Vector2 = tr[int(f["first"]) + 1]
	var ontop := func(p: Vector2) -> bool:
		return p.y < yl - 0.20 and p.y > yl - 0.40 and p.x >= xa - 0.05 \
			and p.x <= xb + 0.05
	if not ontop.call(p0):
		return "FACE"                   # first contact below the top: a wall
	if f["g60"].is_empty() or f["g120"].is_empty():
		return "SLIDEOFF"
	var a: Dictionary = f["g60"]
	var b: Dictionary = f["g120"]
	if bool(a["g"]) and bool(b["g"]) and ontop.call(a["p"]) and ontop.call(b["p"]) \
			and float(b["v"]) < 0.30:
		if int(f["max_air_after"]) > 6:
			return "STOP_BOUNCED"       # rests, but left the ground on the way
		return "STOP"
	if int(f["max_air_after"]) > 6 and ontop.call(b["p"]) == false:
		return "BOUNCEOFF"
	return "SLIDEOFF"
