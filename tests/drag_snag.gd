extends SceneTree
## RE-SNAG: can the beam you just left take the rope again?
##
## Release sets a_armed[k] = 0 and _update_locks re-arms on ONE condition -
## the taut wrap angle falling under th_rel = 1.80 rad. But the taut wrap angle
## reads ~0 for a rope that is merely DRAPED over a beam; that is the whole
## point of the measure. So a chain still lying on the beam with 15+ particles
## in contact re-arms immediately. The next press - the one aimed at the NEXT
## beam - is then live for the OLD beam for GRIP_WINDOW = 15 ticks, and _pinch
## (a self-crossing near the beam) can take it with no wrap angle at all.
##
## This probe instruments both halves of that catch predicate at every tick
## after release, so the trigger is identified, not inferred.

const NT := 90
const EPS := 0.06

func _rig(m_r: float, turns: float, swing_deg: float) -> Node2D:
	var m: Node2D = load("res://tests/main_drag.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -2.2); m.a_r[0] = m_r
	var c: Vector2 = m.a_pos[0]
	var rr: float = m_r + 0.04
	var hang := 2.0
	var rise: float = hang - rr
	var wl: float = turns * TAU * rr
	var A: float = deg_to_rad(swing_deg)
	var u := Vector2(sin(A), cos(A))
	var a0: float = u.angle()
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + u * (hang - s)
		elif s < rise + wl:
			var a: float = a0 + (s - rise) / rr
			p = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = a0 + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			p = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, s - rise - wl)
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + u * (hang + 0.6); m.body_prv = m.body_pos
	return m

func _contacts(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + EPS:
			n += 1
	return n

## reach: 0 = cursor parked on the body, 1 = cursor thrown out ahead along the
## launch direction (the player reaching for the NEXT beam)
func _run(rr: float, turns: float, sd: float, hold: int, regrip: int,
		reach: int) -> Dictionary:
	var m := _rig(rr, turns, sd)
	for t in hold:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free()
		return {"engaged": false}
	var bv: Vector2 = m.body_pos - m.body_prv
	var dir: Vector2 = bv.normalized()
	var v0: float = bv.length() / m.SDT
	var out := {"engaged": true, "v_rel": v0,
		"cont_rel": _contacts(m), "theta_rel": absf(m.a_theta[0])}
	var recatch := -1
	var recatch_th := 0.0
	var recatch_cont := 0
	var recatch_pinch := false
	var recatch_wrap := false
	var armed_at := -1
	var pinch_ticks := 0
	var vx := PackedFloat32Array(); var vy := PackedFloat32Array()
	for t in NT:
		var grip := regrip >= 0 and t >= regrip
		var tgt: Vector2 = m.body_pos
		if reach == 1:
			tgt = m.body_pos + dir * m.REACH
		m.step_tick(tgt, grip)
		var th: float = absf(m.a_theta[0])
		var pin: bool = m._pinch(0)
		if pin:
			pinch_ticks += 1
		if armed_at < 0 and m.a_armed[0] == 1:
			armed_at = t
		if recatch < 0 and m.a_freelen[0] >= 0.0:
			recatch = t
			recatch_th = th
			recatch_cont = _contacts(m)
			recatch_pinch = pin
			recatch_wrap = th >= m.th_part
		var v: Vector2 = (m.body_pos - m.body_prv) / m.SDT
		vx.append(v.x); vy.append(v.y)
	out["recatch"] = recatch
	out["recatch_th"] = recatch_th
	out["recatch_cont"] = recatch_cont
	out["recatch_pinch"] = recatch_pinch
	out["recatch_wrap"] = recatch_wrap
	out["armed_at"] = armed_at
	out["pinch_ticks"] = pinch_ticks
	out["vx"] = vx; out["vy"] = vy
	out["dir"] = dir
	m.free()
	return out

func _initialize() -> void:
	print("=== RE-SNAG: does the beam you just left take the rope again? ===")
	print("The hand opens at t=0. At t=REGRIP the player closes it again - the")
	print("press meant for the NEXT beam. Cursor policy: PARKED = hand held on the")
	print("body; REACH = handle thrown out ahead along the launch direction.")
	print("")
	print("A re-catch needs a_armed==1 (theta under th_rel=1.80) AND either")
	print("theta >= th_part=3.40 (a real wrap) or _pinch (a self-crossing).")
	print("")
	print("  case              regrip | PARKED: caught? tick trigger  th cont | REACH: caught? tick trigger")
	var np_yes := 0
	var np_tot := 0
	var rc_yes := 0
	var rc_tot := 0
	var armed := []
	var worst := []
	for cs: Array in [[0.10, 1.6, 80.0], [0.10, 2.0, 80.0], [0.10, 2.4, 80.0],
			[0.11, 1.6, 80.0], [0.11, 2.0, 80.0], [0.11, 2.4, 80.0],
			[0.20, 2.0, 80.0], [0.22, 2.0, 80.0], [0.11, 2.0, -80.0]]:
		for hold in [35, 45, 55, 65]:
			for rg in [4, 10, 20]:
				var P := _run(cs[0], cs[1], cs[2], hold, rg, 0)
				if not P["engaged"]:
					continue
				var R := _run(cs[0], cs[1], cs[2], hold, rg, 1)
				np_tot += 1
				rc_tot += 1
				if P["armed_at"] >= 0:
					armed.append(float(P["armed_at"]))
				var trig := "-"
				if P["recatch"] >= 0:
					np_yes += 1
					trig = "PINCH" if P["recatch_pinch"] and not P["recatch_wrap"] \
						else ("wrap" if P["recatch_wrap"] else "?")
				var trig2 := "-"
				if R["recatch"] >= 0:
					rc_yes += 1
					trig2 = "PINCH" if R["recatch_pinch"] and not R["recatch_wrap"] \
						else ("wrap" if R["recatch_wrap"] else "?")
				if P["recatch"] >= 0 or R["recatch"] >= 0:
					worst.append([cs[0], cs[1], cs[2], hold, rg, P, R])
					print("  r%.2f %.1ft sd%+3.0f h%-3d rg%-3d | %s %4d %-6s %5.2f %3d | %s %4d %-6s"
						% [cs[0], cs[1], cs[2], hold, rg,
						   ("YES" if P["recatch"] >= 0 else " no"), P["recatch"],
						   trig, P["recatch_th"], P["recatch_cont"],
						   ("YES" if R["recatch"] >= 0 else " no"), R["recatch"],
						   trig2])
	print("")
	print("  cursor PARKED on the body: re-caught the old beam %d / %d" % [np_yes, np_tot])
	print("  cursor REACHING ahead:     re-caught the old beam %d / %d" % [rc_yes, rc_tot])
	armed.sort()
	if not armed.is_empty():
		print("  ticks after release before the old beam RE-ARMS (theta < th_rel):")
		print("    min %.0f  med %.0f  p90 %.0f  max %.0f  (n=%d)"
			% [armed[0], armed[armed.size() / 2],
			   armed[mini(int(armed.size() * 0.9), armed.size() - 1)],
			   armed[armed.size() - 1], armed.size()])
	print("")
	print("=== WHAT A RE-SNAG COSTS ======================================")
	print("For each snagging case: body speed at the end of the window, with the")
	print("re-grip vs with the hand simply kept open.")
	print("  case                     regrip | speed w/ regrip | speed hand-open | delta")
	var shown := 0
	for w: Array in worst:
		if shown >= 12:
			break
		var P: Dictionary = w[5]
		if P["recatch"] < 0:
			continue
		shown += 1
		var open_arm := _run(w[0], w[1], w[2], w[3], -1, 0)
		var s_re := Vector2(P["vx"][NT - 1], P["vy"][NT - 1]).length()
		var s_op := Vector2(open_arm["vx"][NT - 1], open_arm["vy"][NT - 1]).length()
		print("  r%.2f %.1ft sd%+3.0f h%-3d rg%-3d | %13.2f | %15.2f | %+.2f"
			% [w[0], w[1], w[2], w[3], w[4], s_re, s_op, s_re - s_op])
	quit(0)
