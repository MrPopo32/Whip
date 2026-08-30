extends SceneTree
## THE DISMOUNT DRAG, part 3 - what drives it, and can it re-snag you?
##
## (1) TIMELINE. Tick by tick for one bad dismount: contacts, static-mu
##     population, speed, and the drag impulse dV against the ideal launch.
## (2) MU SWEEP. anchor_mu is forced to a value at the release instant and
##     nothing else changes. If the drag tracks mu, it is CONTACT FRICTION,
##     not the geometry of paying rope round a cylinder.
## (3) RE-SNAG. The player opens the hand and then closes it again N ticks
##     later, reaching for the NEXT beam. Can the beam they just left take
##     the rope a second time?
## (4) CAPSTAN. Does the drag scale like e^(mu*theta)? Turns on the beam at
##     release vs impulse taken.

const NT := 200
const EPS := 0.06

func _rig(r: float, turns: float, swing_deg: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -60.0); m.a_r[0] = r
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.04
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

func _static_pop(m: Node2D) -> int:
	if m.a_freelen[0] < 0.0 or m.a_pinidx[0] < 0:
		return 0
	var lo: int = m.a_pinidx[0] + m.a_wlo[0]
	var hi: int = m.a_pinidx[0] + m.a_whi[0]
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if i >= lo and i <= hi and (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + EPS:
			n += 1
	return n

func _bvel(m: Node2D) -> Vector2:
	return (m.body_pos - m.body_prv) / m.SDT

## mu < 0 means "leave anchor_mu alone". clear = teleport the beam away.
func _run(r: float, turns: float, sd: float, hold: int, mu: float,
		clear: bool, regrip_at: int) -> Dictionary:
	var m := _rig(r, turns, sd, )
	for t in hold:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free()
		return {"engaged": false}
	var out := {"engaged": true, "pin": m.a_pinidx[0], "locked": m.a_locked[0],
		"theta_rel": absf(m.a_theta[0]), "contacts_rel": _contacts(m),
		"static_rel": _static_pop(m)}
	var v0 := _bvel(m)
	out["v_rel"] = v0.length(); out["dir"] = v0.normalized()
	out["h_rel"] = rad_to_deg(v0.angle())
	if clear:
		m.a_pos[0] = Vector2(0.0, 900.0)
	if mu >= 0.0:
		m.anchor_mu = mu
	var vx := PackedFloat32Array(); var vy := PackedFloat32Array()
	var con := PackedInt32Array(); var sta := PackedInt32Array()
	var spd := PackedFloat32Array()
	var th := PackedFloat32Array()
	var recatch := -1
	var last_touch := -1
	for t in NT:
		var grip := regrip_at >= 0 and t >= regrip_at
		m.step_tick(m.body_pos, grip)
		var v := _bvel(m)
		vx.append(v.x); vy.append(v.y); spd.append(v.length())
		var n := 0 if clear else _contacts(m)
		con.append(n); sta.append(_static_pop(m))
		th.append(absf(m.a_theta[0]))
		if n > 0:
			last_touch = t
		if recatch < 0 and m.a_freelen[0] >= 0.0:
			recatch = t
	out["vx"] = vx; out["vy"] = vy; out["spd"] = spd
	out["con"] = con; out["sta"] = sta; out["th"] = th
	out["last_touch"] = last_touch; out["recatch"] = recatch
	m.free()
	return out

func _retro(X: Dictionary, C: Dictionary, dir: Vector2) -> Array:
	var fin := Vector2(X["vx"][NT - 1] - C["vx"][NT - 1],
		X["vy"][NT - 1] - C["vy"][NT - 1])
	var acting := 0
	for t in range(NT - 1, 0, -1):
		var a := Vector2(X["vx"][t] - C["vx"][t], X["vy"][t] - C["vy"][t])
		var b := Vector2(X["vx"][t - 1] - C["vx"][t - 1], X["vy"][t - 1] - C["vy"][t - 1])
		if (a - b).length() > 0.01:
			acting = t + 1
			break
	var bend := rad_to_deg(Vector2(C["vx"][NT - 1], C["vy"][NT - 1])
		.angle_to(Vector2(X["vx"][NT - 1], X["vy"][NT - 1])))
	return [-fin.dot(dir), absf(fin.cross(dir)), fin.length(), acting, bend]

func _initialize() -> void:
	# --------------------------------------------------------- (1) TIMELINE --
	var CASES := [[0.10, 2.0, 80.0, 40], [0.11, 2.0, 80.0, 40],
		[0.22, 1.6, 80.0, 45], [0.10, 1.6, 80.0, 40]]
	print("=== (1) TIMELINE OF ONE DISMOUNT ==============================")
	for cs: Array in CASES:
		var A := _run(cs[0], cs[1], cs[2], cs[3], -1.0, false, -1)
		var C := _run(cs[0], cs[1], cs[2], cs[3], -1.0, true, -1)
		if not A["engaged"]:
			continue
		var dir: Vector2 = A["dir"]
		print("beam r=%.2f  %.1f turns rigged  release speed %.2f m/s heading %+.0f deg"
			% [cs[0], cs[1], A["v_rel"], A["h_rel"]])
		print("  wrap at release %.2f turns, %d particles on the beam, %d of them under STATIC mu"
			% [A["theta_rel"] / TAU, A["contacts_rel"], A["static_rel"]])
		print("  ms   contacts static  wrapTurns  speed   ideal   RETRO   LAT")
		for t in range(0, 90):
			if t > 30 and t % 5 != 0:
				continue
			var dv := Vector2(A["vx"][t] - C["vx"][t], A["vy"][t] - C["vy"][t])
			print("  %4.0f    %2d      %2d      %5.2f    %5.2f   %5.2f  %+6.2f  %5.2f"
				% [(t + 1) * 1000.0 / 60.0, A["con"][t], A["sta"][t],
				   A["th"][t] / TAU, A["spd"][t], C["spd"][t],
				   -dv.dot(dir), absf(dv.cross(dir))])
		var rr := _retro(A, C, dir)
		print("  -> total %.2f m/s taken, %.2f m/s of it retrograde, heading bent %+.1f deg, still acting to tick %d (%.0f ms)"
			% [rr[2], rr[0], rr[4], rr[3], rr[3] * 1000.0 / 60.0])
		print("")

	# ---------------------------------------------------------- (2) MU SWEEP --
	print("=== (2) IS IT FRICTION? anchor_mu forced at the release instant ==")
	print("(anchor_mu is the KINETIC coefficient a DISENGAGED beam uses. 0.40 ships.)")
	print("  case          mu | RETRO m/s   LAT   |dV|  bend deg  acting ticks  lastTouch")
	for cs: Array in [[0.10, 2.0, 80.0, 40], [0.11, 1.6, 80.0, 45],
			[0.22, 2.0, 80.0, 45], [0.20, 1.6, 80.0, 55]]:
		var C := _run(cs[0], cs[1], cs[2], cs[3], -1.0, true, -1)
		if not C["engaged"]:
			continue
		for mu in [0.40, 0.30, 0.20, 0.10, 0.05, 0.02, 0.0]:
			var A := _run(cs[0], cs[1], cs[2], cs[3], mu, false, -1)
			var rr := _retro(A, C, A["dir"])
			print("  r%.2f/%.1ft  %.2f | %+8.2f %6.2f %6.2f %+9.1f %11d %10d"
				% [cs[0], cs[1], mu, rr[0], rr[1], rr[2], rr[4], rr[3],
				   A["last_touch"]])
		print("")

	# ------------------------------------------------------------ (3) RESNAG --
	print("=== (3) CAN THE BEAM YOU LEFT TAKE THE ROPE AGAIN? =============")
	print("hand opens at t=0, then closes again at t=REGRIP (reaching for the next beam).")
	print("  case            regrip | re-engaged old beam?  at tick  armed-again tick  min theta after release")
	for cs: Array in [[0.10, 2.0, 80.0, 40], [0.11, 1.6, 80.0, 45],
			[0.22, 2.0, 80.0, 45], [0.20, 1.6, 80.0, 55], [0.10, 1.2, 80.0, 40]]:
		for rg in [3, 6, 10, 15, 20, 30, 45]:
			var A := _run(cs[0], cs[1], cs[2], cs[3], -1.0, false, rg)
			if not A["engaged"]:
				continue
			var mth := 99.0
			for t in NT:
				mth = minf(mth, A["th"][t])
			print("  r%.2f/%.1ft %3d | %s  %6d %26.2f"
				% [cs[0], cs[1], rg,
				   ("YES" if A["recatch"] >= 0 else " no"),
				   A["recatch"], mth])
		print("")
	quit(0)
