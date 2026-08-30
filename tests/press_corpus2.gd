extends SceneTree
## SHIPPED RULE vs SYMMETRIC RULE, over the whole throw corpus.
## One ungripped baseline run per throw gives every quantity both rules read.
## Both rules are then evaluated exactly:
##   OLD catch at press tp  <=>  some tick in [tp, tp+14] qualifies
##   NEW catch at press tp  <=>  OLD, or the last qualifying tick q is within
##                               15 ticks back AND the wrap has not RELEASED
##                               (th < th_rel with no self-pinch) since q
## The OLD predictor was verified tick-for-tick against real gripped re-runs
## on seven throws (tests/press_sweep.gd): zero mismatches.

const RUN := 210
const GW := 15

func _rig(dx: float, dy: float, r: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -dy)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R)
	m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p
		m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

func _tgt(m: Node2D, t: int, c: Array) -> Vector2:
	if t < 30:
		return m.body_pos + Vector2(cos(c[3]), sin(c[3])) * m.REACH
	if t < 30 + int(c[5]):
		return m.body_pos + Vector2(cos(c[4]), sin(c[4])) * m.REACH
	if bool(c[6]) and t < 30 + int(c[5]) + 10:
		return m.body_pos + Vector2(cos(c[3]), sin(c[3])) * m.REACH * 0.7
	return m.body_pos + Vector2(cos(c[4]), sin(c[4])) * m.REACH

func _ms(t: int) -> int:
	return int(round(t * 1000.0 / 60.0))

func _initialize() -> void:
	var cfgs := []
	for r in [0.22, 0.20, 0.11, 0.10]:
		for dy in [2.0, 2.2, 2.4, 2.6]:
			for dx in [1.4, 1.7, 2.0, 2.3, 2.6]:
				for a1 in [-0.42, -0.34]:
					cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI, 9, true])
	var n_old_catchable := 0
	var n_new_catchable := 0
	var holes_old := 0
	var holes_new := 0
	var holed_old := 0
	var holed_new := 0
	var maxhole_old := 0
	var maxhole_new := 0
	var width_old := []
	var width_new := []
	var rt_old := {9: 0, 12: 0, 15: 0, 18: 0}
	var rt_new := {9: 0, 12: 0, 15: 0, 18: 0}
	var rt_n := 0
	var early_new := []
	print("shipped -> symmetric, per throw:")
	print("  r   dx   dy   a1 | catchable | dead press ticks  | window ms")
	print("                   | old  new  | old   new         | old      new")
	for c in cfgs:
		var m := _rig(c[0], c[1], c[2])
		var qual := PackedInt32Array()
		var void_t := PackedInt32Array()
		var lidx := PackedInt32Array()
		var t_hook := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), false)
			var th: float = absf(m.a_theta[0])
			var pin: bool = m._pinch(0)
			qual.append(1 if (th >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx) else 0)
			void_t.append(1 if (th < m.th_rel and not pin) else 0)
			lidx.append(1 if m.a_lockidx[0] >= m.pin_min_idx else 0)
			var ctr: Vector2 = m.a_pos[0]
			var n := 0
			var lft := false
			var rgt := false
			for i in m.NP:
				if (m.pos[i] - ctr).length() - m.a_r[0] - m.p_rad[i] < 0.015:
					n += 1
					if m.pos[i].x < ctr.x: lft = true
					else: rgt = true
			if t_hook < 0 and n >= 3 and lft and rgt:
				t_hook = t
		m.free()
		var anyq := false
		for t in RUN:
			if qual[t] == 1:
				anyq = true
				break
		if not anyq or t_hook < 0:
			continue
		# --- evaluate both rules ---
		var co := PackedInt32Array(); co.resize(RUN)
		var cn := PackedInt32Array(); cn.resize(RUN)
		var qlast := -999
		for tp in RUN:
			var o := 0
			for u in range(tp, mini(tp + GW, RUN)):
				if qual[u] == 1:
					o = 1
					break
			co[tp] = o
			# a_qtick as the sim maintains it
			if void_t[tp] == 1:
				qlast = -999
			if qual[tp] == 1:
				qlast = tp
			var back: int = 1 if (qlast >= 0 and tp - qlast <= GW and lidx[tp] == 1) else 0
			cn[tp] = 1 if (o == 1 or back == 1) else 0
		var fo := -1; var lo_ := -1; var fn := -1; var ln := -1
		for t in RUN:
			if co[t] == 1:
				if fo < 0: fo = t
				lo_ = t
			if cn[t] == 1:
				if fn < 0: fn = t
				ln = t
		var ho := 0; var hn := 0; var mo := 0; var mn := 0
		var ro := 0; var rn := 0
		for t in range(fo, lo_ + 1):
			if co[t] == 0:
				ho += 1; ro += 1; mo = maxi(mo, ro)
			else:
				ro = 0
		for t in range(fn, ln + 1):
			if cn[t] == 0:
				hn += 1; rn += 1; mn = maxi(mn, rn)
			else:
				rn = 0
		n_old_catchable += 1
		n_new_catchable += 1
		holes_old += ho; holes_new += hn
		if ho > 0: holed_old += 1
		if hn > 0: holed_new += 1
		maxhole_old = maxi(maxhole_old, mo)
		maxhole_new = maxi(maxhole_new, mn)
		width_old.append(_ms(lo_ - fo + 1))
		width_new.append(_ms(ln - fn + 1))
		early_new.append(_ms(fn - t_hook))
		rt_n += 1
		for rt in [9, 12, 15, 18]:
			var tp2: int = t_hook + rt
			if tp2 < RUN:
				if co[tp2] == 0: rt_old[rt] += 1
				if cn[tp2] == 0: rt_new[rt] += 1
		if ho != hn or fo != fn or lo_ != ln:
			print("%.2f %4.1f %4.1f %5.2f |  Y    Y   | %3d   %3d (max %d->%d) | %5d    %5d"
				% [c[2], c[0], c[1], c[4] / PI, ho, hn, mo, mn,
				_ms(lo_ - fo + 1), _ms(ln - fn + 1)])
	print("")
	print("throws catchable at all:            old %d   new %d   (identical set)"
		% [n_old_catchable, n_new_catchable])
	print("throws with a DEAD press tick:      old %d (%.0f%%)   new %d (%.0f%%)"
		% [holed_old, 100.0 * holed_old / maxf(n_old_catchable, 1),
		holed_new, 100.0 * holed_new / maxf(n_old_catchable, 1)])
	print("total dead press ticks in corpus:   old %d (%d ms)   new %d (%d ms)"
		% [holes_old, _ms(holes_old), holes_new, _ms(holes_new)])
	print("longest single dead run:            old %d ms   new %d ms"
		% [_ms(maxhole_old), _ms(maxhole_new)])
	width_old.sort(); width_new.sort()
	print("press-window width, median:         old %d ms   new %d ms"
		% [width_old[width_old.size() / 2], width_new[width_new.size() / 2]])
	print("press-window width, minimum:        old %d ms   new %d ms"
		% [width_old[0], width_new[0]])
	print("")
	print("PLAYER PRESSES WHEN THEY SEE THE ROPE HOOK THE BEAM, PLUS REACTION:")
	print("  reaction   presses that do NOTHING (of %d throws)" % rt_n)
	print("             shipped    symmetric")
	for rt in [9, 12, 15, 18]:
		print("   %3d ms      %3d (%2.0f%%)   %3d (%2.0f%%)"
			% [_ms(rt), rt_old[rt], 100.0 * rt_old[rt] / rt_n,
			rt_new[rt], 100.0 * rt_new[rt] / rt_n])
	early_new.sort()
	print("")
	print("earliest catching press vs the visible hook (symmetric): min %d, median %d, max %d ms"
		% [early_new[0], early_new[early_new.size() / 2], early_new[-1]])
	quit(0)
