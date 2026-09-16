extends SceneTree
## THE PUMP ENSEMBLE WITH A BELLY. bot_pump's four rigs lay the free span dead
## straight, so arc == chord and a tether rule that adds (arc - chord) cannot
## be seen by them. Here the same four rigs carry S metres of extra rope in
## the free span, laid as a circular arc bulging to +x (the player's median
## belly is 0.63 m of slack over a 3.14 m chord). Same chord, same body
## position, same wrap turns; the wrap simply starts S further along the
## chain. 41 starts a0 = 8.0000..8.0200 deg per rig, the table-2 bench.
##   godot --headless --path . -s res://tests/pump_belly.gd -- S=0.6
const PUMP := preload("res://tests/bot_pump.gd")

static func rig_belly(hang: float, r: float, turns: float, th0: float, S: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for kk in range(1, m.a_pos.size()):
		m.a_pos[kk] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0)
	m.a_r[0] = r
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.04
	var d := Vector2(sin(th0), cos(th0))
	var a_start: float = d.angle()
	var chord: float = hang - rr
	var L: float = chord + S
	var A: Vector2 = c + d * hang            # handle
	var B: Vector2 = c + d * rr              # first contact
	# circular arc from A to B with arc length L: L/chord = th/sin(th)
	var lo := 1e-6
	var hi := PI - 1e-3
	for it in 200:
		var mid := 0.5 * (lo + hi)
		if mid / sin(mid) < L / chord:
			lo = mid
		else:
			hi = mid
	var th := 0.5 * (lo + hi)
	var R: float = chord / (2.0 * sin(th))
	var n := Vector2(d.y, -d.x)             # bulge side
	if n.x < 0.0:
		n = -n
	var M: Vector2 = 0.5 * (A + B)
	var O: Vector2 = M - n * (R * cos(th))
	var phA: float = (A - O).angle()
	var phB: float = (B - O).angle()
	var dl: float = fposmod(phB - phA + PI, TAU) - PI
	var wl: float = turns * TAU * rr
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < L:
			p = O + Vector2(cos(phA + dl * s / L), sin(phA + dl * s / L)) * R
		elif s < L + wl:
			var a: float = a_start + (s - L) / rr
			p = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = a_start + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			p = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, s - L - wl)
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + d * (hang + 0.6)
	m.body_prv = m.body_pos
	return m

func bench(cfg: Array, a0_deg: float, S: float) -> Dictionary:
	var m: Node2D = rig_belly(cfg[0], cfg[1], cfg[2], deg_to_rad(a0_deg), S)
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free()
		return {}
	var out := {"tether": float(m.a_freelen[0]), "pin": int(m.a_pinidx[0]),
		"locked": int(m.a_locked[0])}
	var t_th: float = TAU * sqrt((float(m.a_freelen[0]) + PUMP.ARM_HANG) / 10.0)
	var prev_body: Vector2 = m.body_pos
	for t in 120:
		prev_body = m.body_pos
		m.step_tick(m.body_pos, true)
	out["depth"] = float(m.body_pos.y - m.a_pos[0].y)
	var pu = PUMP.Track.new()
	pu.period = t_th
	pu.start(m)
	for t in 600:
		var s: Dictionary = PUMP.swing_state(m, 0, prev_body)
		var c: Vector2 = PUMP.pump_cursor(m, 0, prev_body, 0.0, PUMP.LEAD_DEFAULT, true)
		prev_body = m.body_pos
		m.step_tick(c, true)
		if m.a_freelen[0] < 0.0:
			pu.lost = t
			break
		pu.feed(m, t, prev_body, s)
	out["over"] = pu.over
	out["lost"] = pu.lost
	out["amp"] = pu.amp(mini(599, pu.th.size() - 1))
	m.free()
	return out

func _initialize() -> void:
	var S := 0.6
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("S="):
			S = float(String(a).substr(2))
	var t0 := Time.get_ticks_msec()
	var N := 41
	var tot_over := 0
	var tot_lost := 0
	var tot_n := 0
	print("PUMP ENSEMBLE WITH A BELLY: S = %.2f m extra rope in the free span, %d starts a0 = 8.0000..8.0200 deg per rig" % [S, N])
	print("  hang  tether  pin lk  n_caught  over/n   lost/n   over median s   amp@10s median  depth@2s  lost s (list)")
	for cfg in PUMP.RIGS:
		var over := 0
		var lost := 0
		var n := 0
		var overs: Array = []
		var amps: Array = []
		var losts: Array = []
		var tether := 0.0
		var pin := 0
		var lk := 0
		var depth := 0.0
		for j in N:
			var b := bench(cfg, 8.0 + float(j) * 0.0005, S)
			if b.is_empty():
				continue
			n += 1
			tether = b["tether"]; pin = b["pin"]; lk = b["locked"]; depth = b["depth"]
			if int(b["over"]) >= 0:
				over += 1
				overs.append(float(b["over"]) / 60.0)
			if int(b["lost"]) >= 0:
				lost += 1
				losts.append("%.1f" % (float(b["lost"]) / 60.0))
			amps.append(float(b["amp"]))
		overs.sort(); amps.sort()
		print("  %.1f   %.3f  %2d  %2d   %2d/41    %2d/%2d    %2d/%2d    %6s          %6s        %6.3f    %s"
			% [cfg[0], tether, pin, lk, n, over, n, lost, n,
			("%.2f" % overs[overs.size() / 2]) if not overs.is_empty() else "-",
			("%.1f" % amps[amps.size() / 2]) if not amps.is_empty() else "-", depth,
			" ".join(losts)])
		tot_over += over; tot_lost += lost; tot_n += n
	print("  TOTAL over the top %d/%d   wraps lost %d/%d   (%.0f s)"
		% [tot_over, tot_n, tot_lost, tot_n, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
