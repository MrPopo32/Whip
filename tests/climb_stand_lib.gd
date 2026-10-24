extends RefCounted
## THE CLIMB BENCH - one beam over one flat floor, anywhere, thrown for real.
##
## The rig is the lab's floor (x -12..20 at y = 0, walled at both ends) with
## the lab's four stations REMOVED and one ordinary beam (jam 0) put at
## (FEET_X + dx, -dy): dx metres ahead of the feet, dy metres UP from the
## floor the feet stand on. Y IS DOWN IN THE SIM; every number this file
## prints is in "up" metres (dy > 0 = above the floor).
##
## The throw is tests/skill_probe.gd's machinery line for line (stance built
## from the PRISTINE rig every time - skill_cell.gd's lesson - windup 120,
## stroke, optional pull, route_bot's re-arming grip on the wrap cue, 55 held
## ticks after the engage), with two additions a basin sweep needs: a FIXED
## cursor offset added every tick (the aim ladder, in metres) and a press
## shift in ticks (the press ladder), applied through skill_probe's own
## two-pass rewind. Both are zero in the search, and a zero-offset, zero-shift
## throw is bit-identical to skill_probe's (asserted by climb_catch's null).
##
## THE CATCH ORACLE: a_freelen[k] >= 0 and a_locked[k] == 1 after 55 ticks
## with the hand shut. Nothing else is called a catch.
##
## Nothing here enters the tree or writes a save: save_enabled = false, and
## MAIN.new() is never added to a SceneTree, so _ready never runs.
const MAIN := preload("res://main.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")

const FEET_X := 2.0
const K := 0

# THE 108-STROKE GRID. lab_throw's 36 shapes (a0 in {0.85, 1.10} pi, a1 in
# {-0.42, -0.30, -0.18} pi, sd {5, 9, 14}, pull) are a subset. lab_throw's
# 108 is those 36 at three LEADS; here the lead is the cell's own coordinate,
# so the third factor of three is spent where this map needs it: a third
# windup (1.30 pi, hand back and UP) and three more stroke angles (-0.54 pi,
# past vertical; -0.06 and +0.06 pi, flat) because the map moves the target
# over 0.5..6 m of lead and 0.5..4 m of height and lab_throw's a1 range only
# points at 1.6..2.4 m of lead.
const A0S := [0.85, 1.10, 1.30]
const A1S := [-0.54, -0.42, -0.30, -0.18, -0.06, 0.06]
const SDS := [5, 9, 14]

static func grid108() -> Array:
	var g: Array = []
	for a0 in A0S:
		for a1 in A1S:
			for sd in SDS:
				for pull in [false, true]:
					g.append({"a0": PI * float(a0), "a1": PI * float(a1),
						"sd": sd, "pull": pull, "w": 120,
						"ia0": A0S.find(a0), "ia1": A1S.find(a1)})
	return g

# THE FINE GRID: 3x finer on every axis around one stroke - a1 +/- 0.04 pi
# (the coarse step is 0.12 pi), a0 +/- 0.05 pi (coarse 0.15-0.25 pi), sd +/- 2
# (coarse 4-5). 27 strokes including the centre.
static func fine27(c: Dictionary) -> Array:
	var g: Array = []
	for da0 in [-0.05, 0.0, 0.05]:
		for da1 in [-0.04, 0.0, 0.04]:
			for dsd in [-2, 0, 2]:
				var d := c.duplicate()
				d["a0"] = float(c["a0"]) + PI * da0
				d["a1"] = float(c["a1"]) + PI * da1
				d["sd"] = maxi(2, int(c["sd"]) + dsd)
				d["fine"] = [da0, da1, dsd]
				g.append(d)
	return g

static func key_of(c: Dictionary) -> String:
	return "%.5f/%.5f/%d/%s" % [float(c["a0"]), float(c["a1"]), int(c["sd"]),
		str(c["pull"])]

var m: Node2D
var pristine := {}
var stances := {}
var dx := 0.0
var dy := 0.0
var r := 0.11

func _init(dx_: float, dy_: float, r_: float) -> void:
	dx = dx_
	dy = dy_
	r = r_
	m = MAIN.new()
	m.external_drive = true
	m.level_id = "lab"
	m.setup_sim()
	m.save_enabled = false
	# the lab's stations out, ONE beam in. Tables rebuilt and ASSIGNED BACK
	# (a method call through a property mutates a copy - lab_throw strip_floor)
	for nm in ["a_pos", "a_r", "a_jam", "a_name", "a_theta", "a_lockidx",
			"a_freelen", "a_half", "a_pinidx", "a_pinpt", "a_locked", "a_armed",
			"a_pin0", "a_pend", "a_ength", "a_minth", "a_wlo", "a_whi",
			"a_paytick", "a_prun", "a_clear"]:
		var v: Variant = m.get(nm)
		var e: Variant = v.duplicate()
		e.resize(0)
		m.set(nm, e)
	m._add_anchor(Vector2(FEET_X + dx, -dy), r, 0, "T")
	m.clear_anchors()
	assert(m.a_pos.size() == 1 and m.a_r.size() == 1 and m.a_jam[0] == 0)
	pristine = m.snapshot()

func free_sim() -> void:
	m.free()

func stance(a0: float) -> void:
	var key := "%.5f" % a0
	if not stances.has(key):
		m.restore(pristine)
		m.teleport(Vector2(FEET_X, -m.BODY_R))
		for t in 90:
			m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
		stances[key] = m.snapshot()
	m.restore(stances[key])

## THE WINDUP, CACHED (noise-free only). For t < w the aim depends on a0
## alone and the hand is open, so every noise-free stroke sharing a0 runs the
## SAME 90 + 120 ticks. They are run once and snapshotted at t = w; a stroke
## then resumes there. Valid only if the grip never fired during the windup
## (a beam the resting whip already wraps) - checked, and if it did the fast
## path refuses and the caller runs the full throw. climb_catch asserts the
## two paths give one hash.
var wstates := {}
func windup_state(a0: float) -> Dictionary:
	var key := "%.5f" % a0
	if not wstates.has(key):
		stance(a0)
		var ok := true
		for t in 120:
			if absf(float(m.a_theta[K])) >= 2.6 or float(m.a_freelen[K]) >= 0.0:
				ok = false
			m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
		wstates[key] = m.snapshot() if ok else {}
	return wstates[key]

func throw_fast(c: Dictionary, off := Vector2.ZERO, dpress := 0) -> Dictionary:
	var ws := windup_state(float(c["a0"]))
	if ws.is_empty():
		return throw(c, HN.new("null", "fast", 0), off, dpress)
	m.restore(ws)
	var rr := _pass(c, HN.new("null", "fast", 0), int(c["w"]), -2, off,
		false, false)
	if dpress != 0 and int(rr["g0"]) >= 0:
		# the press ladder: same stroke, the FIRST close moved by dpress ticks
		# (clamped to the end of the windup, as skill_probe clamps its jitter)
		var g0: int = int(rr["g0"])
		m.restore(ws)
		rr = _pass(c, HN.new("null", "fast", 0), int(c["w"]),
			maxi(int(c["w"]), g0 + dpress), off, false, false)
		rr["g0"] = g0
	rr.erase("snap_w")
	rr.erase("hn_w")
	return rr

func aim(t: int, c: Dictionary, s: float) -> Array:
	var w := int(c["w"])
	if t < w:
		return [float(c["a0"]), 1.0]
	var te := float(t - w) / s
	if te < float(c["sd"]):
		return [float(c["a1"]), 1.0]
	if bool(c["pull"]) and te < float(c["sd"]) + 10.0:
		return [float(c["a0"]), 0.7]
	return [float(c["a1"]), 1.0]

## One throw from the restored stance. off = a fixed cursor offset (m) added
## every tick of the stroke; dpress = shift of the FIRST press, ticks (the press
## ladder); the hand noise's own jitter is added to it. never_grip = the hand
## never closes (the instrument's must-report-nothing control).
func throw(c: Dictionary, hn: RefCounted, off := Vector2.ZERO, dpress := 0,
		never_grip := false, hold_open := false) -> Dictionary:
	stance(float(c["a0"]))
	var w := int(c["w"])
	var shift: int = int(hn.jit) + dpress
	need_snap = shift != 0
	var rr := _pass(c, hn, w, -1, off, never_grip, hold_open)
	if shift != 0 and int(rr["g0"]) >= 0 and not (rr["snap_w"] as Dictionary).is_empty():
		m.restore(rr["snap_w"])
		hn.restore_state(rr["hn_w"])
		var r2 := _pass(c, hn, w, maxi(w, int(rr["g0"]) + shift), off,
			never_grip, hold_open)
		r2["g0"] = rr["g0"]
		r2.erase("snap_w")
		r2.erase("hn_w")
		return r2
	rr.erase("snap_w")
	rr.erase("hn_w")
	return rr

var need_snap := true
func _pass(c: Dictionary, hn: RefCounted, w: int, press: int, off: Vector2,
		never_grip: bool, hold_open: bool) -> Dictionary:
	var grip := false
	var closes := 0
	var g0 := -1
	var caught := false
	var et := -1
	var out := {"snap_w": {}, "hn_w": {}}
	var t0 := 0
	if press >= 0 or press == -2:
		t0 = w
	for t in range(t0, w + 130):
		if t == w and press == -1 and need_snap:
			out["snap_w"] = m.snapshot()
			out["hn_w"] = hn.save_state()
		var av := aim(t, c, hn.speed)
		var o := off if t >= w else Vector2.ZERO
		var tgt: Vector2 = m.body_pos + Vector2(cos(float(av[0])),
			sin(float(av[0]))) * m.REACH * float(av[1]) + hn.tick() + o
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[K]) < 0.0:
			grip = false
		var fire := false
		if press >= 0 and closes == 0:
			fire = t >= press
		else:
			fire = absf(float(m.a_theta[K])) >= 2.6
		if never_grip:
			fire = false
		if not grip and fire and closes < 4 and float(m.a_freelen[K]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
		if float(m.a_freelen[K]) >= 0.0:
			caught = true
			et = t
			break
	var lock := false
	if caught:
		for t in 55:
			m.step_tick(m.body_pos, not hold_open)
			if float(m.a_freelen[K]) < 0.0:
				break
		lock = float(m.a_freelen[K]) >= 0.0 and int(m.a_locked[K]) == 1
	out["caught"] = caught
	out["lock"] = lock
	out["et"] = et
	out["g0"] = g0
	out["hash"] = m.state_hash()
	out["feet_x"] = m.body_pos.x
	out["body_up"] = -m.body_pos.y - m.BODY_R      # feet height over the floor
	out["tether"] = float(m.a_freelen[K])
	out["grounded"] = bool(m.grounded)
	return out

## After a LOCKED throw (state is left as _pass left it): pump flat out with
## bot_pump's servo for n ticks. Returns the true swing about the beam.
## policy "full": bot_pump.pump_cursor verbatim, flat out.
## policy "short": the same servo with its LENGTHEN half clipped off - the
##   radial command may pull the body up the arm (short pendulum) but never
##   push it out past the parked arm, so a low beam's body is not driven into
##   the floor. The tangential starter is kept.
## policy "park": the cursor parked on the body, hand shut - the control.
func pump_after(n: int, target_deg := 0.0, policy := "full") -> Dictionary:
	var prev: Vector2 = m.body_pos
	var piv: Vector2 = m.a_pos[K]
	var amp := 0.0
	var ground := 0
	var peak_vt := 0.0
	var lost := -1
	var th_u := atan2(m.body_pos.x - piv.x, m.body_pos.y - piv.y)
	var prev_raw := th_u
	var over := -1
	var foot_min := 99.0
	var foot_max := -99.0
	var amp_late := 0.0
	var th_lo := 999.0
	var th_hi := -999.0
	var air := 0
	var vt_late := 0.0
	var t90 := -1
	for t in n:
		var cur: Vector2 = PUMP.pump_cursor(m, K, prev, target_deg)
		if policy == "park":
			cur = m.body_pos
		elif policy == "short":
			var st: Dictionary = PUMP.swing_state(m, K, prev)
			var rh: Vector2 = st["rhat"]
			var u: Vector2 = (cur - m.body_pos) / m.REACH
			var ur := u.dot(rh)
			if ur < 0.0:
				u -= rh * ur
			cur = m.body_pos + u * m.REACH
		var pb: Vector2 = m.body_pos
		m.step_tick(cur, true)
		prev = pb
		if float(m.a_freelen[K]) < 0.0:
			lost = t
			break
		var raw := atan2(m.body_pos.x - piv.x, m.body_pos.y - piv.y)
		var d := raw - prev_raw
		if d > PI: d -= TAU
		elif d < -PI: d += TAU
		prev_raw = raw
		th_u += d
		if absf(th_u) > PI and over < 0:
			over = t
		amp = maxf(amp, absf(rad_to_deg(raw)))
		if t90 < 0 and absf(rad_to_deg(raw)) >= 90.0:
			t90 = t
		if t >= n - 180:
			amp_late = maxf(amp_late, absf(rad_to_deg(raw)))
			th_lo = minf(th_lo, rad_to_deg(raw))
			th_hi = maxf(th_hi, rad_to_deg(raw))
		if m.grounded:
			ground += 1
		var v: Vector2 = (m.body_pos - pb) * 60.0
		var rv: Vector2 = m.body_pos - piv
		var vt := absf((rv.x * v.y - rv.y * v.x) / maxf(rv.length(), 0.05))
		peak_vt = maxf(peak_vt, vt)
		if t >= n - 180:
			vt_late = maxf(vt_late, vt)
		if not m.grounded and -m.body_pos.y - m.BODY_R > 0.02:
			air += 1
		var fu: float = -m.body_pos.y - m.BODY_R
		foot_min = minf(foot_min, fu)
		foot_max = maxf(foot_max, fu)
	# swing = HALF the peak-to-peak body angle over the last 3 s: a body
	# lying still on the floor off to one side of the beam has a large |theta|
	# and zero swing, and only this number tells the two apart
	return {"amp": amp, "amp_late": amp_late, "ground": ground, "n": n,
		"swing": (th_hi - th_lo) * 0.5 if th_hi > th_lo else 0.0,
		"th_lo": th_lo, "th_hi": th_hi, "t90": t90, "air": air, "vt_late": vt_late,
		"lost": lost, "over": over, "peak_vt": peak_vt, "foot_min": foot_min,
		"foot_max": foot_max, "tether": float(m.a_freelen[K]),
		"locked": int(m.a_locked[K])}
