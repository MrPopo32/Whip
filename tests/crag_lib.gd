extends RefCounted
## THE CRAG'S MEASURING KIT, shared by tests/crag_gate.gd and tests/crag_shots.gd
## so the two cannot measure different things.
##
## Nothing here is hand-laid. A feature is "reachable" when a body that
## CRAWLED to a standing spot on the crag's own floor with the lash gait,
## wound up, and threw one of tests/lab_throw.gd's 108 grid strokes, caught
## it and LOCKED it, and the lock survived 55 ticks of holding. The crawl-in
## is route_bot's finding, not a nicety: a hand-draped chain locked 100 times
## in 576 strokes where a chain that arrived by crawling locked 4, so a rig
## that teleports the body to the spot measures the drape, not the anchor.
const MAIN := preload("res://main.gd")

const GAIT_PERIOD := 24               # tests/ground_probe.gd's winner, as
const GAIT_BACK := 2.83               # route_bot and lab_gate L5 use it
const GAIT_FWD := -0.94
const WINDUP := 120                   # route_bot: 2-3x the catch rate of 30
const SETTLE := 55                    # ticks a lock must survive after the catch

# the same 108-stroke grid tests/lab_throw.gd measures the lab with, ordered
# by how often it wins so a search that stops at the first lock stops early
const LEADS := [2.0, 2.4, 1.7]
const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]
const SDS := [9, 14, 5]

static func new_crag(lvl := "crag") -> Node2D:
	# The crag by default; any level by name (a scene level included), since
	# the crawl-in, the wind-up and the grid are properties of the body and
	# the whip, not of the crag. tests/level_gate.gd R passes the name in.
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = lvl
	m.setup_sim()             # FIRST - it re-derives save_path from the level
	m.save_enabled = false    # and no test writes any slot
	return m

# the tier floor under x: the LOWEST horizontal terrain there. Islands all
# float above their tier, so the ground is the largest y.
static func floor_y(m: Node2D, x: float) -> float:
	var best := -1e9
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		if absf(B.y - A.y) > 0.01:
			continue
		if x < minf(A.x, B.x) - 0.5 or x > maxf(A.x, B.x) + 0.5:
			continue
		best = maxf(best, A.y)
	return best

# one tick of the lash gait, hand open; dir = +1 crawls right, -1 left
static func gait_cursor(m: Node2D, t: int, dir: float) -> Vector2:
	var f := float(t % GAIT_PERIOD) / float(GAIT_PERIOD)
	var ang: float = GAIT_BACK if f < 0.45 else GAIT_FWD
	if dir < 0.0:
		ang = PI - ang
	return m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH

# crawl until the body's x passes xstop (in the direction of travel), or
# stall. Returns the ticks spent, -1 if it never got there.
static func crawl_to(m: Node2D, xstop: float, dir: float, cap := 6000) -> int:
	var t := 0
	var stall := 0
	var lastx: float = m.body_pos.x
	while (m.body_pos.x - xstop) * dir < 0.0 and t < cap:
		m.step_tick(gait_cursor(m, t, dir), false)
		t += 1
		if t % 120 == 0:
			if absf(m.body_pos.x - lastx) < 0.15:
				stall += 1
				if stall >= 3:
					return -1
			else:
				stall = 0
			lastx = m.body_pos.x
	return t if (m.body_pos.x - xstop) * dir >= 0.0 else -1

# hold the hand back and let the chain settle
static func settle(m: Node2D, a0: float, n := 60) -> void:
	for t in n:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)

static func touching(m: Node2D, k: int) -> bool:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

# tests/lab_throw.gd's throw_once, with the stroke mirrored for a feature to
# the LEFT of the thrower (dir = -1: every angle a becomes PI - a). The grip
# is a trigger: shut on the cue, re-arm when the window lapses.
static func throw_once(m: Node2D, k: int, c: Dictionary, cue: String,
		dir: float) -> Dictionary:
	var grip := false
	var closes := 0
	var sd: int = int(c["sd"])
	var pull: bool = bool(c["pull"])
	var w: int = int(c["w"])
	var a0: float = float(c["a0"])
	var a1: float = float(c["a1"])
	if dir < 0.0:
		a0 = PI - a0
		a1 = PI - a1
	var caught := false
	var et := -1
	var ex := 0.0
	var ey := 0.0
	var egnd := false
	for t in w + 130:
		var ang: float
		var amp := 1.0
		if t < w:
			ang = a0
		elif t < w + sd:
			ang = a1
		elif pull and t < w + 10 + sd:
			ang = a0; amp = 0.7
		else:
			ang = a1
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(ang), sin(ang)) * m.REACH * amp
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var fire := absf(float(m.a_theta[k])) >= 2.6 if cue == "wrap" \
			else touching(m, k)
		if not grip and fire and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			ex = m.body_pos.x
			ey = m.body_pos.y
			egnd = m.grounded
			break
	if not caught:
		return {"ok": false, "locked": -1, "green": false, "tether": -1.0,
			"et": -1}
	for t in SETTLE:
		m.step_tick(m.body_pos, true)
		if float(m.a_freelen[k]) < 0.0:
			break
	return {"ok": float(m.a_freelen[k]) >= 0.0, "locked": int(m.a_locked[k]),
		"green": bool(m._holds(k)), "tether": float(m.a_freelen[k]), "et": et,
		"ex": ex, "ey": ey, "egnd": egnd}

# WHERE A FEATURE IS THROWN FROM. The floor is the tier at the standing
# spot, and the crawl starts at the near end of that tier: the previous
# lip + 1.2 m, which is where a body dropping off that lip lands, or the
# spawn on the home tier. Returns {dir, start, fy}.
static func approach(m: Node2D, k: int) -> Dictionary:
	var ax: float = m.a_pos[k].x
	var dir := 1.0
	var start: float = m.spawn.x
	var stand: float = ax - float(LEADS[0])
	if ax < m.spawn.x:
		dir = -1.0                        # the wall features: crawl left
	else:
		# the last lip (the top of a face you drop off) BEFORE THE STANDING
		# SPOT, if any: the tier the body throws from starts there. (Before
		# the anchor is wrong - a door hangs past its own lip, and the
		# first build of this started the crawl on the tier below it.)
		# A lip is a GROUND face: vertical, dropping, and topped by the floor
		# to its left (within the 0.35 m the fillet takes off its top). The
		# right edge of an island is also vertical and dropping, and the
		# first version of this took the brow over D1 for a lip and began
		# the crawl 0.3 m from the standing spot.
		var lip := -1e9
		for s in m.t_a.size():
			var A: Vector2 = m.t_a[s]
			var B: Vector2 = m.t_b[s]
			if absf(B.x - A.x) < 0.01 and B.y > A.y and A.x < stand - 0.5 \
					and A.x > lip \
					and absf(floor_y(m, A.x - 0.6) - A.y) < 0.5:
				lip = A.x
		if lip > -1e8:
			start = lip + 1.2
	return {"dir": dir, "start": start}

# CRAWL IN, WIND UP, THROW THE GRID. Stops at the first LOCK unless `all`,
# in which case every stroke is thrown and counted. Returns the ledger, and
# in "m" the sim standing at the moment of the winning catch + SETTLE ticks
# (caller frees it), or no "m" if nothing locked.
static func search(k: int, cue: String, all := false, short_in := false,
		lvl := "crag") -> Dictionary:
	var out := {"k": k, "att": 0, "caught": 0, "locked": 0, "green": 0,
		"crawl_t": -1, "cue": cue}
	var m := new_crag(lvl)
	var ap := approach(m, k)
	var dir: float = float(ap["dir"])
	var ax: float = m.a_pos[k].x
	var stand: float = ax - dir * float(LEADS[0])
	var fy := floor_y(m, stand)
	# put the body at the near end of its tier, on the floor, and crawl. The
	# SECOND arrival (short_in) starts 1.9 m short of the spot instead of at
	# the tier's near end: how the chain lies after a crawl is a hidden
	# variable of the throw (route_bot measured 30x), and the knob on D4
	# caught 9 of 36 from a 1.9 m crawl-in and 0 of 36 from a 3.7 m one.
	# Both are legal standing spots on the crag's own floor, both crawled to.
	var start: float = float(ap["start"])
	if short_in:
		start = stand - dir * 1.9
	out["start"] = start
	m.teleport(Vector2(start, fy - m.BODY_R))
	settle(m, PI * 1.10 if dir > 0.0 else -PI * 0.10, 60)
	var ct := crawl_to(m, stand, dir)
	if ct < 0:
		out["err"] = "could not crawl from %.1f to %.1f" % [float(ap["start"]), stand]
		m.free()
		return out
	out["crawl_t"] = ct
	# the crawl overshoots by a little; every lead is measured from HERE
	var here: float = m.body_pos.x
	out["stand_x"] = here
	out["floor"] = fy
	var base: Dictionary = m.snapshot()
	m.free()
	for lead in LEADS:
		# leads other than the first are reached by crawling on (or back)
		# from the same arrival, so the chain is never laid by hand
		for ang: Array in GRID:
			for sd in SDS:
				for pull in [false, true]:
					var mm := new_crag(lvl)
					mm.restore(base)
					var want: float = ax - dir * float(lead)
					if absf(want - here) > 0.15:
						var d2: float = signf(want - here)
						var ct2 := crawl_to(mm, want, d2, 1500)
						if ct2 < 0:
							mm.free()
							continue
					var x_throw: float = mm.body_pos.x
					var r := throw_once(mm, k, {"a0": ang[0], "a1": ang[1],
						"sd": sd, "pull": pull, "w": WINDUP}, cue, dir)
					out["att"] = int(out["att"]) + 1
					if bool(r["ok"]):
						out["caught"] = int(out["caught"]) + 1
						if int(r["locked"]) == 1:
							out["locked"] = int(out["locked"]) + 1
						if bool(r["green"]):
							out["green"] = int(out["green"]) + 1
					if bool(r["ok"]) and int(r["locked"]) == 1 \
							and not out.has("m"):
						out["m"] = mm
						out["how"] = "lead %.1f (x %.2f, floor %.1f) a0 %.2f a1 %.2f sd %d pull %s cue %s" % [
							lead, x_throw, fy, ang[0], ang[1], sd, str(pull), cue]
						out["tether"] = float(r["tether"])
						out["et"] = int(r["et"])
						out["egnd"] = bool(r["egnd"])
						if not all:
							return out
					else:
						mm.free()
	return out

static func feat_names(m: Node2D) -> Array[String]:
	# the vocabulary, in anchor order, from _build_crag's own table
	var n: Array[String] = ["HORN (wall)", "STALACTITE", "WINDOW",
		"HORN", "STALACTITE", "WINDOW", "BRANCH (rib)", "KNOB", "HORN",
		"STALACTITE", "WINDOW", "BRANCH (rib)"]
	while n.size() < m.a_pos.size():
		n.append("?")
	return n
