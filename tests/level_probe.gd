extends SceneTree
## LEVEL PROBE v2 - the safety-contract gate.
##
## WHAT THIS GATE IS FOR. The lash gait crawls flat ground at ~0.44 m/s and
## CANNOT climb even a 20 degree slope (tests/ground_probe.gd,
## tests/escape_probe.gd), so a body can never walk out of anywhere. Every
## surface a body can come to rest on therefore needs a beam it can actually
## catch from a standstill, or a fall there ends the run. That is the only
## thing this file certifies, and v1 certified it from a state no run is ever
## in.
##
## FOUR DEFECTS IN v1. The first two were found by tests/route_bot.gd; the
## third and fourth turned up while fixing them. All four are fixed here.
##
## (1) THE DRAPE MADE AN INVALID START. v1 laid the chain along the terrain by
##     sampling floor_y(x) at each particle's arc length. The terrain steps
##     3.0 m down at x=20, so for any throwing spot within a whip length past
##     the cliff, ONE 0.2 m segment was placed spanning that 3 m step - a 13.6x
##     stretch. The rope constraint is one-sided (main.gd _solve_rope only acts
##     when l > rest), so that segment snapped shut in the first substep and
##     threw the whip. Every verdict v1 ever printed for A5 came from it.
##     FIX: drape by ARC LENGTH along the connected terrain contour, vertical
##     faces included, instead of by x. Chord <= arc, so a contour drape can
##     never stretch a segment; compression is free because the rope never
##     pushes. Section 0 prints both, and the run REFUSES to report a verdict
##     from a start whose worst segment exceeds STRETCH_TOL.
##
## (2) THE STARTING LAYOUT WAS A HIDDEN VARIABLE WORTH ~30x THE LOCK RATE.
##     Over the same 576-stroke grid, a hand-draped chain locked 100 times
##     where a chain that had arrived by crawling 6 m locked 4. "Every recovery
##     beam LOCKS from a standstill" was measured from a state the game cannot
##     produce. FIX: nothing is hand-placed at the throwing spot any more. The
##     chain must ARRIVE, by one of the three routes a run actually takes:
##       crawl  seeded 6 m back on the same flat, settled, then walked in on
##              the lash gait - the commonest state by far
##       fall   dropped from 3 m up at the spot, landed, settled - the state
##              after a missed catch
##       drop   wound onto the previous recovery beam, hand opened, landed,
##              then crawled in - the state after leaving a beam
##     A recovery beam has to LOCK from ALL THREE or it is not a safety net,
##     it is a safety net that works when you have not needed it yet.
##
## (3) THE WINDUP WAS A FIXED 30 TICKS. The windup is the only chance a stroke
##     gets to lay out a whip the level left in a heap, and 120 ticks catches
##     2-3x as often as 30. v1 hard-coded 30, so it was measuring a stroke no
##     one would throw. Both are run here and both are printed, so the cost of
##     the windup stays visible; the verdict takes the better one.
##
## (4) "LOCK" WAS A TRANSIENT. v1 latched a_locked == 1 at ANY tick of a
##     150-tick window. A wrap that reads LOCKED for three ticks and then pays
##     out is a betrayal, not a catch. Here a LOCK must still be locked after
##     SETTLE ticks of hanging on it.
##
## WHAT THE GATE ASSERTS NOW. A beam can be catchable and not launchable, so
## catchability alone is no longer the whole contract:
##   G-A  SAFETY     every floor a body can rest on has a beam that LOCKS from
##                   all three arrival states. Failure = a terminal fall.
##   G-B  EGRESS     every beam that LOCKS can be left. Leaving by LAUNCH (a
##                   real swing) or by DROP (fall to a floor G-A covers) both
##                   pass; a beam that can only be left by dropping is a DEAD
##                   END and is counted, because a level of them is a crawl
##                   with extra steps.
##   G-C  PROGRESSION  the fast tier must be enterable: at least one fast beam
##                   within launch range of a LAUNCHABLE beam. Not a safety
##                   assert - the assert v1 was missing entirely, and the
##                   reason a level could pass its gate while being a 62 m
##                   crawl. NECESSARY only: the gate can say a launchable beam
##                   is close enough, and route_bot proves the crossing.
##   G-D  CEILING    no FAST beam may LOCK from a standstill on the ground, or
##                   the skill ceiling is reachable by standing under it.
##
## A FIFTH, IN THE SHARED RIG, not fixed at source. bot_leap._wind_on - the rig
## bot_pump, bot_leap and route_bot's hang table all start from - places the
## free tail at e + (+-0.3, s) as it leaves the wrap, which teleports the first
## tail particle 0.3 m sideways off the circle it just left. Measured
## 1.90-1.92 x rest on every beam in this level, the same class of invalid
## start as defect 1. This file uses its own wind_on() with a tail that hangs
## from where the wrap ends; the shared one is left alone because changing it
## would silently move every number bot_pump and bot_leap have published.
##
## COST. Roughly an hour, against v1's four minutes, because nothing is placed
## by hand any more - most of the clock is the crawl arrivals. Run it before
## shipping a level, not in a loop. Do NOT run two Godot instances against one
## project directory while it works: they share .godot and both die with
## exit 127. Copy the project if you want to parallelise.
##
## Run:
##   godot --headless --path . -s res://tests/level_probe.gd
##   godot --headless --path . -s res://tests/level_probe.gd -- "" run.log
##       (second arg = a log flushed line by line, so an hour-long run that
##        dies half way still shows what it had got to)
##   godot --headless --path . -s res://tests/level_probe.gd -- drape
##       (section 0 only - the drape defect, seconds instead of minutes)
##   godot --headless --path . -s res://tests/level_probe.gd -- control
##       (the layout experiment: v1's hand-drape against the three arrivals)
##   godot --headless --path . -s res://tests/level_probe.gd -- 7
##       (one beam, by index)

const LEAP := preload("res://tests/bot_leap.gd")
const PUMP := preload("res://tests/bot_pump.gd")

# the lash gait at the parameters tests/ground_probe.gd measured best
const GAIT_PERIOD := 24
const GAIT_BACK := 2.83
const GAIT_FWD := -0.94
const GAIT_TAUT := 0.50

# v1's stroke grid, unchanged, so the verdicts are comparable
# v1's three leads plus a nearer one. v1 reported 1.8 as the winning lead for
# every single beam, i.e. its ladder was pressed against its own near end, so a
# FAIL from it could always have been the grid rather than the level.
const LEADS := [3.0, 2.4, 1.8, 1.4]   # far to near: the order a player uses
const A0S := [PI * 0.85, PI * 1.10]
const A1S := [-PI * 0.42, -PI * 0.30, -PI * 0.18]
const SDS := [5, 9, 14]
const WINDUPS := [120, 30]

const SETTLE := 55                    # ticks a LOCK must survive after the catch
const STRETCH_TOL := 1.02             # a start above this is not a start
const SEED_BACK := 6.0                # how far back the crawl arrival begins
const FALL_H := 3.0                   # how high the fall arrival begins
const LAUNCH_AMP := 45.0              # deg of swing that counts as launchable
const LAUNCH_GND := 0.50              # ... with feet down less than half the time
const PUMP_TICKS := 1200              # 20 s of pumping flat out

var sim_ticks := 0
var _log: FileAccess = null

func say(t: String) -> void:
	## This gate runs for over an hour. Godot block-buffers stdout when it is
	## redirected, so a run that dies half way leaves an empty file and an hour
	## of nothing. Pass a path as the second user arg and every line is flushed
	## to it as it is produced.
	print(t)
	if _log != null:
		_log.store_line(t)
		_log.flush()

# the connected terrain surface, as one ordered polyline
var c_pt := PackedVector2Array()
var c_nm := PackedVector2Array()
var c_vn := PackedVector2Array()      # mitred vertex normals (see build_contour)
var c_cu := PackedFloat32Array()
var c_len := 0.0

# ------------------------------------------------------------------ basics --

func nl() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	return m

func step(m: Node2D, cur: Vector2, grip: bool) -> void:
	m.step_tick(cur, grip)
	sim_ticks += 1

func floor_y(m: Node2D, x: float) -> float:
	var best := 99.0
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		if absf(B.x - A.x) < 0.01:
			continue
		if x < minf(A.x, B.x) or x > maxf(A.x, B.x):
			continue
		var t := (x - A.x) / (B.x - A.x)
		best = minf(best, A.y + (B.y - A.y) * t)
	return best

func beam_height(m: Node2D, k: int) -> float:
	return floor_y(m, float(m.a_pos[k].x)) - float(m.a_pos[k].y)

func is_fast(m: Node2D, k: int) -> bool:
	return beam_height(m, k) > 4.0

func stretch(m: Node2D) -> float:
	var w := 0.0
	for i in m.rest.size():
		var d: float = m.pos[i].distance_to(m.pos[i + 1]) / float(m.rest[i])
		if d > w:
			w = d
	return w

# ------------------------------------------------------- the terrain contour --
# DEFECT 1. Chain the terrain segments head to tail into one ordered surface,
# vertical faces included, and measure position along it by ARC LENGTH. This is
# the whole fix: sampling by x cannot see a vertical face, so it places two
# consecutive particles on opposite sides of a 3 m cliff.

func build_contour(m: Node2D) -> void:
	c_pt = PackedVector2Array()
	c_nm = PackedVector2Array()
	c_vn = PackedVector2Array()
	c_cu = PackedFloat32Array()
	var n: int = m.t_a.size()
	var start := -1
	for i in n:
		var head := true
		for j in n:
			if i != j and m.t_a[i].distance_to(m.t_b[j]) < 0.001:
				head = false
				break
		if head:
			start = i
			break
	if start < 0:
		start = 0
	var order: Array[int] = [start]
	var used := {start: true}
	while true:
		var last: int = order[order.size() - 1]
		var nxt := -1
		for j in n:
			if used.has(j):
				continue
			if m.t_a[j].distance_to(m.t_b[last]) < 0.001:
				nxt = j
				break
		if nxt < 0:
			break
		order.append(nxt)
		used[nxt] = true
	c_pt.append(m.t_a[order[0]])
	c_nm.append(m.t_n[order[0]])
	c_cu.append(0.0)
	var acc := 0.0
	for oi in order.size():
		var s: int = order[oi]
		acc += float(m.t_a[s].distance_to(m.t_b[s]))
		c_pt.append(m.t_b[s])
		c_nm.append(m.t_n[s])
		c_cu.append(acc)
	c_len = acc
	# MITRE THE OFFSET. Offsetting each particle along its own segment's normal
	# makes the offset direction jump 90 degrees across the cliff top, which
	# pushes the two particles straddling that corner apart by ~sqrt(2)*radius -
	# measured 1.05 x rest at A5's seed, over tolerance and for no physical
	# reason. A normal averaged at each vertex is continuous, so the corner
	# costs a little compression instead, which the rope does not resist.
	for i in c_pt.size():
		var a: Vector2 = c_nm[maxi(i, 1)]
		var b: Vector2 = c_nm[mini(i + 1, c_nm.size() - 1)]
		c_vn.append((a + b).normalized() if (a + b).length() > 0.001 else a)

func c_point(u: float, off: float) -> Vector2:
	# compression at a corner is free (the rope never pushes), clamping is not
	# a stretch, so both ends are safe to clamp
	var uu := clampf(u, 0.0, c_len)
	var i := 0
	while i < c_cu.size() - 2 and float(c_cu[i + 1]) < uu:
		i += 1
	var seg: float = maxf(float(c_cu[i + 1]) - float(c_cu[i]), 0.0001)
	var t: float = clampf((uu - float(c_cu[i])) / seg, 0.0, 1.0)
	var nrm: Vector2 = Vector2(c_vn[i]).lerp(Vector2(c_vn[i + 1]), t).normalized()
	return c_pt[i].lerp(c_pt[i + 1], t) + nrm * off

func c_u_at(m: Node2D, x: float) -> float:
	# arc length of the FLOOR point at x - the surface a body rests on
	var fy := floor_y(m, x)
	var best := 0.0
	var found := false
	for i in range(c_pt.size() - 1):
		var A: Vector2 = c_pt[i]
		var B: Vector2 = c_pt[i + 1]
		if absf(B.x - A.x) < 0.01:
			continue
		if x < minf(A.x, B.x) - 0.001 or x > maxf(A.x, B.x) + 0.001:
			continue
		var t := (x - A.x) / (B.x - A.x)
		if absf(A.y + (B.y - A.y) * t - fy) > 0.05:
			continue
		best = float(c_cu[i]) + t * (float(c_cu[i + 1]) - float(c_cu[i]))
		found = true
	if not found:
		best = 0.0
	return best

func drape(m: Node2D, sx: float) -> float:
	## The SEED only - never the throwing state. Body on the floor at sx, chain
	## laid back along the contour by arc length. Returns the worst segment
	## stretch, which must be <= 1.0 by construction.
	build_contour(m)
	var fy := floor_y(m, sx)
	m.body_pos = Vector2(sx, fy - m.BODY_R)
	m.body_prv = m.body_pos
	var u0 := c_u_at(m, sx) + 0.3
	for i in m.pos.size():
		var p := c_point(u0 - float(m.cum_len[i]) * 0.99, float(m.p_rad[i]))
		m.pos[i] = p
		m.prv[i] = p
	return stretch(m)

func drape_v1_stretch(m: Node2D, sx: float) -> float:
	## v1's drape, computed but never installed, so section 0 can print what it
	## would have started from.
	var fy := floor_y(m, sx)
	var pts := PackedVector2Array()
	for i in m.pos.size():
		var px: float = sx + 0.3 - float(m.cum_len[i]) * 0.99
		var py := floor_y(m, px)
		if py > 90.0:
			py = fy
		pts.append(Vector2(px, minf(py, fy) - float(m.p_rad[i])))
	var w := 0.0
	for i in m.rest.size():
		var d: float = pts[i].distance_to(pts[i + 1]) / float(m.rest[i])
		if d > w:
			w = d
	return w

# ---------------------------------------------------------- a clean wind-on --

func wind_on(m: Node2D, k: int, hang: float, turns: float, th0: float) -> void:
	## bot_leap._wind_on with the tail fixed. Its last branch places the free
	## tail at e + (+-0.3, s), which teleports the first tail particle 0.3 m
	## sideways off the circle it just left: measured 1.90-1.92 x rest on every
	## beam in this level, in the rig bot_pump, bot_leap and route_bot's hang
	## table all start from. Here the tail leaves the wrap where the wrap ends
	## and hangs straight down from it, which costs nothing and stretches
	## nothing.
	var c: Vector2 = m.a_pos[k]
	var rr: float = float(m.a_r[k]) + 0.04
	var d := Vector2(sin(th0), cos(th0))
	var a_start: float = d.angle()
	var rise: float = hang - rr
	var wl: float = turns * TAU * rr
	for i in m.pos.size():
		var sarc: float = float(m.cum_len[i])
		var q: Vector2
		if sarc < rise:
			q = c + d * (hang - sarc)
		elif sarc < rise + wl:
			var a: float = a_start + (sarc - rise) / rr
			q = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = a_start + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			q = e + Vector2(0.0, sarc - rise - wl)
		m.pos[i] = q
		m.prv[i] = q
	m.body_pos = c + d * (hang + 0.6)
	m.body_prv = m.body_pos

# ------------------------------------------------------------- the arrivals --

func settle(m: Node2D, n: int) -> void:
	# hand OPEN so any wrap is dropped, and held BACK so the whip is not left
	# in a pile under the feet (route_bot section 3: from a pile, none of the
	# 36 strokes even catches)
	for t in n:
		step(m, m.body_pos + Vector2(cos(PI * 1.10), sin(PI * 1.10)) * m.REACH,
			false)

func crawl_to(m: Node2D, xstop: float, cap := 4000) -> bool:
	var t := 0
	var stall := 0
	var lastx: float = m.body_pos.x
	while m.body_pos.x < xstop and t < cap:
		var f := float(t % GAIT_PERIOD) / float(GAIT_PERIOD)
		var tgt: Vector2
		var grip := false
		if f < 0.45:
			tgt = m.body_pos + Vector2(cos(GAIT_BACK), sin(GAIT_BACK)) * m.REACH
		else:
			tgt = m.body_pos + Vector2(cos(GAIT_FWD), sin(GAIT_FWD)) * m.REACH
			grip = f > GAIT_TAUT
		step(m, tgt, grip)
		t += 1
		if t % 120 == 0:
			if m.body_pos.x - lastx < 0.15:
				stall += 1
				if stall >= 3:
					break
			else:
				stall = 0
			lastx = m.body_pos.x
	return m.body_pos.x >= xstop - 0.35

func flat_left(m: Node2D, x: float) -> float:
	# left edge of the flat run the throwing spot sits on, plus a margin: the
	# crawl arrival must not have to walk off a cliff to get started
	var fy := floor_y(m, x)
	var q := x
	while q > -200.0:
		var t := q - 0.1
		if absf(floor_y(m, t) - fy) > 0.05:
			break
		q = t
	return q + 0.6

func prev_recovery(m: Node2D, k: int) -> int:
	var best := -1
	for j in m.a_pos.size():
		if j == k or is_fast(m, j):
			continue
		if float(m.a_pos[j].x) >= float(m.a_pos[k].x):
			continue
		if best < 0 or float(m.a_pos[j].x) > float(m.a_pos[best].x):
			best = j
	return best

func arrive(m: Node2D, mode: String, k: int, bx: float) -> Dictionary:
	## Put the sim into a state a run produces, with the body at bx. Returns
	## {"ok", "seed_stretch", "why"}. ok == false means this arrival cannot be
	## staged for this beam, which is itself a finding, not a pass.
	if mode == "crawl":
		var sx := maxf(bx - SEED_BACK, flat_left(m, bx))
		var st := drape(m, sx)
		if st > STRETCH_TOL:
			return {"ok": false, "seed_stretch": st, "why": "seed drape stretched"}
		settle(m, 90)
		var got := crawl_to(m, bx)
		return {"ok": got, "seed_stretch": st,
			"why": "" if got else "crawl stalled short of the spot"}
	if mode == "fall":
		# the state after a missed catch: body in the air, whip extended back
		# and up behind it, nothing held
		var fy := floor_y(m, bx)
		m.body_pos = Vector2(bx, fy - m.BODY_R - FALL_H)
		m.body_prv = m.body_pos
		var hd: Vector2 = m.body_pos + Vector2(-0.35, -0.25)
		var dir := Vector2(cos(PI * 1.14), sin(PI * 1.14))
		for i in m.pos.size():
			var p: Vector2 = hd + dir * (float(m.cum_len[i]) * 0.99)
			m.pos[i] = p
			m.prv[i] = p
		var st2 := stretch(m)
		if st2 > STRETCH_TOL:
			return {"ok": false, "seed_stretch": st2, "why": "fall seed stretched"}
		for t in 400:
			step(m, m.body_pos, false)
			if m.grounded and t > 20:
				break
		settle(m, 90)
		return {"ok": absf(m.body_pos.x - bx) < 1.2, "seed_stretch": st2,
			"why": "" if absf(m.body_pos.x - bx) < 1.2 else "landed off the spot"}
	# mode == "drop": leave the previous recovery beam the way a run leaves it
	var j := prev_recovery(m, k)
	if j < 0:
		return {"ok": false, "seed_stretch": 0.0, "why": "no beam upstream"}
	var teth: float = clampf(beam_height(m, j) - 1.30, 0.8, 2.9)
	wind_on(m, j, teth, 1.8, deg_to_rad(6.0))
	var st3 := stretch(m)
	if st3 > STRETCH_TOL:
		return {"ok": false, "seed_stretch": st3, "why": "wrap seed stretched"}
	for t in 30:
		step(m, m.body_pos, true)
	if float(m.a_freelen[j]) < 0.0:
		return {"ok": false, "seed_stretch": st3, "why": "the wrap did not take"}
	for t in 300:                       # the hand opens: RELEASE IS IMMEDIATE
		step(m, m.body_pos, false)
		if m.grounded and t > 40:
			break
	settle(m, 60)
	var got3 := crawl_to(m, bx)
	return {"ok": got3, "seed_stretch": st3,
		"why": "" if got3 else "could not crawl from the drop to the spot"}

# ------------------------------------------------------------- the throw ----

func throw_once(m: Node2D, k: int, c: Dictionary, do_settle := true) -> Dictionary:
	## One stroke, with the grip used as a TRIGGER (main.gd GRIP_WINDOW): the
	## hand shuts on the wrap reading and re-arms if the window lapses.
	var grip := false
	var closes := 0
	var sd: int = int(c["sd"])
	var pull: bool = bool(c["pull"])
	var w: int = int(c["w"])
	var caught := false
	var transient := false
	var best_th := 0.0
	for t in w + 130:
		var ang: float
		var amp := 1.0
		if t < w:
			ang = float(c["a0"])
		elif t < w + sd:
			ang = float(c["a1"])
		elif pull and t < w + 10 + sd:
			ang = float(c["a0"])
			amp = 0.7
		else:
			ang = float(c["a1"])
		var tgt: Vector2 = m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		if not grip and absf(float(m.a_theta[k])) >= 2.6 and closes < 4 \
				and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		step(m, tgt, grip)
		best_th = maxf(best_th, absf(float(m.a_theta[k])))
		if int(m.a_locked[k]) == 1:
			transient = true
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			break
	if not caught:
		return {"ok": false, "locked": -1, "tether": -1.0, "theta": best_th,
			"trans": transient}
	if do_settle:
		for t in SETTLE:
			step(m, m.body_pos, true)
			best_th = maxf(best_th, absf(float(m.a_theta[k])))
			if int(m.a_locked[k]) == 1:
				transient = true
			if float(m.a_freelen[k]) < 0.0:
				break
	return {"ok": float(m.a_freelen[k]) >= 0.0,
		"locked": int(m.a_locked[k]) if float(m.a_freelen[k]) >= 0.0 else -1,
		"tether": float(m.a_freelen[k]), "theta": best_th, "trans": transient}

func grid(m: Node2D, k: int, w: int, snap: Dictionary) -> Dictionary:
	## The 36-stroke grid at one windup length, every stroke from the SAME
	## arrived state. "lock" means caught and still locked SETTLE ticks later;
	## "trans" means the wrap merely read LOCKED at some tick, which is the
	## weaker test v1's verdict was made on.
	##
	## WHICH LOCK IS KEPT. Not the longest tether - the one nearest
	## beam height - 1.30 m, which is route_bot's own rule and the widest part
	## of bot_leap's envelope. The body rides tether + ARM_MAX under the pin, so
	## a longer catch than that has the feet on the floor for the whole swing.
	## The gate then measures egress from the beam's BEST available catch: a
	## DEAD END verdict must not be an artefact of handing it a bad one.
	var nc := 0
	var nl_ := 0
	var nt := 0
	var best_th := 0.0
	var best: Dictionary = {}
	var best_teth := -1.0
	var want: float = clampf(beam_height(m, k) - 1.30, 0.8, 2.9)
	var best_err := 1e9
	for a0 in A0S:
		for a1 in A1S:
			for sd in SDS:
				for pull in [false, true]:
					LEAP.load_state(m, snap)
					var c := {"a0": a0, "a1": a1, "sd": sd, "pull": pull, "w": w}
					var r := throw_once(m, k, c)
					best_th = maxf(best_th, float(r["theta"]))
					if bool(r["trans"]):
						nt += 1
					if int(r["locked"]) >= 0:
						nc += 1
					if int(r["locked"]) == 1:
						nl_ += 1
						var err: float = absf(float(r["tether"]) - want)
						if best.is_empty() or err < best_err:
							best = c
							best_err = err
							best_teth = float(r["tether"])
	LEAP.load_state(m, snap)
	return {"caught": nc, "lock": nl_, "trans": nt, "theta": best_th,
		"best": best, "tether": best_teth}

# -------------------------------------------------------------- the egress --

func launch_test(m: Node2D, k: int) -> Dictionary:
	## Can you LEAVE this catch? Pump flat out from the catch the grid actually
	## made - not from a rigged wrap - and report the swing it builds and how
	## much of it is spent dragging on the floor. The standstill-catch theorem
	## (memory, tests/bot_pump.gd): a hanging body rides ARM_MAX below the hand
	## but only reaches REACH up, so a catch made with the feet down can never
	## swing clear of the ground at ANY beam height.
	var prev: Vector2 = m.body_pos
	var pk := 0.0
	var vmax := 0.0
	var gnd := 0
	var n := 0
	for t in PUMP_TICKS:
		var cur: Vector2 = PUMP.pump_cursor(m, k, prev, 95.0)
		prev = m.body_pos
		step(m, cur, true)
		n += 1
		if m.grounded:
			gnd += 1
		if float(m.a_freelen[k]) < 0.0:
			break
		var s: Dictionary = PUMP.swing_state(m, k, prev)
		pk = maxf(pk, absf(rad_to_deg(float(s["theta"]))))
		vmax = maxf(vmax, (m.body_pos - prev).length() * 60.0)
	var held: bool = float(m.a_freelen[k]) >= 0.0
	var gf := float(gnd) / float(maxi(n, 1))
	# THREE WAYS TO FAIL, and they are not the same failure. A wrap that pays
	# out under its own pump never had a swing to measure, and reporting its
	# ground fraction over the 60 ticks it survived reads as "feet clear" -
	# measured on a 2.29 m catch that dropped off after a second and printed
	# 5% grounded. So a launch needs the wrap to still be there.
	var why := ""
	if not held:
		why = "PAID OUT under its own pump after %.1f s" % (float(n) / 60.0)
	elif gf >= LAUNCH_GND:
		why = "feet down %.0f%% of the swing" % (gf * 100.0)
	elif pk < LAUNCH_AMP:
		why = "swing tops out at %.0f deg" % pk
	return {"amp": pk, "vmax": vmax, "gnd": gf, "held": held, "n": n, "why": why,
		"launch": held and n >= 300 and pk >= LAUNCH_AMP and gf < LAUNCH_GND}

# ---------------------------------------------------------------- sections --

func sec_drape() -> void:
	say("0) THE DRAPE. v1 laid the chain along the terrain by sampling floor_y")
	say("   at each particle's arc length. The terrain steps 3.0 m down at")
	say("   x=20, so a chain whose tail reaches back past the cliff had one")
	say("   0.2 m segment placed across a 3 m step. main.gd's rope constraint")
	say("   is one-sided, so that segment snapped shut in the first substep.")
	say("   v2 marches the same chain along the connected surface by ARC")
	say("   LENGTH, vertical faces included: chord <= arc, so it cannot")
	say("   stretch, and compression costs nothing because rope never pushes.")
	say("")
	say("   beam   throwing spot   v1 worst segment   v2 worst segment")
	var m := nl()
	build_contour(m)
	var bad1 := 0
	for k in m.a_pos.size():
		var w1 := 0.0
		var w2 := 0.0
		var wx := 0.0
		for lead in LEADS:
			var bx: float = float(m.a_pos[k].x) - lead
			var s1 := drape_v1_stretch(m, bx)
			if s1 > w1:
				w1 = s1
				wx = bx
			var s2 := drape(m, bx)
			w2 = maxf(w2, s2)
		var tag := ""
		if w1 > STRETCH_TOL:
			tag = "  <-- v1 START INVALID"
			bad1 += 1
		say("   A%-3d   x=%5.1f          %6.2f x rest       %5.2f x rest%s"
			% [k, wx, w1, w2, tag])
	m.free()
	say("   beams whose v1 verdict came from a stretched start: %d" % bad1)
	say("")

func sec_beams(only_k := -1) -> String:
	say("1) EVERY BEAM, FROM A STATE A RUN ACTUALLY PRODUCES.")
	say("   Nothing is hand-placed at the throwing spot. Three arrivals:")
	say("     crawl  seeded %.0f m back on the same flat, settled, walked in" % SEED_BACK)
	say("     fall   dropped from %.1f m over the spot and landed" % FALL_H)
	say("     drop   wound onto the previous recovery beam, hand opened, landed,")
	say("            crawled in")
	say("   crawl and drop WALK the lead ladder carrying the whip the last")
	say("   attempt left them; fall is staged fresh at each lead, because")
	say("   where you land is not a choice. Far lead first, stopping at the")
	say("   first lead that locks. w=30 is v1's windup, run at the far lead")
	say("   only, and it is in the table to be looked at, not to decide.")
	say("   caught/lock/trans are counts out of 36 at the deciding lead:")
	say("   'lock' = caught AND still locked %d ticks later; 'trans' = merely" % SETTLE)
	say("   read LOCKED at some tick, which is all v1 required.")
	say("")
	say("   beam    over    arrival  lead  chain   w=120      w=30       verdict")
	say("                            m     offset  c/lk/tr    c/lk/tr")
	var m0 := nl()
	var n: int = m0.a_pos.size()
	var geo := []
	for k in n:
		geo.append([m0.a_pos[k], float(m0.a_r[k]), beam_height(m0, k), is_fast(m0, k)])
	m0.free()

	var rows := []
	var g_a_fail := []
	var dead_ends := []
	var launchable := []
	for k in n:
		if only_k >= 0 and k != only_k:
			continue
		var high: bool = bool(geo[k][3])
		# A fast beam is out of reach from the ground BY DESIGN. Certify that
		# once, from the commonest arrival, instead of burning three full grids
		# on a foregone conclusion.
		var modes: Array = ["crawl"] if high else ["crawl", "fall", "drop"]
		var per := {}
		var any_lock := false
		var best_state := {}
		for mode in modes:
			var res := beam_mode(k, mode)
			per[mode] = res
			if bool(res["lock"]):
				any_lock = true
				if best_state.is_empty():
					best_state = res
			var lw: String = "%2d/%2d/%2d" % [int(res["c120"]), int(res["l120"]),
				int(res["t120"])]
			var ls: String = "%2d/%2d/%2d" % [int(res["c30"]), int(res["l30"]),
				int(res["t30"])]
			var v: String
			if not bool(res["staged"]):
				v = "NO ARRIVAL: %s" % res["why"]
			elif bool(res["lock"]):
				v = "LOCK  tether %.2f m" % float(res["tether"])
			elif int(res["c120"]) + int(res["c30"]) > 0:
				v = "catch only (pays out)"
			else:
				v = "UNREACHABLE  (best theta %.2f)" % float(res["theta"])
			say("   A%-3d %6.2f  %-7s %4.1f  %5.2f  %s   %s   %s"
				% [k, float(geo[k][2]), mode, float(res["lead"]),
				   float(res["chain"]), lw, ls, v])
		# ---- the three asserts, per beam ----
		var lt := {}
		if any_lock:
			lt = best_state["launch"]
			if bool(lt["launch"]):
				launchable.append(k)
			else:
				dead_ends.append(k)
		if not high:
			# A0 has nothing upstream to drop from - that is arithmetic, not a
			# level bug. Every OTHER unstaged arrival is a finding: it means the
			# level cannot put a body there in one piece.
			var all3 := true
			for mode in modes:
				if String(per[mode]["why"]) == "no beam upstream":
					continue
				if not bool(per[mode]["lock"]):
					all3 = false
			if not all3:
				g_a_fail.append(k)
		if any_lock:
			say("        egress: pumped %5.2f s, swing %5.1f deg, feet down %3.0f%%,"
				% [float(lt["n"]) / 60.0, float(lt["amp"]), float(lt["gnd"]) * 100.0]
				+ " peak %.2f m/s" % float(lt["vmax"]))
			say("                -> %s%s" % [
				"LAUNCHABLE" if bool(lt["launch"]) else "DEAD END: ",
				"" if bool(lt["launch"]) else String(lt["why"])])
		rows.append({"k": k, "any": any_lock, "high": high, "per": per})
	say("")
	return _gate(n, geo, rows, g_a_fail, dead_ends, launchable)

func beam_mode(k: int, mode: String) -> Dictionary:
	## One beam, one arrival, the lead ladder far to near. The arrival is built
	## ONCE at the far lead and then walked forward, so the chain the near lead
	## throws with is the chain the far lead's failed attempt left behind -
	## which is what a run has.
	var m := nl()
	build_contour(m)
	var bx0: float = float(m.a_pos[k].x) - float(LEADS[0])
	var a := arrive(m, mode, k, bx0)
	var out := {"staged": bool(a["ok"]), "why": a["why"], "lead": float(LEADS[0]),
		"c120": 0, "l120": 0, "t120": 0, "c30": 0, "l30": 0, "t30": 0,
		"lock": false, "tether": -1.0, "theta": 0.0, "chain": 0.0,
		"launch": {"amp": 0.0, "vmax": 0.0, "gnd": 1.0, "launch": false, "n": 0,
			"held": false, "why": "no lock to leave"}}
	if not bool(a["ok"]):
		m.free()
		return out
	for li in LEADS.size():
		var lead: float = float(LEADS[li])
		var bx: float = float(m.a_pos[k].x) - lead
		if li > 0:
			# WHO CHOOSES THE LEAD. Walking in is a choice, so crawl and drop
			# walk the ladder and carry the whip the last attempt left them -
			# which is what route_bot's ground_capture does and what a player
			# does. Where you LAND is not a choice, so the fall arrival is
			# staged fresh at each lead instead: landing 1.4 m short of a beam
			# is exactly as available to the level as landing 3.0 m short, and
			# making the fall walk the ladder tests "fell, then walked", which
			# is just the crawl arrival with extra steps. Measured, the
			# difference is the whole verdict: A0 from a fall staged at 1.8 m
			# locks 3 of 36, and the same fall walked in from 3.0 m locks 0.
			if mode == "fall":
				m.free()
				m = nl()
				build_contour(m)
				var a2 := arrive(m, mode, k, bx)
				if not bool(a2["ok"]):
					continue
			else:
				crawl_to(m, bx, 900)
		out["lead"] = lead
		# THE LAYOUT, AS A NUMBER. route_bot measured that a whip lying in a
		# pile under the feet catches nothing where the same grid from a laid
		# out chain catches 4 of 36. Mean chain x minus body x: about -3 m is
		# laid out behind, about 0 is a pile.
		var off := 0.0
		for i in m.pos.size():
			off += m.pos[i].x - m.body_pos.x
		out["chain"] = off / float(m.pos.size())
		var snap := LEAP.save_state(m)
		var g120 := grid(m, k, 120, snap)
		out["c120"] = int(g120["caught"]); out["l120"] = int(g120["lock"])
		out["t120"] = int(g120["trans"])
		out["theta"] = float(g120["theta"])
		# v1's 30-tick windup is run at the FIRST lead only. It is here to show
		# what v1 was measuring, not to decide anything: it has never once
		# beaten the 120-tick windup, and running it at all three leads tripled
		# the gate's clock for a column.
		var g30: Dictionary = {"caught": 0, "lock": 0, "trans": 0, "theta": 0.0,
			"best": {}, "tether": -1.0}
		if li == 0:
			g30 = grid(m, k, 30, snap)
			out["c30"] = int(g30["caught"]); out["l30"] = int(g30["lock"])
			out["t30"] = int(g30["trans"])
			out["theta"] = maxf(out["theta"], float(g30["theta"]))
		var win: Dictionary = {}
		var teth := -1.0
		if int(g120["lock"]) > 0:
			win = g120["best"]; teth = float(g120["tether"])
		elif int(g30["lock"]) > 0:
			win = g30["best"]; teth = float(g30["tether"])
		if not win.is_empty():
			out["lock"] = true
			out["tether"] = teth
			LEAP.load_state(m, snap)
			throw_once(m, k, win)
			if float(m.a_freelen[k]) >= 0.0:
				out["launch"] = launch_test(m, k)
			m.free()
			return out
	m.free()
	return out

func _gate(n: int, geo: Array, rows: Array, g_a_fail: Array, dead_ends: Array,
		launchable: Array) -> String:
	say("2) THE GATE. A beam can be catchable and not launchable, so")
	say("   catchability alone is no longer the whole contract.")
	say("")
	var fails := 0
	say("   G-A  SAFETY - every floor a body can rest on has a beam that")
	say("        LOCKS from ALL THREE arrivals. A recovery beam that locks")
	say("        only from a hand-placed chain is not a safety net.")
	if g_a_fail.is_empty():
		say("        PASS")
	else:
		fails += 1
		var s := ""
		for k in g_a_fail:
			s += "A%d " % k
		say("        FAIL: %s" % s)
		for k in g_a_fail:
			var per: Dictionary = {}
			for r in rows:
				if int(r["k"]) == k:
					per = r["per"]
			var miss := ""
			for mode in ["crawl", "fall", "drop"]:
				if not per.has(mode):
					continue
				if String(per[mode]["why"]) == "no beam upstream":
					continue
				if not bool(per[mode]["lock"]):
					miss += "%s " % mode
			say("          A%-3d does not lock from: %s" % [k, miss])
	say("")
	say("   G-B  EGRESS - every beam that LOCKS can be left. Launching passes;")
	say("        so does dropping to a floor G-A covers, but a drop-only beam")
	say("        is a DEAD END and the count is the level's dead-end budget.")
	var lstr := ""
	for k in launchable:
		lstr += "A%d " % k
	var dstr := ""
	for k in dead_ends:
		dstr += "A%d " % k
	say("        launchable: %s" % ("(none)" if lstr == "" else lstr))
	say("        dead ends : %s" % ("(none)" if dstr == "" else dstr))
	if launchable.is_empty():
		fails += 1
		say("        FAIL: nothing in the level can be launched from. Every")
		say("        catch is a rest stop and the whole traverse is a crawl.")
	else:
		say("        PASS (with %d dead ends)" % dead_ends.size())
	say("")
	say("   G-C  PROGRESSION - the fast tier must be enterable. At least one")
	say("        fast beam must sit within launch range of a LAUNCHABLE beam,")
	say("        or the fast line is decorative and the level is its spine.")
	var m := nl()
	var entry := -1
	var from := -1
	for k in n:
		if not is_fast(m, k):
			continue
		for j in launchable:
			var d: float = m.a_pos[k].distance_to(m.a_pos[j])
			if float(m.a_pos[j].x) < float(m.a_pos[k].x) and d < 9.0:
				entry = k
				from = j
				break
		if entry >= 0:
			break
	m.free()
	if entry >= 0:
		say("        PASS: A%d is within launch range of A%d." % [entry, from])
		say("        NOTE this is the NECESSARY condition only. The gate can")
		say("        say a launchable beam is close enough; only flying it")
		say("        proves the crossing, and that is route_bot's job.")
	else:
		fails += 1
		say("        FAIL: no fast beam sits within launch range of any")
		say("        launchable beam. The fast tier cannot be entered, so the")
		say("        level is a %s crawl however well it is played."
			% ("62 m" if n > 12 else ""))
	say("")
	say("   G-D  CEILING - no FAST beam may LOCK from a standstill on the")
	say("        ground. A fast beam you can catch by walking under it and")
	say("        stroking is not a skill ceiling, it is a tall recovery beam.")
	var fl := ""
	for r in rows:
		if bool(r["high"]) and bool(r["any"]):
			fl += "A%d " % int(r["k"])
	if fl == "":
		say("        PASS: every fast beam is unreachable from the floor")
	else:
		fails += 1
		say("        FAIL: %s lock from the ground" % fl)
	say("")
	var verdict := "GATE PASS" if fails == 0 else "GATE FAIL (%d of 4 asserts)" % fails
	say("   %s" % verdict)
	say("   simulated ticks: %d (%.0f s of sim time)" % [sim_ticks, sim_ticks / 60.0])
	return verdict

func sec_height() -> void:
	## IS THERE A HEIGHT THAT PASSES BOTH G-A AND G-B? route_bot showed the two
	## requirements pull opposite ways - a beam you can LAUNCH from must be
	## about 3.2 m over its floor, a beam catchable from a STANDSTILL about
	## 2.2 m - but nobody has swept the band between them from a real arrival.
	## A9 is the most isolated recovery beam on the lower tier, so it is the one
	## to move. Crawl arrival, w=120, the same lead ladder, then the same pump.
	say("3) THE BAND BETWEEN THE TWO REQUIREMENTS, SWEPT.")
	say("   A9 moved to each height over its own floor. Everything else in the")
	say("   level is untouched. This is the measurement G-B makes necessary:")
	say("   the gate now has two requirements pulling opposite ways and no one")
	say("   has flown the ground between them.")
	say("")
	say("   height  lead  c/lk/tr  tether  pumped  swing  feet  peak   verdict")
	for h in [2.2, 2.6, 3.0, 3.4, 3.8, 4.2]:
		var m := nl()
		m.a_pos[9] = Vector2(38.9, 3.0 - h)
		build_contour(m)
		var bx0: float = 38.9 - float(LEADS[0])
		var a := arrive(m, "crawl", 9, bx0)
		if not bool(a["ok"]):
			say("   %.2f m  (no arrival: %s)" % [h, a["why"]])
			m.free()
			continue
		var got := false
		for lead in LEADS:
			crawl_to(m, 38.9 - lead, 900)
			var snap := LEAP.save_state(m)
			var g := grid(m, 9, 120, snap)
			if int(g["lock"]) == 0:
				if lead == float(LEADS[LEADS.size() - 1]):
					say("   %.2f m  %.1f   %2d/%2d/%2d   -       -       -      -     -      NO LOCK from a standstill"
						% [h, lead, int(g["caught"]), int(g["lock"]),
						   int(g["trans"])])
				continue
			LEAP.load_state(m, snap)
			throw_once(m, 9, g["best"])
			var teth: float = float(m.a_freelen[9])
			var lt := launch_test(m, 9)
			say("   %.2f m  %.1f   %2d/%2d/%2d   %.2f m  %5.2fs  %5.1f  %3.0f%%  %5.2f  %s"
				% [h, lead, int(g["caught"]), int(g["lock"]), int(g["trans"]),
				   teth, float(lt["n"]) / 60.0, float(lt["amp"]),
				   float(lt["gnd"]) * 100.0, float(lt["vmax"]),
				   "CATCH + LAUNCH" if bool(lt["launch"])
				   else "catch only: " + String(lt["why"])])
			got = true
			break
		if not got:
			pass
		m.free()
	say("")

func v1_drape(m: Node2D, sx: float) -> void:
	## v1's hand-drape, kept only so section C can show what it was measuring.
	var fy := floor_y(m, sx)
	m.body_pos = Vector2(sx, fy - m.BODY_R)
	m.body_prv = m.body_pos
	for i in m.pos.size():
		var px: float = sx + 0.3 - float(m.cum_len[i]) * 0.99
		var py := floor_y(m, px)
		if py > 90.0:
			py = fy
		var q := Vector2(px, minf(py, fy) - float(m.p_rad[i]))
		m.pos[i] = q
		m.prv[i] = q

func sec_control() -> void:
	## THE CONTROL. Same beams, same 36-stroke grid, same leads; only the state
	## the chain is in differs. This is the whole case for rewriting the probe,
	## and it is here rather than in a scratch file so it can be re-run.
	say("C) THE STARTING LAYOUT, AGAINST v1's HAND-DRAPE AS A CONTROL.")
	say("   'hand' and 'tip' are offsets from the body; 'chain' is the mean")
	say("   chain x minus body x. About -2.6 is laid out behind you, about 0")
	say("   is a heap around your feet.")
	say("")
	say("   beam mode     lead  w=120     w=30     hand          chain   tip")
	for k in [0, 7]:
		for mode in ["v1drape", "crawl", "fall", "drop"]:
			for lead in LEADS:
				var m := nl()
				build_contour(m)
				var bx: float = float(m.a_pos[k].x) - lead
				var okk := true
				var why := ""
				if mode == "v1drape":
					v1_drape(m, bx)
				else:
					var a := arrive(m, mode, k, bx)
					okk = bool(a["ok"])
					why = String(a["why"])
				if not okk:
					say("   A%-3d %-8s %.1f   (not staged: %s)" % [k, mode, lead, why])
					m.free()
					continue
				var off := 0.0
				for i in m.pos.size():
					off += m.pos[i].x - m.body_pos.x
				off /= float(m.pos.size())
				var last: int = m.pos.size() - 1
				var snap := LEAP.save_state(m)
				var g1 := grid(m, k, 120, snap)
				var g2 := grid(m, k, 30, snap)
				say("   A%-3d %-8s %.1f  %2d/%2d/%2d  %2d/%2d/%2d  %+.2f,%+.2f  %+.2f  %+.2f,%+.2f"
					% [k, mode, lead,
					   int(g1["caught"]), int(g1["lock"]), int(g1["trans"]),
					   int(g2["caught"]), int(g2["lock"]), int(g2["trans"]),
					   m.pos[0].x - m.body_pos.x, m.pos[0].y - m.body_pos.y, off,
					   m.pos[last].x - m.body_pos.x, m.pos[last].y - m.body_pos.y])
				m.free()
	say("")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only: String = args[0] if args.size() > 0 else ""
	if args.size() > 1:
		_log = FileAccess.open(args[1], FileAccess.WRITE)
	say("LEVEL PROBE v2 - the safety-contract gate")
	say("")
	sec_drape()
	if only == "drape":
		quit(0)
		return
	if only == "control":
		sec_control()
		quit(0)
		return
	if only == "height":
		sec_height()
		quit(0)
		return
	sec_beams(int(only) if only.is_valid_int() else -1)
	if only == "":
		sec_height()
	quit(0)
