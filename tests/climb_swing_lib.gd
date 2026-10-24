extends RefCounted
## THE SWING BENCH - MOVE 3: hanging LOCKED on beam A, pump, let go, throw at
## beam B, catch it. Beam A's centre is THE ORIGIN of everything this file
## prints; B sits at (dx, dy) in "up" metres (dy > 0 = B ABOVE A). Y IS DOWN
## IN THE SIM, so B's sim position is (dir * dx, -dy).
##
## THE RIG. Two beams and one flat floor FLOOR_DROP m under A (deep on
## purpose: this maps the move in open air; how far under A the floor may sit
## before the pump drags its feet is bot_leap's number, 3.6 m of tether over a
## 4.5 m floor). The chain is wound onto A exactly as tests/bot_leap.gd
## _wind_on does it (HANG metres, 1.8 turns), held 30 ticks, and must read
## a_freelen >= 0 and a_locked == 1 before anything is pumped.
##
## THE PUMP. tests/bot_pump.gd pump_cursor, servoing on the amplitude target
## (flat out for 180). The swing is read the honest way (bot_leap): the TRUE
## body angle about A's centre, and a half-swing's amplitude is its peak |theta|.
## A pump is "at amplitude Amp" on the first forward pass through the bottom
## whose PREVIOUS completed half-swing peaked within +/-AMP_TOL of Amp (for
## 180: the first bottom pass after the body has gone over the top). Every
## tick from 14 before that bottom pass to the forward peak is snapshotted, so
## a release is simply "open the hand at tick k of the window" - every tick is
## a candidate, and the release timing ladder is the same array.
##
## THE FLIGHT is bot_leap.gd's fly phase line for line (hand pointed away from
## B until the stroke, then (body -> B) rotated by `aim`, stroke fired `lead`
## ticks before the ballistic closest approach clamped to [s0_min, s0_max],
## grip on the wrap cue a_theta >= 2.6 with two re-arms), plus noise hooks:
## a per-tick cursor error from tests/hand_noise.gd, a release shift and a
## grip shift in ticks (two-pass rewind for the grip, as skill_probe does it).
## A zero-noise flight is bit-identical to bot_leap's own leap_step (asserted
## by climb_swing_null.gd).
##
## THE CATCH ORACLE: a_freelen[B] >= 0 and a_locked[B] == 1 after 55 ticks
## held with the hand shut. Nothing else is called a catch.
##
## Nothing here enters the tree or writes a save: save_enabled = false, and
## MAIN.new() is never added to a SceneTree, so _ready never runs.
const MAIN := preload("res://main.gd")
const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const HN := preload("res://tests/hand_noise.gd")

const KA := 0
const KB := 1
const FLOOR_DROP := 30.0
const PARK := Vector2(0.0, 900.0)
const AMP_TOL := 7.5
const PRE := 14            # window starts this many ticks before the bottom pass
const HOLD := 55

var m: Node2D
var r := 0.10
var hang := 2.4
var start_ok := false
var start_tether := -1.0
var late_cut := 90         # ticks after the stroke with no grip cue -> give up

func _init(r_: float, hang_ := 2.4, th0_deg := 6.0) -> void:
	r = r_
	hang = hang_
	m = MAIN.new()
	m.external_drive = true
	m.level_id = "lab"
	m.setup_sim()
	m.save_enabled = false
	for nm in ["a_pos", "a_r", "a_jam", "a_name", "a_theta", "a_lockidx",
			"a_freelen", "a_half", "a_pinidx", "a_pinpt", "a_locked", "a_armed",
			"a_pin0", "a_pend", "a_ength", "a_minth", "a_wlo", "a_whi",
			"a_paytick", "a_prun", "a_clear"]:
		var v: Variant = m.get(nm)
		var e: Variant = v.duplicate()
		e.resize(0)
		m.set(nm, e)
	m._add_anchor(Vector2.ZERO, r, 0, "A")
	m._add_anchor(PARK, r, 0, "B")
	m.clear_anchors()
	var ta := PackedVector2Array([Vector2(-80.0, FLOOR_DROP)])
	var tb := PackedVector2Array([Vector2(80.0, FLOOR_DROP)])
	m.t_a = ta
	m.t_b = tb
	m.t_arc_c = PackedVector2Array()
	m.t_arc_r = PackedFloat32Array()
	m.t_arc_ang = PackedVector2Array()
	m._finish_terrain()
	m.goal_x = 999.0
	assert(m.a_pos.size() == 2 and m.t_a.size() == 1)
	LEAP._wind_on(m, KA, hang, 1.8, deg_to_rad(th0_deg))
	for t in 30:
		m.step_tick(m.body_pos, true)
	start_ok = m.a_freelen[KA] >= 0.0 and m.a_locked[KA] == 1
	start_tether = m.a_freelen[KA]

func free_sim() -> void:
	m.free()

static func true_theta(m_: Node2D) -> float:
	# body angle about A's centre, from straight down, + toward +x (y-down)
	return atan2(m_.body_pos.x - m_.a_pos[KA].x, m_.body_pos.y - m_.a_pos[KA].y)

## THE PUMP, IN TWO PASSES. The servo does not hold an arbitrary amplitude
## (climb_swing_peaks.gd: target 90 settles at 77; 120 and 150 wander 75-137;
## flat out goes over the top), so an amplitude CLASS is harvested, not
## commanded: pass 1 pumps at each target in `targets` and logs every forward
## (+x) pass through the bottom with the peak that forward half-swing then
## reaches; the pass nearest the class (within AMP_TOL; for 180, the first
## bottom pass after going over the top) is chosen. Pass 2 re-runs that pump
## from the start - bit-identical, no RNG - and snapshots every tick from PRE
## ticks before that bottom pass to the forward peak.
## Returns {ok, target, amp_fwd, amp_prev, dir, snaps: [{snap, prev, th, v,
## tick, pos}], k0 (index of the bottom pass), pump_t, over, log}
## `never` = the class is unreachable on purpose (instrument null: the window
## must come back empty and ok = false).
func pump_window(amp: float, targets: Array, max_ticks := 2400,
		never := false) -> Dictionary:
	var s0: Dictionary = m.snapshot()
	var best := {}
	var berr := 1e9
	var logs := []
	for tg in targets:
		m.restore(s0)
		var passes := _pump_run(float(tg), max_ticks, -1)
		for ps in passes:
			var fp: float = float(ps["fwd"])
			var err: float
			if amp >= 179.0:
				err = 0.0 if bool(ps["over"]) else 1e9
			else:
				err = absf(fp - amp) if not bool(ps["over"]) else 1e9
			if never:
				err = 1e9
			logs.append("%.0f@%d:%.0f%s" % [tg, int(ps["t"]), fp, "o" if bool(ps["over"]) else ""])
			if err <= AMP_TOL and err < berr - 1e-6:
				berr = err
				best = ps.duplicate()
				best["target"] = float(tg)
		if amp >= 179.0 and not best.is_empty():
			break
	var out := {"ok": false, "snaps": [], "k0": -1, "dir": 1, "amp_prev": 0.0,
		"amp_fwd": 0.0, "pump_t": -1, "over": false, "log": logs}
	if best.is_empty():
		m.restore(s0)
		return out
	m.restore(s0)
	var sn: Array = _pump_run(float(best["target"]), int(best["t"]) + 200,
		int(best["t"]))
	m.restore(s0)
	out["ok"] = sn.size() > PRE
	out["snaps"] = sn
	out["k0"] = PRE
	out["target"] = best["target"]
	out["amp_fwd"] = best["fwd"]
	out["amp_prev"] = best["prev_pk"]
	out["pump_t"] = best["t"]
	out["over"] = best["over"]
	return out

## One pump from the current state at `target` (0 = flat out). grab < 0:
## return the list of forward bottom passes {t, fwd, prev_pk, over}. grab >= 0:
## return the snapshot window around the bottom pass at tick `grab`.
func _pump_run(target: float, max_ticks: int, grab: int) -> Array:
	var prev: Vector2 = m.body_pos
	var pk := 0.0
	var last_pk := 0.0
	var sgn := 0.0
	var th_u := true_theta(m)
	var prev_raw := th_u
	var over := false
	var passes: Array = []
	var open_i := -1
	var snaps: Array = []
	var peak := -999.0
	for t in max_ticks:
		var raw := true_theta(m)
		var d := raw - prev_raw
		if d > PI: d -= TAU
		elif d < -PI: d += TAU
		prev_raw = raw
		th_u += d
		if absf(th_u) > PI:
			over = true
		var thd := rad_to_deg(raw)
		pk = maxf(pk, absf(thd))
		var sg := signf(thd)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0:
				last_pk = pk
				if open_i >= 0:
					passes[open_i]["fwd"] = last_pk
					open_i = -1
				if absf(thd) < 90.0 and d > 0.0 and grab < 0:
					passes.append({"t": t, "fwd": 0.0, "prev_pk": last_pk,
						"over": over})
					open_i = passes.size() - 1
			sgn = sg
			pk = 0.0
		if grab >= 0 and t >= grab - PRE:
			snaps.append({"snap": m.snapshot(), "prev": prev, "th": thd,
				"v": (m.body_pos - prev) * 60.0, "tick": t, "pos": m.body_pos})
			peak = maxf(peak, thd)
			if t > grab + 3 and (thd < peak - 1.0 or thd > 175.0):
				return snaps
		var cur: Vector2 = PUMP.pump_cursor(m, KA, prev, target)
		prev = m.body_pos
		m.step_tick(cur, true)
		if m.a_freelen[KA] < 0.0:
			break
	if grab >= 0:
		return snaps
	# a forward pass that went over the top before swinging back
	if open_i >= 0:
		passes[open_i]["fwd"] = maxf(pk, 180.0 if over else pk)
	for ps in passes:
		if float(ps["fwd"]) >= 179.0:
			ps["over"] = true
	return passes

## The policy knobs a cell searches over (bot_leap names).
static func stroke(aim: float, lead: int, s0_min := 4, s0_max := 40) -> Dictionary:
	var p := LEAP.default_policy()
	p["aim"] = aim
	p["lead"] = lead
	p["s0_min"] = s0_min
	p["s0_max"] = s0_max
	return p

## One attempt. Restores snaps[ki] (the release tick = ki; the hand opens on
## the first step of this call), moves B to (dir*dx, -dy), flies bot_leap's
## throw and holds HOLD ticks. hn: a tests/hand_noise.gd instance or null.
## gshift: extra grip-press shift (the press ladder); the noise's own jitter is
## added. hn_grip supplies the grip jitter (a second, independent draw).
## never_grip: the hand never closes (the must-report-nothing control).
## no_stroke: the hand stays pointed back (the throw never fires).
func attempt(win: Dictionary, ki: int, dx: float, dy: float, p: Dictionary,
		hn: RefCounted = null, hn_grip: RefCounted = null, gshift := 0,
		never_grip := false, no_stroke := false, carry := 0,
		aim_off := Vector2.ZERO, rb := -1.0) -> Dictionary:
	var snaps: Array = win["snaps"]
	var e: Dictionary = snaps[ki]
	m.restore(e["snap"])
	var dir: float = float(win["dir"])
	var B := Vector2(dir * dx, -dy)
	m.a_pos[KB] = B
	if rb > 0.0:
		m.a_r[KB] = rb          # B's radius; A keeps the rig's
	var shift: int = gshift + (int(hn_grip.jit) if hn_grip != null else 0)
	var hs: Dictionary = hn.save_state() if hn != null else {}
	var snap_rel: Dictionary = m.snapshot() if shift != 0 else {}
	var r1 := _fly(e, B, p, hn, -1, never_grip, no_stroke, aim_off)
	if shift != 0 and int(r1["g0"]) >= 0:
		m.restore(snap_rel)
		m.a_pos[KB] = B
		if rb > 0.0:
			m.a_r[KB] = rb
		if hn != null:
			hn.restore_state(hs)
		var r2 := _fly(e, B, p, hn, maxi(0, int(r1["g0"]) + shift), never_grip,
			no_stroke, aim_off)
		r2["g0_cue"] = r1["g0"]
		r1 = r2
	var res := _judge(r1, B, hn, carry)
	return res

## bot_leap.leap_step's "fly" phase, with the noise hooks. press >= 0: the
## FIRST close fires at flight tick `press` (the grip ladder / jitter pass);
## re-arms after that are cue-driven as in bot_leap.
func _fly(e: Dictionary, B: Vector2, p: Dictionary, hn: RefCounted, press: int,
		never_grip: bool, no_stroke: bool, aim_off: Vector2) -> Dictionary:
	var prev: Vector2 = e["prev"]
	# THE LAUNCH: the release tick is this one - body leaves on its tangent
	var v: Vector2 = (m.body_pos - prev) * 60.0
	var tmin := 0
	var dmin := 1e9
	for i in 240:
		var tt: float = float(i) / 60.0
		var q: Vector2 = m.body_pos + v * tt + Vector2(0.0, 0.5 * float(m.GRAV.y) * tt * tt)
		var dd: float = q.distance_to(B)
		if dd < dmin:
			dmin = dd; tmin = i
	var s0: int = clampi(tmin - int(p["lead"]), int(p["s0_min"]), int(p["s0_max"]))
	if hn != null:
		s0 = maxi(int(p["s0_min"]), int(round(float(s0) * float(hn.speed))))
	if no_stroke:
		s0 = 99999
	var u: Vector2 = (B - m.body_pos).normalized()
	var wind: Vector2 = u.rotated(PI + float(p["wind"]))
	var aimv := Vector2.ZERO
	var closed := false
	var closes := 0
	var close_t := -999
	var g0 := -1
	var caught := false
	var f := 0
	var t := 0
	var launch_v := v
	var launch_p: Vector2 = m.body_pos
	var min_d := 1e9
	var apex_y: float = m.body_pos.y
	# tick 0: the hand opens (bot_leap returns the wind cursor, grip false, on
	# the release tick)
	var cur0: Vector2 = m.body_pos + wind * m.REACH
	if hn != null:
		cur0 += hn.tick()
	prev = m.body_pos
	m.step_tick(cur0, false)
	t += 1
	while f < int(p["max_fly"]):
		# leap_step increments t then f; f is the flight tick
		t += 1
		var fi := f
		f += 1
		if fi == s0:
			aimv = (B - m.body_pos).normalized().rotated(float(p["aim"]))
		var dir_v: Vector2
		if fi < s0:
			dir_v = wind
		else:
			dir_v = aimv
		var cur: Vector2 = m.body_pos + dir_v * m.REACH + (aim_off if fi >= s0 else Vector2.ZERO)
		if hn != null:
			cur += hn.tick()
		var grip := closed
		var since: int = t - close_t
		if grip and since > m.GRIP_WINDOW:
			grip = false
			closed = false
		if not grip:
			var want := false
			if press >= 0 and closes == 0:
				want = fi >= press
			else:
				want = absf(m.a_theta[KB]) >= float(p["grip_arm"])
			if never_grip:
				want = false
			if want and closes <= int(p["retries"]) and since > 1:
				grip = true
				closed = true
				close_t = t
				closes += 1
				if g0 < 0:
					g0 = fi
		prev = m.body_pos
		m.step_tick(cur, grip)
		min_d = minf(min_d, m.body_pos.distance_to(B))
		apex_y = minf(apex_y, m.body_pos.y)
		if m.a_freelen[KB] >= 0.0:
			caught = true
			break
		if m.grounded:
			break
		# 90 ticks after the stroke with the wrap cue never once reached, the
		# wave is long gone (the tip runs out in 30-40 ticks, bot_leap sec 3;
		# climb_swing_map logs every catch's tick-after-stroke to keep this
		# honest). An early out for the bench's sake, not a physical claim.
		if closes == 0 and fi > s0 + late_cut:
			break
		# the whip is 5.25 m and the reach 1.15: a beam more than 6.5 m above
		# a FALLING body can no longer be touched. A physical bound, not a guess.
		if m.body_pos.y > B.y + 6.5 and (m.body_pos.y - prev.y) > 0.0:
			break
	return {"caught": caught, "g0": g0, "s0": s0, "f": f, "closes": closes,
		"launch_v": launch_v, "launch_p": launch_p, "min_d": min_d,
		"late": caught and f - s0 > 90,
		"apex_up": -apex_y}

func _judge(r1: Dictionary, B: Vector2, hn: RefCounted, carry: int) -> Dictionary:
	var lock := false
	var tether := -1.0
	var pin := -1
	if bool(r1["caught"]):
		for t in HOLD:
			var c: Vector2 = m.body_pos
			if hn != null:
				c += hn.tick()
			m.step_tick(c, true)
			if m.a_freelen[KB] < 0.0:
				break
		lock = m.a_freelen[KB] >= 0.0 and m.a_locked[KB] == 1
		tether = m.a_freelen[KB]
		pin = m.a_pinidx[KB]
	r1["lock"] = lock
	r1["tether"] = tether
	r1["pin"] = pin
	r1["hash"] = m.state_hash()
	r1["a_hold"] = m.a_freelen[KA]      # must be -1: the hand opened on A
	if lock and carry > 0:
		r1.merge(_carry(B, carry), true)
	return r1

## THE CARRIED SWING. After a lock on B: hold the hand shut with the cursor
## parked on the body (no pumping) for n ticks and read the true swing about
## B: peak |theta| of each completed half-swing, and whether the wrap holds.
func _carry(B: Vector2, n: int) -> Dictionary:
	var pk := 0.0
	var sgn := 0.0
	var peaks: Array = []
	var th_u := atan2(m.body_pos.x - B.x, m.body_pos.y - B.y)
	var prev_raw := th_u
	var over := false
	var held := true
	for t in n:
		m.step_tick(m.body_pos, true)
		if m.a_freelen[KB] < 0.0:
			held = false
			break
		var raw := atan2(m.body_pos.x - B.x, m.body_pos.y - B.y)
		var d := raw - prev_raw
		if d > PI: d -= TAU
		elif d < -PI: d += TAU
		prev_raw = raw
		th_u += d
		if absf(th_u) > PI:
			over = true
		var thd := rad_to_deg(raw)
		pk = maxf(pk, absf(thd))
		var sg := signf(thd)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0:
				peaks.append(pk)
			sgn = sg
			pk = 0.0
	return {"c_peaks": peaks, "c_held": held, "c_over": over,
		"c_tether": m.a_freelen[KB]}
