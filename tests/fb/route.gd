extends SceneTree
## THE ROUTE BOT - the whole real level, from the real spawn, with nothing but
## the whip. Stage 1 (tests/bot_pump.gd) proved a body on a wrap can grow its
## own swing; stage 2 (tests/bot_leap.gd) turned one swing into one crossing on
## an isolated pair of beams. This runs the actual level end to end and reports
## how far it gets, so completability is a measurement instead of a claim.
##
## TWO ROUTES, REPORTED SEPARATELY:
##   spine  the RECOVERY line - the 2.2 m beams (A0 A1 A2 A3 A4 A5 A6).
##          The safety contract: slow, throwable from the floor, no fall fatal.
##   fast   the 4.5 m beams (A2 A6 A8 A10 A12), catchable only from the apex of
##          a swing. Never verified before this file.
##
## WHAT THE BOT IS ALLOWED TO DO. It PLANS: at every decision it snapshots the
## sim, simulates a small grid of candidate strokes / release angles, keeps the
## best, and then EXECUTES that one for real. The sim has no RNG, so the
## executed leg is bit-identical to the candidate that was scored - the reported
## run is one continuous physical trajectory, not a stitched highlight reel. The
## planning cost is reported as "candidates", so the difficulty stays visible: a
## leg that needed twenty candidates is a leg a player would miss most of the
## time. The bot does NOT rewind committed time. A leg no candidate holds is
## executed anyway (the least-bad one), the body hits the floor, and that counts
## as a fall - with the clock still running.
##
## THE THREE VERBS, all measured elsewhere and only assembled here:
##   ground throw   the tests/level_probe.gd stroke grid, from a standstill
##   leap           bot_leap's leap_begin/leap_step, unmodified
##   crawl          the lash gait at the parameters tests/ground_probe.gd found
##                  best (period 24, back 2.83 rad, fwd -0.94 rad, taut from 50%
##                  of the cycle: 4.38 m in 10 s on flat ground)
##
## Run:
##   godot --headless --path . -s res://tests/route_bot.gd            (everything)
##   godot --headless --path . -s res://tests/route_bot.gd -- spine
##   godot --headless --path . -s res://tests/route_bot.gd -- fast
##   godot --headless --path . -s res://tests/route_bot.gd -- chain
##   godot --headless --path . -s res://tests/route_bot.gd -- door
##   godot --headless --path . -s res://tests/route_bot.gd -- gate
##   godot --headless --path . -s res://tests/route_bot.gd -- layout
##   godot --headless --path . -s res://tests/route_bot.gd -- hang
##   godot --headless --path . -s res://tests/route_bot.gd -- a2
##   godot --headless --path . -s res://tests/route_bot.gd -- entry
##   godot --headless --path . -s res://tests/route_bot.gd -- sweep
##   godot --headless --path . -s res://tests/route_bot.gd -- lip
##   godot --headless --path . -s res://tests/route_bot.gd -- ledge

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

# the lash gait, as measured by tests/ground_probe.gd
const GAIT_PERIOD := 24
const GAIT_BACK := 2.83
const GAIT_FWD := -0.94
const GAIT_TAUT := 0.50

# Release angles the leap search snapshots on the way up. They all sit on the
# SAME upswing, so however many are tried the pump is paid for once.
const RELS := [8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0,
	52.0, 62.0, 74.0]

var sim_ticks := 0          # every tick simulated, planning included

class Ledger:
	var ticks := 0          # COMMITTED ticks - the run's own clock
	var catches := 0
	var locks := 0
	var falls := 0          # a leg that ended with the body on the floor
	var stuck := 0          # a beam the swing could never leave
	var throws := 0
	var crawl := 0
	var cands := 0
	var maxx := -1e9
	var eng := {}
	var lk := {}
	var fail_k := -1
	var fail_why := ""
	var reached := false
	var legs: Array = []

	func snap() -> Dictionary:
		return {"t": ticks, "c": catches, "l": locks, "e": eng.duplicate(),
			"k": lk.duplicate(), "x": maxx}

	func restore(d: Dictionary) -> void:
		ticks = int(d["t"]); catches = int(d["c"]); locks = int(d["l"])
		eng = (d["e"] as Dictionary).duplicate()
		lk = (d["k"] as Dictionary).duplicate()
		maxx = float(d["x"])

# ------------------------------------------------------------------ helpers --

func step(m: Node2D, cur: Vector2, grip: bool, L) -> void:
	m.step_tick(cur, grip)
	sim_ticks += 1
	if L == null:
		return
	L.ticks += 1
	if m.body_pos.x > L.maxx:
		L.maxx = m.body_pos.x
	for k in m.a_pos.size():
		var e: bool = float(m.a_freelen[k]) >= 0.0
		if e and not bool(L.eng.get(k, false)):
			L.catches += 1
		L.eng[k] = e
		if e and int(m.a_locked[k]) == 1:
			if not bool(L.lk.get(k, false)):
				L.locks += 1
				L.lk[k] = true
		elif not e:
			L.lk[k] = false

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

# THE OTHER HEIGHT. beam_height asks how much air is under the beam, which is
# what decides whether you can SWING on it. This asks how high it is over the
# floor you would be STANDING ON to throw at it, which is what decides whether
# you can get on it in the first place - and on a beam hung past a cliff lip
# those are two different floors. Every beam on flat ground reads the same
# either way; the lip beam is the one place they diverge, which is exactly why
# it is the door.
func throw_height(m: Node2D, k: int) -> float:
	return floor_y(m, float(m.a_pos[k].x) - 2.4) - float(m.a_pos[k].y)

func from_ground(m: Node2D, k: int) -> bool:
	return throw_height(m, k) <= 3.0

# The honest test of "can I throw at this beam from where I would stand": how
# high is it above the FLOOR AT THE THROWING STATION, 2.4 m behind it? On the
# flat v1 level that is the beam's own height and this picks exactly the 2.2 m
# recovery beams. On a terraced level it picks the beams that hang past a lip -
# low over the terrace behind them, high over the one they swing on.
func stand_height(m: Node2D, k: int) -> float:
	var f := floor_y(m, float(m.a_pos[k].x) - 2.4)
	if f > 90.0:
		return -1.0
	return f - float(m.a_pos[k].y)

func throwable_ahead(m: Node2D, x: float) -> int:
	var best := -1
	for k in m.a_pos.size():
		if float(m.a_pos[k].x) < x:
			continue
		var h := stand_height(m, k)
		if h < 1.2 or h > 2.4:
			continue
		if best < 0 or float(m.a_pos[k].x) < float(m.a_pos[best].x):
			best = k
	return best

func recovery_ahead(m: Node2D, x: float) -> int:
	var best := -1
	for k in m.a_pos.size():
		if not from_ground(m, k):
			continue
		if float(m.a_pos[k].x) < x:
			continue
		if best < 0 or float(m.a_pos[k].x) < float(m.a_pos[best].x):
			best = k
	return best

func new_level() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	if use_v2:
		apply_v2(m)
	return m

# --------------------------------------------------------------- the crawl --

func settle_ground(m: Node2D, L, n := 90) -> void:
	# Hand OPEN so any wrap is dropped that tick, and held BACK so the chain is
	# not left in a heap. Measured (tests/_tmp_layout.gd, kept in the report):
	# settling with the cursor parked ON the body collapses the whip into a
	# pile under the feet - mean chain offset +0.12 m instead of -3.3 m - and
	# from that pile NONE of the 36 stroke candidates even catches A0, where the
	# same grid from a laid-out chain catches 4 and locks 3. The layout of your
	# own whip is a hidden state variable of the throw.
	for t in n:
		step(m, m.body_pos + Vector2(cos(PI * 1.10), sin(PI * 1.10)) * m.REACH,
			false, L)

func crawl_to(m: Node2D, xstop: float, L, cap := 4000) -> bool:
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
		step(m, tgt, grip, L)
		t += 1
		if t % 120 == 0:
			if m.body_pos.x - lastx < 0.15:
				stall += 1
				if stall >= 3:
					break         # 0.45 m in 6 s is not a gait, it is a snag
			else:
				stall = 0
			lastx = m.body_pos.x
	if L != null:
		L.crawl += t
	return m.body_pos.x >= xstop - 0.35

func crawl_back(m: Node2D, xstop: float, L, cap := 2000) -> bool:
	# The lash gait run in mirror image: hand back-and-up while SLACK, forward-
	# and-down while gripped. Measured at 0.42 m/s backwards, the same speed the
	# forward gait makes - which matters, because a throw drives the body toward
	# the beam (the 120-tick windup holds the hand back and the arm force is an
	# internal pair). Without a way to step back out, a body gets two throws at a
	# beam and then is standing under it.
	var t := 0
	var stall := 0
	var lastx: float = m.body_pos.x
	while m.body_pos.x > xstop and t < cap:
		var f := float(t % GAIT_PERIOD) / float(GAIT_PERIOD)
		var tgt: Vector2
		var grip := false
		if f < 0.45:
			tgt = m.body_pos + Vector2(cos(PI - GAIT_FWD), sin(PI - GAIT_FWD)) * m.REACH
		else:
			tgt = m.body_pos + Vector2(cos(PI - GAIT_BACK), sin(PI - GAIT_BACK)) * m.REACH
			grip = f > GAIT_TAUT
		step(m, tgt, grip, L)
		t += 1
		if t % 120 == 0:
			if lastx - m.body_pos.x < 0.15:
				stall += 1
				if stall >= 2:
					break
			else:
				stall = 0
			lastx = m.body_pos.x
	if L != null:
		L.crawl += t
	return m.body_pos.x <= xstop + 0.35

# --------------------------------------------------- the throw from a stand --

func throw_once(m: Node2D, k: int, c: Dictionary, L, settle := 55) -> Dictionary:
	var grip := false
	var closes := 0
	var sd: int = int(c["sd"])
	var pull: bool = bool(c["pull"])
	var w: int = int(c["w"])
	var caught := false
	var ex := 0.0
	var ey := 0.0
	var egnd := false
	var et := -1
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
		# GRIP IS A TRIGGER: shut on the wrap reading, re-arm if the 15-tick
		# window lapses with nothing caught
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		if not grip and absf(float(m.a_theta[k])) >= 2.6 and closes < 4 \
				and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		step(m, tgt, grip, L)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			ex = m.body_pos.x
			ey = m.body_pos.y
			egnd = m.grounded
			et = t
			break
	if not caught:
		return {"ok": false, "locked": -1, "tether": -1.0, "et": -1,
			"ex": m.body_pos.x, "ey": m.body_pos.y, "egnd": m.grounded}
	for t in settle:
		step(m, m.body_pos, true, L)
		if float(m.a_freelen[k]) < 0.0:
			break
	return {"ok": float(m.a_freelen[k]) >= 0.0, "locked": int(m.a_locked[k]),
		"tether": float(m.a_freelen[k]), "et": et, "ex": ex, "ey": ey,
		"egnd": egnd}

# level_probe's stroke grid, scored for a route instead of for an audit: a LOCK
# is the only acceptable outcome (a partial pays out and drops you) and among
# locks the longest tether wins, because the tether IS the next leap's range.
# The winner is ALWAYS executed, win or lose, so a missed throw still costs the
# run its two and a half seconds.
func plan_throw(m: Node2D, k: int, L) -> Dictionary:
	var snap := LEAP.save_state(m)
	var lsnap: Dictionary = L.snap() if L != null else {}
	var best := {}
	var bs := -1e9
	var tried := 0
	var done := false
	# HOW LONG A CATCH DO YOU WANT? Not the longest one. The body rides
	# tether + 0.24 m under the pin and the pump pushes the arm out to 1.30 m,
	# so on a beam h metres over its floor a tether over about h - 1.6 m has the
	# feet on the floor through the whole stroke and there is no pendulum at all
	# - measured here: a 2.66 m catch on A1 (2.2 m up) gave a 0 degree swing and
	# could not be left, a 1.04 m catch on the same beam gave 50 degrees and
	# launched. On a 4.5 m fast beam the same rule asks for ~2.8 m, which is
	# where bot_leap's own envelope is widest. So the route wants a SHORT catch
	# on a low beam and a long one on a high beam, and that is one rule.
	var want: float = clampf(beam_height(m, k) - 1.30, 0.8, 2.9)
	# The WINDUP is the layout. level_probe hand-drapes the chain behind the body
	# and then holds the hand back for a fixed 30 ticks; a body that arrived here
	# by living in the level has its whip wherever the last fall left it, and the
	# windup is the only chance to organise it. Sweeping it is worth more than
	# any other knob in this grid (measured in the report).
	# One windup length, not two. Measured in section 3: a 120-tick windup
	# catches two to three times as often as the 30-tick one level_probe uses,
	# and the second value bought nothing but clock.
	for w in [120]:
		for a0 in [PI * 0.85, PI * 1.10]:
			for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
				for sd in [5, 9, 14]:
					for pull in [false, true]:
						if done:
							continue
						LEAP.load_state(m, snap)
						var c := {"a0": a0, "a1": a1, "sd": sd, "pull": pull,
							"w": w}
						var r := throw_once(m, k, c, null)
						tried += 1
						var s := -absf(float(r["tether"]) - want)
						if int(r["locked"]) == 1:
							s += 100.0
							if absf(float(r["tether"]) - want) < 0.30:
								done = true  # good enough; stop burning clock
						elif bool(r["ok"]):
							s += 10.0
						if s > bs:
							bs = s
							best = c
	LEAP.load_state(m, snap)
	if L != null:
		L.restore(lsnap)
		L.cands += tried
	var rr := throw_once(m, k, best, L)      # COMMIT the winner, good or bad
	rr["tried"] = tried
	rr["c"] = best
	return rr

# Crawl into range behind beam k and throw. Leads are tried far to near, which
# is the order a player uses: back off, stroke, close in.
func ground_capture(m: Node2D, k: int, L) -> Dictionary:
	var bx: float = float(m.a_pos[k].x)
	if L != null:
		L.throws += 1
	var tried := 0
	var last := {"ok": false, "locked": -1, "tether": -1.0}
	# HOW FAR BACK TO STAND. The lead sets the catch length: measured on A4,
	# throwing from 3.4 m back fixes a 2.97 m tether and from 1.6 m back a
	# 1.34 m one. Five attempts, closing in 0.4 m each time, walking back out
	# with the reverse gait when the last throw drove the body inside its own
	# lead. A short catch is what a low beam needs and a long one is what a fast
	# beam needs, and the same lead ladder produces both.
	var lead: float = minf(bx - m.body_pos.x, 2.9)
	var stepd := 0.4
	var n_att := 5
	for att in n_att:
		if lead < 1.2:
			break                           # too close to stroke at it at all
		# walk to the lead this attempt wants, from either side. A stalled crawl
		# is not a reason to give up on the beam - throw from where the whip has
		# got the body stuck.
		if m.body_pos.x < bx - lead - 0.15:
			crawl_to(m, bx - lead, L)
		elif m.body_pos.x > bx - lead + 0.15:
			crawl_back(m, bx - lead, L)
		var r := plan_throw(m, k, L)
		tried += int(r["tried"])
		last = r
		if bool(r["ok"]) and int(r["locked"]) == 1:
			# Take any lock. Refusing a too-long one and closing in for a shorter
			# was tried and is strictly worse: the 120-tick windup drives the
			# body forward (the arm force is an internal pair), so the second
			# attempt is already inside its own lead and the beam is lost
			# altogether - measured, that turned 5 caught beams into 0. The
			# preference for a short catch lives in plan_throw's scoring, where
			# it costs nothing.
			r["tried"] = tried
			return r
		# Drop whatever it got, WITHOUT holding the hand back: the arm force is
		# an internal pair, so parking the cursor behind the body drives the
		# body FORWARDS (measured: 3.6 m in 90 ticks near A7), which walks the
		# throw out of its own lead between attempts. The windup at the head
		# of the next stroke does the laying-out instead.
		for t in 20:
			step(m, m.body_pos, false, L)
		lead -= stepd
	last["tried"] = tried
	last["ok"] = false
	return last

# ---------------------------------------------------------------- the leap --

func leap_policy(m: Node2D, ka: int) -> Dictionary:
	var p: Dictionary = LEAP.default_policy()
	# bot_leap's amp_max = 105 deg is a guard against launching off a swing
	# nothing chose. On this level it also rejects the best swing available: a
	# SHORT catch on a 2.2 m beam (0.7-1.1 m of tether) pumps to 110-180 deg,
	# measured in section 4, and the shipped guard throws all of it away.
	p["amp_max"] = 250.0
	p["max_half"] = 22
	if beam_height(m, ka) < 3.5:
		p["amp"] = 55.0
	return p

# Pump on ka toward kb and snapshot the sim as the swing sweeps up past each
# candidate release angle. Every snapshot is a point on the SAME committed
# trajectory, so choosing one later costs only the ticks after it.
func pump_snaps(m: Node2D, ka: int, kb: int, p: Dictionary, L) -> Array:
	var prev: Vector2 = m.body_pos
	var dir: float = signf(float(m.a_pos[kb].x) - float(m.a_pos[ka].x))
	var pk := 0.0
	var last_pk := 0.0
	var half := 0
	var sgn := 0.0
	var got := {}
	var out: Array = []
	var amp: float = float(p["amp"])
	var mh: int = int(p["max_half"])
	for t in 2400:
		if float(m.a_freelen[ka]) < 0.0:
			break
		var s := PUMP.swing_state(m, ka, prev)
		var th: float = rad_to_deg(float(s["theta"])) * dir
		var om: float = float(s["omega"]) * dir
		pk = maxf(pk, absf(th))
		var sg: float = signf(th)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0:
				last_pk = pk
				half += 1
			sgn = sg
			pk = 0.0
		if (last_pk >= amp or half >= mh) and om > 0.0:
			for rel in RELS:
				if th >= float(rel) and not got.has(rel):
					got[rel] = true
					out.append({"snap": LEAP.save_state(m), "prev": prev,
						"rel": float(rel), "amp": last_pk,
						"L": L.snap() if L != null else {}})
		if got.size() == RELS.size():
			break
		if t > 900 and out.is_empty() and last_pk < float(RELS[0]):
			# 15 s of pumping and the swing has not reached even 8 degrees. On a
			# 2.2 m beam that is not bad luck, it is the geometry: the body hangs
			# tether + 0.24 m under the pin and the pump extends the arm to
			# 1.30 m, so anything but a very short tether has the feet on the
			# floor at the bottom of every stroke. Stop wasting the clock.
			break
		var cur: Vector2 = PUMP.pump_cursor(m, ka, prev, float(p["target"]))
		prev = m.body_pos
		step(m, cur, true, L)
	return out

# Fly one release snapshot. bot_leap's policy verbatim; the only thing added is
# a watch for a FOREIGN catch - on the real level a recovery beam sits 3.9 m
# along and 2.3 m below every fast beam, right under the flight path, and
# snagging it is a real outcome the two-beam bench cannot see.
func fly_one(m: Node2D, e: Dictionary, ka: int, kb: int, p: Dictionary, L,
		hold := 120) -> Dictionary:
	LEAP.load_state(m, e["snap"])
	if L != null:
		L.restore(e["L"])
	var pp := p.duplicate()
	pp["rel"] = float(e["rel"])
	var st := LEAP.leap_begin(m, ka, kb, pp)
	st["half"] = int(pp["max_half"])
	var prev: Vector2 = e["prev"]
	var alt := -1
	var guard := 0
	while st["phase"] != "fail" and st["phase"] != "hang" and guard < 420:
		var cg: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		step(m, cg[0], cg[1], L)
		guard += 1
		for j in m.a_pos.size():
			if j != kb and j != ka and float(m.a_freelen[j]) >= 0.0:
				alt = j
		if alt >= 0:
			break
	var on := kb if st["phase"] == "hang" else alt
	var held := false
	var locked := -1
	var tether := -1.0
	var gnd := 0
	if on >= 0 and float(m.a_freelen[on]) >= 0.0:
		held = true
		for t in hold:
			step(m, m.body_pos, true, L)
			if m.grounded:
				gnd += 1
			# Ground contact is NOT a failure here. A 2.2 m recovery beam with a
			# 1.7 m tether hangs the body 1.94 m down with 0.26 m of clearance
			# and a 0.28 m body radius, so hanging on the spine means standing
			# on your own feet. Only losing the wrap is losing the beam.
			if float(m.a_freelen[on]) < 0.0:
				held = false
				break
		locked = int(m.a_locked[on])
		tether = float(m.a_freelen[on])
	if not held:
		on = -1
		for t in 160:
			step(m, m.body_pos, false, L)
			if m.grounded:
				break
		settle_ground(m, L, 40)
	return {"held": held, "on": on, "locked": locked, "tether": tether,
		"x": m.body_pos.x, "fly": int(st["f"]), "rel": float(e["rel"]),
		"caught": st["phase"] == "hang" or alt >= 0, "amp": float(e["amp"]),
		"grounded": m.grounded, "launched": int(st["rel_t"]) >= 0,
		"air_gnd": int(st["ground_t"]), "hang_gnd": gnd}

# Score a flight for a ROUTE. Holding the beam you aimed at beats holding any
# other; a lock beats a partial; and among locks a tether near 2.7 m wins,
# because bot_leap measured both ends of that trap - under ~1.9 m you cannot
# reach the next beam, over ~3.4 m you cannot pump clear of the floor to leave.
func score(m: Node2D, r: Dictionary, ka: int, kb: int) -> float:
	var on: int = int(r["on"])
	if bool(r["held"]) and on >= 0:
		if float(m.a_pos[on].x) <= float(m.a_pos[ka].x) + 0.5:
			return float(r["x"])          # held something BEHIND us: no progress
		var s := 2000.0 if on == kb else 1400.0
		if int(r["locked"]) == 1:
			s += 600.0
		s += float(m.a_pos[on].x)
		s -= absf(float(r["tether"]) - 2.7) * 20.0
		return s
	if bool(r["caught"]):
		return 400.0 + float(r["x"])      # caught, then betrayed
	return float(r["x"])

func leap_search(m: Node2D, ka: int, kb: int, L,
		aims := [-0.5, -0.8], leads := [38]) -> Dictionary:
	var p0 := leap_policy(m, ka)
	var snaps := pump_snaps(m, ka, kb, p0, L)
	if snaps.is_empty():
		return {"held": false, "on": -1, "x": m.body_pos.x, "cands": 0,
			"locked": -1, "tether": -1.0, "caught": false, "rel": -1.0,
			"amp": 0.0, "fly": 0, "launched": false, "grounded": m.grounded,
			"air_gnd": 0, "hang_gnd": 0,
			"why": "NEVER LAUNCHED - the swing never reached a release angle"}
	var be := {}
	var bp := {}
	var bs := -1e9
	var n := 0
	for e in snaps:
		for aim in aims:
			for lead in leads:
				var p := p0.duplicate()
				p["aim"] = aim
				p["lead"] = lead
				var r := fly_one(m, e, ka, kb, p, null)
				n += 1
				var s := score(m, r, ka, kb)
				if s > bs:
					bs = s
					be = e
					bp = p
	if L != null:
		L.cands += n
	var out := fly_one(m, be, ka, kb, bp, L)      # COMMIT the winner
	out["cands"] = n
	out["why"] = ""
	if not bool(out["held"]):
		out["why"] = "caught, then betrayed" if bool(out["caught"]) else "missed"
	return out

# ----------------------------------------------------------------- the run --

func run_route(route: Array, cap := 90000) -> Ledger:
	var m := new_level()
	var L := Ledger.new()
	L.maxx = m.body_pos.x
	var goal: float = float(m.goal_x)
	print("    step  leg           verb    what happened")
	settle_ground(m, L, 120)
	var cur := -1
	var i := 0
	var stepn := 0
	var guard := 0
	while i < route.size() and L.ticks < cap and guard < 40:
		guard += 1
		if m.body_pos.x > goal:
			break
		var k: int = int(route[i])
		stepn += 1
		if cur >= 0:
			var r := leap_search(m, cur, k, L)
			var tag := ""
			if bool(r["held"]):
				tag = "HELD A%d, %s, tether %.2f m, %d ticks airborne%s" % [
					int(r["on"]), "LOCK" if int(r["locked"]) == 1 else "partial",
					float(r["tether"]), int(r["fly"]),
					"" if int(r["hang_gnd"]) == 0
					else ", feet down %d ticks of the hang" % int(r["hang_gnd"])]
			else:
				tag = "%s - down at x %.1f" % [str(r["why"]), float(r["x"])]
			print("    %4d  A%-2d -> A%-2d    leap    rel %2.0f off a %3.0f deg swing: %s  [%d cand]"
				% [stepn, cur, k, float(r["rel"]), float(r["amp"]), tag,
				   int(r["cands"])])
			L.legs.append([cur, k, "leap", bool(r["held"])])
			if bool(r["held"]):
				cur = int(r["on"])
				while i < route.size() and float(m.a_pos[int(route[i])].x) \
						<= float(m.a_pos[cur].x) + 0.01:
					i += 1
				continue
			if L.fail_k < 0:
				L.fail_k = k
				L.fail_why = "A%d -> A%d: %s" % [cur, k, str(r["why"])]
			if not bool(r["launched"]):
				L.stuck += 1        # never left the beam: not a fall, a dead end
				settle_ground(m, L, 60)
			else:
				if not m.grounded:
					settle_ground(m, L, 150)
				if m.grounded:
					L.falls += 1
			cur = -1
			while i < route.size() \
					and float(m.a_pos[int(route[i])].x) < m.body_pos.x + 1.2:
				i += 1
			continue
		# on the floor
		var kt := k
		if not from_ground(m, k):
			kt = recovery_ahead(m, m.body_pos.x + 1.2)
			if kt < 0:
				break
		if float(m.a_pos[kt].x) < m.body_pos.x + 1.2:
			i += 1
			continue
		var rr := ground_capture(m, kt, L)
		if bool(rr["ok"]) and int(rr["locked"]) == 1:
			var off := ""
			if is_fast(m, kt) and m.grounded:
				# The beam you just caught hangs over a drop and you are still
				# standing on the high side of it. HAUL: the only move there is
				# while attached, because opening your hand takes you off the
				# beam that tick.
				var hh := haul_off(m, kt, L)
				off = " then hauled %+.2f m off the lip into %.1f m of air" % [
					float(hh["dx"]), beam_height(m, kt)] if bool(hh["air"]) else ""
			print("    %4d  floor -> A%-2d  throw   LOCK from a standstill, tether %.2f m%s%s  [%d cand]"
				% [stepn, kt, float(rr["tether"]),
				   "" if float(rr["tether"]) <= beam_height(m, kt) - 0.8
				   else " - TOO LONG TO SWING ON", off,
				   int(rr["tried"])])
			L.legs.append([-1, kt, "throw", true])
			cur = kt
			while i < route.size() and float(m.a_pos[int(route[i])].x) \
					<= float(m.a_pos[kt].x) + 0.01:
				i += 1
			continue
		print("    %4d  floor -> A%-2d  throw   NO STROKE LOCKED IT from any lead  [%d cand]"
			% [stepn, kt, int(rr["tried"])])
		L.legs.append([-1, kt, "throw", false])
		if L.fail_k < 0:
			L.fail_k = kt
			L.fail_why = "A%d: no stroke from a standstill locked it" % kt
		if not crawl_to(m, float(m.a_pos[kt].x) + 1.5, L):
			break
		i += 1
	# the last stretch to the flag is flat ground: crawl it
	if m.body_pos.x <= goal and L.ticks < cap:
		if cur >= 0:
			settle_ground(m, L, 150)
		var before: float = m.body_pos.x
		crawl_to(m, goal + 0.4, L, mini(cap - L.ticks, 8000))
		if m.body_pos.x > before + 0.3:
			print("    %4d  floor         crawl   %.1f m of lash gait -> x %.1f"
				% [stepn + 1, m.body_pos.x - before, m.body_pos.x])
	L.reached = m.body_pos.x > goal
	m.free()
	return L

func report(L: Ledger, label: String) -> void:
	var goal := 58.0
	var spawn := -4.6
	print("")
	print("   %s" % label)
	print("     furthest x reached      %.2f m  (spawn %.1f, goal %.1f = %.0f%% of the traverse)"
		% [L.maxx, spawn, goal, 100.0 * (L.maxx - spawn) / (goal - spawn)])
	print("     reached the goal        %s" % ("YES" if L.reached else "no"))
	print("     run time                %.1f s (%d ticks), %.1f s of it crawling"
		% [L.ticks / 60.0, L.ticks, L.crawl / 60.0])
	print("     catches                 %d, of which %d classified LOCKED"
		% [L.catches, L.locks])
	print("     falls to the floor      %d" % L.falls)
	print("     dead ends on a beam     %d  (caught it, then could not build a"
		% L.stuck)
	print("                             swing big enough to leave it)")
	print("     candidates simulated    %d - the planning cost, i.e. how many"
		% L.cands)
	print("                             tries a player would need")
	if L.fail_k >= 0:
		print("     first failure           %s" % L.fail_why)
	else:
		print("     first failure           none")

# ------------------------------------------------------------- the sections --

func sec_level(m: Node2D) -> void:
	print("0) THE LEVEL AS BUILT. 'over floor' is measured to the terrain directly")
	print("   under the beam, which is what decides whether a body can hang there.")
	print("   'over the floor you throw from' is measured 2.4 m BEHIND the beam,")
	print("   which is where you stand to stroke at it. On flat ground the two are")
	print("   the same number; over a cliff lip they are not, and that gap is the")
	print("   only door onto the fast line.")
	print("   beam    x      y     r    over  throw  kind      next of its kind")
	print("                                floor  from")
	var rec: Array = []
	var fst: Array = []
	for k in m.a_pos.size():
		if is_fast(m, k):
			fst.append(k)
		else:
			rec.append(k)
	for k in m.a_pos.size():
		var lst: Array = fst if is_fast(m, k) else rec
		var nxt := -1
		for j in lst:
			if float(m.a_pos[j].x) > float(m.a_pos[k].x) + 0.01:
				nxt = int(j)
				break
		var g := "-"
		if nxt >= 0:
			g = "%.1f m to A%d (%+.1f m in height)" % [
				float(m.a_pos[nxt].x) - float(m.a_pos[k].x), nxt,
				float(m.a_pos[k].y) - float(m.a_pos[nxt].y)]
		var kind := "FAST" if is_fast(m, k) else "recovery"
		if is_fast(m, k) and from_ground(m, k):
			kind = "THE DOOR"
		print("   A%-3d  %5.1f  %5.1f  %.2f  %.2f  %5.2f  %-9s %s"
			% [k, float(m.a_pos[k].x), float(m.a_pos[k].y), float(m.a_r[k]),
			   beam_height(m, k), throw_height(m, k), kind, g])
	print("   spawn (%.1f, %.1f), goal x = %.1f"
		% [float(m.spawn.x), float(m.spawn.y), float(m.goal_x)])
	print("")

func one_leg(ka: int, kb: int, hang: float, aims: Array, leads: Array) -> Dictionary:
	var m := new_level()
	LEAP._wind_on(m, ka, hang, 1.8, deg_to_rad(6.0))
	for t in 30:
		step(m, m.body_pos, true, null)
	if float(m.a_freelen[ka]) < 0.0:
		m.free()
		return {}
	var r := leap_search(m, ka, kb, null, aims, leads)
	r["tether0"] = 0.0
	m.free()
	return r

func sec_entry() -> void:
	print("6) THE LEGS THE ROUTE ONLY GETS ONE GO AT, measured on their own with a")
	print("   spread of starting tethers - the length YOUR previous catch happened")
	print("   to fix. A1->A2 is the upper tier's fast beam; A4->A6 is the lip")
	print("   launcher into the lower fast line; the rest are the alternatives a")
	print("   route would fall back on.")
	print("     leg        gap    climb   held   result per start tether")
	for leg in [[1, 2], [3, 4], [4, 5], [4, 6], [5, 6], [5, 7], [7, 9], [12, 13]]:
		var ka: int = int(leg[0])
		var kb: int = int(leg[1])
		var nh := 0
		var n := 0
		var line := ""
		# The starting tether has to FIT. _wind_on hangs the body 0.6 m below the
		# last of `hang` metres of rope, and the body is 0.28 m across, so on a
		# beam h metres over its floor anything past h - 0.88 starts the run
		# inside the ground. On a 2.2 m recovery beam that ceiling is 1.32 m -
		# which is the whole story of why the spine cannot launch anything.
		var mh := new_level()
		var hmax: float = maxf(beam_height(mh, ka) - 0.88, 0.7)
		mh.free()
		for fr in [0.45, 0.65, 0.85]:
			var hang: float = maxf(hmax * float(fr), 0.6)
			var r := one_leg(ka, kb, hang, [-0.5, -0.8], [38])
			if r.is_empty():
				line += "  -"
				continue
			n += 1
			if bool(r["held"]) and int(r["on"]) == kb:
				nh += 1
				line += "  L" if int(r["locked"]) == 1 else "  h"
			elif bool(r["held"]):
				line += " A%d" % int(r["on"])
			elif not bool(r["launched"]):
				line += "  x"
			elif bool(r["caught"]):
				line += "  p"
			else:
				line += "  ."
		var m2 := new_level()
		var d: float = float(m2.a_pos[ka].distance_to(m2.a_pos[kb]))
		var dy: float = float(m2.a_pos[ka].y) - float(m2.a_pos[kb].y)
		m2.free()
		print("     A%-2d->A%-2d  %5.2f m  %+.2f m  %d/%d   %s  (tethers up to %.2f m)"
			% [ka, kb, d, dy, nh, n, line, hmax])
	print("   L = held the beam it aimed at and it was a LOCK, h = held a partial,")
	print("   A<n> = held a DIFFERENT beam, p = caught then betrayed, . = missed,")
	print("   x = never launched (the swing could not reach a release angle).")
	print("   The three columns are 45%, 65% and 85% of the longest tether that")
	print("   beam can physically hang without the body starting underground.")
	print("")

func sec_sweep() -> void:
	print("7) IS 7.8 M THE RIGHT FAST SPACING? bot_leap's isolated two-beam bench")
	print("   said 6.0-8.5 m works and 9.5 m does not. This asks the same question")
	print("   ON THE REAL LEVEL: A6 stays put, A8 moves, every other beam - the")
	print("   recovery beams under the flight path included - is left alone.")
	print("   4 starting tethers per gap, all 10 release angles, aim -0.5.")
	print("     gap     legs held  caught  mean catch tether  held a DIFFERENT beam")
	var hangs := [2.0, 2.4, 2.8, 3.2]
	for gap in [6.0, 6.8, 7.8, 8.6, 9.4, 10.5]:
		var nh := 0
		var nc := 0
		var ns := 0
		var n := 0
		var ts := 0.0
		for hang in hangs:
			var m := new_level()
			m.a_pos[8] = Vector2(float(m.a_pos[6].x) + gap, float(m.a_pos[6].y))
			LEAP._wind_on(m, 6, hang, 1.8, deg_to_rad(6.0))
			for t in 30:
				step(m, m.body_pos, true, null)
			if float(m.a_freelen[6]) < 0.0:
				m.free()
				continue
			n += 1
			var r := leap_search(m, 6, 8, null, [-0.5], [38])
			if bool(r["held"]):
				if int(r["on"]) == 8:
					nh += 1
					ts += float(r["tether"])
				else:
					ns += 1
			if bool(r["caught"]):
				nc += 1
			m.free()
		print("    %5.1f m    %d / %d      %d       %5.2f m            %d"
			% [gap, nh, n, nc, ts / maxf(nh, 1), ns])
	print("")
	print("   The same question asked of HEIGHT: A6 and A8 moved up or down")
	print("   together, spacing held at the level's own 7.8 m. Height is what")
	print("   decides whether the pump has room to breathe under the beam.")
	print("     height over floor  legs held  mean swing at release")
	for h in [3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.5]:
		var nh := 0
		var n := 0
		var amp := 0.0
		# tethers scaled to the beam's own headroom, because the longest tether a
		# beam can hang at all is h - 0.88 (body 0.6 m under the rope end, 0.28 m
		# of body). Feeding a 3.2 m tether to a 3.0 m beam starts the run inside
		# the floor and measures nothing.
		for fr in [0.45, 0.60, 0.75, 0.90]:
			var hang: float = maxf((h - 0.88) * fr, 0.6)
			var m := new_level()
			var fy := floor_y(m, 27.2)
			m.a_pos[6] = Vector2(27.2, fy - h)
			m.a_pos[8] = Vector2(35.0, fy - h)
			LEAP._wind_on(m, 6, hang, 1.8, deg_to_rad(6.0))
			for t in 30:
				step(m, m.body_pos, true, null)
			if float(m.a_freelen[6]) < 0.0:
				m.free()
				continue
			n += 1
			var r := leap_search(m, 6, 8, null, [-0.5], [38])
			amp += float(r["amp"])
			if bool(r["held"]) and int(r["on"]) == 8:
				nh += 1
			m.free()
		print("        %.1f m            %d / %d       %.0f deg"
			% [h, nh, n, amp / maxf(n, 1)])
	print("")

func sec_door() -> void:
	print("2c) THE DOOR ONTO THE FAST LINE. Section 2b shows the line flies once")
	print("    you are on it with the right tether; this is the separate question")
	print("    of how you ever get on. A6 is 4.5 m over the lower floor and the")
	print("    only beams upstream of it are A4 (2.2 m over the UPPER tier, right")
	print("    on the cliff lip) and A5 (2.2 m over the lower tier, 3.78 m short of")
	print("    A6 and 2.30 m below it). Widest search in this file: every start")
	print("    tether the beam can physically hold, all %d release angles, three" % RELS.size())
	print("    aims, two stroke leads - 78 flights per start.")
	print("     leg       start tether  held  caught  closest the BODY got to the")
	print("                                           target, and the whip TIP")
	for leg in [[4, 6], [5, 6], [4, 5], [3, 5]]:
		var ka: int = int(leg[0])
		var kb: int = int(leg[1])
		for teth in [0.6, 0.8, 1.0, 1.2]:
			var m := new_level()
			LEAP._wind_on(m, ka, teth, 1.8, deg_to_rad(6.0))
			for t in 30:
				step(m, m.body_pos, true, null)
			if float(m.a_freelen[ka]) < 0.0:
				print("     A%-2d->A%-2d  %.2f m        (the start wrap did not take)"
					% [ka, kb, teth])
				m.free()
				continue
			var t0: float = float(m.a_freelen[ka])
			var B: Vector2 = m.a_pos[kb]
			var p0 := leap_policy(m, ka)
			var pre := LEAP.save_state(m)
			var snaps := pump_snaps(m, ka, kb, p0, null)
			var why := ""
			if snaps.is_empty():
				why = ("the wrap let go while pumping"
					if float(m.a_freelen[ka]) < 0.0
					else "the swing never reached even 8 deg toward the target")
			var nh := 0
			var nc := 0
			var n := 0
			var dmin := 1e9
			var tmin := 1e9
			for e in snaps:
				for aim in [-0.3, -0.5, -0.8]:
					for lead in [28, 38]:
						var p := p0.duplicate()
						p["aim"] = aim
						p["lead"] = lead
						LEAP.load_state(m, e["snap"])
						var pp := p.duplicate()
						pp["rel"] = float(e["rel"])
						var st := LEAP.leap_begin(m, ka, kb, pp)
						st["half"] = int(pp["max_half"])
						var prev: Vector2 = e["prev"]
						var g := 0
						n += 1
						while st["phase"] != "fail" and st["phase"] != "hang" \
								and g < 400:
							var cg: Array = LEAP.leap_step(m, st, prev)
							prev = m.body_pos
							step(m, cg[0], cg[1], null)
							g += 1
							dmin = minf(dmin, m.body_pos.distance_to(B))
							tmin = minf(tmin, m.pos[m.NP - 1].distance_to(B)
								- float(m.a_r[kb]))
						if st["phase"] == "hang":
							nc += 1
							var ok := true
							for t in 120:
								step(m, m.body_pos, true, null)
								if float(m.a_freelen[kb]) < 0.0:
									ok = false
									break
							if ok:
								nh += 1
			LEAP.load_state(m, pre)
			if n == 0:
				print("     A%-2d->A%-2d  %.2f m        never launched: %s"
					% [ka, kb, t0, why])
			else:
				print("     A%-2d->A%-2d  %.2f m        %2d/%-3d %2d      body %.2f m,  tip %.2f m"
					% [ka, kb, t0, nh, n, nc, dmin, tmin])
			m.free()
	print("")

func sec_gate() -> void:
	print("2d) WHAT WOULD OPEN THE DOOR. Section 2c says nothing on the lower tier")
	print("    can launch at A6, and sections 2b and 4 say why: to bridge 7.8 m you")
	print("    need about 2.3 m of tether, and to swing at all you need the tether")
	print("    to fit under the beam (tether + the pump's 1.30 m arm + 0.28 m of")
	print("    body). So a beam you can LEAVE has to be roughly 3.1 m over its own")
	print("    floor, and every beam before A6 is 2.2 m. This raises A5 - the last")
	print("    recovery beam before the fast line - and measures both halves: can")
	print("    you still THROW at it from the floor, and can you then LEAVE it?")
	print("     A5 height  locks from a standstill  best tether  A5 -> A6 (3.78 m,")
	print("     over floor  (of 36 strokes)          it fixes    climbing 4.5-h)")
	for h in [2.2, 2.8, 3.2, 3.6, 4.0, 4.5]:
		var m := new_level()
		var fy := floor_y(m, 24.2)
		m.a_pos[5] = Vector2(24.2, fy - h)
		place(m, 24.2 - 2.4)
		var snap := LEAP.save_state(m)
		var nl := 0
		var bestt := -1.0
		for a0 in [PI * 0.85, PI * 1.10]:
			for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
				for sd in [5, 9, 14]:
					for pull in [false, true]:
						LEAP.load_state(m, snap)
						var r := throw_once(m, 5,
							{"a0": a0, "a1": a1, "sd": sd, "pull": pull, "w": 120},
							null)
						if int(r["locked"]) == 1:
							nl += 1
							bestt = maxf(bestt, float(r["tether"]))
		m.free()
		# and can it be left? try every tether the raised beam can hold
		var nh := 0
		var n := 0
		var best_line := ""
		for fr in [0.45, 0.65, 0.85]:
			var teth: float = maxf((h - 0.88) * fr, 0.6)
			var m2 := new_level()
			var fy2 := floor_y(m2, 24.2)
			m2.a_pos[5] = Vector2(24.2, fy2 - h)
			LEAP._wind_on(m2, 5, teth, 1.8, deg_to_rad(6.0))
			for t in 30:
				step(m2, m2.body_pos, true, null)
			if float(m2.a_freelen[5]) < 0.0:
				m2.free()
				best_line += " -"
				continue
			n += 1
			var r2 := leap_search(m2, 5, 6, null, [-0.5, -0.8], [38])
			if bool(r2["held"]) and int(r2["on"]) == 6:
				nh += 1
				best_line += " L" if int(r2["locked"]) == 1 else " h"
			elif bool(r2["held"]):
				best_line += " A%d" % int(r2["on"])
			elif not bool(r2["launched"]):
				best_line += " x"
			elif bool(r2["caught"]):
				best_line += " p"
			else:
				best_line += " ."
			m2.free()
		print("     %.1f m       %2d                       %s      %d/%d  %s"
			% [h, nl, ("%.2f m" % bestt) if bestt > 0.0 else "  -  ", nh, n,
			   best_line])
	print("     (L = held A6 on a green lock, h = held an amber, p = caught then")
	print("      betrayed, . = missed, x = never launched. Tethers are 45/65/85%")
	print("      of what the beam can hold.)")
	print("")
	print("   AND THE OTHER HALF OF THE SAME IDEA. A beam on a cliff LIP is exactly")
	print("   the thing that can be both: thrown at from the high side, swung on")
	print("   over the low one. A4 is meant to be that beam and misses by 0.40 m -")
	print("   it sits at x=19.6 and the lip is at x=20.0, so a body hanging under")
	print("   it is still over the upper tier and stands on the floor. This walks")
	print("   A4 past the lip and re-asks both questions. The gap to A6 shrinks as")
	print("   it moves, which is shown.")
	print("     A4 at x   gap to A6  locks from the upper tier  tether  body y   A4 -> A6")
	for ax in [19.6, 20.4, 21.0, 21.6, 22.4]:
		var m := new_level()
		m.a_pos[4] = Vector2(ax, -2.2)
		place(m, ax - 2.4)
		var snap := LEAP.save_state(m)
		var nl := 0
		var bt := -1.0
		var bc := {}
		for a0 in [PI * 0.85, PI * 1.10]:
			for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
				for sd in [5, 9, 14]:
					for pull in [false, true]:
						LEAP.load_state(m, snap)
						var c := {"a0": a0, "a1": a1, "sd": sd, "pull": pull,
							"w": 120}
						var r := throw_once(m, 4, c, null)
						if int(r["locked"]) == 1:
							nl += 1
							if float(r["tether"]) > bt:
								bt = float(r["tether"])
								bc = c
		var gap: float = float(m.a_pos[6].x) - ax
		if nl == 0:
			print("     %.1f      %.2f m     %2d                          -       -        -"
				% [ax, gap, nl])
			m.free()
			continue
		LEAP.load_state(m, snap)
		var rr := throw_once(m, 4, bc, null)
		var by: float = m.body_pos.y
		var lr := leap_search(m, 4, 6, null, [-0.5, -0.8], [38])
		var v := "missed"
		if bool(lr["held"]) and int(lr["on"]) == 6:
			v = "HELD A6 (%s, %.2f m)" % [
				"LOCK" if int(lr["locked"]) == 1 else "amber", float(lr["tether"])]
		elif bool(lr["held"]):
			v = "held A%d instead" % int(lr["on"])
		elif not bool(lr["launched"]):
			v = "never launched"
		print("     %.1f      %.2f m     %2d                         %.2f m  %+.2f   %s"
			% [ax, gap, nl, float(rr["tether"]), by, v])
		m.free()
	print("")

func sec_chain() -> void:
	print("2b) THE FAST LINE ITSELF, GIVEN THAT YOU ARE ALREADY ON IT. Getting")
	print("    ONTO the line and flying it are two different questions and the")
	print("    route run answers them together, which hides whichever one is the")
	print("    real problem. Here the body starts hung on A6 with a chosen tether")
	print("    and flies A6 -> A8 -> A10 -> A12 -> A13 with every beam in the")
	print("    level present. 'feet' counts ticks of ground contact in flight -")
	print("    the fast line's whole promise is that there are none.")
	print("    start tether   legs held   x reached   time   feet   per leg")
	for teth in [1.6, 2.0, 2.4, 2.8, 3.2]:
		var m := new_level()
		LEAP._wind_on(m, 6, teth, 1.8, deg_to_rad(6.0))
		var L := Ledger.new()
		L.maxx = m.body_pos.x
		for t in 30:
			step(m, m.body_pos, true, L)
		if float(m.a_freelen[6]) < 0.0:
			print("    %.2f m         (the start wrap did not take)" % teth)
			m.free()
			continue
		var t0: float = float(m.a_freelen[6])
		var cur := 6
		var line := ""
		var ok := 0
		var feet := 0
		for kb in [8, 10, 12, 13]:
			var r := leap_search(m, cur, kb, L)
			feet += int(r["air_gnd"])
			if bool(r["held"]) and int(r["on"]) == kb:
				ok += 1
				line += " A%d(%s,%.1fm)" % [kb,
					"L" if int(r["locked"]) == 1 else "p", float(r["tether"])]
				cur = kb
			elif bool(r["held"]):
				line += " ->A%d!" % int(r["on"])
				cur = int(r["on"])
			else:
				line += " A%d:%s" % [kb, str(r["why"])]
				break
		print("    %.2f m         %d of 4      %5.1f m    %4.1f s  %3d  %s"
			% [t0, ok, L.maxx, L.ticks / 60.0, feet, line])
		m.free()
	print("    (L = locked green, p = amber partial that still held 2 s.)")
	print("")

func place(m: Node2D, sx: float) -> void:
	# level_probe's hand-drape: body on the floor, chain laid along the terrain
	# behind it. This is the state every static probe measures from.
	var fy := floor_y(m, sx)
	m.body_pos = Vector2(sx, fy - m.BODY_R)
	m.body_prv = m.body_pos
	for i in m.pos.size():
		var px: float = sx + 0.3 - float(m.cum_len[i]) * 0.99
		var py := floor_y(m, px)
		if py > 90.0:
			py = fy
		var p := Vector2(px, minf(py, fy) - float(m.p_rad[i]))
		m.pos[i] = p
		m.prv[i] = p

func grid36(m: Node2D, k: int, w: int) -> Array:
	# level_probe's stroke grid at one windup length. Returns
	# [caught, locked-and-still-on-55-ticks-later, locked-at-any-tick].
	var snap := LEAP.save_state(m)
	var nc := 0
	var nl := 0
	var nt := 0
	for a0 in [PI * 0.85, PI * 1.10]:
		for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
			for sd in [5, 9, 14]:
				for pull in [false, true]:
					LEAP.load_state(m, snap)
					var trans := false
					var c := {"a0": a0, "a1": a1, "sd": sd, "pull": pull, "w": w}
					var r := throw_once(m, k, c, null)
					if int(m.a_locked[k]) == 1:
						trans = true
					if bool(r["ok"]) or float(r["tether"]) > 0.0:
						pass
					if int(r["locked"]) >= 0:
						nc += 1
					if int(r["locked"]) == 1:
						nl += 1
						trans = true
					if trans:
						nt += 1
	LEAP.load_state(m, snap)
	return [nc, nl, nt]

func sec_layout() -> void:
	print("3) THE LAYOUT OF YOUR OWN WHIP IS A HIDDEN STATE VARIABLE OF THE THROW.")
	print("   level_probe audits every beam from a HAND-DRAPED chain: body placed")
	print("   on the floor, whip laid out along the terrain behind it. A run is")
	print("   never in that state - it is in whatever state the last fall and the")
	print("   crawl to the spot left the whip in. Same beams, same 36-stroke grid,")
	print("   same leads; only the starting layout differs.")
	print("   FIRST, A BUG IN THE DRAPE ITSELF. The drape lays the chain along the")
	print("   terrain by x, and the terrain steps 3 m down at x=20, so for any beam")
	print("   whose throwing spot is within a whip length past the cliff the chain")
	print("   starts with one segment stretched across it. Worst stretch found, by")
	print("   beam and lead, at level_probe's own three leads:")
	for k in [0, 1, 2, 3, 4, 5, 6]:
		var m := new_level()
		var worst := 0.0
		var wl := 0.0
		for lead in [1.8, 2.4, 3.0]:
			var bx: float = float(m.a_pos[k].x) - lead
			var f0 := floor_y(m, bx)
			var pts := PackedVector2Array()
			for i in m.pos.size():
				var px: float = bx + 0.3 - float(m.cum_len[i]) * 0.99
				var py := floor_y(m, px)
				if py > 90.0:
					py = f0
				pts.append(Vector2(px, minf(py, f0) - float(m.p_rad[i])))
			for i in range(pts.size() - 1):
				var d: float = pts[i].distance_to(pts[i + 1]) / float(m.rest[i])
				if d > worst:
					worst = d
					wl = lead
		m.free()
		if worst > 2.0:
			print("     A%-3d  %.1f x its rest length at lead %.1f m  <-- INVALID START:"
				% [k, worst, wl])
			print("           that segment snaps shut in the first substep and throws")
			print("           the whip. Every verdict this probe family has ever")
			print("           printed for A%d is measured from it." % k)
		else:
			print("     A%-3d  %.1f x rest - clean" % [k, worst])
	print("")
	print("                       hand-draped            arrived by crawling 6 m")
	print("   beam lead windup  caught lock transient   caught lock transient")
	var t := [0, 0, 0, 0, 0, 0]
	for k in [0, 1, 2, 3, 4, 5, 6]:
		for w in [30, 120]:
			var lead := 2.0
			var md := new_level()
			var bx: float = float(md.a_pos[k].x) - lead
			place(md, bx)
			var d := grid36(md, k, w)
			md.free()
			var mc := new_level()
			place(mc, bx - 6.0)
			crawl_to(mc, bx, null)
			var c := grid36(mc, k, w)
			mc.free()
			for i in 3:
				t[i] += int(d[i])
				t[i + 3] += int(c[i])
			print("   A%-3d %.1f  %4d      %2d    %2d    %2d          %2d    %2d    %2d"
				% [k, lead, w, int(d[0]), int(d[1]), int(d[2]),
				   int(c[0]), int(c[1]), int(c[2])])
	print("   TOTALS of %d strokes each   %3d   %3d   %3d         %3d   %3d   %3d"
		% [8 * 2 * 36, t[0], t[1], t[2], t[3], t[4], t[5]])
	print("   'lock' = caught AND still LOCKED 55 ticks later. 'transient' = the")
	print("   wrap read LOCKED at some tick, which is the weaker test level_probe's")
	print("   own verdict is made on.")
	print("")

func sec_hang() -> void:
	print("4) WHY A RECOVERY BEAM CANNOT LAUNCH ANYTHING, AND WHAT WOULD FIX IT.")
	print("   Hang a body on a 2.2 m beam at a chosen tether and pump flat out for")
	print("   20 s. The body rides tether + 0.24 m under the pin and the pump")
	print("   pushes the arm out to 1.30 m, so the whole question is whether that")
	print("   fits under the beam.")
	print("   beam  over floor  tether  deepest hang  swing after 20 s  peak speed")
	for k in [1, 3, 5, 7, 8]:
		for teth in [0.8, 1.0, 1.2, 1.4, 1.7, 2.1, 2.6]:
			var m := new_level()
			var h := beam_height(m, k)
			if teth > h - 0.95:
				m.free()
				continue
			LEAP._wind_on(m, k, teth, 1.8, deg_to_rad(6.0))
			for t in 30:
				step(m, m.body_pos, true, null)
			if float(m.a_freelen[k]) < 0.0:
				print("   A%-3d  %.2f m      %.2f m  (the wrap did not take)"
					% [k, h, teth])
				m.free()
				continue
			var tt: float = float(m.a_freelen[k])
			var prev: Vector2 = m.body_pos
			var pk := 0.0
			var vmax := 0.0
			for t in 1200:
				var cur: Vector2 = PUMP.pump_cursor(m, k, prev, 95.0)
				prev = m.body_pos
				step(m, cur, true, null)
				if float(m.a_freelen[k]) < 0.0:
					break
				var s := PUMP.swing_state(m, k, prev)
				pk = maxf(pk, absf(rad_to_deg(float(s["theta"]))))
				vmax = maxf(vmax, (m.body_pos - prev).length() * 60.0)
			print("   A%-3d  %.2f m      %.2f m  %.2f m        %5.1f deg         %5.2f m/s"
				% [k, h, tt, tt + 1.30 + 0.28, pk, vmax])
			m.free()
	print("   'deepest hang' is tether + the pump's 1.30 m arm + the body radius.")
	print("   Compare it with 'over floor': the swing collapses exactly where that")
	print("   number crosses the beam height.")
	print("")

func sec_a2() -> void:
	var m0 := new_level()
	var A2: Vector2 = m0.a_pos[2]
	var whip: float = float(m0.cum_len[m0.NP - 1])
	print("5) IS A2 REACHABLE BY ANYTHING? A2 is at (%.1f,%.1f), %.2f m over the"
		% [A2.x, A2.y, beam_height(m0, 2)])
	print("   upper tier, and the only beam upstream of it is A1, a 2.2 m recovery")
	print("   beam 6.8 m back. Everything below reports the closest the whip TIP")
	print("   came, so nothing can be blamed on the catch: if the tip never")
	print("   arrives there is nothing to catch. Whip %.2f m, arm %.2f m."
		% [whip, float(m0.REACH)])
	m0.free()
	print("   from the floor, lead   strokes   best wrap on A2   closest tip")
	for lead in [1.5, 2.5, 3.5, 4.5]:
		var m := new_level()
		place(m, A2.x - lead)
		var snap := LEAP.save_state(m)
		var best := 0.0
		var tipmin := 1e9
		var n := 0
		for w in [30, 120]:
			for a0 in [PI * 0.85, PI * 1.10]:
				for a1 in [-PI * 0.60, -PI * 0.42, -PI * 0.30]:
					for sd in [5, 9, 14]:
						LEAP.load_state(m, snap)
						n += 1
						for t in w + 120:
							var ang: float = a0 if t < w else a1
							step(m, m.body_pos
								+ Vector2(cos(ang), sin(ang)) * m.REACH, false, null)
							best = maxf(best, absf(float(m.a_theta[2])))
							tipmin = minf(tipmin, m.pos[m.NP - 1].distance_to(A2)
								- float(m.a_r[2]))
		print("        %.1f m              %3d      %5.2f rad        %.2f m"
			% [lead, n, best, tipmin])
		m.free()
	print("   from a swing on A1, every release angle -20 to 48 deg, three aims:")
	var caught := 0
	var held := 0
	var tries := 0
	var tip2 := 1e9
	for teth in [1.0, 1.3]:
		for rel in [-20.0, -8.0, 4.0, 16.0, 28.0, 40.0, 52.0]:
			for aim in [-0.5, -0.9, -1.3]:
				var m := new_level()
				LEAP._wind_on(m, 1, teth, 1.8, deg_to_rad(6.0))
				for t in 30:
					step(m, m.body_pos, true, null)
				if float(m.a_freelen[1]) < 0.0:
					m.free()
					continue
				var p: Dictionary = LEAP.default_policy()
				p["amp"] = 60.0
				p["amp_max"] = 300.0
				p["max_half"] = 24
				p["target"] = 110.0
				p["rel"] = rel
				p["aim"] = aim
				var st := LEAP.leap_begin(m, 1, 2, p)
				var prev: Vector2 = m.body_pos
				var g := 0
				tries += 1
				while st["phase"] != "fail" and st["phase"] != "hang" and g < 2400:
					var cg: Array = LEAP.leap_step(m, st, prev)
					prev = m.body_pos
					step(m, cg[0], cg[1], null)
					g += 1
					tip2 = minf(tip2, m.pos[m.NP - 1].distance_to(A2)
						- float(m.a_r[2]))
				if st["phase"] == "hang":
					caught += 1
					var ok := true
					for t in 120:
						step(m, m.body_pos, true, null)
						if float(m.a_freelen[2]) < 0.0:
							ok = false
							break
					if ok:
						held += 1
				m.free()
	print("     %d launches: %d caught A2, %d still on it 2 s later. Closest the"
		% [tries, caught, held])
	print("     tip came across every one of them: %.2f m." % tip2)
	print("")

func sec_lip() -> void:
	print("8) THE LIP LAUNCHER A4. main.gd's claim: 'Catch it close and you dangle")
	print("   over the drop with nothing in range; catch it FAR and you get a 4 m")
	print("   tether swinging in 5 m of open air.' A4 is 2.2 m over the tier it")
	print("   stands on and 5.2 m over the one that starts 0.4 m past it, so where")
	print("   you are standing when you catch it decides which beam it is.")
	print("   catching from a standstill on the upper tier:")
	print("     lead    locked  tether  deepest hang  then A4 -> A6")
	for lead in [1.6, 2.2, 2.8, 3.4]:
		var m := new_level()
		place(m, 19.6 - lead)
		var r := plan_throw(m, 4, null)
		if not (bool(r["ok"]) and int(r["locked"]) == 1):
			print("     %.1f m   no      -       -             -" % lead)
			m.free()
			continue
		var tt: float = float(r["tether"])
		var lr := leap_search(m, 4, 6, null, [-0.5, -0.8], [38])
		print("     %.1f m   yes     %.2f m  %.2f m        %s"
			% [lead, tt, tt + 1.58,
			   ("HELD A6, %s" % ("LOCK" if int(lr["locked"]) == 1 else "partial"))
			   if bool(lr["held"]) and int(lr["on"]) == 6
			   else ("held A%d instead" % int(lr["on"])) if bool(lr["held"])
			   else str(lr["why"])])
		m.free()
	print("   The upper tier floor is at y=0 and A4 is at y=-2.2, so the deepest a")
	print("   body can hang under A4 while still over that floor is 2.2 m. Every")
	print("   catch above is a dead hang standing on the ground.")
	print("")
	print("   So the long catch has to be made from PAST the lip - on the way down")
	print("   into the drop, where there is 5.2 m of air under A4. The body crawls")
	print("   off the edge at x=20 and throws back up at A4 while falling, at a")
	print("   sweep of delays after it leaves the floor. 27 strokes per delay.")
	print("     throw fired  locked  tether  closest the whip TIP came to A4")
	for delay in [0, 8, 16, 24, 32, 40]:
		var m := new_level()
		place(m, 15.0)
		crawl_to(m, 20.6, null)
		for t in 240:
			step(m, m.body_pos, false, null)
			if m.body_pos.y > 0.2:
				break
		var snap := LEAP.save_state(m)
		var got := -1.0
		var tipmin := 1e9
		for a0 in [PI * 0.85, PI * 1.10, -PI * 0.30]:
			for a1 in [PI * 0.95, PI * 1.15, PI * 0.75]:
				for sd in [6, 10, 16]:
					LEAP.load_state(m, snap)
					var grip := false
					var closes := 0
					for t in 200:
						var ang: float = a0 if t < delay else a1
						if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW 								and float(m.a_freelen[4]) < 0.0:
							grip = false
						if not grip and absf(float(m.a_theta[4])) >= 2.6 								and closes < 4 and float(m.a_freelen[4]) < 0.0:
							grip = true
							closes += 1
						step(m, m.body_pos
							+ Vector2(cos(ang), sin(ang)) * m.REACH, grip, null)
						tipmin = minf(tipmin, m.pos[m.NP - 1].distance_to(m.a_pos[4])
							- float(m.a_r[4]))
						if float(m.a_freelen[4]) >= 0.0:
							break
					if float(m.a_freelen[4]) < 0.0:
						continue
					var tt: float = float(m.a_freelen[4])
					for t in 90:
						step(m, m.body_pos, true, null)
						if float(m.a_freelen[4]) < 0.0:
							break
					if float(m.a_freelen[4]) >= 0.0 and int(m.a_locked[4]) == 1:
						got = maxf(got, tt)
		print("     %3d ticks    %s   %s   %.2f m"
			% [delay, "yes" if got > 0.0 else "no ",
			   ("%.2f m" % got) if got > 0.0 else "  -   ", tipmin])
		m.free()
	print("")


# ------------------------------------------------ THE RECOVERY-SPINE LENS --
# Sections 9-12 exist to answer one question: given that a 2.2 m recovery beam
# can be CAUGHT from a standstill and never LEFT, what should the spine be?
# Everything below is measured on the same sim, with the same three verbs.

func set_terrain(m: Node2D, pts: Array) -> void:
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for i in range(pts.size() - 1):
		m.t_a.append(pts[i]); m.t_b.append(pts[i + 1])
	for i in m.t_a.size():
		var d: Vector2 = Vector2(m.t_b[i]) - Vector2(m.t_a[i])
		m.t_n.append(Vector2(d.y, -d.x).normalized())

func banish(m: Node2D) -> void:
	# park every anchor where nothing can touch it, so a bench measures one beam
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(-900.0, -900.0)

func gait_run(m: Node2D, ticks: int, L) -> void:
	for t in ticks:
		var f := float(t % GAIT_PERIOD) / float(GAIT_PERIOD)
		var tgt: Vector2
		var grip := false
		if f < 0.45:
			tgt = m.body_pos + Vector2(cos(GAIT_BACK), sin(GAIT_BACK)) * m.REACH
		else:
			tgt = m.body_pos + Vector2(cos(GAIT_FWD), sin(GAIT_FWD)) * m.REACH
			grip = f > GAIT_TAUT
		step(m, tgt, grip, L)

func pump_peak(m: Node2D, k: int, secs := 20) -> Array:
	# pump flat out and report [peak swing deg, peak body speed, still on?]
	var prev: Vector2 = m.body_pos
	var pk := 0.0
	var vmax := 0.0
	for t in secs * 60:
		var cur: Vector2 = PUMP.pump_cursor(m, k, prev, 95.0)
		prev = m.body_pos
		step(m, cur, true, null)
		if float(m.a_freelen[k]) < 0.0:
			return [pk, vmax, false]
		var s := PUMP.swing_state(m, k, prev)
		pk = maxf(pk, absf(rad_to_deg(float(s["theta"]))))
		vmax = maxf(vmax, (m.body_pos - prev).length() * 60.0)
	return [pk, vmax, true]

func sec_grade() -> void:
	print("9) HOW STEEP A SLOPE CAN THE LASH GAIT ACTUALLY CLIMB? Every claim in")
	print("   this project rests on tests/escape_probe.gd, which measured DIPS")
	print("   that no longer exist in the level. Re-measured here on clean ramps,")
	print("   30 s of gait each, no anchors in reach. This decides whether a")
	print("   terraced or ramped floor is even legal.")
	print("     grade      travelled   height gained   net speed")
	for g in [0.0, 3.0, 6.0, 9.0, 12.0, 16.0, 20.0, -6.0, -12.0, -20.0]:
		var m := new_level()
		banish(m)
		var s := tan(deg_to_rad(g))
		set_terrain(m, [Vector2(-30, 0), Vector2(0, 0),
			Vector2(30, -30.0 * s), Vector2(50, -30.0 * s)])
		place(m, -2.0)
		var x0: float = m.body_pos.x
		var y0: float = m.body_pos.y
		gait_run(m, 1800, null)
		var dx: float = m.body_pos.x - x0
		var dy: float = y0 - m.body_pos.y
		print("     %+5.1f deg   %6.2f m     %+6.2f m       %.2f m/s"
			% [g, dx, dy, dx / 30.0])
		m.free()
	print("")

func sec_shelf() -> void:
	print("10) THE TWO HALVES OF A RECOVERY BEAM, AS ONE CURVE IN ONE NUMBER.")
	print("    A clean bench: flat floor, ONE recovery beam h metres over it at")
	print("    x=10, and a fast beam 4.5 m over the same floor 3.0 m further on")
	print("    (the real A5->A6 geometry, generalised). The body is placed 8 m")
	print("    back and CRAWLS in, so the whip is in the state a run leaves it,")
	print("    not hand-draped. Then the route's own lead ladder throws at it,")
	print("    then it pumps for 20 s, then it tries to leave.")
	print("     h      catch from a standstill        pump      leave for the fast beam")
	print("            lock  tether  ticks to catch   peak sw   ")
	for h in [2.0, 2.2, 2.6, 3.0, 3.4, 3.8, 4.2]:
		var m := new_level()
		banish(m)
		set_terrain(m, [Vector2(-30, 0), Vector2(45, 0)])
		m.a_pos[5] = Vector2(10.0, -h); m.a_r[5] = 0.18
		m.a_pos[6] = Vector2(13.0, -4.5); m.a_r[6] = 0.10
		place(m, 2.0)
		var L := Ledger.new()
		L.maxx = m.body_pos.x
		var t0 := L.ticks
		var r := ground_capture(m, 5, L)
		var tcatch := L.ticks - t0
		if not (bool(r["ok"]) and int(r["locked"]) == 1):
			print("     %.1f m  NO    -       %5.1f s          -         -"
				% [h, tcatch / 60.0])
			m.free()
			continue
		var teth: float = float(r["tether"])
		var save := LEAP.save_state(m)
		var pk := pump_peak(m, 5, 20)
		LEAP.load_state(m, save)
		var lr := leap_search(m, 5, 6, null, [-0.5, -0.8], [38])
		var v := "missed"
		if bool(lr["held"]) and int(lr["on"]) == 6:
			v = "HELD the fast beam (%s, %.2f m)" % [
				"LOCK" if int(lr["locked"]) == 1 else "amber", float(lr["tether"])]
		elif bool(lr["held"]):
			v = "held something else"
		elif not bool(lr["launched"]):
			v = "NEVER LAUNCHED"
		elif bool(lr["caught"]):
			v = "caught then betrayed"
		print("     %.1f m  yes   %.2f m  %5.1f s          %3.0f deg   %s"
			% [h, teth, tcatch / 60.0, float(pk[0]), v])
		m.free()
	print("")


func sec_terrace() -> void:
	print("11) THE TERRACE. Section 10 says a 2.2 m beam can be caught and never")
	print("    left, and says WHY: the throw from a standstill fixes a 1.6-2.3 m")
	print("    tether, and tether + the pump arm 1.30 + body 0.28 has to fit under")
	print("    the beam. So do not raise the beam - drop the floor PAST it. The")
	print("    beam stays 2.0 m over the terrace you throw from and becomes")
	print("    2.0 + step over the one you swing over. Clean bench: upper floor to")
	print("    x=0, a face, lower floor beyond, beam `off` metres past the lip at")
	print("    2.0 m over the UPPER floor, and a fast beam 6.0 m on at 4.5 m over")
	print("    the LOWER one. Body placed 8 m back on the upper terrace, CRAWLS in.")
	print("     step  off   face   catch from the upper terrace   pump    onto the fast beam")
	# `off` cannot exceed ~2.5 m: the thrower has to STAND on the upper terrace,
	# and the lead ladder tops out at 2.9 m. off 3.0+ walks the body off the
	# edge before it throws, which measures the bot, not the level.
	for cell in [[2.2, 2.0, 90.0], [2.6, 2.0, 90.0], [3.0, 2.0, 90.0],
			[3.4, 2.0, 90.0], [3.0, 1.4, 90.0], [3.0, 2.5, 90.0]]:
		var d: float = float(cell[0])
		var off: float = float(cell[1])
		var fa: float = float(cell[2])
		var m := new_level()
		banish(m)
		var fw: float = 0.0 if fa >= 89.0 else d / tan(deg_to_rad(fa))
		set_terrain(m, [Vector2(-30, 0), Vector2(0, 0), Vector2(fw, d),
			Vector2(45, d)])
		m.a_pos[5] = Vector2(off, -2.0); m.a_r[5] = 0.18
		m.a_pos[6] = Vector2(off + 6.0, d - 4.5); m.a_r[6] = 0.10
		place(m, -8.0)
		var L := Ledger.new()
		L.maxx = m.body_pos.x
		var t0 := L.ticks
		var r := ground_capture(m, 5, L)
		var tc := L.ticks - t0
		if not (bool(r["ok"]) and int(r["locked"]) == 1):
			print("     %.1f   %.1f   %2.0f     NO LOCK  (%.1f s spent)          -       -"
				% [d, off, fa, tc / 60.0])
			m.free()
			continue
		var teth: float = float(r["tether"])
		var save := LEAP.save_state(m)
		var pk := pump_peak(m, 5, 20)
		LEAP.load_state(m, save)
		var lr := leap_search(m, 5, 6, null, [-0.5, -0.8], [38])
		var v := "missed"
		if bool(lr["held"]) and int(lr["on"]) == 6:
			v = "HELD (%s, %.2f m)" % ["LOCK" if int(lr["locked"]) == 1
				else "amber", float(lr["tether"])]
		elif bool(lr["held"]):
			v = "held something else"
		elif not bool(lr["launched"]):
			v = "NEVER LAUNCHED"
		elif bool(lr["caught"]):
			v = "caught then betrayed"
		print("     %.1f   %.1f   %2.0f     lock, tether %.2f m, %4.1f s   %3.0f deg  %s"
			% [d, off, fa, teth, tc / 60.0, float(pk[0]), v])
		m.free()
	print("     (deepest a hang can reach = tether + 1.30 + 0.28. Compare it with")
	print("      2.0 + step, which is what the beam is over the floor it swings on.)")
	print("")


func sec_descend() -> void:
	print("12) CAN THE FAST LINE DESCEND? If the recovery beam has to be 2.0 m")
	print("    over the terrace you throw from and 4.5 m over the one you swing")
	print("    on, the world has to step down. That makes every fast leg a")
	print("    DESCENDING one, which nothing has measured: section 7 only ever")
	print("    moved A8 sideways. Clean bench, two beams, both 4.5 m over their")
	print("    own floor, the step between them at the midpoint.")
	print("     gap    drop   legs held  mean catch tether  mean swing at release")
	for gap in [7.4]:
		for dy in [0.0, 1.2, 2.5, 3.7]:
			var nh := 0
			var n := 0
			var ts := 0.0
			var amp := 0.0
			for teth in [2.0, 2.4, 2.8]:
				var m := new_level()
				banish(m)
				set_terrain(m, [Vector2(-15, 0), Vector2(gap * 0.5, 0),
					Vector2(gap * 0.5, dy), Vector2(40, dy)])
				m.a_pos[6] = Vector2(0.0, -4.5); m.a_r[6] = 0.10
				m.a_pos[8] = Vector2(gap, dy - 4.5); m.a_r[8] = 0.10
				LEAP._wind_on(m, 6, teth, 1.8, deg_to_rad(6.0))
				for t in 30:
					step(m, m.body_pos, true, null)
				if float(m.a_freelen[6]) < 0.0:
					m.free()
					continue
				n += 1
				var r := leap_search(m, 6, 8, null, [-0.5], [38])
				amp += float(r["amp"])
				if bool(r["held"]) and int(r["on"]) == 8:
					nh += 1
					ts += float(r["tether"])
				m.free()
			print("     %.1f m  %.1f m   %d / %d      %5.2f m            %3.0f deg"
				% [gap, dy, nh, n, ts / maxf(nh, 1), amp / maxf(n, 1)])
	print("")


# ------------------------------------------------------- THE TERRACED LEVEL --
# v2 of the lower tier. ONE line of beams, every one of them 4.5-5.0 m over the
# floor it swings on. The floor steps down 2.5 m every 14.8 m, and the beam at
# each lip is therefore ALSO only 2.0 m over the terrace behind it - which is
# inside the standstill catch ceiling section 10 measured. There is no second
# road: the "recovery spine" is the set of on-ramps to the only line there is.
var use_v2 := false

func apply_v2(m: Node2D) -> void:
	set_terrain(m, [Vector2(-14, 0), Vector2(20, 0), Vector2(20, 3.0),
		Vector2(34.8, 3.0), Vector2(34.8, 6.0), Vector2(49.6, 6.0),
		Vector2(49.6, 9.0), Vector2(64, 9.0)])
	m.t_a.append(Vector2(-14, -8)); m.t_b.append(Vector2(-14, 0))
	m.t_a.append(Vector2(64, 9.0)); m.t_b.append(Vector2(64, -4.0))
	m.t_n.clear()
	for i in m.t_a.size():
		var d: Vector2 = Vector2(m.t_b[i]) - Vector2(m.t_a[i])
		m.t_n.append(Vector2(d.y, -d.x).normalized())
	# indices kept so every existing tool still addresses them by name
	var v := {0: Vector2(-2.0, -2.2), 1: Vector2(3.6, -2.2),
		2: Vector2(10.4, -4.5),
		4: Vector2(21.4, -2.0),      # ON-RAMP off the upper tier
		6: Vector2(28.8, -1.5),      # over T1
		5: Vector2(36.2, 1.0),       # ON-RAMP off T1
		8: Vector2(43.6, 1.5),       # over T2
		7: Vector2(51.0, 4.0),       # ON-RAMP off T2
		10: Vector2(58.4, 4.5)}      # over T3
	var rr := {0: 0.22, 1: 0.22, 2: 0.10, 4: 0.16, 6: 0.10, 5: 0.16, 8: 0.10,
		7: 0.16, 10: 0.10}
	for k in m.a_pos.size():
		if v.has(k):
			m.a_pos[k] = v[k]
			m.a_r[k] = float(rr[k])
		else:
			m.a_pos[k] = Vector2(-900.0, -900.0)
	m.goal_x = 62.0

func new_level_v2() -> Node2D:
	var m := new_level()
	apply_v2(m)
	return m

func sec_v2() -> void:
	print("13) THE TERRACED LOWER TIER, AND THE ONLY QUESTION THAT MATTERS:")
	print("    A BODY DROPPED AT THE WORST POINT ON EACH FLOOR, CAN IT GET BACK?")
	var m0 := new_level_v2()
	print("    beam    x      y    over its own floor   over the floor 2.4 m")
	print("                                             behind it (the throw)")
	for k in [0, 1, 2, 4, 6, 5, 8, 7, 10]:
		print("    A%-3d  %5.1f  %5.1f      %.2f m               %.2f m"
			% [k, float(m0.a_pos[k].x), float(m0.a_pos[k].y),
			   beam_height(m0, k), stand_height(m0, k)])
	print("    terraces: upper y=0 to x=20, T1 y=3.0 to x=34.8, T2 y=6.0 to")
	print("    x=49.6, T3 y=9.0 to the flag at x=62. Every step is 3.0 m - the")
	print("    same drop the level already has at x=20, repeated.")
	print("")
	print("    THE DROP TEST. The body is put on the floor at the WORST x on each")
	print("    terrace - the far side of the beam it just missed, so the whole")
	print("    terrace has to be crawled - and then does nothing but the three")
	print("    verbs. 'back in play' = hung on a beam with 4.5 m of air under it.")
	print("      dropped at   crawl        throw        result                 total")
	for d in [[-4.6, 4, 6], [20.4, 5, 8], [32.5, 5, 8], [35.2, 7, 10],
			[47.3, 7, 10]]:
		var dx: float = float(d[0])
		var kr: int = int(d[1])
		var kn: int = int(d[2])
		var m := new_level_v2()
		place(m, dx)
		var L := Ledger.new()
		L.maxx = m.body_pos.x
		settle_ground(m, L, 90)
		var t0 := L.ticks
		var target: float = float(m.a_pos[kr].x) - 2.9
		crawl_to(m, target, L, 6000)
		var tcrawl := L.ticks - t0
		var t1 := L.ticks
		var r := ground_capture(m, kr, L)
		var tthrow := L.ticks - t1
		if not (bool(r["ok"]) and int(r["locked"]) == 1):
			print("      x %5.1f      %5.1f s      %5.1f s      NO LOCK on A%d          -"
				% [dx, tcrawl / 60.0, tthrow / 60.0, kr])
			m.free()
			continue
		var t2 := L.ticks
		var lr := leap_search(m, kr, kn, L)
		var tleap := L.ticks - t2
		var v := "missed A%d" % kn
		if bool(lr["held"]) and int(lr["on"]) == kn:
			v = "A%d->A%d %s, %.2f m" % [kr, kn, "LOCK"
				if int(lr["locked"]) == 1 else "amber", float(lr["tether"])]
		elif bool(lr["held"]):
			v = "held A%d instead" % int(lr["on"])
		elif not bool(lr["launched"]):
			v = "NEVER LAUNCHED off A%d" % kr
		print("      x %5.1f      %5.1f s      %5.1f s      %-22s %5.1f s"
			% [dx, tcrawl / 60.0, tthrow / 60.0 + tleap / 60.0, v,
			   L.ticks / 60.0])
		m.free()
	m0.free()
	print("")

func sec_v2run() -> void:
	print("14) THE WHOLE TERRACED LEVEL, FROM THE REAL SPAWN, ONE ROUTE.")
	use_v2 = true
	var L := run_route([0, 1, 4, 6, 5, 8, 7, 10])
	report(L, "THE TERRACED LINE")
	use_v2 = false
	print("")


func sec_v2band() -> void:
	print("15) THE TWO OUTCOMES OF AN ON-RAMP. Hung on each on-ramp at a chosen")
	print("    tether: (a) leap at the next beam, (b) from the SAME state, just")
	print("    OPEN THE HAND and let go. (b) is the whole point of hanging the")
	print("    beam past a lip. On the flat level, releasing a recovery beam puts")
	print("    the body back on the floor it threw from, at the x it threw from -")
	print("    a fixed point, which is what a dead end IS. Here the beam overhangs")
	print("    the next terrace down, so the failed catch is a slide, not a trap.")
	print("      leg        tether  leap                      let go -> lands at")
	for leg in [[4, 6], [5, 8], [7, 10]]:
		var ka: int = int(leg[0])
		var kb: int = int(leg[1])
		for teth in [1.8, 2.4, 3.0]:
			var m := new_level_v2()
			LEAP._wind_on(m, ka, teth, 1.8, deg_to_rad(6.0))
			for t in 30:
				step(m, m.body_pos, true, null)
			if float(m.a_freelen[ka]) < 0.0:
				print("      A%-2d->A%-2d   %.2f m  (the start wrap did not take)"
					% [ka, kb, teth])
				m.free()
				continue
			var t0: float = float(m.a_freelen[ka])
			var xthrow: float = float(m.a_pos[ka].x) - 2.9
			var save := LEAP.save_state(m)
			var r := leap_search(m, ka, kb, null, [-0.5, -0.8], [38])
			var v := "missed"
			if bool(r["held"]) and int(r["on"]) == kb:
				v = "HELD A%d (%s, %.2f m)" % [kb, "LOCK"
					if int(r["locked"]) == 1 else "amber", float(r["tether"])]
			elif bool(r["held"]):
				v = "held A%d instead" % int(r["on"])
			elif not bool(r["launched"]):
				v = "never launched"
			elif bool(r["caught"]):
				v = "caught then betrayed"
			LEAP.load_state(m, save)
			for t in 400:
				step(m, m.body_pos, false, null)
				if m.grounded and t > 120:
					break
			settle_ground(m, null, 40)
			var lx: float = m.body_pos.x
			var ly := floor_y(m, lx)
			print("      A%-2d->A%-2d   %.2f m  %-24s x %.1f on the y=%.1f floor (%+.1f m from the throw)"
				% [ka, kb, t0, v, lx, ly, lx - xthrow])
			m.free()
	print("")


func sec_v2gap() -> void:
	print("16) WHAT SPACING DOES A TERRACED LEG WANT? Section 7 measured spacing")
	print("    between two beams at the SAME height over the SAME flat floor and")
	print("    found 7.8 m at the peak. An on-ramp leg is not that: it starts on a")
	print("    beam that overhangs a lip, with the tether a ground throw fixed.")
	print("    A4 stays put, A6 moves, on the terraced level.")
	print("      gap    held  caught  per tether (2.0 / 2.4 / 2.8 m)")
	for gap in [5.0, 5.6, 6.2, 6.8, 7.4]:
		var nh := 0
		var nc := 0
		var n := 0
		var line := ""
		for teth in [2.0, 2.4, 2.8]:
			var m := new_level_v2()
			m.a_pos[6] = Vector2(21.4 + gap, -1.5)
			LEAP._wind_on(m, 4, teth, 1.8, deg_to_rad(6.0))
			for t in 30:
				step(m, m.body_pos, true, null)
			if float(m.a_freelen[4]) < 0.0:
				line += "  -"
				m.free()
				continue
			n += 1
			var r := leap_search(m, 4, 6, null, [-0.5, -0.8], [38])
			if bool(r["held"]) and int(r["on"]) == 6:
				nh += 1
				line += "  L" if int(r["locked"]) == 1 else "  h"
			elif bool(r["held"]):
				line += " A%d" % int(r["on"])
			elif not bool(r["launched"]):
				line += "  x"
			elif bool(r["caught"]):
				line += "  p"
			else:
				line += "  ."
			if bool(r["caught"]):
				nc += 1
			m.free()
		print("      %.1f m   %d/%d    %d      %s" % [gap, nh, n, nc, line])
	print("      (L = green lock, h = amber, p = caught then betrayed,")
	print("       . = missed, x = never launched)")
	print("")


func sec_v2worst() -> void:
	print("17) THE DROP TEST, DONE HONESTLY. Section 13 put the body straight onto")
	print("    the worst x with place(), which lays the whip along the terrain by")
	print("    x - and at the foot of a face that drapes one segment across the")
	print("    step, the bug section 3 documents. So instead the body is placed in")
	print("    clean middle of the terrace, walked BACKWARDS to the worst x with")
	print("    the reverse gait, and only then does the clock start. Worst x is")
	print("    the foot of the face: you have just fallen the whole step and the")
	print("    entire terrace is in front of you.")
	print("      terrace  worst x  crawl to the throw   throw to a LOCK   tether")
	for c in [[3.0, 30.0, 20.4, 5], [6.0, 44.0, 35.2, 7]]:
		var fy: float = float(c[0])
		var mid: float = float(c[1])
		var worst: float = float(c[2])
		var kr: int = int(c[3])
		var m := new_level_v2()
		place(m, mid)
		settle_ground(m, null, 90)
		crawl_back(m, worst, null, 4000)
		var xstart: float = m.body_pos.x
		var L := Ledger.new()
		L.maxx = m.body_pos.x
		var target: float = float(m.a_pos[kr].x) - 2.9
		crawl_to(m, target, L, 8000)
		var tcrawl := L.ticks
		var xafter: float = m.body_pos.x
		var t1 := L.ticks
		var r := ground_capture(m, kr, L)
		var tthrow := L.ticks - t1
		if not (bool(r["ok"]) and int(r["locked"]) == 1):
			print("      y=%.1f    %.1f     %.1f s (%.1f m)       NO LOCK on A%d"
				% [fy, xstart, tcrawl / 60.0, xafter - xstart, kr])
			m.free()
			continue
		print("      y=%.1f    %.1f     %.1f s (%.1f m)       %.1f s            %.2f m"
			% [fy, xstart, tcrawl / 60.0, xafter - xstart, tthrow / 60.0,
			   float(r["tether"])])
		print("               -> back in play %.1f s after landing, hanging on A%d"
			% [L.ticks / 60.0, kr])
		print("                  with %.2f m of air under it (the fast line is 4.5)"
			% beam_height(m, kr))
		m.free()
	print("")

# ------------------------------------------------------------------- entry --

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var want := "all"
	if args.size() > 0:
		want = str(args[0])
	print("THE ROUTE BOT - the real level, from the real spawn, whip only.")
	print("The RECOVERY SPINE (the safety contract) and the FAST LINE (never")
	print("verified before this run), reported separately.")
	print("")
	var m := new_level()
	sec_level(m)
	m.free()

	if want == "all" or want == "spine":
		print("1) THE RECOVERY SPINE. A0 A1 A2 A3 A4 A5 A6, every one of")
		print("   them 2.2 m over its own floor and catchable from a standstill.")
		var L1 := run_route([0, 1, 2, 3, 4, 5, 6])
		report(L1, "RECOVERY SPINE")
		print("")

	if want == "all" or want == "fast":
		print("2) THE FAST LINE. A7 A8 A9 A10, 4.5 m over their own floors, entered")
		print("   lower, 4.5 m over their floors. The bot still has to get ONTO the")
		print("   line from the ground, so A0/A1 and the lip launcher A4 are in the")
		print("   route; a fast beam it cannot hold drops it onto the recovery")
		print("   spine, which is exactly what the spine is for.")
		var L2 := run_route([0, 1, 2, 3, 7, 8, 9, 10])
		report(L2, "FAST LINE")
		print("")

	if want == "all" or want == "chain":
		sec_chain()
	if want == "all" or want == "door":
		sec_door()
	if want == "all" or want == "gate":
		sec_gate()
	if want == "all" or want == "layout":
		sec_layout()
	if want == "all" or want == "hang":
		sec_hang()
	if want == "all" or want == "a2":
		sec_a2()
	if want == "all" or want == "entry":
		sec_entry()
	if want == "all" or want == "sweep":
		sec_sweep()
	if want == "all" or want == "lip":
		sec_lip()
	if want == "all" or want == "ledge":
		sec_ledge()
	if want == "all" or want == "grade":
		sec_grade()
	if want == "all" or want == "shelf":
		sec_shelf()
	if want == "all" or want == "terrace":
		sec_terrace()
	if want == "all" or want == "descend":
		sec_descend()
	if want == "v2":
		sec_v2()
	if want == "v2run":
		sec_v2run()
	if want == "v2band":
		sec_v2band()
	if want == "v2gap":
		sec_v2gap()
	if want == "v2worst":
		sec_v2worst()

	print("total simulated: %d ticks (%.0f s of sim time), wall clock %.0f s"
		% [sim_ticks, sim_ticks / 60.0, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)

# ------------------------------------------------------------- the ledge --

# The ONLY way to move while attached. Opening the hand takes you off the beam
# that tick (main.gd: "HAND OPEN = OFF THE BEAM, THIS TICK"), so the lash gait
# cannot be walked with a wrap on: its slack half-cycle would drop the beam.
# What is left is the haul - grip closed, cursor pointed at the anchor. The arm
# force is an internal pair, so with the rope taut it drags the BODY toward the
# beam, which is the README's own "TAUT grip: bear load, haul". Hauling stops
# the moment the feet leave the ground: after that the same cursor is reeling
# the body up its own arm, which shortens the pendulum instead of seeding it.
func haul_off(m: Node2D, k: int, L, cap := 240) -> Dictionary:
	var t := 0
	var x0: float = m.body_pos.x
	var y0: float = m.body_pos.y
	while t < cap and m.grounded and float(m.a_freelen[k]) >= 0.0:
		var d: Vector2 = (Vector2(m.a_pos[k]) - m.body_pos).normalized()
		step(m, m.body_pos + d * m.REACH, true, L)
		t += 1
	return {"t": t, "dx": m.body_pos.x - x0, "dy": m.body_pos.y - y0,
		"on": float(m.a_freelen[k]) >= 0.0, "air": not m.grounded,
		"x": m.body_pos.x, "y": m.body_pos.y}

# Ride it. Grip closed, cursor held out at the anchor so the arm stays extended
# and the rope stays taut - no pump, no cleverness, the thing a player does the
# first time. Reports the swing the terrain alone paid for.
func swing_watch(m: Node2D, k: int, n: int, dir: float) -> Dictionary:
	var prev: Vector2 = m.body_pos
	var pk := -999.0
	var pkb := 999.0
	var clr := 99.0
	var lost := -1
	var gnd := 0
	for t in n:
		if float(m.a_freelen[k]) < 0.0:
			lost = t
			break
		var s := PUMP.swing_state(m, k, prev)
		var th: float = rad_to_deg(float(s["theta"])) * dir
		pk = maxf(pk, th)
		pkb = minf(pkb, th)
		clr = minf(clr, floor_y(m, m.body_pos.x) - m.body_pos.y - m.BODY_R)
		if m.grounded:
			gnd += 1
		var d: Vector2 = (Vector2(m.a_pos[k]) - m.body_pos).normalized()
		prev = m.body_pos
		step(m, m.body_pos + d * m.REACH, true, null)
	# how much of the whip is still lying on the upper tier behind the lip?
	var drape := 0
	for i in m.NP:
		var p: Vector2 = m.pos[i]
		if p.x < 20.05 and p.y > -0.20:
			drape += 1
	return {"fwd": pk, "back": pkb, "clr": clr, "lost": lost, "gnd": gnd,
		"drape": drape}

func sec_ledge() -> void:
	print("9) THE HAUL-OFF - AN ENTRANCE MADE OF TERRAIN INSTEAD OF BEAMS.")
	print("   Section 8 says the lip launcher fails, and section 2d says nothing")
	print("   on the lower tier can launch at A6 either. Both failures are the")
	print("   same one and it is not the beam, it is the FLOOR under it. A4 sits")
	print("   0.4 m SHORT of the lip at x=20, so a body hanging under it is still")
	print("   over the UPPER tier: it stands on its own feet and the pump has")
	print("   nothing to swing in. Move the same beam a couple of metres PAST the")
	print("   lip and NOTHING about the throw changes - it is still 2.2 m over the")
	print("   floor you are standing on, still inside the standstill envelope -")
	print("   but the hang is now over 5.2 m of open air.")
	print("   AND THE STEP-OFF IS FREE ENERGY. The tether is fixed by where you")
	print("   stood when it locked, so a throw made from the edge is already at")
	print("   full stretch when the feet leave: the drop off the lip goes into the")
	print("   swing as TANGENTIAL speed instead of into a radial yank. That is the")
	print("   seed a 2.2 m beam can never give you, and the 5.2 m of air under the")
	print("   lip beam is the room to pump it up.")
	print("   'caught at' is where the body was the tick the wrap engaged, and")
	print("   whether its feet were still on the ledge.")
	print("")
	var wins: Array = []
	for xe in [21.0, 21.4, 21.8, 22.2, 22.6]:
		print("   --- A4 moved to (%.1f, -2.2), %.2f m to A6 -----------------------"
			% [xe, Vector2(xe, -2.2).distance_to(Vector2(27.2, -1.5))])
		for xs in [18.8, 19.2, 19.6]:
			var m := new_level()
			m.a_pos[4] = Vector2(xe, -2.2)
			m.a_r[4] = 0.11
			place(m, xs)
			var r := plan_throw(m, 4, null)
			var cau := "caught at (%.1f,%+.2f) %s" % [float(r["ex"]), float(r["ey"]),
				"feet on the ledge" if bool(r["egnd"]) else "already off the edge"]
			if not (bool(r["ok"]) and int(r["locked"]) == 1):
				print("   stand %.1f (lead %.1f)  no lock%s"
					% [xs, xe - xs, "" if int(r["et"]) < 0 else " - %s, then it betrayed" % cau])
				m.free()
				continue
			var tt: float = float(r["tether"])
			var h := haul_off(m, 4, null)
			if not bool(h["on"]):
				print("   stand %.1f (lead %.1f)  LOCK %.2f m, %s, then lost it hauling"
					% [xs, xe - xs, tt, cau])
				m.free()
				continue
			var snap := LEAP.save_state(m)
			var w := swing_watch(m, 4, 300, 1.0)
			LEAP.load_state(m, snap)
			var lr := leap_search(m, 4, 6, null, [-0.5, -0.8], [38])
			var v := "missed"
			if bool(lr["held"]) and int(lr["on"]) == 6:
				v = "HELD A6 (%s, tether %.2f m)" % [
					"LOCK" if int(lr["locked"]) == 1 else "amber", float(lr["tether"])]
			elif bool(lr["held"]):
				v = "held A%d instead" % int(lr["on"])
			elif not bool(lr["launched"]):
				v = "never launched"
			elif bool(lr["caught"]):
				v = "caught A6 then betrayed"
			print("   stand %.1f (lead %.1f)  LOCK %.2f m, %s" % [xs, xe - xs, tt, cau])
			print("                        haul %+.2f m / %.1f s -> %s; riding it: %+.0f deg forward, floor clear %.2f m%s"
				% [float(h["dx"]), float(h["t"]) / 60.0,
				   "AIRBORNE at x %.1f" % float(h["x"]) if bool(h["air"]) else "still standing",
				   float(w["fwd"]), float(w["clr"]),
				   ", dropped the beam at %.1f s" % (float(w["lost"]) / 60.0)
					if int(w["lost"]) >= 0 else ""])
			print("                        A4 -> A6: rel %2.0f off a %3.0f deg swing: %s  [%d cand]"
				% [float(lr["rel"]), float(lr["amp"]), v, int(lr["cands"])])
			if bool(lr["held"]) and int(lr["on"]) == 6 and int(lr["locked"]) == 1:
				wins.append([xe, xs, float(lr["tether"])])
			m.free()
	print("")
	print("   THE WHOLE LINE, ENTERED THROUGH THE DOOR THAT JUST OPENED. Each")
	print("   winner above is flown on: A4 -> A6 -> A8 -> A10 -> A12 -> A13, one")
	print("   continuous trajectory from the standstill throw on the upper tier.")
	print("   'feet' counts ticks of ground contact in flight - the fast line's")
	print("   whole promise is that there are none.")
	print("     A4 at  stand   legs held   x reached   time    feet   per leg")
	for wq: Array in wins:
		var xe: float = float(wq[0])
		var xs: float = float(wq[1])
		var m := new_level()
		m.a_pos[4] = Vector2(xe, -2.2)
		m.a_r[4] = 0.11
		place(m, xs)
		var L := Ledger.new()
		L.maxx = m.body_pos.x
		var r := plan_throw(m, 4, L)
		if not (bool(r["ok"]) and int(r["locked"]) == 1):
			m.free()
			continue
		haul_off(m, 4, L)
		var cur := 4
		var line := ""
		var ok := 0
		var feet := 0
		for kb in [6, 8, 10, 12, 13]:
			var lr := leap_search(m, cur, kb, L)
			feet += int(lr["air_gnd"])
			if bool(lr["held"]) and int(lr["on"]) == kb:
				ok += 1
				line += " A%d(%s,%.1fm)" % [kb,
					"L" if int(lr["locked"]) == 1 else "p", float(lr["tether"])]
				cur = kb
			elif bool(lr["held"]):
				line += " ->A%d!" % int(lr["on"])
				cur = int(lr["on"])
			else:
				line += " A%d:%s" % [kb, str(lr["why"])]
				break
		print("     %.1f   %.1f     %d of 5      %5.1f m    %4.1f s  %3d  %s"
			% [xe, xs, ok, L.maxx, L.ticks / 60.0, feet, line])
		m.free()
	print("")
