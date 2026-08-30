extends SceneTree
## catch_cue.gd - WHAT IS THE MISSING CUE WORTH?
##
## The residual misses are a timing problem the player cannot solve, because
## the moment they must hit - the wrap crossing th_part - is invisible. The ring
## has three readings and all three are about what the CATCH is doing (merely
## touching / caught / locked). None of them says the one thing the player has
## to time against: the rope is wound enough RIGHT NOW.
##
## This measures the ceiling: if the player could see that instant and pressed
## with an ordinary visual reaction delay after it, how many of their good
## throws would catch? Present state only - the cue is a fact about the rope
## that has already happened, not a prediction, and a throw that never winds
## never lights it.

const NT := 115

func _rig(path: String, dx: float, h: float, r: float) -> Node2D:
	var m: Node2D = load(path).new()
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

func _trial(path: String, s: Array, press: int) -> int:
	var m := _rig(path, s[0], s[1], s[2])
	var out := 0
	for t in NT:
		m.step_tick(_target(m, t, s), t >= press)
		if m.a_freelen[0] >= 0.0:
			out = 1
			if m.a_locked[0] == 1:
				out = 2
				break
			if m.a_locked[0] == 0:
				break
	m.free()
	return out

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var strokes := _strokes()
	var good: Array = []
	var tq: Array = []
	var tt: Array = []
	for s in strokes:
		var m := _rig("res://main.gd", s[0], s[1], s[2])
		var t_qual := -1
		var t_touch := -1
		for t in NT:
			m.step_tick(_target(m, t, s), false)
			if t_qual < 0 and absf(m.a_theta[0]) >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx:
				t_qual = t
			if t_touch < 0:
				for i in m.pos.size():
					if m.pos[i].distance_to(m.a_pos[0]) < m.a_r[0] + m.p_rad[i] + m.wrap_shell:
						t_touch = t
						break
		m.free()
		if t_qual >= 0 and t_touch >= 0:
			good.append(s)
			tq.append(t_qual)
			tt.append(t_touch)
	# how variable is the lead? that variance is what defeats fixed timing.
	var lo := 999
	var hi := -999
	var sum := 0
	for i in good.size():
		var l: int = tq[i] - tt[i]
		lo = mini(lo, l); hi = maxi(hi, l); sum += l
	print("=== WHY FIXED TIMING CANNOT WIN ==============================")
	print("%d good throws. Lead from beam contact to a qualifying wrap:" % good.size())
	print("  shortest %d ticks, longest %d ticks, mean %.1f." % [lo, hi, float(sum) / good.size()])
	print("  The player cannot know THIS throw's lead, and it varies by %d ticks" % (hi - lo))
	print("  (%.0f ms) - wider than the window itself. That spread is the residual." % [
		1000.0 * (hi - lo) / 60.0])
	print("")
	print("=== IF THE PLAYER COULD SEE THE WRAP GO LIVE =================")
	print("press this many ticks after the wrap first qualifies (a reaction to")
	print("a cue that is present state, not a prediction):")
	print("")
	print(" delay    ms    shipped rule        with the arrival window")
	print("                LOCK BETRAY MISS+   LOCK BETRAY MISS+")
	for d in [0, 3, 6, 9, 12, 15, 18, 21]:
		var r := [0, 0, 0, 0, 0, 0]
		for i in good.size():
			var p: int = tq[i] + d
			var a := _trial("res://main.gd", good[i], p)
			var b := _trial("res://tests/jb/whip_arrival.gd", good[i], p)
			if a == 2: r[0] += 1
			elif a == 1: r[1] += 1
			else: r[2] += 1
			if b == 2: r[3] += 1
			elif b == 1: r[4] += 1
			else: r[5] += 1
		print(" %+4d  %+5.0f    %4d %6d %5d   %4d %6d %5d     (%.0f%% / %.0f%% catch)" % [
			d, 1000.0 * d / 60.0, r[0], r[1], r[2], r[3], r[4], r[5],
			100.0 * (r[0] + r[1]) / good.size(), 100.0 * (r[3] + r[4]) / good.size()])
	print("")
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
