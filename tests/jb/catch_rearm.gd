extends SceneTree
## catch_rearm.gd - IS THE BEAM YOU JUST LEFT SILENTLY DEAD?
##
## a_armed goes to 0 on a deliberate release and on a slide-off, and only comes
## back when the MEASURED winding falls under th_rel (1.8 rad). If the whip is
## still draped over the beam after you let go - a fold measures up to 2.6 rad
## while winding nothing - the beam stays refused with no tell of any kind.
## That is exactly the shape of "sometimes it doesn't catch when it should",
## and it is the one that would bite hardest in beam-to-beam flow.
##
## Reported: how many ticks the beam stays disarmed after each way of leaving
## it, and what the winding angle was doing during that time.

var SCRIPT := "res://main.gd"

func _sim() -> Node2D:
	var m: Node2D = load(SCRIPT).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 3.0)); m.t_b.append(Vector2(60.0, 3.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.clear_anchors()
	return m

func _prewrap(m: Node2D, turns: float) -> void:
	m.a_r[0] = 0.20
	m.a_pos[0] = Vector2(0.0, 0.0)
	var c: Vector2 = m.a_pos[0]
	var r: float = m.a_r[0] + 0.04
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

func _run(turns: float, hold: int, tag: String) -> void:
	var m := _sim()
	_prewrap(m, turns)
	var left := -1
	var armed_back := -1
	var th_at_left := 0.0
	var th_max_after := 0.0
	var th_min_after := 99.0
	var engaged_end := -1
	for t in 600:
		var grip := t < hold
		# after letting go, the player immediately swings the hand as if to
		# throw again at the same beam
		var tgt: Vector2 = m.body_pos + Vector2(0.6, -0.9)
		if t >= hold:
			var ph := float(t - hold) * 0.18
			tgt = m.body_pos + Vector2(cos(ph) * 1.0, -0.6).normalized() * m.REACH
		m.step_tick(tgt, grip)
		var th: float = absf(m.a_theta[0])
		if left < 0 and t >= hold:
			left = t
			th_at_left = th
		if t >= hold:
			th_max_after = maxf(th_max_after, th)
			th_min_after = minf(th_min_after, th)
			if armed_back < 0 and m.a_armed[0] == 1:
				armed_back = t
		if m.a_freelen[0] >= 0.0:
			engaged_end = t
	var dis := -1
	if armed_back >= 0:
		dis = armed_back - hold
	print("%-34s let go at t=%d, theta then %.2f" % [tag, hold, th_at_left])
	if armed_back < 0:
		print("   RE-ARMED: NEVER in the 600-tick run (%.1f s of dead beam)" % [
			(600.0 - hold) / 60.0])
	else:
		print("   RE-ARMED after %d ticks (%.0f ms)" % [dis, 1000.0 * dis / 60.0])
	print("   theta after letting go: min %.2f  max %.2f   (th_rel = %.1f)" % [
		th_min_after, th_max_after, m.th_rel])
	m.free()

func _slide_off() -> void:
	# a partial wrap that betrays: _advance_pin disarms the anchor when the
	# whip finally runs off its own tail. How long until it can be caught again?
	var m := _sim()
	_prewrap(m, 0.9)
	var off := -1
	var armed_back := -1
	var th_at_off := 0.0
	for t in 900:
		var tgt: Vector2 = m.body_pos + Vector2(0.6, -0.9)
		m.step_tick(tgt, true)          # hand stays SHUT the whole time
		if off < 0 and m.a_freelen[0] < 0.0 and t > 5:
			off = t
			th_at_off = absf(m.a_theta[0])
		if off >= 0 and armed_back < 0 and m.a_armed[0] == 1:
			armed_back = t
	print("slide-off (partial betrays, hand stays shut)")
	if off < 0:
		print("   never came off in 15 s")
	else:
		print("   came off at t=%d with theta %.2f" % [off, th_at_off])
		if armed_back < 0:
			print("   RE-ARMED: NEVER (dead beam for the rest of the run)")
		else:
			print("   RE-ARMED after %d ticks (%.0f ms)" % [
				armed_back - off, 1000.0 * (armed_back - off) / 60.0])
	m.free()

func _initialize() -> void:
	if "fix" in OS.get_cmdline_user_args():
		SCRIPT = "res://tests/main_fix.gd"
	print("SIM UNDER TEST: %s" % SCRIPT)
	print("")
	print("=== HOW LONG IS A BEAM DEAD AFTER YOU LEAVE IT? ==============")
	for turns in [1.4, 1.1, 0.9]:
		for hold in [60, 120]:
			_run(turns, hold, "release after %.1f turns, %d t" % [turns, hold])
	print("")
	_slide_off()
	quit(0)
