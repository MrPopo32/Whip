extends SceneTree
## THE DISMOUNT DRAG, part 2.
##
## Same four arms, but the headline metric is now the VELOCITY DIFFERENCE
## VECTOR against the ideal launch:  dV(t) = v_arm(t) - v_clear(t).
## Gravity is identical in both, so dV is exactly the impulse the beam has
## delivered to the body since the hand opened. When dV stops changing, the
## rope has stopped acting on you. That instant is the number the report wants.
##
## dV is resolved into the release heading:
##   RETRO = component opposing the direction you launched (being pulled back)
##   LAT   = component across it (heading bent)

const NT := 240
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

func _bvel(m: Node2D) -> Vector2:
	return (m.body_pos - m.body_prv) / m.SDT

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

## mode: 0 A real | 1 D preclear | 2 B preclear+slick | 3 C beam removed
##       4 = A but anchor_mu forced to `mu_free` from the release tick on
func _arm(r: float, turns: float, swing_deg: float, hold: int, mode: int,
		regrip_at: int, mu_free: float) -> Dictionary:
	var m := _rig(r, turns, swing_deg)
	for t in hold:
		m.step_tick(m.body_pos, true)
	var out := {}
	if m.a_freelen[0] < 0.0:
		out["engaged"] = false
		m.free()
		return out
	out["engaged"] = true
	out["pin"] = m.a_pinidx[0]
	out["locked"] = m.a_locked[0]
	out["theta_rel"] = absf(m.a_theta[0])
	out["contacts_rel"] = _contacts(m)
	out["static_rel"] = _static_pop(m)
	var v0 := _bvel(m)
	out["v_rel"] = v0.length()
	out["dir"] = v0.normalized()
	out["h_rel"] = rad_to_deg(v0.angle())

	if mode == 1 or mode == 2:
		m.a_freelen[0] = -1.0; m.a_pinidx[0] = -1
		m.a_locked[0] = -1; m.a_armed[0] = 0
	if mode == 2:
		m.anchor_mu = 0.0
	if mode == 3:
		m.a_pos[0] = Vector2(0.0, 900.0)
	if mode == 4:
		m.anchor_mu = mu_free

	var vx := PackedFloat32Array(); var vy := PackedFloat32Array()
	var con := PackedInt32Array(); var sta := PackedInt32Array()
	var recatch := -1
	var last_touch := -1
	for t in NT:
		var grip := regrip_at >= 0 and t >= regrip_at
		m.step_tick(m.body_pos, grip)
		var v := _bvel(m)
		vx.append(v.x); vy.append(v.y)
		var n := _contacts(m) if mode != 3 else 0
		con.append(n)
		sta.append(_static_pop(m))
		if n > 0:
			last_touch = t
		if recatch < 0 and m.a_freelen[0] >= 0.0:
			recatch = t
	out["vx"] = vx; out["vy"] = vy; out["con"] = con; out["sta"] = sta
	out["last_touch"] = last_touch; out["recatch"] = recatch
	m.free()
	return out

func _diff(X: Dictionary, C: Dictionary, dir: Vector2) -> Dictionary:
	var dv := []
	for t in NT:
		dv.append(Vector2(X["vx"][t] - C["vx"][t], X["vy"][t] - C["vy"][t]))
	var fin: Vector2 = dv[NT - 1]
	var mag: float = fin.length()
	var t50 := -1
	var t90 := -1
	for t in NT:
		var l: float = (dv[t] as Vector2).length()
		if t50 < 0 and l >= 0.50 * mag:
			t50 = t
		if t90 < 0 and l >= 0.90 * mag:
			t90 = t
	# the rope has stopped acting when dV stops changing (< 1 cm/s per tick)
	var acting := 0
	for t in range(NT - 1, 0, -1):
		if ((dv[t] as Vector2) - (dv[t - 1] as Vector2)).length() > 0.01:
			acting = t + 1
			break
	return {
		"retro": -fin.dot(dir),                     # + = pulled backwards
		"lat": absf(fin.cross(dir)),
		"mag": mag,
		"bend": rad_to_deg(Vector2(C["vx"][NT - 1], C["vy"][NT - 1])
			.angle_to(Vector2(X["vx"][NT - 1], X["vy"][NT - 1]))),
		"t50": t50, "t90": t90, "acting": acting,
		"dvspd_30": sqrt(C["vx"][29] * C["vx"][29] + C["vy"][29] * C["vy"][29])
			- sqrt(X["vx"][29] * X["vx"][29] + X["vy"][29] * X["vy"][29]),
	}

func _case(r: float, turns: float, sd: float, hold: int) -> Dictionary:
	var A := _arm(r, turns, sd, hold, 0, -1, 0.0)
	if not A["engaged"]:
		return {"engaged": false}
	var C := _arm(r, turns, sd, hold, 3, -1, 0.0)
	var D := _arm(r, turns, sd, hold, 1, -1, 0.0)
	var B := _arm(r, turns, sd, hold, 2, -1, 0.0)
	var dir: Vector2 = A["dir"]
	var res := {"engaged": true, "r": r, "turns": turns, "hold": hold,
		"v_rel": A["v_rel"], "h_rel": A["h_rel"], "theta_rel": A["theta_rel"],
		"contacts_rel": A["contacts_rel"], "static_rel": A["static_rel"],
		"pin": A["pin"], "locked": A["locked"], "last_touch": A["last_touch"],
		"recatch": A["recatch"]}
	res["A"] = _diff(A, C, dir)
	res["D"] = _diff(D, C, dir)
	res["B"] = _diff(B, C, dir)
	return res

func _initialize() -> void:
	print("=== DISMOUNT DRAG 2 : the impulse after you let go ==============")
	print("dV = body velocity minus the ideal (beam removed) launch.")
	print("RETRO = m/s taken off along your launch direction (+ = pulled back)")
	print("LAT   = m/s across it.   ACT = last tick dV was still moving.")
	print("")
	var rows: Array = []
	print("  r  turns hold | vrel  head | turnsOn cont stat pin lk | lastTouch | A:RETRO   LAT  bend  ACT t50 t90 | D:RETRO ACT | B:RETRO ACT")
	for sd in [80.0, -80.0]:
		for r in [0.10, 0.11, 0.20, 0.22]:
			for turns in [1.2, 1.6, 2.0, 2.4]:
				for hold in [35, 45, 55, 65, 75, 85]:
					var res := _case(r, turns, sd, hold)
					if not res["engaged"]:
						continue
					rows.append(res)
					var a: Dictionary = res["A"]
					var d: Dictionary = res["D"]
					var b: Dictionary = res["B"]
					print("%5.2f %4.1f  %2d | %5.2f %+6.1f | %6.2f  %2d   %2d  %2d %2d | %5d | %+7.2f %5.2f %+6.1f %4d %3d %3d | %+6.2f %4d | %+6.2f %4d"
						% [r, turns, hold, res["v_rel"], res["h_rel"],
						   res["theta_rel"] / TAU, res["contacts_rel"],
						   res["static_rel"], res["pin"], res["locked"],
						   res["last_touch"],
						   a["retro"], a["lat"], a["bend"], a["acting"], a["t50"], a["t90"],
						   d["retro"], d["acting"], b["retro"], b["acting"]])
	_summarize(rows)
	quit(0)

func _summarize(rows: Array) -> void:
	print("")
	print("--- distribution over %d releases -----------------------------" % rows.size())
	_st(rows, "A", "retro", "SPEED PULLED BACK, shipped build (m/s)")
	_st(rows, "D", "retro", "  ... with the pin+static mu precleared")
	_st(rows, "B", "retro", "  ... with a FRICTIONLESS beam (geometry only)")
	_st(rows, "A", "lat",   "SIDEWAYS kick, shipped (m/s)")
	_st(rows, "A", "bend",  "HEADING BENT, shipped (deg)")
	_st(rows, "A", "acting","TICKS the rope is still acting on you")
	_st(rows, "B", "acting","  ... frictionless beam")
	_st(rows, "A", "t50",   "ticks to half the total drag impulse")
	_st(rows, "A", "t90",   "ticks to 90% of it")
	_flat(rows, "last_touch", "ticks until the LAST particle leaves the beam")
	_flat(rows, "v_rel", "release speed (m/s)")
	_flat(rows, "contacts_rel", "particles on the beam at release")
	_flat(rows, "static_rel", "particles under STATIC mu on the release tick")

func _st(rows: Array, arm: String, key: String, label: String) -> void:
	var v: Array = []
	for r: Dictionary in rows:
		v.append(float((r[arm] as Dictionary)[key]))
	_emit(v, label)

func _flat(rows: Array, key: String, label: String) -> void:
	var v: Array = []
	for r: Dictionary in rows:
		v.append(float(r[key]))
	_emit(v, label)

func _emit(v: Array, label: String) -> void:
	v.sort()
	var s := 0.0
	for x: float in v:
		s += x
	var p90: float = v[mini(int(v.size() * 0.9), v.size() - 1)]
	print("  %-44s min %7.2f med %7.2f mean %7.2f p90 %7.2f max %7.2f"
		% [label, v[0], v[v.size() / 2], s / v.size(), p90, v[v.size() - 1]])
