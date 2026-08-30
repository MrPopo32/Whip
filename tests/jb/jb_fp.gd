extends SceneTree
## catch_fp.gd - FALSE-POSITIVE STRESS. The designer's one hard constraint is
## that it must never catch when it should not, so any change to the catch gate
## has to be attacked from the other side.
##
## Two attacks, run against both the shipped rule and the candidate fix:
##
##  S1 THE STIR. Close the hand early, land the whip on the beam, then stop
##     throwing and just wave the hand around. If the machine will pick the
##     instant for you, a wrap accumulated by stirring will catch. Measured as
##     "how long after the press did the catch fire" - a throw catches within
##     a few dozen ticks; a stir catches hundreds of ticks later.
##
##  S2 ACCIDENTAL COLLECTION. Hang on one beam with the hand shut and swing
##     past a second one. The shipped rule promises you cannot pick up beams
##     you did not reach for. Any catch on beam B here is a regression.

const NT := 340

var SCRIPT := "res://main.gd"

func _rig(dx: float, h: float, r: float, r2: float, d2: Vector2) -> Node2D:
	var m: Node2D = load(SCRIPT).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -h)
	m.a_r[0] = r
	if r2 > 0.0:
		m.a_pos[1] = d2
		m.a_r[1] = r2
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

func _target(m: Node2D, t: int, s: Array) -> Vector2:
	var a0: float = s[3]
	var a1: float = s[4]
	var sd: int = s[5]
	var b: Vector2 = m.body_pos
	if t < 30:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return b + Vector2(cos(a1), sin(a1)) * m.REACH
	if t < 70:
		return b + Vector2(cos(a1), sin(a1)) * m.REACH
	# THE STIR: from here on the player is not throwing, just waving.
	var ph := float(t - 70) * 0.16
	return b + Vector2(cos(ph) * 0.9, -0.55 + sin(ph) * 0.55).normalized() * m.REACH

func _strokes() -> Array:
	var out: Array = []
	for beam in [[0.22, 2.2], [0.11, 2.2], [0.11, 2.6]]:
		for dx in [1.8, 2.5]:
			for a0 in [PI * 0.85, PI * 1.10]:
				for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
					for sd in [5, 9, 14]:
						out.append([dx, beam[1], beam[0], a0, a1, sd, 0])
	return out

# ---------------------------------------------------------------- S1 stir ---
func _stir(s: Array) -> Array:
	# find the arrival tick with the hand open, then re-run pressing 10 ticks
	# BEFORE it and holding, and see when (if ever) a catch fires.
	var m := _rig(s[0], s[1], s[2], -1.0, Vector2.ZERO)
	var t_touch := -1
	for t in NT:
		m.step_tick(_target(m, t, s), false)
		if t_touch < 0:
			var c: Vector2 = m.a_pos[0]
			for i in m.pos.size():
				if m.pos[i].distance_to(c) < m.a_r[0] + m.p_rad[i] + m.wrap_shell:
					t_touch = t
					break
	m.free()
	if t_touch < 0:
		return [-1, -1, 0.0]
	var press := maxi(t_touch - 10, 0)
	var m2 := _rig(s[0], s[1], s[2], -1.0, Vector2.ZERO)
	var engage_t := -1
	var maxth := 0.0
	for t in NT:
		m2.step_tick(_target(m2, t, s), t >= press)
		maxth = maxf(maxth, absf(m2.a_theta[0]))
		if engage_t < 0 and m2.a_freelen[0] >= 0.0:
			engage_t = t
	m2.free()
	var lag := -1
	if engage_t >= 0:
		lag = engage_t - press
	return [lag, t_touch, maxth]

# ------------------------------------------------------- S2 collection ------
func _prewrap(m: Node2D, k: int, turns: float, at: Vector2) -> void:
	m.a_r[k] = 0.20
	m.a_pos[k] = at
	var c: Vector2 = m.a_pos[k]
	var r: float = m.a_r[k] + 0.04
	var hang := 2.0
	var rise := hang - r
	var wl := turns * TAU * r
	for i in m.pos.size():
		var sl: float = m.cum_len[i]
		var p: Vector2
		if sl < rise:
			p = c + Vector2(0.0, hang - sl)
		elif sl < rise + wl:
			var ang: float = PI / 2.0 + (sl - rise) / r
			p = c + Vector2(cos(ang), sin(ang)) * r
		else:
			var a2: float = PI / 2.0 + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * r
			p = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, sl - rise - wl)
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + Vector2(0.0, hang + 0.6)
	m.body_prv = m.body_pos

func _collect(bx: float, by: float, amp: float) -> Array:
	# hang on beam A at the origin, hand shut the whole time, swing hard and
	# let the tail sweep across beam B.
	var m: Node2D = load(SCRIPT).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 40.0)); m.t_b.append(Vector2(60.0, 40.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.clear_anchors()
	_prewrap(m, 0, 1.4, Vector2(0.0, -30.0))
	m.a_pos[1] = Vector2(bx, -30.0 + by)
	m.a_r[1] = 0.11
	var b_caught := 0
	var b_maxth := 0.0
	var a_held := 0
	for t in 900:
		var ph := float(t) * 0.055
		var tgt: Vector2 = m.body_pos + Vector2(cos(ph) * amp, -0.5).normalized() * m.REACH
		m.step_tick(tgt, true)
		b_maxth = maxf(b_maxth, absf(m.a_theta[1]))
		if m.a_freelen[1] >= 0.0:
			b_caught += 1
		if m.a_freelen[0] >= 0.0:
			a_held += 1
	m.free()
	return [b_caught, b_maxth, a_held]

func _initialize() -> void:
	if "arrival" in OS.get_cmdline_user_args():
		SCRIPT = "res://tests/jb/whip_arrival.gd"
	print("SIM UNDER TEST: %s" % SCRIPT)
	print("")
	print("=== S1  THE STIR =============================================")
	print("hand closed 10 ticks before the whip reaches the beam, then held")
	print("while the player stops throwing and just waves (from tick 70 on).")
	print("A catch is HONEST if it fires while the throw is still arriving;")
	print("it is MANUFACTURED if it fires long after, out of stirring.")
	var n := 0
	var caught := 0
	var lag_max := -1
	var late := 0        # catches fired more than 60 ticks (1 s) after the press
	var lag_sum := 0
	for s in _strokes():
		var r := _stir(s)
		if int(r[1]) < 0:
			continue
		n += 1
		var lag := int(r[0])
		if lag >= 0:
			caught += 1
			lag_sum += lag
			lag_max = maxi(lag_max, lag)
			if lag > 60:
				late += 1
	print("%d strokes whose whip reaches the beam; %d catch." % [n, caught])
	if caught > 0:
		print("press -> catch lag: mean %.1f ticks, worst %d ticks (%.0f ms)" % [
			float(lag_sum) / caught, lag_max, 1000.0 * lag_max / 60.0])
	print("MANUFACTURED catches (fired more than 1 s after the press): %d" % late)
	print("")
	print("=== S2  ACCIDENTAL COLLECTION ================================")
	print("hanging on beam A, hand shut for 15 s, swinging past beam B.")
	print("beam B at        ticks B engaged   B peak theta   A held")
	var tot := 0
	for bx in [-1.6, -1.1, 1.1, 1.6]:
		for by in [-0.5, 0.0, 0.6]:
			for amp in [1.0, 1.6]:
				var r := _collect(bx, by, amp)
				tot += int(r[0])
				if int(r[0]) > 0:
					print("  (%+.1f,%+.1f) amp %.1f    %5d          %5.2f       %d  <-- COLLECTED" % [
						bx, by, amp, r[0], r[1], r[2]])
	print("total ticks beam B was engaged across 24 swings: %d" % tot)
	quit(0)
