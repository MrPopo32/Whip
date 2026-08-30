extends SceneTree
## THE PUMP - a reusable pumping policy for a body hanging on a locked wrap,
## plus the bench that measures it.
##
## WHY A PUMP AND NOT A HAUL. The arm force is an INTERNAL pair: it is applied
## to the handle and its reaction to the body. Pointing the hand AT the anchor
## therefore pushes the body AWAY from it (measured below, "sign check"), which
## is why a naive haul bot produces zero net motion. What the pair CAN do is
## exert a torque about the anchor, because its two ends sit at different radii:
## torque = f x (r_handle - r_body). That is the whole locomotion budget, and
## the way to spend it is to change the pendulum's LENGTH in phase with the
## swing.
##
## THE MECHANISM. The body rides on the arm below the handle. With the cursor
## parked on the body the arm sits ~0.24 m long (the spring carries the body's
## 80 N at SPRING_K = 340 N/m); with the cursor pushed to the far side of the
## reach circle the arm force saturates at F_MAX = 320 N and hauls the body up
## to the handle; with the cursor pulled toward the anchor the body is pushed
## out to ARM_MAX = 1.30 m. So the hand commands a pendulum radius anywhere in
## R+0.05 .. R+1.30 - a ~1.25 m stroke on a 1-4 m pendulum, i.e. a 30-120%
## length modulation. Shorten at the bottom of the swing, lengthen at the ends:
## a swing-rider's parametric pump, driven at 2x the swing frequency.
##
## THE POLICY (self-contained; no state beyond one tick of body position):
##
##   static func pump_cursor(m: Node2D, k: int, prev_body: Vector2,
##                           target_deg := 0.0, lead := 1.2,
##                           starter := true) -> Vector2
##
##     m          main.gd instance running with external_drive = true
##     k          index of the anchor you are hanging on (a_freelen[k] >= 0)
##     prev_body  m.body_pos as of the PREVIOUS tick (pass m.body_pos on tick 0)
##     target_deg swing amplitude to servo to, in degrees. <= 0 = pump flat out.
##                Over the target the drive backs off and flips to the braking
##                phase. Most of the servo's authority is the gain falling to
##                zero, not the brake: the anti-phase drive does damp a small
##                swing (table 3, lead 0.0) but at 90 deg it is inconsistent
##                and sometimes no better than simply stopping (table 6).
##     lead       phase lead, radians. 1.2 is the measured optimum; the pumping
##                band is 0.6-1.6 and lead 0.0 (== PI) is the brake (table 3).
##     starter    below 14 deg of swing, blend in a 1f tangential kick. The
##                parametric law grows an existing swing exponentially but
##                cannot seed one; the kick grows a dead hang linearly.
##     returns    a cursor position in WORLD METRES for m.step_tick(cursor,
##                true). The grip must stay closed the whole time.
##
##   Usage:
##     const PUMP := preload("res://tests/bot_pump.gd")
##     var prev := m.body_pos
##     for t in 600:
##         var cur: Vector2 = PUMP.pump_cursor(m, k, prev, 60.0)
##         prev = m.body_pos
##         m.step_tick(cur, true)
##
##   swing_state(m, k, prev_body) -> Dictionary is exported too, for bots that
##   want the swing phase for their own release timing:
##     {pivot, radius, rhat, that, theta, omega, w0, phase, amp}
##   theta is the body angle from straight down (+ = +x side); phase runs 0 at a
##   swing end to +-PI/2 at the bottom; amp is the amplitude the swing would
##   have at the un-pumped radius, from the angle and the TANGENTIAL speed only
##   (so hauling the body up the arm does not read as swing), PI if circulating.

const LEAD_DEFAULT := 1.2     # measured optimum; 0.8-1.2 is the pumping band
const LEAD_BRAKE := 0.0       # the anti-phase: damps a small swing, unreliable
                              # as a brake once the swing is near 90 deg
const ARM_HANG := 0.24        # m: arm length with the cursor parked on the body

# ------------------------------------------------------------- the policy --

static func swing_state(m: Node2D, k: int, prev_body: Vector2) -> Dictionary:
	var pivot: Vector2 = m.a_pinpt[k] if m.a_pinidx[k] >= 0 else m.a_pos[k]
	var r: Vector2 = m.body_pos - pivot
	var rad: float = maxf(r.length(), 0.05)
	var rhat: Vector2 = r / rad
	var that_ := Vector2(-rhat.y, rhat.x)      # +that = increasing theta
	var theta: float = atan2(r.x, r.y)
	var v: Vector2 = (m.body_pos - prev_body) * 60.0
	var omega: float = (r.y * v.x - r.x * v.y) / (rad * rad)
	var g: float = absf(m.GRAV.y)
	var w0: float = sqrt(g / rad)
	# Amplitude from swing energy, referred to the UN-PUMPED radius r0: the
	# pendulum's own cos(A) = cos(theta) - v_t^2 / (2 g r0). Only the TANGENTIAL
	# speed counts - radial speed is the arm working, not swing, and folding it
	# in made the servo read a straight haul as a 90 degree swing.
	var r0: float = maxf(m.a_freelen[k], 0.05) + ARM_HANG
	var vt: float = omega * rad
	var ca: float = cos(theta) - vt * vt / (2.0 * g * r0)
	return {
		"pivot": pivot, "radius": rad, "rhat": rhat, "that": that_,
		"theta": theta, "omega": omega, "w0": w0,
		"phase": atan2(-omega / w0, theta),
		"amp": PI if ca <= -1.0 else acos(clampf(ca, -1.0, 1.0)),
	}

static func pump_cursor(m: Node2D, k: int, prev_body: Vector2,
		target_deg := 0.0, lead := LEAD_DEFAULT, starter := true) -> Vector2:
	if k < 0 or k >= m.a_pos.size() or m.a_freelen[k] < 0.0:
		return m.body_pos                       # not hanging on anything
	var s := swing_state(m, k, prev_body)
	var amp: float = s["amp"]
	var phase: float = s["phase"]
	var gain := 1.0
	var ph_lead := lead
	if target_deg > 0.0:
		# proportional over a full-scale band: at the target the drive is zero,
		# so the last approach is gentle. A narrow band plus a 320 N arm
		# overshot a 30 degree target into a full rotation.
		var err: float = deg_to_rad(target_deg) - amp
		gain = clampf(absf(err) / deg_to_rad(target_deg), 0.0, 1.0)
		if err < 0.0:
			ph_lead = LEAD_BRAKE                # over the target: shed swing
	# RADIAL, at 2x the swing frequency. +1 = cursor AWAY from the beam = the
	# arm force saturates and hauls the body up to the handle = SHORT pendulum;
	# -1 = cursor toward the beam = the body is pushed out to ARM_MAX = LONG.
	# With lead = 1.2 the "short" command peaks just after each pass through the
	# bottom: the lag is the time the 320 N arm needs to move 8 kg a metre.
	var u: Vector2 = Vector2(s["rhat"]) * (gain * cos(2.0 * (phase + ph_lead)))
	# TANGENTIAL, at 1x, only while the swing is too small to have a phase worth
	# locking to. This is the seed, not the pump: left running at large
	# amplitude the same term stops being a pump and becomes a crank (table 11).
	if starter:
		var w := clampf((deg_to_rad(14.0) - amp) / deg_to_rad(14.0), 0.0, 1.0)
		if w > 0.0:
			u += Vector2(s["that"]) * (gain * w * 0.9 * -sin(phase))
	return m.body_pos + u.limit_length(1.0) * m.REACH

# --------------------------------------------------------------- the bench --

# A hanging rig: an isolated beam in open air (or over a floor), the chain
# wound `turns` onto it, the whole assembly tilted `th0` from vertical so the
# run starts as a clean free swing of known amplitude.
static func rig(hang: float, r: float, turns: float, th0: float,
		floor_drop := -1.0) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for kk in range(1, m.a_pos.size()):
		m.a_pos[kk] = Vector2(0.0, 900.0)         # park the rest of the level
	m.a_pos[0] = Vector2(0.0, -40.0)
	m.a_r[0] = r
	if floor_drop > 0.0:
		# one flat floor `floor_drop` metres under the beam, wound so its
		# outward normal points up (air side), as _build_level requires
		var fy: float = -40.0 + floor_drop
		m.t_a.append(Vector2(-30.0, fy)); m.t_b.append(Vector2(30.0, fy))
		m.t_n.append(Vector2(0.0, -1.0))
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.04
	var d := Vector2(sin(th0), cos(th0))          # y-down: th0 = 0 is straight down
	var a_start: float = d.angle()
	var rise: float = hang - rr
	var wl: float = turns * TAU * rr
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + d * (hang - s)
		elif s < rise + wl:
			var a: float = a_start + (s - rise) / rr
			p = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = a_start + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			p = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, s - rise - wl)
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + d * (hang + 0.6)
	m.body_prv = m.body_pos
	return m

# hang, beam radius, turns -> a wrap that classifies LOCKED at that length
const RIGS := [
	[1.2, 0.10, 1.3], [2.0, 0.10, 1.3], [2.8, 0.10, 1.8], [3.6, 0.10, 1.8],
]

# Everything reported is the TRUE body angle about the beam, never the policy's
# internal estimate: amplitude at tick t = max |theta| over the swing period
# ending at t. That is well defined whether the body is swinging or circulating.
class Track:
	var th: Array = []          # true body angle, degrees, one per tick
	var th_u := 0.0             # unwrapped, for detecting a full rotation
	var prev_raw := 0.0
	var over := -1              # tick the body first went over the top
	var peak_v := 0.0
	var peak_vt := 0.0          # tangential (= launchable) body speed
	var max_cur := 0.0
	var lost := -1              # tick the wrap let go
	var period := 1.0           # seconds

	func start(m: Node2D) -> void:
		prev_raw = atan2(m.body_pos.x - m.a_pos[0].x, m.body_pos.y - m.a_pos[0].y)
		th_u = prev_raw

	func feed(m: Node2D, t: int, prev_body: Vector2, s: Dictionary) -> void:
		var raw: float = atan2(m.body_pos.x - m.a_pos[0].x,
			m.body_pos.y - m.a_pos[0].y)
		var d := raw - prev_raw
		if d > PI: d -= TAU
		elif d < -PI: d += TAU
		prev_raw = raw
		th_u += d
		if absf(th_u) > PI and over < 0:
			over = t
		peak_v = maxf(peak_v, (m.body_pos - prev_body).length() * 60.0)
		peak_vt = maxf(peak_vt, absf(float(s["omega"]) * float(s["radius"])))
		th.append(rad_to_deg(raw))

	func amp(t: int) -> float:
		# amplitude = max |theta| over the swing period ending at tick t
		if th.is_empty():
			return NAN
		var lo: int = maxi(t - int(period * 60.0), 0)
		var hi: int = mini(t, th.size() - 1)
		if hi <= lo:
			return NAN
		var a := 0.0
		for i in range(lo, hi + 1):
			a = maxf(a, absf(th[i]))
		return a

	func first_at(deg: float) -> int:
		for i in th.size():
			if absf(th[i]) >= deg:
				return i
		return -1

	func rate(lo: float, hi: float) -> float:
		# degrees of amplitude gained per swing CYCLE, from the time the swing
		# takes to climb from lo to hi
		var a := first_at(lo)
		var b := first_at(hi)
		if a < 0 or b < 0 or b <= a:
			return NAN
		return (hi - lo) / maxf(float(b - a) / 60.0 / period, 0.001)

	func decay(t0: int, t1: int) -> float:
		var a0 := amp(t0)
		var a1 := amp(t1)
		if is_nan(a0) or is_nan(a1):
			return NAN
		return (a1 - a0) / maxf(float(t1 - t0) / 60.0 / period, 0.001)

func _mk(cfg: Array, a0_deg: float, floor_drop: float) -> Node2D:
	var m: Node2D = rig(cfg[0], cfg[1], cfg[2], deg_to_rad(a0_deg), floor_drop)
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free(); return null
	return m

# Run one bench: settle, coast (free swing), then pump.
#  drive       < 1.0 replaces pump_cursor with a raw radial drive of that
#              fraction of the reach circle (no servo, no starter)
#  tangential  > 0 replaces it with a 1f tangential drive (the crank)
#  open_loop   > 0 drives the radial term OPEN LOOP at 2x the theoretical
#              frequency with a fixed phase offset = `lead`
#  slew        > 0 caps how fast the cursor may move RELATIVE TO THE BODY, in
#              m/s - the camera tracks the body, so that is the hand speed a
#              player actually has to produce (1 m = 60 screen px)
func bench(cfg: Array, ticks: int, target := 0.0, lead := LEAD_DEFAULT,
		a0_deg := 8.0, coast_ticks := 120, floor_drop := -1.0,
		drive := 1.0, tangential := 0.0, starter := true,
		open_loop := 0.0, slew := 0.0) -> Dictionary:
	var m := _mk(cfg, a0_deg, floor_drop)
	if m == null:
		return {}
	var out := {"tether": m.a_freelen[0], "pin": m.a_pinidx[0],
		"locked": m.a_locked[0]}
	var t_th: float = TAU * sqrt((float(m.a_freelen[0]) + ARM_HANG) / 10.0)
	var co := Track.new()
	co.period = t_th
	co.start(m)
	var prev_body: Vector2 = m.body_pos
	var zc: Array = []
	var prev_th := 0.0
	for t in coast_ticks:
		var sc := swing_state(m, 0, prev_body)
		prev_body = m.body_pos
		m.step_tick(m.body_pos, true)          # cursor parked: no pump input
		co.feed(m, t, prev_body, sc)
		var thv: float = sc["theta"]
		if t > 0 and (prev_th <= 0.0) != (thv <= 0.0):
			zc.append(t)
		prev_th = thv
	out["coast"] = co
	out["t_theory"] = t_th
	out["t_meas"] = (float(zc[zc.size() - 1] - zc[0]) / float(maxi(zc.size() - 1, 1))
		* 2.0 / 60.0) if zc.size() >= 3 else NAN
	var pu := Track.new()
	pu.period = t_th
	pu.start(m)
	var prev_cur: Vector2 = m.body_pos
	for t in ticks:
		var s := swing_state(m, 0, prev_body)
		var cur: Vector2
		if tangential != 0.0:
			cur = m.body_pos + Vector2(s["that"]) * (tangential * m.REACH
				* cos(float(s["phase"]) + lead))
		elif open_loop > 0.0:
			cur = m.body_pos + Vector2(s["rhat"]) * (open_loop * m.REACH
				* cos(2.0 * TAU * float(t) / 60.0 / t_th + lead))
		elif drive != 1.0:
			cur = m.body_pos + Vector2(s["rhat"]) * (drive * m.REACH
				* cos(2.0 * (float(s["phase"]) + lead)))
		else:
			cur = pump_cursor(m, 0, prev_body, target, lead, starter)
		# hand speed = cursor motion relative to the body, because the camera
		# rides the body: on screen only that difference is hand movement
		var rel: Vector2 = (cur - m.body_pos) - (prev_cur - prev_body)
		if slew > 0.0 and rel.length() > slew / 60.0:
			cur = m.body_pos + (prev_cur - prev_body) + rel.normalized() * slew / 60.0
			rel = (cur - m.body_pos) - (prev_cur - prev_body)
		pu.max_cur = maxf(pu.max_cur, rel.length() * 60.0)
		prev_cur = cur
		prev_body = m.body_pos
		m.step_tick(cur, true)
		if m.a_freelen[0] < 0.0:
			pu.lost = t
			break
		pu.feed(m, t, prev_body, s)
	out["pump"] = pu
	out["final_r"] = (m.body_pos - m.a_pos[0]).length()
	m.free()
	return out

# Servo to a SETTLED `upto`-degree swing, then drive the given lead for
# `brake_ticks` and see what the swing is worth afterwards. lead < 0 means
# "park the cursor on the body" - the do-nothing control.
# Returns [a0, a1, deg per cycle, lost].
func brake_bench(cfg: Array, upto: float, lead: float, brake_ticks: int) -> Array:
	var m := _mk(cfg, 8.0, -1.0)
	if m == null:
		return []
	var t_th: float = TAU * sqrt((float(m.a_freelen[0]) + ARM_HANG) / 10.0)
	var prev_body: Vector2 = m.body_pos
	var tr := Track.new()
	tr.period = t_th
	tr.start(m)
	var t := 0
	for i in 600:                    # 10 s of servo: arrive at `upto` and settle
		var cur: Vector2 = pump_cursor(m, 0, prev_body, upto, LEAD_DEFAULT, true)
		prev_body = m.body_pos
		m.step_tick(cur, true)
		if m.a_freelen[0] < 0.0:
			m.free(); return []
		tr.feed(m, t, prev_body, swing_state(m, 0, prev_body))
		t += 1
	var a0: float = tr.amp(t - 1)
	var lost := false
	for i in brake_ticks:
		var s := swing_state(m, 0, prev_body)
		var cur: Vector2 = m.body_pos
		if lead >= 0.0:
			cur += Vector2(s["rhat"]) * (m.REACH
				* cos(2.0 * (float(s["phase"]) + lead)))
		prev_body = m.body_pos
		m.step_tick(cur, true)
		if m.a_freelen[0] < 0.0:
			lost = true
			break
		tr.feed(m, t, prev_body, s)
		t += 1
	var a1: float = tr.amp(t - 1)
	var cycles: float = float(brake_ticks) / 60.0 / t_th
	m.free()
	return [a0, a1, (a1 - a0) / cycles, lost]

func _sign_check() -> void:
	# Which way does the hand move the body? Hold the cursor at a fixed offset
	# and watch the anchor->body radius. This is the fact the haul bot missed.
	print("sign check: hold the cursor still and watch the pendulum radius")
	for dir in [1.0, -1.0]:
		var m: Node2D = rig(2.0, 0.10, 1.3, 0.0)
		for t in 30:
			m.step_tick(m.body_pos, true)
		var r0: float = (m.body_pos - m.a_pos[0]).length()
		for t in 60:
			var rh: Vector2 = (m.body_pos - m.a_pos[0]).normalized()
			m.step_tick(m.body_pos + rh * dir * m.REACH, true)
		var r1: float = (m.body_pos - m.a_pos[0]).length()
		print("   cursor %-18s  radius %.2f -> %.2f m  = %s"
			% ["AWAY from beam" if dir > 0.0 else "TOWARD beam", r0, r1,
			   "SHORTER" if r1 < r0 else "LONGER"])
		m.free()
	print("   -> pointing the hand AT the beam pushes the body AWAY from it.")
	print("      The hand is a length lever, not a winch.")
	print("")

func _f(v: float, w := 6, d := 1) -> String:
	if is_nan(v):
		return "%*s" % [w, "-"]
	return "%*.*f" % [w, d, v]

func _lost(tr: Track) -> String:
	return "" if tr.lost < 0 else "  WRAP LOST at %.1f s" % (tr.lost / 60.0)

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("THE PUMP - can a body on a locked wrap grow its own swing?")
	print("All amplitudes are the TRUE body angle about the beam: max |theta|")
	print("over the swing period ending at that moment. 180 = over the top.")
	print("")
	_sign_check()

	print("1) THE PENDULUM: free period vs T = 2*pi*sqrt((R+arm)/g), arm = 0.24 m")
	print("   R(m)  pin lk  T_meas  T_theory   err     free decay / cycle   A over 15 s")
	for cfg in RIGS:
		var b := bench(cfg, 0, 0.0, LEAD_DEFAULT, 10.0, 900)
		if b.is_empty():
			print("   (no locked rig for hang %.1f)" % cfg[0]); continue
		var co: Track = b["coast"]
		print("   %.2f  %2d  %2d  %s  %s  %+5.1f%%   %s deg      %.1f -> %.1f"
			% [b["tether"], b["pin"], b["locked"], _f(b["t_meas"], 6, 3),
			   _f(b["t_theory"], 6, 3),
			   100.0 * (float(b["t_meas"]) - float(b["t_theory"])) / float(b["t_theory"]),
			   _f(co.decay(150, 890), 6, 2), co.amp(150), co.amp(890)])
	print("")

	print("2) THE PUMP: 10 s at full drive from an 8 deg swing, no amplitude cap")
	print("   R(m)   A0    A@2s   A@5s   A@10s  deg/cyc  ->45deg ->90deg ->over  peak vt  cursor")
	for cfg in RIGS:
		var b := bench(cfg, 600, 0.0, LEAD_DEFAULT, 8.0, 120)
		if b.is_empty(): continue
		var co: Track = b["coast"]
		var pu: Track = b["pump"]
		print("   %.2f %s %s %s %s %s  %6s %6s %6s %5.1f m/s %5.0f m/s%s"
			% [b["tether"], _f(co.amp(119), 6), _f(pu.amp(120), 6), _f(pu.amp(300), 6),
			   _f(pu.amp(600), 6), _f(pu.rate(10.0, 90.0), 7),
			   ("%.1fs" % (pu.first_at(45.0) / 60.0)) if pu.first_at(45.0) >= 0 else "-",
			   ("%.1fs" % (pu.first_at(90.0) / 60.0)) if pu.first_at(90.0) >= 0 else "-",
			   ("%.1fs" % (pu.over / 60.0)) if pu.over >= 0 else "-",
			   pu.peak_vt, pu.max_cur, _lost(pu)])
	print("   A0 = amplitude after a 2 s un-pumped coast. deg/cyc is measured over")
	print("   the 10->90 deg climb. 'over' = the swing became a full rotation.")
	print("   peak vt = peak tangential body speed, i.e. what a release converts")
	print("   into flight. cursor = fastest the hand ever has to move relative")
	print("   to the body, which is what the player sees on screen (60 px/m).")
	print("")

	var leads := [0.0, 0.4, 0.8, 1.0, 1.2, 1.6, 2.0, 2.4, 2.8]
	print("3) IS IT RESONANCE? Weak drive (30%% of the reach circle, radial only,")
	print("   no servo, no starter), phase lead swept over its full period (PI).")
	print("   A real parametric pump is phase-selective: the wrong lead must")
	print("   FAIL. Amplitude in degrees after 10 s, from an 8 deg start:")
	var hdr := "   lead:   "
	for l in leads:
		hdr += "%5.1f" % l
	print(hdr)
	for cfg in RIGS:
		var row := ""
		var rlab := ""
		for l in leads:
			var b := bench(cfg, 600, 0.0, l, 8.0, 30, -1.0, 0.30, 0.0, false)
			if b.is_empty(): continue
			rlab = "   R %.2f " % b["tether"]
			var pu: Track = b["pump"]
			row += _f(pu.amp(mini(599, pu.th.size() - 1)), 5, 0)
		print(rlab + row)
	print("")

	print("4) OPEN LOOP vs PHASE LOCK. The brief's starting guess was to drive")
	print("   at a fixed frequency derived from the tether, 2/T. That is table")
	print("   3's law with the phase taken from a clock instead of from the")
	print("   body. Same 30%% drive, phase offset swept. Amplitude after 10 s:")
	hdr = "   phase:  "
	for l in leads:
		hdr += "%5.1f" % l
	print(hdr)
	for cfg in RIGS:
		var row := ""
		var rlab := ""
		for l in leads:
			var b := bench(cfg, 600, 0.0, l, 8.0, 30, -1.0, 1.0, 0.0, false, 0.30)
			if b.is_empty(): continue
			rlab = "   R %.2f " % b["tether"]
			var pu: Track = b["pump"]
			row += _f(pu.amp(mini(599, pu.th.size() - 1)), 5, 0)
		print(rlab + row)
	print("")

	print("5) HOW HARD DO YOU HAVE TO PUMP? Radial drive amplitude swept at the")
	print("   best lead, phase-locked. Drive is the fraction of the reach circle")
	print("   the cursor uses: 0.15 is a 17 cm hand movement. Top row per rig is")
	print("   deg gained per cycle over the 10->90 climb, second is A after 15 s:")
	var drives := [0.10, 0.15, 0.20, 0.30, 0.50, 0.75, 1.00]
	hdr = "   drive:  "
	for dv in drives:
		hdr += "%6.2f" % dv
	print(hdr)
	for cfg in RIGS:
		var row := ""
		var row2 := ""
		var rlab := ""
		for dv in drives:
			var b := bench(cfg, 900, 0.0, LEAD_DEFAULT, 8.0, 30, -1.0,
				dv if dv < 1.0 else 0.999, 0.0, false)
			if b.is_empty(): continue
			rlab = "   R %.2f " % b["tether"]
			var pu: Track = b["pump"]
			row += _f(pu.rate(10.0, 90.0), 6, 1)
			row2 += _f(pu.amp(mini(899, pu.th.size() - 1)), 6, 0)
		print(rlab + row)
		print("          " + row2)
	print("")

	print("6) THE BRAKE: servo to a settled 90 deg swing, then drive a chosen")
	print("   lead at full stroke for 5 s. Can a swing be shed as fast as it is")
	print("   won, so a bot can arrive at a chosen amplitude? Amplitude after")
	print("   the 5 s, and in brackets the deg per cycle it moved:")
	var blead := [-1.0, 0.0, 0.4, 0.8, 1.2, 2.0]
	hdr = "   lead:      coast"
	for l in blead:
		if l >= 0.0:
			hdr += "%13.1f" % l
	print(hdr)
	for cfg in RIGS:
		var row := ""
		var rlab := ""
		for l in blead:
			var r := brake_bench(cfg, 90.0, l, 300)
			if r.is_empty():
				row += "            ."; continue
			rlab = "   R %.1f  from %2.0f: " % [cfg[0], r[0]]
			row += "%6.0f (%+5.1f)" % [r[1], r[2]]
		print(rlab + row)
	print("")

	print("7) AMPLITUDE SERVO: pump_cursor(..., target_deg) must ARRIVE and HOLD")
	print("   R(m)  target   A@5s   A@10s  A@15s   mean err over the last 5 s")
	for cfg in RIGS:
		for tg in [30.0, 60.0, 90.0]:
			var b := bench(cfg, 900, tg, LEAD_DEFAULT, 8.0, 30)
			if b.is_empty(): continue
			var pu: Track = b["pump"]
			var err := 0.0
			var n := 0
			for i in range(600, mini(900, pu.th.size())):
				var a := pu.amp(i)
				if not is_nan(a):
					err += absf(a - tg); n += 1
			print("   %.2f  %5.0f  %s %s %s   %s deg%s%s"
				% [b["tether"], tg, _f(pu.amp(300), 6), _f(pu.amp(600), 6),
				   _f(pu.amp(899), 6), _f(err / maxf(n, 1), 5, 1),
				   "" if pu.over < 0 else "   (WENT OVER THE TOP)", _lost(pu)])
	print("")

	print("8) COLD START: dead hang, zero swing, with and without the starter.")
	print("   R(m)  starter   A@2s   A@5s   A@10s   first 45 deg swing at")
	for cfg in RIGS:
		for st in [true, false]:
			var b := bench(cfg, 600, 0.0, LEAD_DEFAULT, 0.0, 30, -1.0, 1.0, 0.0, st)
			if b.is_empty(): continue
			var pu: Track = b["pump"]
			var t45: int = pu.first_at(45.0)
			print("   %.2f  %-7s %s %s %s    %s%s"
				% [b["tether"], "on" if st else "off", _f(pu.amp(120), 6),
				   _f(pu.amp(300), 6), _f(pu.amp(600), 6),
				   ("%.1f s" % (t45 / 60.0)) if t45 >= 0 else "never", _lost(pu)])
	print("")

	print("9) HOW FAST DOES THE HAND HAVE TO MOVE? The policy commands a cursor")
	print("   position; a real player commands a mouse VELOCITY. Cap the cursor's")
	print("   speed relative to the body (the camera rides the body, so that is")
	print("   the hand speed on screen; 1 m = 60 px). Amplitude after 10 s:")
	var slews := [2.0, 4.0, 8.0, 16.0, 32.0, 0.0]
	hdr = "   m/s:    "
	for sl in slews:
		hdr += "%6s" % (("%.0f" % sl) if sl > 0.0 else "none")
	print(hdr)
	for cfg in RIGS:
		var row := ""
		var rlab := ""
		for sl in slews:
			var b := bench(cfg, 600, 0.0, LEAD_DEFAULT, 8.0, 30, -1.0, 1.0,
				0.0, true, 0.0, sl)
			if b.is_empty(): continue
			rlab = "   R %.2f " % b["tether"]
			var pu: Track = b["pump"]
			row += _f(pu.amp(mini(599, pu.th.size() - 1)), 6, 0)
		print(rlab + row)
	print("   (2 m/s = 120 px/s, a slow drag; 16 m/s = 960 px/s, a brisk flick;")
	print("    'none' is the unlimited policy, which peaks near 90 m/s.)")
	print("")

	print("10) WITH A FLOOR UNDER THE BEAM - the reason FAST beams exist.")
	print("    Identical pump, but the beam is now a level beam over a floor.")
	print("    R+1.30 is how deep the body can hang when the pump extends the")
	print("    arm; when that exceeds the drop, the pump drags its own feet.")
	print("    Drive is swept because a SMALLER stroke hangs shallower.")
	print("    Amplitude after 10 s, by drive fraction:")
	hdr = "    drop  R(m)  R+1.3   0.15  0.25  0.40  0.60  1.00   peak vt"
	print(hdr)
	for fd in [2.2, 4.5]:
		for cfg in RIGS:
			var row := ""
			var rlab := ""
			var vt := 0.0
			for dv in [0.15, 0.25, 0.40, 0.60, 1.00]:
				var b := bench(cfg, 600, 0.0, LEAD_DEFAULT, 8.0, 30, fd,
					dv if dv < 1.0 else 0.999, 0.0, false)
				if b.is_empty():
					continue
				rlab = "    %.1fm  %.2f  %.2f " % [fd, b["tether"],
					float(b["tether"]) + 1.30]
				var pu: Track = b["pump"]
				row += _f(pu.amp(mini(599, pu.th.size() - 1)), 6, 0)
				vt = maxf(vt, pu.peak_vt)
			if rlab == "":
				print("    %.1fm  hang %.1f: the wrap did not hold" % [fd, cfg[0]])
			else:
				print(rlab + row + "  %5.1f m/s" % vt)
	print("")

	print("11) THE OTHER PUMP (report it, do not ship a bot that uses it): a 1f")
	print("    TANGENTIAL drive - circling the cursor - is not a swing pump at")
	print("    all. It is a crank, and nothing in the sim caps it.")
	print("    R(m)  peak body speed in 10 s   final radius   full turns")
	for cfg in RIGS:
		var b := bench(cfg, 600, 0.0, 1.6, 8.0, 30, -1.0, 1.0, 1.0)
		if b.is_empty(): continue
		var pu: Track = b["pump"]
		print("    %.2f      %6.1f m/s             %.2f m        %.1f%s"
			% [b["tether"], pu.peak_v, b["final_r"], absf(pu.th_u) / TAU, _lost(pu)])
	print("")
	print("(bench %.0f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
