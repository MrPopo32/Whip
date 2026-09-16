extends SceneTree
## THE DISMOUNT DRAG - the measurement.
##
## Runs on the real main.gd with ONE value changed after setup: the
## out-of-world safety-net teleport is pushed out of reach. That teleport fires mid-
## window on a body in free fall and silently resets the whole sim, which
## poisoned every late sample. Nothing else differs (diff --strip-trailing-cr
## reports exactly that one line). Moving the rig high up instead is NOT an
## option: past |y| ~ 40 m the float32 positions quantise the per-substep
## gravity increment (1.085e-5 m) away entirely. Run with `-- check` to see it.
##
## dV(t) = v_arm(t) - v_ideal(t). Gravity is identical in both, so dV IS the
## impulse the beam has delivered to the body since the hand opened.
##   RETRO   = component opposing the launch direction (+ = dragged backwards)
##   LAT     = component across it
##   TOBEAM  = component pointing straight back at the beam you just left
##
## ARMS, all sharing a bit-identical prefix and differing only at release:
##   A  shipped main.gd
##   D  the wrap's pin + static-mu window cleared BEFORE the release tick's
##      substeps instead of after them (isolates the one-tick-late clear)
##   B  D, plus anchor_mu = 0 (frictionless cylinder: pure unspool geometry)
##   C  beam teleported clear at the release instant (the ideal launch)
##   M  shipped, with anchor_mu forced to a given value at the release instant

const NT := 120        # 2.0 s. Past this the falling body's float32 y quantises
                       # gravity - see `-- check`.
const TAIL := 15       # ticks averaged to kill velocity-readout quantisation
const HZ := 30         # the gameplay horizon: 500 ms, about one beam-to-beam hop
const EPS := 0.06

func _rig(r: float, turns: float, swing_deg: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	# THE NET, PUSHED OUT OF REACH. This used to need tests/main_drag.gd, a
	# copy of main.gd with one line changed, which drifted 3600 lines behind
	# the game and measured a build that never shipped (no ALIGN, no payout
	# fix). world_bottom is a var derived from the terrain now, so the real
	# main.gd is loaded and the net moved after setup_sim() has derived it.
	m.world_bottom = 1.0e9
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -2.2); m.a_r[0] = r
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

## mode 0 A | 1 D | 2 B | 3 C | 4 M(mu)
func _run(r: float, turns: float, sd: float, hold: int, mode: int,
		mu: float, regrip_at: int) -> Dictionary:
	var m := _rig(r, turns, sd)
	for t in hold:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free()
		return {"engaged": false}
	var beam: Vector2 = m.a_pos[0]
	var out := {"engaged": true, "pin": m.a_pinidx[0], "locked": m.a_locked[0],
		"theta_rel": absf(m.a_theta[0]), "contacts_rel": _contacts(m),
		"static_rel": _static_pop(m), "beam": beam}
	var v0 := _bvel(m)
	out["v_rel"] = v0.length(); out["dir"] = v0.normalized()
	out["h_rel"] = rad_to_deg(v0.angle())
	if mode == 1 or mode == 2:
		m.a_freelen[0] = -1.0; m.a_pinidx[0] = -1
		m.a_locked[0] = -1; m.a_armed[0] = 0
	if mode == 2:
		m.anchor_mu = 0.0
	if mode == 3:
		m.a_pos[0] = Vector2(0.0, 900.0)
	if mode == 4:
		m.anchor_mu = mu
	var vx := PackedFloat32Array(); var vy := PackedFloat32Array()
	var bx := PackedFloat32Array(); var by := PackedFloat32Array()
	var spd := PackedFloat32Array(); var th := PackedFloat32Array()
	var con := PackedInt32Array(); var sta := PackedInt32Array()
	var recatch := -1
	var last_touch := -1
	for t in NT:
		var grip := regrip_at >= 0 and t >= regrip_at
		m.step_tick(m.body_pos, grip)
		var v := _bvel(m)
		vx.append(v.x); vy.append(v.y); spd.append(v.length())
		bx.append(m.body_pos.x); by.append(m.body_pos.y)
		var n := 0 if mode == 3 else _contacts(m)
		con.append(n); sta.append(_static_pop(m)); th.append(absf(m.a_theta[0]))
		if n > 0:
			last_touch = t
		if recatch < 0 and m.a_freelen[0] >= 0.0:
			recatch = t
	out["vx"] = vx; out["vy"] = vy; out["spd"] = spd; out["th"] = th
	out["bx"] = bx; out["by"] = by
	out["con"] = con; out["sta"] = sta
	out["last_touch"] = last_touch; out["recatch"] = recatch
	out["falls"] = m.falls
	m.free()
	return out

func _diff(X: Dictionary, C: Dictionary) -> Dictionary:
	var dir: Vector2 = X["dir"]
	var beam: Vector2 = X["beam"]
	var dvv := []
	for t in NT:
		dvv.append(Vector2(X["vx"][t] - C["vx"][t], X["vy"][t] - C["vy"][t]))
	var fin := Vector2.ZERO
	for t in range(NT - TAIL, NT):
		fin += dvv[t]
	fin /= float(TAIL)
	var mag := fin.length()
	var t50 := 0
	var t90 := 0
	var t95 := 0
	for t in NT:
		var l: float = (dvv[t] as Vector2).length()
		if l < 0.50 * mag:
			t50 = t + 1
		if l < 0.90 * mag:
			t90 = t + 1
		if l < 0.95 * mag:
			t95 = t + 1
	var vA := Vector2(X["vx"][HZ], X["vy"][HZ])
	var vC := Vector2(C["vx"][HZ], C["vy"][HZ])
	var pA := Vector2(X["bx"][HZ], X["by"][HZ])
	var pC := Vector2(C["bx"][HZ], C["by"][HZ])
	var to_beam := (beam - pA).normalized()
	return {"retro": -fin.dot(dir), "lat": absf(fin.cross(dir)), "mag": mag,
		"acting": t95, "t50": t50, "t90": t90,
		"loss_pct": 100.0 * (-fin.dot(dir)) / maxf(X["v_rel"], 0.001),
		"dspd_hz": vC.length() - vA.length(),
		"dhead_hz": rad_to_deg(vC.angle_to(vA)),
		"tobeam_hz": (dvv[HZ] as Vector2).dot(to_beam),
		"retro_hz": -(dvv[HZ] as Vector2).dot(dir),
		"pct_hz": 100.0 * (vC.length() - vA.length()) / maxf(X["v_rel"], 0.001),
		"short_hz": (pC - pA).length()}

func _initialize() -> void:
	var arg := "sweep"
	for a in OS.get_cmdline_user_args():
		arg = a
	match arg:
		"sweep": _sweep()
		"mu": _mu()
		"snag": _snag()
		"line": _line()
		"check": _check()
	quit(0)

# ------------------------------------------------------------------ 1. SWEEP --
func _sweep() -> void:
	print("=== DISMOUNT DRAG: the sweep ==================================")
	print("open air, no ground. Cursor parked on the body in every arm.")
	print("At 500 ms (about one beam-to-beam hop): dSPD = speed you are missing,")
	print("dHEAD = degrees your heading is bent, TOBEAM = m/s aimed straight back")
	print("at the beam you left, SHORT = metres behind the ideal launch you are.")
	print("")
	print("   r  trn hold| vrel   head |wrapT cnt sta pin lk|lastT| RETRO  %vrel   LAT | dSPD  dHEAD TOBEAM SHORT | t50 t90 ACT | D_RET B_RET")
	var rows: Array = []
	for sd in [80.0, -80.0]:
		for r in [0.10, 0.11, 0.20, 0.22]:
			for turns in [1.2, 1.6, 2.0, 2.4]:
				for hold in [35, 45, 55, 65, 75, 85]:
					var A := _run(r, turns, sd, hold, 0, 0.0, -1)
					if not A["engaged"]:
						continue
					var C := _run(r, turns, sd, hold, 3, 0.0, -1)
					var D := _run(r, turns, sd, hold, 1, 0.0, -1)
					var B := _run(r, turns, sd, hold, 2, 0.0, -1)
					if A["falls"] > 0 or C["falls"] > 0:
						continue
					var da := _diff(A, C)
					var dd := _diff(D, C)
					var db := _diff(B, C)
					var row := {"r": r, "turns": turns, "hold": hold, "sd": sd,
						"v_rel": A["v_rel"], "h_rel": A["h_rel"],
						"turnsOn": A["theta_rel"] / TAU,
						"cnt": A["contacts_rel"], "sta": A["static_rel"],
						"pin": A["pin"], "lk": A["locked"],
						"lastT": A["last_touch"], "recatch": A["recatch"],
						"retro": da["retro"], "lat": da["lat"],
						"pct": da["loss_pct"], "t50": da["t50"],
						"t90": da["t90"], "act": da["acting"],
						"dspd": da["dspd_hz"], "dhead": da["dhead_hz"],
						"tobeam": da["tobeam_hz"], "short": da["short_hz"],
						"D_retro": dd["retro"], "D_dspd": dd["dspd_hz"],
						"B_retro": db["retro"], "B_dspd": db["dspd_hz"],
						"B_act": db["acting"], "retro_hz": da["retro_hz"],
						"pct_hz": da["pct_hz"], "B_pct": db["pct_hz"],
						"D_pct": dd["pct_hz"],
						"stuck": 1.0 if A["last_touch"] >= NT - 1 else 0.0}
					rows.append(row)
					print("%5.2f %3.1f %3d| %5.2f %+6.1f |%5.2f %3d %3d %3d %2d |%4d |%+6.2f %+6.0f %5.2f |%+5.2f %+6.1f %+6.2f %5.2f | %3d %3d %3d | %+5.2f %+5.2f"
						% [r, turns, hold, row["v_rel"], row["h_rel"],
						   row["turnsOn"], row["cnt"], row["sta"], row["pin"],
						   row["lk"], row["lastT"], row["retro"], row["pct"],
						   row["lat"], row["dspd"], row["dhead"], row["tobeam"],
						   row["short"], row["t50"], row["t90"], row["act"],
						   row["D_retro"], row["B_retro"]])
	_summary(rows)

func _summary(rows: Array) -> void:
	print("")
	print("--- distribution over %d dismounts ----------------------------" % rows.size())
	print("  AT THE 500 ms HORIZON - about one beam-to-beam hop after the hand opens.")
	_st(rows, "dspd",    "speed you are missing (m/s)")
	_st(rows, "D_dspd",  "  ... with the pin+static-mu precleared")
	_st(rows, "B_dspd",  "  ... on a FRICTIONLESS beam (geometry only)")
	_st(rows, "pct_hz",  "  ... as a percent of your release speed")
	_st(rows, "B_pct",   "  ... frictionless, as a percent")
	_st(rows, "retro_hz","m/s taken straight off your launch direction")
	_st(rows, "tobeam",  "m/s aimed back AT the beam you left")
	_st(rows, "dhead",   "heading bent (deg)")
	_st(rows, "short",   "metres short of the ideal launch")
	print("")
	print("  OVER THE WHOLE 2 s WINDOW (dominated by the wraps that never come off;")
	print("  read alongside `never left the beam` below, not on its own).")
	_st(rows, "retro",   "settled RETRO (m/s)")
	_st(rows, "lat",     "settled SIDEWAYS (m/s)")
	print("")
	_st(rows, "t50",     "ticks to half the drag impulse")
	_st(rows, "t90",     "ticks to 90 percent of it")
	_st(rows, "act",     "ticks the rope keeps acting on you")
	_st(rows, "B_act",   "  ... on a frictionless beam")
	_st(rows, "lastT",   "ticks until the LAST particle leaves the beam")
	var stuck := 0
	for r: Dictionary in rows:
		if r["stuck"] > 0.5:
			stuck += 1
	print("  never left the beam inside the 2 s window: %d / %d" % [stuck, rows.size()])
	print("")
	_st(rows, "v_rel",   "release speed (m/s)")
	_st(rows, "cnt",     "particles on the beam at release")
	_st(rows, "sta",     "particles under STATIC mu on the release tick")
	_st(rows, "turnsOn", "measured turns still on the beam at release")
	var rc := 0
	for r: Dictionary in rows:
		if r["recatch"] >= 0:
			rc += 1
	print("  re-caught the beam it just left (hand stays open): %d / %d" % [rc, rows.size()])
	print("")
	print("--- what drives it --------------------------------------------")
	for rr in [0.10, 0.11, 0.20, 0.22]:
		_slice(rows, "r", rr, "beam radius %.2f m" % rr)
	print("")
	for tt in [1.2, 1.6, 2.0, 2.4]:
		_slice(rows, "turns", tt, "%.1f turns rigged" % tt)
	print("")
	for hh in [35, 45, 55, 65, 75, 85]:
		_slice(rows, "hold", float(hh), "release phase: %d ticks of swing" % hh)
	print("")
	_bucket(rows, "cnt", [0, 6, 10, 14, 30], "particles on the beam at release")
	_bucket(rows, "v_rel", [0.0, 3.5, 4.5, 5.5, 99.0], "release speed (m/s)")

func _slice(rows: Array, key: String, val: float, label: String) -> void:
	var v: Array = []
	var lt: Array = []
	var ac: Array = []
	var ds: Array = []
	for r: Dictionary in rows:
		if absf(float(r[key]) - val) < 0.001:
			v.append(float(r["retro"])); lt.append(float(r["lastT"]))
			ac.append(float(r["act"])); ds.append(float(r["dspd"]))
	if v.is_empty():
		return
	v.sort(); lt.sort(); ac.sort(); ds.sort()
	print("  %-32s n=%2d | RETRO med %6.2f max %6.2f | @500ms dSPD med %5.2f max %5.2f | lastTouch med %3.0f max %3.0f | acting med %3.0f"
		% [label, v.size(), v[v.size() / 2], v[v.size() - 1],
		   ds[ds.size() / 2], ds[ds.size() - 1],
		   lt[lt.size() / 2], lt[lt.size() - 1], ac[ac.size() / 2]])

func _bucket(rows: Array, key: String, edges: Array, label: String) -> void:
	print("  binned by %s:" % label)
	for e in range(edges.size() - 1):
		var lo: float = edges[e]
		var hi: float = edges[e + 1]
		var v: Array = []
		var lt: Array = []
		for r: Dictionary in rows:
			var x := float(r[key])
			if x >= lo and x < hi:
				v.append(float(r["retro"])); lt.append(float(r["lastT"]))
		if v.is_empty():
			continue
		v.sort(); lt.sort()
		print("    %6.1f - %-6.1f n=%2d | RETRO med %6.2f max %6.2f | lastTouch med %3.0f max %3.0f"
			% [lo, hi, v.size(), v[v.size() / 2], v[v.size() - 1],
			   lt[lt.size() / 2], lt[lt.size() - 1]])

func _st(rows: Array, key: String, label: String) -> void:
	var v: Array = []
	for r: Dictionary in rows:
		v.append(float(r[key]))
	v.sort()
	var s := 0.0
	for x: float in v:
		s += x
	print("  %-44s min %7.2f med %7.2f mean %7.2f p90 %7.2f max %7.2f"
		% [label, v[0], v[v.size() / 2], s / v.size(),
		   v[mini(int(v.size() * 0.9), v.size() - 1)], v[v.size() - 1]])

# --------------------------------------------------------------------- 2. MU --
func _mu() -> void:
	print("=== IS THE DRAG FRICTION, OR GEOMETRY? ========================")
	print("anchor_mu - the KINETIC coefficient a DISENGAGED beam uses; 0.40 ships -")
	print("is forced at the release instant. Nothing else changes.")
	print("")
	print("  case               mu | RETRO  LAT  |dV| | @500ms dSPD dHEAD TOBEAM | t90 acting lastTouch")
	for cs: Array in [[0.10, 2.0, 80.0, 45], [0.11, 2.0, 80.0, 45],
			[0.11, 1.6, 80.0, 55], [0.10, 2.4, 80.0, 55],
			[0.20, 2.0, 80.0, 45], [0.22, 1.6, 80.0, 45]]:
		var C := _run(cs[0], cs[1], cs[2], cs[3], 3, 0.0, -1)
		if not C["engaged"]:
			continue
		for mu in [0.40, 0.30, 0.20, 0.15, 0.10, 0.05, 0.02, 0.0]:
			var A := _run(cs[0], cs[1], cs[2], cs[3], 4, mu, -1)
			var d := _diff(A, C)
			print("  r%.2f %.1ft h%-3d %.2f |%+6.2f %5.2f %5.2f |%+6.2f %+6.1f %+6.2f | %3d %5d %8d"
				% [cs[0], cs[1], cs[3], mu, d["retro"], d["lat"], d["mag"],
				   d["dspd_hz"], d["dhead_hz"], d["tobeam_hz"], d["t90"],
				   d["acting"], A["last_touch"]])
		print("")

# ------------------------------------------------------------------- 3. SNAG --
func _snag() -> void:
	print("=== CAN THE BEAM YOU JUST LEFT TAKE THE ROPE AGAIN? ===========")
	print("The hand opens at t=0 and closes again at t=REGRIP - the player reaching")
	print("for the NEXT beam. Release sets a_armed=0, so re-engaging the OLD beam")
	print("needs theta to fall under th_rel=1.80 rad and then climb back over")
	print("th_part=3.40 rad (or produce a self-crossing) inside GRIP_WINDOW=15")
	print("ticks of that new press.")
	print("")
	print("  case              regrip | re-engaged?  tick | min theta | re-armed at | max theta once re-armed")
	var yes := 0
	var tot := 0
	for cs: Array in [[0.10, 1.2, 80.0, 45], [0.10, 1.6, 80.0, 45],
			[0.10, 2.0, 80.0, 45], [0.10, 2.4, 80.0, 55],
			[0.11, 1.6, 80.0, 45], [0.11, 2.0, 80.0, 55],
			[0.11, 2.4, -80.0, 45], [0.20, 1.6, 80.0, 55],
			[0.20, 2.0, 80.0, 45], [0.22, 2.0, 80.0, 45],
			[0.22, 1.6, 80.0, 65], [0.22, 2.4, -80.0, 55]]:
		for rg in [2, 4, 6, 8, 10, 12, 15, 20, 30, 45, 60]:
			var A := _run(cs[0], cs[1], cs[2], cs[3], 0, 0.0, rg)
			if not A["engaged"]:
				continue
			tot += 1
			var mth := 99.0
			var armed_at := -1
			var post := 0.0
			for t in NT:
				var th: float = A["th"][t]
				mth = minf(mth, th)
				if armed_at < 0 and th < 1.80:
					armed_at = t
				if armed_at >= 0:
					post = maxf(post, th)
			if A["recatch"] >= 0:
				yes += 1
			print("  r%.2f %.1ft h%-3d rg%-3d | %s %5d | %8.2f | %11d | %.2f"
				% [cs[0], cs[1], cs[3], rg,
				   ("  YES" if A["recatch"] >= 0 else "   no"), A["recatch"],
				   mth, armed_at, post])
	print("")
	print("  re-engaged the beam it had just left: %d / %d" % [yes, tot])

# ------------------------------------------------------------------- 4. LINE --
func _line() -> void:
	print("=== TICK BY TICK ==============================================")
	for cs: Array in [[0.11, 2.0, 80.0, 45], [0.10, 2.0, 80.0, 45],
			[0.11, 1.6, 80.0, 55], [0.22, 1.6, 80.0, 45]]:
		var A := _run(cs[0], cs[1], cs[2], cs[3], 0, 0.0, -1)
		var C := _run(cs[0], cs[1], cs[2], cs[3], 3, 0.0, -1)
		if not A["engaged"]:
			continue
		var dir: Vector2 = A["dir"]
		var beam: Vector2 = A["beam"]
		var d := _diff(A, C)
		print("beam r=%.2f  %.1f turns rigged  release %.2f m/s heading %+.0f deg  wrap %.2f turns  %d particles on the beam (%d under STATIC mu)"
			% [cs[0], cs[1], A["v_rel"], A["h_rel"], A["theta_rel"] / TAU,
			   A["contacts_rel"], A["static_rel"]])
		print("   ms  cnt  wrapTurns  speed  ideal   RETRO    LAT  TOBEAM")
		for t in range(0, NT):
			if t > 36 and t % 6 != 0:
				continue
			var dv := Vector2(A["vx"][t] - C["vx"][t], A["vy"][t] - C["vy"][t])
			var tb := (beam - Vector2(A["bx"][t], A["by"][t])).normalized()
			print("  %4.0f  %3d    %5.2f    %5.2f  %5.2f  %+6.2f %6.2f  %+6.2f"
				% [(t + 1) * 1000.0 / 60.0, A["con"][t], A["th"][t] / TAU,
				   A["spd"][t], C["spd"][t], -dv.dot(dir), absf(dv.cross(dir)),
				   dv.dot(tb)])
		print("  -> %.2f m/s dragged back (%.0f%% of the launch), %.2f m/s sideways."
			% [d["retro"], d["loss_pct"], d["lat"]])
		print("     at 500 ms: %.2f m/s of speed missing, heading bent %+.1f deg, %.2f m/s aimed back at the beam, %.2f m short."
			% [d["dspd_hz"], d["dhead_hz"], d["tobeam_hz"], d["short_hz"]])
		print("     half the impulse by %.0f ms, 90%% by %.0f ms, done at %.0f ms; last contact %.0f ms."
			% [d["t50"] * 1000.0 / 60.0, d["t90"] * 1000.0 / 60.0,
			   d["acting"] * 1000.0 / 60.0, (A["last_touch"] + 1) * 1000.0 / 60.0])
		print("")

# ------------------------------------------------------ 0. PRECISION CHECK --
func _check() -> void:
	print("=== FLOAT32 PRECISION: how long is the window good for? =======")
	print("ideal (beam-removed) arm. expected dVy per tick = g*DT = 0.16667 m/s")
	print("  tick    ms   body y     dVy/tick   err ppm   ulp(y)*1e9  g-step/ulp")
	var C := _run(0.11, 1.6, 80.0, 45, 3, 0.0, -1)
	for t in [1, 20, 40, 60, 80, 100, 119]:
		if t >= NT:
			continue
		var dvy: float = C["vy"][t] - C["vy"][t - 1]
		var y: float = C["by"][t]
		var ulp: float = maxf(absf(y), 1.0) * pow(2.0, -23.0)
		print("  %4d %5.0f  %8.2f   %10.6f  %8.0f  %10.3f   %8.1f"
			% [t, t * 1000.0 / 60.0, y, dvy,
			   1e6 * absf(dvy - 10.0 / 60.0) / (10.0 / 60.0), ulp * 1e9,
			   1.085e-5 / ulp])
