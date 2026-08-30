extends SceneTree
## THE LEAP - beam to beam, feet never on the ground.
##
## Stage 1 (tests/bot_pump.gd) showed a body on a locked wrap can grow its own
## swing. This is the other half of the loop: turn that swing into a crossing.
##
## WHY THE ORDER IS PUMP -> OPEN -> THROW -> SHUT, and why nothing else works:
##
##  * The hand cannot pull you anywhere. The arm force is an INTERNAL pair, so
##    pointing it at the next beam pushes the body away from it (bot_pump's sign
##    check). All locomotion is: earn speed on a swing, then spend it.
##  * OPENING the hand IS the launch. A wrap holds only while gripped and the
##    release is total and instantaneous, so the release angle alone decides the
##    launch vector - there is no second chance to adjust it.
##  * The swing IS the windup. At the release point the whip is streaming
##    BEHIND the body (it has just come off the beam you were hanging on), so
##    the stroke can start at once - measured, 4 to 18 ticks after the hand
##    opens, and a bot that winds up first wastes the only airtime it has. The
##    tip needs 30-40 ticks (0.5-0.65 s) to travel from behind the body to the
##    beam and the whole flight is 60-90 ticks, so the stroke is the second
##    thing you do, and it tolerates about +-4 ticks.
##  * Throwing COSTS the body its forward speed. The whip is 1/8 of the mass and
##    the stroke hurls it forward, so the body pays for it: measured on the
##    traced leap below, 7.1 m/s at the launch and 3.2 m/s while the wave runs
##    out. That is the deal, and it is a good one, because the body does not
##    have to cross the gap - the WHIP does. Of the level's 7.8 m, the swing
##    carried the body 1.7 m, the flight 3.9 m, and the whip covered the last
##    2.2 m. The body only ever has to get inside the whip's reach.
##  * SHUTTING the hand is the catch, and it is a trigger, not a latch: the wrap
##    can only take within GRIP_WINDOW (15 ticks) of the hand closing. Holding
##    the button through the flight catches nothing.
##
## WHAT IT COMES TO (every figure below is measured by the bench in this file):
##
##  * The fast line is completable. On the REAL level, with every other beam
##    present, 18 of 32 legs held and 2 of 16 starting states carried the body
##    A6 -> A8 -> A10 -> A12 - the whole 23.4 m fast line, three leaps, feet
##    never on the ground.
##  * At the level's 7.8 m spacing on an isolated pair of beams the same policy
##    holds 6 of 10 attempts. The two it never holds are the two that start
##    from a 1.5 m tether, and those fail at EVERY release angle tried.
##  * The envelope is 6.0 to 8.5 m at 5-6 of 10, with a wall between 8.5 and
##    9.5: at 9.5 m the whip touches the beam twice in ten tries and holds none
##    of them. 7.8 m sits just inside a real limit, which is the nicest thing
##    that can be said about a spacing that was picked from a geometric bound.
##  * Climbing barely works. A beam 1.5 m higher holds 2 of 10 at best, at any
##    aim. The fast line has to run level or downhill.
##  * A catch off a leap is a LOCK almost every time: 98 of 118 catches across
##    the whole grid, and of the 20 ambers only 3 survived two seconds. A throw
##    that reaches a beam 4 m away arrives fast and lays on more than a turn.
##    The failure mode of a leap is missing the beam, not catching an amber -
##    which is the opposite of a throw from a standstill, where main.gd's own
##    figures are half of blind strokes catching and only one in six locking.
##  * Your own catch can trap you at both ends. Under ~1.9 m of tether you
##    cannot reach the next beam; over ~3.4 m you cannot pump clear of a 4.5 m
##    floor, so you can never leave the beam you are on. Both were measured
##    here, and both are what makes the length of a catch a real decision.
##
## THE POLICY - reusable, self-contained, no state but the previous tick's body
## position and one dictionary you own:
##
##   static func default_policy() -> Dictionary
##       every free parameter, documented at its declaration below.
##
##   static func leap_begin(m: Node2D, ka: int, kb: int,
##                          p := default_policy()) -> Dictionary
##       m   a main.gd instance with external_drive = true, already hanging on
##           a wrap at anchor ka (m.a_freelen[ka] >= 0)
##       ka  the anchor you are leaving      kb  the anchor you are going to
##       p   policy overrides; the defaults are the measured optimum
##       -> the leap state dictionary, `st`
##
##   static func leap_step(m: Node2D, st: Dictionary,
##                         prev_body: Vector2) -> Array
##       prev_body  m.body_pos as of the PREVIOUS tick (pass m.body_pos on the
##                  first call)
##       -> [cursor: Vector2 (world metres), grip: bool] for m.step_tick()
##
##   st["phase"] runs "pump" -> "fly" -> "hang", or "fail". Read st["phase"],
##   st["rel_t"], st["grip_t"], st["ground_t"] for the ledger.
##
##   Usage:
##     const LEAP := preload("res://tests/bot_leap.gd")
##     var st := LEAP.leap_begin(m, 6, 8)
##     var prev := m.body_pos
##     while st["phase"] != "hang" and st["phase"] != "fail":
##         var cg := LEAP.leap_step(m, st, prev)
##         prev = m.body_pos
##         m.step_tick(cg[0], cg[1])
##
## Run the bench:
##   godot --headless --path . -s res://tests/bot_leap.gd

const PUMP := preload("res://tests/bot_pump.gd")

# ------------------------------------------------------------------ policy --

static func default_policy() -> Dictionary:
	return {
		# --- the pump (stage 1 does the work; these say when to stop) ---
		"amp": 70.0,       # deg: launch once a half-swing has peaked this high
		"amp_max": 105.0,  # deg: ... but not while it is peaking HIGHER than this.
		                   # You arrive on a new beam carrying the swing you crossed
		                   # on, and a second leg was once seen launching off a
		                   # 151 deg swing - most of the way round the beam - which
		                   # fires the body flat out on a phase nothing chose. A
		                   # guard, not a lever: with the shipped numbers removing
		                   # it changes nothing (12 of 24 legs either way).
		"max_half": 26,    # half-swings after which the bot goes with whatever it
		                   # has. The pump ceiling falls as the tether grows -
		                   # measured 88 deg at 1.5 m, 84 at 2.7 m, 80 at 3.2 m -
		                   # so a fixed target can be unreachable.
		"target": 95.0,    # deg: amplitude target handed to PUMP.pump_cursor
		# --- the release ---
		"rel": -1.0,       # deg: body angle about beam A at which the hand OPENS,
		                   # measured from straight down, on the way up toward the
		                   # target. < 0 = take it from rel_for_gap(), which is
		                   # what lets ONE policy cover a range of gaps. Both beams
		                   # are on screen, so this is knowledge the player has as
		                   # well. It works out to 30 deg at the level's own 7.8 m.
		# --- the throw ---
		"lead": 38,        # ticks before the ballistically predicted closest
		                   # approach at which the stroke starts.
		"s0_min": 4,       # ticks: earliest the stroke may fire after the hand
		                   # opens. A very short gap predicts an immediate closest
		                   # approach, and throwing on tick 0 - while the whip is
		                   # still coming off the beam you just left - lands 0/10.
		"s0_max": 18,      # ticks: latest. A slow or steep launch predicts a late
		                   # closest approach and the stroke waits so long that the
		                   # body is already falling when the tip arrives.
		"wind": 0.0,       # rad: hand direction before the stroke = (away from the
		                   # target) rotated by this. Swept +-0.5: no consistent
		                   # effect, because the swing has already laid the whip
		                   # out behind you - there is nothing left to wind up.
		"aim": -0.5,       # rad: hand direction during and after the stroke =
		                   # (body -> target) rotated by this. Negative = above the
		                   # beam, and it has to be: the tip sags ~1.5 m over its
		                   # run, and aiming straight at the beam threw the first
		                   # working stroke 1.5 m under it.
		"sd": 10,          # ticks of stroke before the follow-through. Inert while
		                   # pull = 0, since the follow-through holds the same
		                   # direction; it only bites for the reversal variant.
		"pull": 0,         # ticks of stroke REVERSAL after it (the crack). Zero,
		                   # measured: a reversal cracks the tip back off the beam
		                   # it was about to wrap. The crack is a different verb.
		# --- the catch ---
		"grip_arm": 2.6,   # rad of measured wrap on the target that shuts the hand.
		                   # Below th_part (3.4) on purpose: shutting on the reading
		                   # that qualifies is already too late by a tick or two.
		"grip_at": -1,     # >= 0: shut the hand at this tick after release instead
		                   # of on the wrap reading (used to measure the tolerance)
		"retries": 2,      # extra times the hand may re-open and re-shut if the
		                   # 15-tick window lapses without the wrap taking
		"max_fly": 200,    # ticks of flight before the attempt is abandoned
	}

# WHERE ON THE SWING TO LET GO, given how far away the next beam is. A straight
# line through the MEASURED optimum (section 2 repeated at six gaps: 40 deg at
# 5 m, 35 at 6, 30 at 7, 30 at 7.8, 25 at 8.5), not a theory - and worth reading
# twice, because the obvious theory has it backwards. You would reason that a
# far beam needs a high ballistic launch and a near one a flat skim. It is the
# other way round: a FAR beam wants the flattest, fastest release the swing can
# give, and a NEAR beam a steep slow one. The reason is that the whip crosses
# the gap, not the body - all the launch has to do is put you about 4 m from the
# beam with airtime left - and the commonest way to miss a near beam is to sail
# past it while the wave is still running out.
#
# A physically-derived alternative was tried and rejected: predicting each
# candidate angle's ballistic arc and taking the one whose closest approach
# lands at a target distance. It is prettier, and it produces exactly the
# opposite trend to the measurement (12 deg at 5 m rising to 34 at 9.5 m),
# because closest approach alone says nothing about whether you are still up
# there when the tip arrives.
static func rel_for_gap(dist: float) -> float:
	return clampf(30.0 + 4.0 * (7.8 - dist), 22.0, 45.0)

static func leap_begin(m: Node2D, ka: int, kb: int,
		p := default_policy()) -> Dictionary:
	var pp := p.duplicate()
	return {
		"p": pp, "ka": ka, "kb": kb, "phase": "pump", "t": 0,
		"rel_t": -1, "throw_t": -1, "grip_t": -1, "catch_t": -1,
		"f": 0, "s0": 9999, "wind": Vector2.ZERO, "aim": Vector2.ZERO,
		"closed": false, "closes": 0, "close_t": -999,
		"ground_t": 0, "pump_ground": 0, "min_d": 1e9, "max_th": 0.0,
		"peak_v": 0.0,
		"pk": 0.0, "last_pk": 0.0, "half": 0, "sgn": 0.0, "rel_amp": 0.0,
		"rel_deg": -1.0,
	}

static func leap_step(m: Node2D, st: Dictionary, prev_body: Vector2) -> Array:
	var p: Dictionary = st["p"]
	var ka: int = st["ka"]
	var kb: int = st["kb"]
	var B: Vector2 = m.a_pos[kb]
	st["t"] = int(st["t"]) + 1
	if m.grounded:
		st["ground_t"] = int(st["ground_t"]) + 1
	st["min_d"] = minf(float(st["min_d"]), m.body_pos.distance_to(B))
	st["max_th"] = maxf(float(st["max_th"]), absf(m.a_theta[kb]))

	match st["phase"]:
		"pump":
			var s := PUMP.swing_state(m, ka, prev_body)
			var dir: float = signf(B.x - m.a_pos[ka].x)
			var th: float = rad_to_deg(float(s["theta"])) * dir
			var om: float = float(s["omega"]) * dir
			# Amplitude the honest way: the peak |theta| of the last COMPLETED
			# half-swing. swing_state's energy estimate is what the pump servos
			# on and it runs optimistic - trusting it here launched a 66 deg
			# swing that believed it was 80.
			st["pk"] = maxf(float(st["pk"]), absf(th))
			var sg: float = signf(th)
			if sg != 0.0 and sg != float(st["sgn"]):
				if float(st["sgn"]) != 0.0:
					st["last_pk"] = st["pk"]
					st["half"] = int(st["half"]) + 1
				st["sgn"] = sg
				st["pk"] = 0.0
			var ready: bool = (float(st["last_pk"]) >= float(p["amp"])
				and float(st["last_pk"]) <= float(p["amp_max"])) \
				or int(st["half"]) >= int(p["max_half"])
			if ready and float(st["rel_deg"]) < 0.0:
				# the swing is big enough: now choose where on it to let go
				st["rel_deg"] = float(p["rel"]) if float(p["rel"]) >= 0.0 else \
					rel_for_gap(m.a_pos[ka].distance_to(B))
			if ready and th >= float(st["rel_deg"]) and om > 0.0:
				# THE LAUNCH. Opening the hand frees the wrap this tick, so the
				# body leaves on the tangent it happens to have right now.
				st["phase"] = "fly"
				st["rel_t"] = st["t"]
				st["rel_amp"] = st["last_pk"]
				st["f"] = 0
				var v: Vector2 = (m.body_pos - prev_body) * 60.0
				st["peak_v"] = v.length()
				# Ballistic forecast of the closest approach to the target beam.
				# The body's flight is ballistic to within 0.02 m over 40 ticks
				# (measured) until the stroke fires, so this is a fair thing for
				# a player to have in their head.
				var tmin := 0
				var dmin := 1e9
				for i in 240:
					var tt: float = float(i) / 60.0
					var q: Vector2 = m.body_pos + v * tt \
						+ Vector2(0.0, 0.5 * float(m.GRAV.y) * tt * tt)
					var dd: float = q.distance_to(B)
					if dd < dmin:
						dmin = dd; tmin = i
				st["s0"] = clampi(tmin - int(p["lead"]), int(p["s0_min"]),
					int(p["s0_max"]))
				st["pump_ground"] = st["ground_t"]
				st["ground_t"] = 0        # the LEAP is what must stay off the floor
				var u: Vector2 = (B - m.body_pos).normalized()
				st["wind"] = u.rotated(PI + float(p["wind"]))
				return [m.body_pos + Vector2(st["wind"]) * m.REACH, false]
			return [PUMP.pump_cursor(m, ka, prev_body, float(p["target"])), true]
		"fly":
			var f: int = int(st["f"])
			st["f"] = f + 1
			# --- the stroke: hand back, then through, then hold ---
			var s0: int = int(st["s0"])
			var sd: int = int(p["sd"])
			var pl: int = int(p["pull"])
			if f == s0:
				st["throw_t"] = f
				st["aim"] = (B - m.body_pos).normalized().rotated(float(p["aim"]))
			var dir_v: Vector2
			if f < s0:
				dir_v = Vector2(st["wind"])
			elif f < s0 + sd:
				dir_v = Vector2(st["aim"])
			elif f < s0 + sd + pl:
				dir_v = Vector2(st["wind"]) * 0.7
			else:
				dir_v = Vector2(st["aim"])
			var cur: Vector2 = m.body_pos + dir_v * m.REACH
			# --- the catch: GRIP IS A TRIGGER ---
			var grip: bool = bool(st["closed"])
			var since: int = int(st["t"]) - int(st["close_t"])
			if grip and since > m.GRIP_WINDOW:
				grip = false                       # the window lapsed: re-arm
				st["closed"] = false
			if not grip:
				var want := false
				if int(p["grip_at"]) >= 0:
					want = f >= int(p["grip_at"])
				else:
					want = absf(m.a_theta[kb]) >= float(p["grip_arm"])
				if want and int(st["closes"]) <= int(p["retries"]) and since > 1:
					grip = true
					st["closed"] = true
					st["close_t"] = st["t"]
					st["closes"] = int(st["closes"]) + 1
					if int(st["grip_t"]) < 0:
						st["grip_t"] = f
			if m.a_freelen[kb] >= 0.0:
				st["phase"] = "hang"
				st["catch_t"] = st["t"]
				return [m.body_pos, true]
			if f >= int(p["max_fly"]) or int(st["ground_t"]) > 0:
				st["phase"] = "fail"
			return [cur, grip]
		"hang":
			if m.a_freelen[kb] < 0.0:
				st["phase"] = "fail"
			return [m.body_pos, true]
	return [m.body_pos, false]

# ------------------------------------------------------------- state store --
# Every mutable field of the sim. Snapshotting lets a search re-run only the
# part it varies (the throw) instead of re-pumping for every sample; there is no
# RNG, so a restored state replays bit-identically (asserted in section 0).
const STATE_KEYS := ["pos", "prv", "body_pos", "body_prv", "taut", "tick_count",
	"grip_edge", "cursor_m", "target_m", "a_theta", "a_lockidx", "a_freelen",
	"a_half", "a_pinidx", "a_pinpt", "a_paytick", "a_locked", "a_armed",
	"a_pin0", "a_pend", "a_ength", "a_minth", "a_wlo", "a_whi", "a_lastth",
	"a_shed", "a_prun", "tip_speed", "crack_cooldown", "crack_flash",
	"slipping", "grounded", "run_ticks", "finished", "falls"]

# A packed array handed out by get() SHARES its buffer with the sim's own field:
# without this duplicate, running one variant corrupted the snapshot and the
# next variant restored a chain whose prv was 500 m/s out of date.
static func _dup(v: Variant) -> Variant:
	match typeof(v):
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_INT32_ARRAY, TYPE_ARRAY, TYPE_DICTIONARY:
			return v.duplicate()
	return v

static func save_state(m: Node2D) -> Dictionary:
	var d := {}
	for k in STATE_KEYS:
		d[k] = _dup(m.get(k))
	return d

static func load_state(m: Node2D, d: Dictionary) -> void:
	for k in STATE_KEYS:
		m.set(k, _dup(d[k]))

# -------------------------------------------------------------------- rigs --

# Two beams in open air over one flat floor `drop` metres under beam A, which is
# the level's own FAST-beam geometry (4.5 m). The chain starts wound `turns`
# onto beam A, hanging `hang` metres, the assembly tilted th0 from vertical.
static func rig2(hang: float, r: float, turns: float, th0: float,
		gap: float, dy: float, drop: float) -> Node2D:
	var m: Node2D = load("res://tests/main_drag.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for kk in range(2, m.a_pos.size()):
		m.a_pos[kk] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0)
	m.a_r[0] = r
	m.a_pos[1] = Vector2(gap, -40.0 - dy)
	m.a_r[1] = 0.10
	if drop > 0.0:
		var fy: float = -40.0 + drop
		m.t_a.append(Vector2(-20.0, fy)); m.t_b.append(Vector2(60.0, fy))
		m.t_n.append(Vector2(0.0, -1.0))
	_wind_on(m, 0, hang, turns, th0)
	return m

# The same wrap built onto an anchor of the REAL level, with all of its terrain
# and every other beam present. This is what decides whether the fast line is
# completable: recovery beams sit 3.9 m from every fast beam and 2.3 m below,
# directly under the flight path, and a two-beam rig cannot see them.
static func rig_level(k: int, hang: float, turns: float, th0: float) -> Node2D:
	var m: Node2D = load("res://tests/main_drag.gd").new()
	m.external_drive = true
	m.setup_sim()
	_wind_on(m, k, hang, turns, th0)
	return m

static func _wind_on(m: Node2D, k: int, hang: float, turns: float,
		th0: float) -> void:
	var c: Vector2 = m.a_pos[k]
	var rr: float = m.a_r[k] + 0.04
	var d := Vector2(sin(th0), cos(th0))          # y-down: th0 = 0 is straight down
	var a_start: float = d.angle()
	var rise: float = hang - rr
	var wl: float = turns * TAU * rr
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var q: Vector2
		if s < rise:
			q = c + d * (hang - s)
		elif s < rise + wl:
			var a: float = a_start + (s - rise) / rr
			q = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = a_start + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			q = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, s - rise - wl)
		m.pos[i] = q; m.prv[i] = q
	m.body_pos = c + d * (hang + 0.6)
	m.body_prv = m.body_pos

# hang, beam radius, turns -> a start hang that classifies LOCKED and pumps
# clear of a floor 4.5 m under the beam. These span the tether a real catch on a
# FAST beam can leave you with: 1.5 m (a close, greedy catch) to 3.2 m (a long
# one). 3.6 m and over drags its feet - measured 300 grounded ticks in 400 and
# an amplitude ceiling of 24 deg - so it is not a state you can leap from.
const STARTS := [
	[1.6, 0.10, 1.8], [2.0, 0.10, 1.8], [2.4, 0.10, 1.8],
	[2.8, 0.10, 1.8], [3.2, 0.10, 1.8],
]

# ------------------------------------------------------------------- bench --

# Pump each start ONCE with the target beam parked out of the way, and
# snapshot the sim at every release angle in `rels` as the swing sweeps past
# them. Every later trial replays from a snapshot, so the pump is paid for once.
static func releases(drop: float, starts: Array, th0s: Array, rels: Array,
		amp := 70.0, max_half := 26) -> Array:
	var out: Array = []
	for si in starts:
		for th0 in th0s:
			var s: Array = STARTS[si]
			var m := rig2(s[0], s[1], s[2], deg_to_rad(th0), 30.0, 0.0, drop)
			for t in 30:
				m.step_tick(m.body_pos, true)
			if m.a_freelen[0] < 0.0:
				m.free(); continue
			var prev: Vector2 = m.body_pos
			var pk := 0.0
			var last_pk := 0.0
			var half := 0
			var sgn := 0.0
			var got := {}
			for t in 1600:
				var st := PUMP.swing_state(m, 0, prev)
				var th: float = rad_to_deg(float(st["theta"]))
				var om: float = float(st["omega"])
				pk = maxf(pk, absf(th))
				var sg: float = signf(th)
				if sg != 0.0 and sg != sgn:
					if sgn != 0.0:
						last_pk = pk
						half += 1
					sgn = sg
					pk = 0.0
				if (last_pk >= amp or half >= max_half) and om > 0.0:
					for rel in rels:
						if th >= float(rel) and not got.has(rel):
							got[rel] = true
							out.append({"m": m, "snap": save_state(m), "prev": prev,
								"rel": float(rel), "si": si, "th0": th0,
								"tether": m.a_freelen[0], "amp": last_pk,
								"v": (m.body_pos - prev).length() * 60.0,
								"pump_t": t, "bx": m.body_pos.x,
								"by": m.body_pos.y + 40.0,
								"pivot": st["pivot"], "radius": st["radius"]})
				if got.size() == rels.size():
					break
				var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 95.0)
				prev = m.body_pos
				m.step_tick(cur, true)
				if m.a_freelen[0] < 0.0:
					break
	return out

# Replay one release snapshot with the target beam moved to (gap, dy), fly the
# throw, and hold on afterwards. Returns the full ledger of the attempt.
static func fly(e: Dictionary, p: Dictionary, gap: float, dy: float,
		hold := 120) -> Dictionary:
	var m: Node2D = e["m"]
	load_state(m, e["snap"])
	m.a_pos[1] = Vector2(gap, -40.0 - dy)
	var pp := p.duplicate()
	pp["rel"] = e["rel"]
	var st := leap_begin(m, 0, 1, pp)
	# the snapshot IS the release tick, so short-circuit the "has the swing
	# grown enough" gate rather than faking an amplitude (a faked one has to
	# satisfy amp_max as well, and a value that fails it silently turns every
	# replay back into a pump)
	st["half"] = int(pp["max_half"])
	var prev: Vector2 = e["prev"]
	var B: Vector2 = m.a_pos[1]
	var tip_min := 1e9
	var tip_t := -1
	var guard := 0
	while st["phase"] != "fail" and st["phase"] != "hang" and guard < 400:
		var cg := leap_step(m, st, prev)
		prev = m.body_pos
		m.step_tick(cg[0], cg[1])
		var td: float = m.pos[m.NP - 1].distance_to(B)
		if td < tip_min:
			tip_min = td
			tip_t = int(st["f"])
		guard += 1
	var held := false
	var locked := -1
	var tether := -1.0
	var pin := -1
	if st["phase"] == "hang":
		held = true
		tether = m.a_freelen[1]
		pin = m.a_pinidx[1]
		for t in hold:
			var cg2 := leap_step(m, st, prev)
			prev = m.body_pos
			m.step_tick(cg2[0], cg2[1])
			if m.a_freelen[1] < 0.0 or m.grounded:
				held = false
				break
		locked = m.a_locked[1]
	return {"catch": st["phase"] == "hang", "held": held, "locked": locked,
		"tether": tether, "pin": pin, "grip_t": st["grip_t"],
		"closes": st["closes"], "throw_t": st["throw_t"], "fly_t": st["f"],
		"ground": st["ground_t"], "scrape": st["pump_ground"],
		"min_d": st["min_d"], "max_th": st["max_th"],
		"tip_min": tip_min, "tip_t": tip_t, "v": e["v"], "rel": e["rel"],
		"tether0": e["tether"]}

# The snapshot bench pins the release angle (a snapshot IS a release instant),
# so to test the gap-adaptive rule offline: work out what rel_for_gap() would
# have chosen for this target, and replay the snapshot nearest that angle. The
# snapshots are 4 deg apart, so the quantisation error is at most 2 deg. The
# real-level section runs the rule live, with no snapshots at all.
static func auto_entry(pop: Array, si: int, th0: float, gap: float,
		dy: float) -> Dictionary:
	var want := rel_for_gap(Vector2(0.0, -40.0).distance_to(
		Vector2(gap, -40.0 - dy)))
	var best := {}
	var berr := 1e9
	for e in pop:
		if int(e["si"]) != si or absf(float(e["th0"]) - th0) > 0.01:
			continue
		var err: float = absf(float(e["rel"]) - want)
		if err < berr:
			berr = err
			best = e
	return best

static func free_pop(pop: Array) -> void:
	var seen := {}
	for e in pop:
		var m: Node2D = e["m"]
		seen[m.get_instance_id()] = m
	for id in seen:
		(seen[id] as Node2D).free()

# One whole leap on the REAL level, start to finish, and then as many more as
# `chain` asks for. No snapshots, no shortcuts: the bot pumps, launches, throws
# and catches with every beam in the level present.
static func level_run(k0: int, hang: float, turns: float, th0: float,
		p: Dictionary, chain := 1, hold := 120) -> Dictionary:
	var m := rig_level(k0, hang, turns, th0)
	for t in 30:
		m.step_tick(m.body_pos, true)
	var out := {"legs": [], "ok": false, "ground": 0, "ticks": 0}
	if m.a_freelen[k0] < 0.0:
		out["why"] = "the start wrap did not take"
		m.free()
		return out
	var prev: Vector2 = m.body_pos
	var k: int = k0
	var ground := 0
	var ticks := 0
	for leg in chain:
		var kb: int = k + 2
		if kb >= m.a_pos.size():
			break
		var st := leap_begin(m, k, kb, p)
		var from_tether: float = m.a_freelen[k]
		var guard := 0
		while st["phase"] != "fail" and st["phase"] != "hang" and guard < 2000:
			var cg := leap_step(m, st, prev)
			prev = m.body_pos
			m.step_tick(cg[0], cg[1])
			guard += 1
		ticks += guard
		var rec := {"from": k, "to": kb, "phase": st["phase"],
			"rel_t": st["rel_t"], "throw_t": st["throw_t"],
			"grip_t": st["grip_t"], "closes": st["closes"],
			"ground": st["ground_t"], "scrape": st["pump_ground"],
			"fly": st["f"], "min_d": st["min_d"],
			"amp": st["rel_amp"], "tether": -1.0, "locked": -1, "held": false,
			"snagged": -1, "stuck": false, "from_tether": from_tether}
		if st["phase"] == "pump":
			# never launched at all: the swing never reached the release angle.
			# Over a 4.5 m floor that means the tether it caught with is too
			# long to pump - the body drags its feet at the bottom of every
			# swing and the amplitude ceiling collapses.
			rec["stuck"] = true
			rec["scrape"] = st["ground_t"]
			rec["ground"] = 0
		# did anything ELSE take? (a recovery beam sits 3.9 m from every fast
		# beam, right under the flight path). The beam being LEFT does not
		# count - if the bot never launched, it is still legitimately on it.
		for j in m.a_pos.size():
			if j != kb and j != k and m.a_freelen[j] >= 0.0:
				rec["snagged"] = j
		if st["phase"] == "hang":
			rec["tether"] = m.a_freelen[kb]
			var held := true
			for t in hold:
				var cg2 := leap_step(m, st, prev)
				prev = m.body_pos
				m.step_tick(cg2[0], cg2[1])
				ticks += 1
				if m.grounded:
					held = false
				if m.a_freelen[kb] < 0.0:
					held = false
					break
			rec["held"] = held
			rec["locked"] = m.a_locked[kb]
		ground += int(st["ground_t"])
		out["legs"].append(rec)
		if not bool(rec["held"]):
			break
		k = kb
	out["ground"] = ground
	out["ticks"] = ticks
	out["ok"] = out["legs"].size() == chain
	for r in out["legs"]:
		if not bool(r["held"]):
			out["ok"] = false
	out["end"] = k
	m.free()
	return out

# --------------------------------------------------------------- the bench --

func _f(v: float, w := 6, d := 2) -> String:
	return "%*.*f" % [w, d, v]

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var P: Dictionary = default_policy()
	print("THE LEAP - can a body get from one FAST beam to the next without")
	print("touching the ground? Beams 4.5 m over their floor, 7.8 m apart.")
	print("Every number below is measured; nothing is asserted from geometry.")
	print("")

	# ---------------------------------------------------------------- pop --
	var rels := [12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0,
		52.0, 56.0, 60.0]
	var pop := releases(4.5, [0, 1, 2, 3, 4], [6.0, 11.0], rels)
	var pairs := []
	for si in range(5):
		for th0 in [6.0, 11.0]:
			pairs.append([si, th0])
	var starts_seen := {}
	print("0) THE ATTEMPT POPULATION. The sim has no RNG, so 'success rate' can")
	print("   only mean 'over a spread of honest starting states'. Each start is")
	print("   a different tether - the length YOUR catch on the previous beam")
	print("   happened to fix - crossed with two initial swing seeds. The pump")
	print("   (tests/bot_pump.gd) is run once per start and the release state is")
	print("   snapshotted at each candidate release angle on the same swing.")
	# the replay the whole bench rests on
	var chk := rig2(2.0, 0.10, 1.8, deg_to_rad(6.0), 7.8, 0.0, 4.5)
	for t in 40:
		chk.step_tick(chk.body_pos, true)
	var snap := save_state(chk)
	for t in 50:
		chk.step_tick(chk.body_pos + Vector2(0.6, -0.4), t % 7 < 3)
	var h1: int = chk.state_hash()
	load_state(chk, snap)
	for t in 50:
		chk.step_tick(chk.body_pos + Vector2(0.6, -0.4), t % 7 < 3)
	print("   replay check: a restored snapshot re-runs bit-identically: %s"
		% ("yes" if chk.state_hash() == h1 else "NO - the bench is invalid"))
	chk.free()
	print("   start  tether  pump ceiling  ticks to pump  release speed @30 deg")
	for e in pop:
		var key := "%d/%.0f" % [e["si"], e["th0"]]
		if starts_seen.has(key) or absf(float(e["rel"]) - 28.0) > 0.01:
			continue
		starts_seen[key] = true
		print("   s%d/%2.0f   %.2f m     %3.0f deg      %4d        %.2f m/s"
			% [e["si"], e["th0"], e["tether"], e["amp"], e["pump_t"], e["v"]])
	print("")

	_sec1(P)
	_sec2(pop, P, rels)
	var auto78 := _auto_pop(pop, pairs, 7.8, 0.0)
	_sec3(auto78, P)
	_sec4(auto78, P)
	_sec5(pop, P, pairs)
	_sec6(P)
	free_pop(pop)
	print("(bench %.0f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)

# ---- 1: one leap, traced ---------------------------------------------------
func _sec1(P: Dictionary) -> void:
	print("1) ONE LEAP, TRACED. Start: hanging on a locked wrap, 2.63 m of")
	print("   tether, beam A at (0,-40), beam B 7.8 m away, floor 4.5 m below.")
	var m := rig2(2.8, 0.10, 1.8, deg_to_rad(6.0), 7.8, 0.0, 4.5)
	for t in 30:
		m.step_tick(m.body_pos, true)
	var p := P.duplicate()
	p["rel"] = 30.0
	var st := leap_begin(m, 0, 1, p)
	var prev: Vector2 = m.body_pos
	var B: Vector2 = m.a_pos[1]
	var guard := 0
	var pumped := 0
	var log := []
	var rel_x := 0.0
	var catch_x := 0.0
	while st["phase"] != "fail" and guard < 1600:
		var f: int = int(st["f"])
		var cg := leap_step(m, st, prev)
		prev = m.body_pos
		m.step_tick(cg[0], cg[1])
		guard += 1
		if st["phase"] == "pump":
			pumped = guard
			continue
		if st["phase"] == "fly" and log.size() > 0 \
				and int(log[log.size() - 1][0]) == f:
			continue                       # the release tick reports f = 0 twice
		if f == 0:
			rel_x = m.body_pos.x
		log.append([f, m.body_pos, m.pos[m.NP - 1], absf(m.a_theta[1]), cg[1],
			m.a_freelen[1], st["phase"] == "hang"])
		if st["phase"] == "hang":
			if catch_x == 0.0:
				catch_x = m.body_pos.x
			if int(st["t"]) - int(st["catch_t"]) > 120:
				break
	print("   pumped for %d ticks (%.1f s), released at %.0f deg with the swing"
		% [pumped, pumped / 60.0, float(st["rel_amp"])])
	print("   peaking at %.0f deg. Stroke starts %d ticks after the hand opens."
		% [float(st["rel_amp"]), int(st["throw_t"])])
	print("    tick  body            tip             gap to B  wrap  hand")
	for row in log:
		var f: int = row[0]
		var show: bool = f % 6 == 0 or f == int(st["throw_t"]) \
			or f == int(st["grip_t"]) or bool(row[6])
		if not show:
			continue
		var tag := ""
		if f == 0:
			tag = "  <- HAND OPENS: the launch"
		elif f == int(st["throw_t"]):
			tag = "  <- the stroke"
		elif f == int(st["grip_t"]):
			tag = "  <- HAND SHUTS: the catch"
		elif bool(row[6]):
			tag = "  <- the wrap takes"
		print("   %4d  (%5.2f,%6.2f)  (%5.2f,%6.2f)  %5.2f    %4.2f  %s%s"
			% [f, (row[1] as Vector2).x, (row[1] as Vector2).y,
			   (row[2] as Vector2).x, (row[2] as Vector2).y,
			   (row[1] as Vector2).distance_to(B), row[3],
			   "SHUT" if row[4] else "open", tag])
		if bool(row[6]):
			break
	print("   result: %s, tether %.2f m, %s, %d ground contacts in the flight."
		% [st["phase"], m.a_freelen[1],
		   "LOCKED (green)" if m.a_locked[1] == 1 else "partial (amber)",
		   int(st["ground_t"])])
	print("   The swing carried the body %.2f m of the 7.8 m gap and the flight"
		% rel_x)
	print("   another %.2f m; the whip covered the remaining %.2f m."
		% [catch_x - rel_x, 7.8 - catch_x])
	print("")
	m.free()

# ---- 2: the release --------------------------------------------------------
func _sec2(pop: Array, P: Dictionary, rels: Array) -> void:
	print("2) THE RELEASE PHASE. Opening the hand is the launch and it cannot be")
	print("   taken back, so the only choice is WHERE on the swing to do it.")
	print("   Release angle is the body's angle about beam A, measured from")
	print("   straight down, on the way up toward the target. L = caught and held")
	print("   a LOCK, p = caught a partial, . = never caught. Gap 7.8 m.")
	var hdr := "   tether "
	for r in rels:
		hdr += "%4.0f" % r
	print(hdr + "   deg    <- the angle rel_for_gap() chooses")
	var by_start := {}
	var order := []
	for e in pop:
		var key := "%d/%.0f" % [e["si"], e["th0"]]
		if not by_start.has(key):
			by_start[key] = {}
			order.append(key)
		by_start[key][float(e["rel"])] = fly(e, P.duplicate(), 7.8, 0.0, 120)
	for key in order:
		var row := ""
		var tether := 0.0
		var d: Dictionary = by_start[key]
		for r in rels:
			if not d.has(float(r)):
				row += "   -"
				continue
			var res: Dictionary = d[float(r)]
			tether = float(res["tether0"])
			row += "   " + ("L" if bool(res["held"]) and int(res["locked"]) == 1
				else ("h" if bool(res["held"]) else
				("p" if bool(res["catch"]) else ".")))
		var si: int = int(key.split("/")[0])
		var th0: float = float(key.split("/")[1])
		var pick: Dictionary = auto_entry(pop, si, th0, 7.8, 0.0)
		print("   %.2f m %s   %2.0f" % [tether, row,
			float(pick["rel"]) if pick.has("rel") else 0.0])
	print("   A tether of 1.5 m cannot make the level's spacing at ANY release")
	print("   angle - which is exactly the claim main.gd makes for the fast line")
	print("   ('a lazy close catch leaves you short'), now measured rather than")
	print("   asserted. From 1.9 m up there is a workable band of release angles;")
	print("   it is widest around 2.4-3.2 m of tether.")
	print("")

# ---- 3: the throw ----------------------------------------------------------
func _sec3(sel: Array, P: Dictionary) -> void:
	print("3) THE THROW. When does the stroke have to start? Here the stroke tick")
	print("   is commanded directly (ticks after the hand opens). 'tip run' is")
	print("   the measured time from the stroke to the tip's closest approach to")
	print("   the target beam, and 'tip miss' how close it got. Gap 7.8 m.")
	print("   stroke at  held  lock  tip run   tip miss")
	for s0m in [0, 4, 7, 9, 11, 13, 15, 19, 25, 35]:
		var p := P.duplicate()
		p["lead"] = 999          # let the floor decide: s0 = s0_min exactly
		p["s0_min"] = s0m
		p["s0_max"] = maxi(s0m, 18)
		var nh := 0
		var nl := 0
		var n := 0
		var wave := 0.0
		var nw := 0
		var miss := 0.0
		for e in sel:
			n += 1
			var r := fly(e, p, 7.8, 0.0, 120)
			if bool(r["held"]): nh += 1
			if int(r["locked"]) == 1: nl += 1
			if int(r["tip_t"]) >= 0 and int(r["throw_t"]) >= 0:
				wave += float(int(r["tip_t"]) - int(r["throw_t"]))
				miss += float(r["tip_min"])
				nw += 1
		print("      %3d     %2d/%2d  %2d    %5.1f     %.2f m"
			% [s0m, nh, n, nl, wave / maxf(nw, 1), miss / maxf(nw, 1)])
	print("   The tip needs 30-40 ticks (0.5-0.65 s) to get from trailing behind")
	print("   the body to the beam, and the whole flight is 60-90 ticks - so the")
	print("   stroke is almost the first thing you do after letting go. It is")
	print("   also the tightest timing in the leap: about +-4 ticks (70 ms).")
	print("   No fixed tick beats the adaptive rule the policy ships: fire %d"
		% int(P["lead"]))
	print("   ticks before the ballistically predicted closest approach, held")
	print("   inside [%d, %d]. That is worth 6-8 of 10 where the best fixed tick"
		% [int(P["s0_min"]), int(P["s0_max"])])
	print("   is worth 5, because each launch gets its own answer - and it is")
	print("   what lets one policy cover more than one gap:")
	print("     gap    stroke fires at tick")
	for gap in [5.0, 7.0, 7.8, 9.5, 11.0]:
		var s0 := 0.0
		var n2 := 0
		for e in sel:
			var r := fly(e, P.duplicate(), gap, 0.0, 1)
			s0 += float(r["throw_t"])
			n2 += 1
		print("    %5.1f      %.1f" % [gap, s0 / maxf(n2, 1)])
	print("")

# ---- 4: the catch ----------------------------------------------------------
func _sec4(sel: Array, P: Dictionary) -> void:
	print("4) THE CATCH IS A TRIGGER. A wrap can only take within GRIP_WINDOW")
	print("   (15 ticks) of the hand SHUTTING. The bot shuts on the wrap reading")
	print("   passing %.1f rad; here that instant is replaced by a fixed tick," % float(P["grip_arm"]))
	print("   offset from it, with re-tries disabled - one shut, one chance.")
	var base := []
	for e in sel:
		base.append([e, fly(e, P.duplicate(), 7.8, 0.0, 120)])
	var n := base.size()
	print("   offset from the bot's own instant   held / %d" % n)
	for d in [-20, -15, -10, -6, -3, 0, 3, 6, 9, 12, 15, 20, 30]:
		var nh := 0
		var tried := 0
		for b in base:
			var r0: Dictionary = b[1]
			if int(r0["grip_t"]) < 0:
				continue
			tried += 1
			var p := P.duplicate()
			p["grip_at"] = maxi(int(r0["grip_t"]) + d, 0)
			p["retries"] = 0
			var r := fly(b[0], p, 7.8, 0.0, 120)
			if bool(r["held"]):
				nh += 1
		print("        %+4d ticks                       %2d / %2d" % [d, nh, tried])
	print("   Controls:")
	var ctl := P.duplicate()
	ctl["grip_at"] = 0
	ctl["retries"] = 0
	var c1 := 0
	for b in base:
		if bool((fly(b[0], ctl, 7.8, 0.0, 120) as Dictionary)["held"]):
			c1 += 1
	print("     hand shut at the launch and HELD there (the button-holder): %d/%d"
		% [c1, n])
	var ctl2 := P.duplicate()
	ctl2["retries"] = 0
	var c2 := 0
	for b in base:
		if bool((fly(b[0], ctl2, 7.8, 0.0, 120) as Dictionary)["held"]):
			c2 += 1
	print("     one shut only, no re-tries, on the wrap reading:             %d/%d"
		% [c2, n])
	var ctl3 := P.duplicate()
	ctl3["s0_min"] = 9999        # the stroke never fires inside the flight
	ctl3["s0_max"] = 9999
	var c3 := 0
	var th3 := 0.0
	for b in base:
		var r := fly(b[0], ctl3, 7.8, 0.0, 120)
		if bool(r["held"]):
			c3 += 1
		th3 = maxf(th3, float(r["max_th"]))
	print("     no stroke at all, just release and fly:                      %d/%d  (best wrap %.2f rad)"
		% [c3, n, th3])
	print("   Read the offsets as the catch's tolerance: roughly -6 to +15 ticks")
	print("   (a 350 ms window), and lopsided - shutting LATE is far cheaper than")
	print("   shutting early, because the wrap keeps winding for a few more ticks")
	print("   after it first qualifies while an early shut spends its 15 ticks on")
	print("   an empty beam. And the two controls are the mechanic in one line:")
	print("   holding the button from the launch catches NOTHING, and one shut")
	print("   with no re-tries is nearly as good as three - it is a trigger, and")
	print("   it only has to be pulled once, at the right moment.")
	print("")

# ---- 5: the envelope -------------------------------------------------------
func _sec5(pop: Array, P: Dictionary, pairs: Array) -> void:
	print("5) THE ENVELOPE. Success = caught the target AND still on it 2 s")
	print("   later AND the body never touched the ground. 10 attempts per cell")
	print("   (5 tethers x 2 swing seeds).")
	var gaps := [5.0, 6.0, 7.0, 7.8, 8.5, 9.5, 11.0]
	print("   held / 10, then the catch tether it leaves you with. The columns")
	print("   under it are the five start tethers (1.5 / 2.0 / 2.4 / 2.6 / 3.2 m),")
	print("   2 attempts each - which is where the interesting result lives.")
	var t_catch := 0
	var t_lock := 0
	var t_held := 0
	var t_lockheld := 0
	for dy in [1.5, 0.75, 0.0, -0.75, -1.5]:
		print("   target beam %+.2f m in height (%s):" % [dy,
			"climbing" if dy > 0.0 else ("level" if dy == 0.0 else "dropping")])
		print("     gap    held  lock  caught  catch tether   1.5 2.0 2.4 2.6 3.2")
		for gap in gaps:
			var nh := 0
			var nl := 0
			var nc := 0
			var n := 0
			var tsum := 0.0
			var per := {}
			for e in _auto_pop(pop, pairs, gap, dy):
				n += 1
				var r := fly(e, P.duplicate(), gap, dy, 120)
				if bool(r["catch"]):
					nc += 1
					t_catch += 1
				if bool(r["held"]):
					nh += 1
					t_held += 1
					tsum += float(r["tether"])
					if int(r["locked"]) == 1:
						t_lockheld += 1
				if int(r["locked"]) == 1:
					nl += 1
					t_lock += 1
				var si: int = e["si"]
				per[si] = int(per.get(si, 0)) + (1 if bool(r["held"]) else 0)
			var pr := ""
			for si in range(5):
				pr += "  %d " % int(per.get(si, 0))
			print("    %5.1f    %2d/%2d  %2d    %2d      %5.2f m       %s"
				% [gap, nh, n, nl, nc, tsum / maxf(nh, 1), pr])
	print("   LOCK OR PARTIAL? Over the whole grid: %d catches, of which %d"
		% [t_catch, t_lock])
	print("   classified LOCKED and %d partial. %d survived the 2 s hold, %d of"
		% [t_catch - t_lock, t_held, t_lockheld])
	print("   them locks - so a partial held %d of the %d times it caught. A leap"
		% [t_held - t_lockheld, t_catch - t_lock])
	print("   that catches at all nearly always catches a LOCK: the throw that")
	print("   reaches a beam 4 m away arrives fast and lays on more than a turn.")
	print("   The failure mode is missing entirely, not catching an amber.")
	print("   Can a higher beam be aimed at harder? Best of aim -0.5/-0.8/-1.1")
	print("   rad, climbing, held out of 10:")
	print("     gap    +0.75 m   +1.50 m")
	for gap in [6.0, 7.0, 7.8]:
		var cells := []
		for dy in [0.75, 1.5]:
			var best := 0
			for aim in [-0.5, -0.8, -1.1]:
				var nh := 0
				for e in _auto_pop(pop, pairs, gap, dy):
					var p := P.duplicate()
					p["aim"] = aim
					if bool((fly(e, p, gap, dy, 120) as Dictionary)["held"]):
						nh += 1
				best = maxi(best, nh)
			cells.append(best)
		print("    %5.1f      %d/10      %d/10" % [gap, cells[0], cells[1]])
	print("")

# ---- 6: the real level -----------------------------------------------------
func _sec6(P: Dictionary) -> void:
	print("6) THE FAST LINE, ON THE REAL LEVEL. Beams 6, 8, 10, 12 at x = 27.2,")
	print("   35.0, 42.8, 50.6, y = -1.5, over a floor at y = 3.0 - and every")
	print("   other beam in the level present, including the recovery beams that")
	print("   sit 3.9 m along and 2.3 m below, directly under the flight path.")
	print("   start hang  leg       swing  stroke  shut  fly  tether  verdict")
	var ok := 0
	var tries := 0
	var legs := 0
	var legs_ok := 0
	var stuck := 0
	for hang in [2.0, 2.4, 2.8, 3.2]:
		for th0 in [4.0, 6.0, 8.0, 11.0]:
			tries += 1
			var res := level_run(6, hang, 1.8, deg_to_rad(th0), P, 3, 120)
			var first := true
			for r in res["legs"]:
				legs += 1
				var v := "held a LOCK" if bool(r["held"]) and int(r["locked"]) == 1 \
					else ("held a partial" if bool(r["held"])
					else ("caught, then betrayed" if int(r["locked"]) >= 0
					else "missed"))
				if bool(r["stuck"]):
					v = "NEVER LAUNCHED - a %.2f m catch cannot be pumped clear of a 4.5 m floor" % float(r["from_tether"])
					stuck += 1
				if bool(r["held"]):
					legs_ok += 1
				if int(r["snagged"]) >= 0:
					v += " (also snagged A%d)" % int(r["snagged"])
				if int(r["scrape"]) > 0:
					v += " [%d scrapes while pumping]" % int(r["scrape"])
				print("   %s  A%d->A%-2d  %3d deg   %3d    %3d  %3d  %5.2f  %s"
					% ["%.1f/%2.0f     " % [hang, th0] if first else "            ",
					   int(r["from"]), int(r["to"]), int(r["amp"]),
					   int(r["throw_t"]), int(r["grip_t"]), int(r["fly"]),
					   float(r["tether"]), v])
				first = false
			if bool(res["ok"]):
				ok += 1
			print("            -> %d of 3 legs, %d ground contacts in flight, %.1f s"
				% [_held_legs(res), int(res["ground"]), int(res["ticks"]) / 60.0])
	print("   legs held: %d of %d.  Full three-leap runs of the fast line: %d of %d."
		% [legs_ok, legs, ok, tries])
	if stuck > 0:
		print("   %d of the failures never launched at all: the previous leap had"
			% stuck)
		print("   caught LONG (3.4 m and over) and a tether that long hangs the")
		print("   body within its own arm's reach of the floor, so the pump drags")
		print("   its feet and the swing never reaches a release angle. A greedy")
		print("   catch is a trap at the far end as well as the near one.")
	print("   A missed leap is not a lost run: the body lands on the lower floor")
	print("   between two RECOVERY beams, which tests/level_probe.gd already shows")
	print("   lock from a standstill. The cost of missing is the height, the")
	print("   tether and the time - which is the level's stated safety contract.")
	print("")

func _auto_pop(pop: Array, pairs: Array, gap: float, dy: float) -> Array:
	var out := []
	for pr in pairs:
		var e := auto_entry(pop, int(pr[0]), float(pr[1]), gap, dy)
		if not e.is_empty():
			out.append(e)
	return out

func _held_legs(res: Dictionary) -> int:
	var n := 0
	for r in res["legs"]:
		if bool(r["held"]):
			n += 1
	return n
