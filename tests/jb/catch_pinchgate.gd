extends SceneTree
## catch_pinchgate.gd - DOES th_part REFUSE TURNS THAT ARE PHYSICALLY REAL?
##
## The design's own answer to "what actually holds a body on a beam" is
## _pinch(): the chain crossing ITSELF against the beam, with more than 0.75 of
## a turn of chain between the two strands. That is the thing the lock verdict
## is decided on, and the comment on it says bulk winding angle was the wrong
## proxy. But ENGAGEMENT is still gated on the bulk winding angle (th_part), so
## a throw can make a genuine self-crossing turn and be refused because a
## noisier measure of the same event happened to read low.
##
## This counts, over the same stroke grid, how often that happens.

const NT := 115

func _rig(dx: float, h: float, r: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -h)
	m.a_r[0] = r
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
	var fin: int = s[6]
	var b: Vector2 = m.body_pos
	if t < 30:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return b + Vector2(cos(a1), sin(a1)) * m.REACH
	if fin == 2 and t < 30 + sd + 8:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
	return b + Vector2(cos(a1), sin(a1)) * m.REACH

func _strokes() -> Array:
	var out: Array = []
	for beam in [[0.22, 2.2], [0.11, 2.2], [0.11, 2.6]]:
		for dx in [1.8, 2.5]:
			for a0 in [PI * 0.85, PI * 1.10]:
				for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
					for sd in [5, 9, 14]:
						for fin in [0, 2]:
							out.append([dx, beam[1], beam[0], a0, a1, sd, fin])
	return out

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var strokes := _strokes()
	var both := 0            # real turn AND theta qualifies
	var pinch_only := 0      # real turn, theta refuses it  <- false negative
	var theta_only := 0      # theta qualifies with no self-crossing (a partial)
	var neither := 0
	var pinch_ticks := 0
	var pinch_runs := 0
	var hist := PackedInt32Array()
	hist.resize(7)           # peak theta buckets
	var pinch_peak_sum := 0.0
	for s in strokes:
		var m := _rig(s[0], s[1], s[2])
		var maxth := 0.0
		var qual := false
		var pinched := false
		var pt := 0
		var run := 0
		var best_run := 0
		var pinch_peak := 0.0
		for t in NT:
			m.step_tick(_target(m, t, s), false)
			var th: float = absf(m.a_theta[0])
			maxth = maxf(maxth, th)
			if th >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx:
				qual = true
			if m._pinch(0):
				pinched = true
				pt += 1
				run += 1
				best_run = maxi(best_run, run)
				pinch_peak = maxf(pinch_peak, th)
			else:
				run = 0
		m.free()
		var b := 0
		if maxth >= 6.0: b = 6
		elif maxth >= 5.0: b = 5
		elif maxth >= 4.0: b = 4
		elif maxth >= 3.4: b = 3
		elif maxth >= 2.6: b = 2
		elif maxth >= 1.5: b = 1
		hist[b] += 1
		if pinched and qual:
			both += 1
		elif pinched and not qual:
			pinch_only += 1
			pinch_ticks += pt
			pinch_runs = maxi(pinch_runs, best_run)
			pinch_peak_sum += pinch_peak
		elif qual:
			theta_only += 1
		else:
			neither += 1
	print("=== PEAK WINDING OVER %d STROKES =============================" % strokes.size())
	print("  < 1.5 rad (nothing)          %d" % hist[0])
	print("  1.5 - 2.6 (a lean or brush)  %d" % hist[1])
	print("  2.6 - 3.4 (LOOKS like a wrap, refused: fold range up to 2.62)  %d" % hist[2])
	print("  3.4 - 4.0 (just qualifies)   %d" % hist[3])
	print("  4.0 - 5.0                    %d" % hist[4])
	print("  5.0 - 6.0                    %d" % hist[5])
	print("  >= 6.0 (a turn and more)     %d" % hist[6])
	print("")
	print("=== THE SELF-CROSSING, WHICH IS WHAT ACTUALLY HOLDS ==========")
	print("real self-crossing turn AND theta qualifies:   %d  (catchable)" % both)
	print("real self-crossing turn, theta REFUSES it:     %d  <- refused a real turn" % pinch_only)
	print("theta qualifies with no self-crossing:         %d  (a partial: catches, betrays)" % theta_only)
	print("neither:                                       %d" % neither)
	if pinch_only > 0:
		print("")
		print("those refused turns held the crossing for %d ticks in total," % pinch_ticks)
		print("longest unbroken run %d ticks (%.0f ms), and their winding" % [
			pinch_runs, 1000.0 * pinch_runs / 60.0])
		print("peaked at %.2f rad on average against a th_part of 3.4." % [
			pinch_peak_sum / pinch_only])
	print("")
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
