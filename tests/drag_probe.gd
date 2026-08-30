extends SceneTree
## THE DISMOUNT DRAG.
## The hand opens. What does the rope do to you AFTER that, and for how long?
##
## Four arms run the SAME deterministic prefix (identical rig, identical swing,
## identical cursor policy) and differ only in what happens at the release tick:
##
##   A  REAL      - main.gd exactly as shipped.
##   D  PRECLEAR  - the wrap's pin + static-mu window are cleared BEFORE the
##                  release tick's substeps instead of after them. Beam still
##                  there, kinetic anchor_mu still there. Isolates the cost of
##                  clearing one tick late.
##   B  SLICK     - preclear AND anchor_mu = 0. Beam is still a solid cylinder
##                  the coil must geometrically pay off. Pure unspool geometry.
##   C  CLEAR     - the beam is teleported away at the release instant. The
##                  ideal launch. This is the control everything is measured
##                  against.
##
## Per tick after release we log: particles still touching the beam, body speed,
## body heading, and the divergence from C.

const NT := 150          # ticks logged after release
const EPS := 0.06        # m past the surface that still counts as "touching"

# ------------------------------------------------------------------- rigging --
func _rig(r: float, turns: float, swing_deg: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()          # open air, no ground
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)                 # park every other beam
	m.a_pos[0] = Vector2(0.0, -40.0); m.a_r[0] = r
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.04
	var hang := 2.0
	var rise: float = hang - rr
	var wl: float = turns * TAU * rr
	# hang direction: A = 0 is straight down (y-down), A raises the pendulum
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

# --------------------------------------------------------------- measurement --
func _contacts(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + EPS:
			n += 1
	return n

func _bvel(m: Node2D) -> Vector2:
	return (m.body_pos - m.body_prv) / m.SDT

## how many particles would take the STATIC (engaged-wrap) mu this tick
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

# ------------------------------------------------------------------ the swing --
## Build, engage the wrap, swing to the release tick. Returns the sim, ready to
## take its release tick. Identical for every arm.
func _swing(r: float, turns: float, swing_deg: float, hold: int) -> Node2D:
	var m := _rig(r, turns, swing_deg)
	for t in hold:
		m.step_tick(m.body_pos, true)
	return m

# --------------------------------------------------------------------- an arm --
## mode: 0 = A real, 1 = D preclear, 2 = B slick, 3 = C clear
func _arm(r: float, turns: float, swing_deg: float, hold: int, mode: int,
		regrip_at: int) -> Dictionary:
	var m := _swing(r, turns, swing_deg, hold)
	var out := {}
	out["engaged"] = m.a_freelen[0] >= 0.0
	if not out["engaged"]:
		m.free()
		return out
	out["pin"] = m.a_pinidx[0]
	out["locked"] = m.a_locked[0]
	out["theta_rel"] = absf(m.a_theta[0])
	out["contacts_rel"] = _contacts(m)
	out["static_rel"] = _static_pop(m)
	var v0 := _bvel(m)
	out["v_rel"] = v0.length()
	out["h_rel"] = rad_to_deg(v0.angle())
	out["p_rel"] = m.body_pos

	# ---- the release instant ------------------------------------------------
	if mode >= 1:
		# clear the wrap LOGICALLY before the substeps rather than after
		m.a_freelen[0] = -1.0
		m.a_pinidx[0] = -1
		m.a_locked[0] = -1
		m.a_armed[0] = 0
	if mode == 2:
		m.anchor_mu = 0.0
	if mode == 3:
		m.a_pos[0] = Vector2(0.0, 900.0)     # rope teleported clear of the beam

	var spd := PackedFloat32Array()
	var hed := PackedFloat32Array()
	var con := PackedInt32Array()
	var sta := PackedInt32Array()
	var px := PackedFloat32Array()
	var py := PackedFloat32Array()
	var recatch := -1
	var last_touch := -1
	for t in NT:
		var grip := regrip_at >= 0 and t >= regrip_at
		m.step_tick(m.body_pos, grip)
		var v := _bvel(m)
		spd.append(v.length())
		hed.append(rad_to_deg(v.angle()))
		var n := _contacts(m) if mode != 3 else 0
		con.append(n)
		sta.append(_static_pop(m))
		px.append(m.body_pos.x); py.append(m.body_pos.y)
		if n > 0:
			last_touch = t
		if recatch < 0 and m.a_freelen[0] >= 0.0:
			recatch = t
	out["spd"] = spd; out["hed"] = hed; out["con"] = con; out["sta"] = sta
	out["px"] = px; out["py"] = py
	out["last_touch"] = last_touch
	out["recatch"] = recatch
	m.free()
	return out

# ------------------------------------------------------------------------ run --
func _case(r: float, turns: float, swing_deg: float, hold: int,
		verbose: bool, regrip_at: int) -> Dictionary:
	var A := _arm(r, turns, swing_deg, hold, 0, regrip_at)
	if not A["engaged"]:
		return {"engaged": false}
	var D := _arm(r, turns, swing_deg, hold, 1, regrip_at)
	var B := _arm(r, turns, swing_deg, hold, 2, regrip_at)
	var C := _arm(r, turns, swing_deg, hold, 3, regrip_at)

	var res := {"engaged": true}
	res["v_rel"] = A["v_rel"]; res["h_rel"] = A["h_rel"]
	res["theta_rel"] = A["theta_rel"]; res["turns_rel"] = A["theta_rel"] / TAU
	res["contacts_rel"] = A["contacts_rel"]; res["static_rel"] = A["static_rel"]
	res["pin"] = A["pin"]; res["locked"] = A["locked"]
	res["last_touch"] = A["last_touch"]
	res["recatch"] = A["recatch"]

	# divergence from the ideal launch
	var arms := {"A": A, "D": D, "B": B}
	for key in arms.keys():
		var X: Dictionary = arms[key]
		var dv_max := 0.0
		var settle := -1
		for t in NT:
			var vx: float = X["px"][t]
			var dv: float = absf(X["spd"][t] - C["spd"][t])
			var dh: float = absf(X["hed"][t] - C["hed"][t])
			if dv > dv_max:
				dv_max = dv
		# distance between the two body trajectories, and when it stops growing
		var sep := PackedFloat32Array()
		for t in NT:
			sep.append(Vector2(X["px"][t] - C["px"][t],
				X["py"][t] - C["py"][t]).length())
		# "the rope stops acting" = separation growth falls under 1 mm/tick
		# and stays there
		var acting := 0
		for t in range(NT - 1, 0, -1):
			if sep[t] - sep[t - 1] > 0.001:
				acting = t + 1
				break
		res[key + "_acting"] = acting
		res[key + "_dv30"] = C["spd"][29] - X["spd"][29]
		res[key + "_dv60"] = C["spd"][59] - X["spd"][59]
		res[key + "_dh30"] = X["hed"][29] - C["hed"][29]
		res[key + "_dh60"] = X["hed"][59] - C["hed"][59]
		res[key + "_sep60"] = sep[59]
		res[key + "_dvmax"] = dv_max
		res[key + "_last"] = X["last_touch"]
	res["Cv30"] = C["spd"][29]
	res["Cv60"] = C["spd"][59]

	if verbose:
		print("   t  |  A contacts  static  Aspeed  Cspeed  dV    Ahead  Chead  dH")
		for t in range(0, 40):
			print("  %3d |     %2d        %2d    %6.2f  %6.2f  %+5.2f  %6.1f %6.1f %+6.1f"
				% [t, A["con"][t], A["sta"][t], A["spd"][t], C["spd"][t],
				   A["spd"][t] - C["spd"][t], A["hed"][t], C["hed"][t],
				   A["hed"][t] - C["hed"][t]])
	return res

func _initialize() -> void:
	print("=== THE DISMOUNT DRAG =========================================")
	print("open air, no ground. cursor parked on the body in every arm.")
	print("A=shipped  D=preclear(pin+static mu cleared before the substeps)")
	print("B=preclear+frictionless beam  C=beam removed (ideal launch)")
	print("")

	# ---- headline sweep ----
	print("--- sweep: beam radius x turns x release phase -----------------")
	print("r     turns swing hold | v_rel  head | wrapT cont stat pin lk | last | A_act A_dv30 A_dv60 A_dh60 | D_act D_dv60 | B_act B_dv60")
	var rows: Array = []
	for r in [0.10, 0.11, 0.20, 0.22]:
		for turns in [0.9, 1.2, 1.6, 2.0]:
			for hold in [40, 55, 70]:
				var res := _case(r, turns, 80.0, hold, false, -1)
				if not res["engaged"]:
					print("%.2f  %.1f   80   %2d | (wrap did not hold)" % [r, turns, hold])
					continue
				rows.append(res)
				print("%.2f  %.1f   80   %2d | %5.2f %+6.1f | %5.2f  %2d   %2d  %2d %2d | %4d | %4d %+6.2f %+6.2f %+7.1f | %4d %+6.2f | %4d %+6.2f"
					% [r, turns, hold, res["v_rel"], res["h_rel"],
					   res["turns_rel"], res["contacts_rel"], res["static_rel"],
					   res["pin"], res["locked"], res["last_touch"],
					   res["A_acting"], res["A_dv30"], res["A_dv60"], res["A_dh60"],
					   res["D_acting"], res["D_dv60"],
					   res["B_acting"], res["B_dv60"]])
	_summarize(rows)
	quit(0)

func _summarize(rows: Array) -> void:
	if rows.is_empty():
		return
	print("")
	print("--- distribution over %d releases ------------------------------" % rows.size())
	_stat(rows, "A_acting", "ticks the rope keeps acting (A vs C)")
	_stat(rows, "D_acting", "ticks the rope keeps acting (D preclear)")
	_stat(rows, "B_acting", "ticks the rope keeps acting (B slick)")
	_stat(rows, "last_touch", "last tick a particle touched the beam")
	_stat(rows, "A_dv60", "speed lost at +60 ticks (A)")
	_stat(rows, "D_dv60", "speed lost at +60 ticks (D)")
	_stat(rows, "B_dv60", "speed lost at +60 ticks (B)")
	_stat(rows, "A_dh60", "heading bend at +60 ticks (A, deg)")
	_stat(rows, "D_dh60", "heading bend at +60 ticks (D, deg)")
	_stat(rows, "A_sep60", "body displaced from ideal at +60 (m)")
	_stat(rows, "D_sep60", "body displaced from ideal at +60 (m)")
	_stat(rows, "v_rel", "release speed")
	_stat(rows, "Cv60", "ideal speed at +60")
	_stat(rows, "static_rel", "particles under STATIC mu on the release tick")
	_stat(rows, "contacts_rel", "particles touching the beam at release")
	var rc := 0
	for r: Dictionary in rows:
		if r["recatch"] >= 0:
			rc += 1
	print("  re-caught the same beam after release: %d / %d" % [rc, rows.size()])

func _stat(rows: Array, key: String, label: String) -> void:
	var v: Array = []
	for r: Dictionary in rows:
		v.append(float(r[key]))
	v.sort()
	var s := 0.0
	for x: float in v:
		s += x
	print("  %-46s min %7.2f  med %7.2f  mean %7.2f  max %7.2f"
		% [label, v[0], v[v.size() / 2], s / v.size(), v[v.size() - 1]])
