extends SceneTree
## IS THE POST-RELEASE DRAG REAL, AND HOW BIG IS IT?
##
## Releasing is already immediate in the LOGIC: a_freelen, a_pinidx and
## a_locked all clear on the tick the hand opens. The claim under test is
## PHYSICAL: at that instant the chain is still coiled a turn or two round the
## beam, and it has to unspool over the beam surface before the body is
## actually free.
##
## THE EXPERIMENT. The sim is deterministic, so identical scripted input gives
## bit-identical state up to any tick. Run each throw twice:
##
##   KEEP     throw, catch, hang, swing, open the hand at T. Beam stays.
##   CONTROL  bit-identical up to T; at T the beam is DELETED.
##
## From T onward the ONLY difference between the two worlds is whether the beam
## is there to act on a chain the player has already let go of. The divergence
## IS the drag, with no modelling assumption at all.
##
## CONTROL is also the CEILING: it is exactly what "let the rope pass through
## the beam once disengaged" would buy. No honest change can beat it.
##
## Variants answer WHERE the drag comes from, on the same corpus:
##   mu 0.15 / mu 0.00  beam kept, anchor_mu lowered at the release tick only

const HANG_MIN := 40
const HANG_MAX := 140
const POST := 90

var BUILD := "res://main.gd"

func _rig(dx: float, dy: float, r: float) -> Node2D:
	var m: Node2D = load(BUILD).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in range(m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 5000.0)
	m.a_pos[0] = Vector2(dx, -dy)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R)
	m.body_prv = m.body_pos
	for i in range(m.pos.size()):
		var p := Vector2(0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p
		m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

func _tgt(m: Node2D, t: int, c: Array, caught: bool) -> Vector2:
	var b: Vector2 = m.body_pos
	if caught:
		var d: Vector2 = m.a_pos[0] - b
		if d.length() < 0.0001:
			d = Vector2(0.0, -1.0)
		return b + d.normalized() * m.REACH
	if t < 30:
		return b + Vector2(cos(c[3]), sin(c[3])) * m.REACH
	return b + Vector2(cos(c[4]), sin(c[4])) * m.REACH

func _contacts(m: Node2D, shell: float) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in range(m.pos.size()):
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + shell:
			n += 1
	return n

## mode 0 scout | 1 keep | 2 control (beam deleted) | 3 mu=0 | 4 mu=0.15
func _run(c: Array, mode: int, t_rel: int) -> Dictionary:
	var m := _rig(c[0], c[1], c[2])
	var caught_at := -1
	var grip := false
	var vx := PackedFloat32Array()
	var tx := PackedFloat32Array()
	var ty := PackedFloat32Array()
	var tvx := PackedFloat32Array()
	var tvy := PackedFloat32Array()
	var still_on := 0
	var lim: int = (t_rel + POST) if t_rel >= 0 else (30 + HANG_MAX + 80)
	var out := {}
	var th_rel_state := 0.0
	var nc_rel := 0
	var lock_rel := -1
	var spd_rel := 0.0
	for t in range(lim):
		if not grip and absf(m.a_theta[0]) >= m.th_part:
			grip = true
		if t == t_rel:
			th_rel_state = absf(m.a_theta[0])
			nc_rel = _contacts(m, 0.02)
			lock_rel = m.a_locked[0]
			spd_rel = ((m.body_pos - m.body_prv) / m.SDT).length()
			if mode == 2:
				m.a_pos[0] = Vector2(0.0, 5000.0)
			elif mode == 3:
				m.anchor_mu = 0.0
			elif mode == 4:
				m.anchor_mu = 0.15
		var hold: bool = grip and (t_rel < 0 or t < t_rel)
		m.step_tick(_tgt(m, t, c, caught_at >= 0), hold)
		if caught_at < 0 and m.a_freelen[0] >= 0.0:
			caught_at = t
		vx.append(((m.body_pos.x - m.body_prv.x) / m.SDT) if caught_at >= 0 else -99.0)
		if t_rel >= 0 and t >= t_rel:
			tx.append(m.body_pos.x)
			ty.append(m.body_pos.y)
			tvx.append((m.body_pos.x - m.body_prv.x) / m.SDT)
			tvy.append((m.body_pos.y - m.body_prv.y) / m.SDT)
			if mode != 2 and _contacts(m, 0.02) > 0:
				still_on = t - t_rel + 1
	out["caught_at"] = caught_at
	if t_rel < 0:
		var best := -1
		var bv := -1e9
		if caught_at >= 0:
			for t in range(caught_at + HANG_MIN, mini(caught_at + HANG_MAX, vx.size())):
				if vx[t] > bv:
					bv = vx[t]
					best = t
		out["t_rel"] = best
		out["vrel"] = bv
	else:
		out["x"] = tx; out["y"] = ty; out["vx"] = tvx; out["vy"] = tvy
		out["still_on"] = still_on
		out["theta"] = th_rel_state
		out["nc"] = nc_rel
		out["locked"] = lock_rel
		out["speed"] = spd_rel
	m.free()
	return out

func _initialize() -> void:
	var env := OS.get_environment("WHIP_BUILD")
	if env != "":
		BUILD = env
	var cfgs := []
	for r in [0.10, 0.11, 0.20, 0.22]:
		for dy in [2.0, 2.2]:
			for dx in [1.8, 2.1, 2.4]:
				for a1 in [-0.34, -0.26]:
					cfgs.append([dx, dy, r, 0.85 * PI, a1 * PI])
	print("DRAG AFTER RELEASE - build %s" % BUILD)
	print("corpus: %d thrown catches, released at the swing's fastest forward tick"
		% cfgs.size())
	print("")
	var n := 0
	var s_nc := 0.0
	var s_turn := 0.0
	var s_on := 0.0
	var s15 := 0.0
	var s30 := 0.0
	var s90 := 0.0
	var s_xl := 0.0
	var s_pull := 0.0
	var w_pull := 0.0
	var w_xl := -1e9
	var s30_0 := 0.0
	var sxl_0 := 0.0
	var s30_l := 0.0
	var sxl_l := 0.0
	var rows := []
	for c in cfgs:
		var s := _run(c, 0, -1)
		if int(s["caught_at"]) < 0 or int(s["t_rel"]) < 0:
			continue
		var t_rel: int = s["t_rel"]
		var keep := _run(c, 1, t_rel)
		var ctrl := _run(c, 2, t_rel)
		var mu0 := _run(c, 3, t_rel)
		var mul := _run(c, 4, t_rel)
		var kx: PackedFloat32Array = keep["x"]
		var ky: PackedFloat32Array = keep["y"]
		var cx: PackedFloat32Array = ctrl["x"]
		var cy: PackedFloat32Array = ctrl["y"]
		if kx.size() < POST or cx.size() < POST:
			continue
		var beam := Vector2(c[0], -c[1])
		var pull := 0.0
		for i in range(POST):
			var dv := Vector2(keep["vx"][i] - ctrl["vx"][i],
				keep["vy"][i] - ctrl["vy"][i])
			var tw := beam - Vector2(cx[i], cy[i])
			if tw.length() > 0.0001:
				pull = maxf(pull, dv.dot(tw.normalized()))
		var d15 := Vector2(kx[15] - cx[15], ky[15] - cy[15]).length()
		var d30 := Vector2(kx[30] - cx[30], ky[30] - cy[30]).length()
		var d90 := Vector2(kx[POST - 1] - cx[POST - 1],
			ky[POST - 1] - cy[POST - 1]).length()
		var xl: float = cx[POST - 1] - kx[POST - 1]
		n += 1
		s_nc += float(keep["nc"])
		s_turn += float(keep["theta"]) / TAU
		s_on += float(keep["still_on"])
		s15 += d15
		s30 += d30
		s90 += d90
		s_xl += xl
		s_pull += pull
		w_pull = maxf(w_pull, pull)
		w_xl = maxf(w_xl, xl)
		var m0x: PackedFloat32Array = mu0["x"]
		var m0y: PackedFloat32Array = mu0["y"]
		var mlx: PackedFloat32Array = mul["x"]
		var mly: PackedFloat32Array = mul["y"]
		s30_0 += Vector2(m0x[30] - cx[30], m0y[30] - cy[30]).length()
		sxl_0 += cx[POST - 1] - m0x[POST - 1]
		s30_l += Vector2(mlx[30] - cx[30], mly[30] - cy[30]).length()
		sxl_l += cx[POST - 1] - mlx[POST - 1]
		if rows.size() < 16:
			rows.append("  r%.2f (%.1f,-%.1f) | %.2f turns, %2d/26 on beam | stays %2d tk | drift %.3f m | fwd lost %+.3f m | pull %.2f m/s"
				% [c[2], c[0], c[1], float(keep["theta"]) / TAU, int(keep["nc"]),
				int(keep["still_on"]), d30, xl, pull])
	for r in rows:
		print(r)
	print("")
	print("=================================================================")
	print("  usable runs                                    %d" % n)
	if n == 0:
		quit(0)
		return
	print("  AT THE INSTANT THE HAND OPENS")
	print("    wrap still round the beam         %.2f turns" % (s_turn / n))
	print("    chain particles touching the beam %.1f of 26" % (s_nc / n))
	print("")
	print("  AFTER THE HAND OPENS  (vs the same world with the beam deleted)")
	print("    ticks the chain stays on the beam %.1f   (%.0f ms)"
		% [s_on / n, s_on / n * 1000.0 / 60.0])
	print("    body drift at +15 tk (250 ms)     %.3f m" % (s15 / n))
	print("    body drift at +30 tk (500 ms)     %.3f m" % (s30 / n))
	print("    body drift at +90 tk (1.5 s)      %.3f m" % (s90 / n))
	print("    forward distance lost at +90 tk   %+.3f m  (worst %+.3f m)"
		% [s_xl / n, w_xl])
	print("    peak velocity pulled BEAMWARD     %.2f m/s (worst %.2f m/s)"
		% [s_pull / n, w_pull])
	print("")
	print("  IS IT FRICTION?  anchor_mu changed at the release tick only")
	print("    drift@30 / fwd lost, mu 0.40      %.3f m / %+.3f m" % [s30 / n, s_xl / n])
	print("    drift@30 / fwd lost, mu 0.15      %.3f m / %+.3f m" % [s30_l / n, sxl_l / n])
	print("    drift@30 / fwd lost, mu 0.00      %.3f m / %+.3f m" % [s30_0 / n, sxl_0 / n])
	print("=================================================================")
	quit(0)
