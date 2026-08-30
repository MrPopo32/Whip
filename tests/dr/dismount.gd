extends SceneTree
## THE DISMOUNT, MEASURED. A controlled corpus where the size of the coil is a
## dial, so "how much rope is round the beam" can be separated from "how hard
## the beam pulls you back after you let go".
##
##   rig -> settle -> PUMP to a real swing -> open the hand at the fastest
##   forward tick -> watch what the beam does to a body that has let go.
##
## Every run is executed four times from bit-identical state at the release
## tick T:
##   KEEP     the world as shipped
##   CONTROL  the beam is DELETED at T (the ceiling: what "let the rope pass
##            through the beam" would buy, and the definition of zero drag)
##   MU15     beam kept, anchor_mu 0.15 from T
##   MU00     beam kept, anchor_mu 0.00 from T
##
## The pump policy is tests/bot_pump.gd, unmodified.

const PUMP := preload("res://tests/bot_pump.gd")
const SETTLE := 60
const SWING := 320
const SCAN_FROM := 200
const POST := 90

var BUILD := "res://main.gd"

func _rig(hang: float, r: float, turns: float, th0: float) -> Node2D:
	var m: Node2D = load(BUILD).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for kk in range(1, m.a_pos.size()):
		m.a_pos[kk] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0)
	m.a_r[0] = r
	m.clear_anchors()
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.04
	var d := Vector2(sin(th0), cos(th0))
	var a_start: float = d.angle()
	var rise: float = hang - rr
	var wl: float = turns * TAU * rr
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + d * (hang - s)
		elif s < rise + wl:
			var a: float = a_start + (s - rise) / rr
			p = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = a_start + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			p = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, s - rise - wl)
		m.pos[i] = p
		m.prv[i] = p
	m.body_pos = c + d * (hang + 0.6)
	m.body_prv = m.body_pos
	return m

func _contacts(m: Node2D, shell: float) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in range(m.pos.size()):
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + shell:
			n += 1
	return n

## arc length of chain lying inside the contact shell: the rope that has to be
## paid back off the cylinder before the whip is really off the beam
func _coiled_len(m: Node2D, shell: float) -> float:
	var c: Vector2 = m.a_pos[0]
	var L := 0.0
	for i in range(m.pos.size() - 1):
		var a: bool = (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + shell
		var b: bool = (m.pos[i + 1] - c).length() < m.a_r[0] + m.p_rad[i + 1] + shell
		if a and b:
			L += m.rest[i]
		elif a or b:
			L += m.rest[i] * 0.5
	return L

## mode 0 scout | 1 keep | 2 control | 3 mu 0.00 | 4 mu 0.15
func _run(cfg: Array, mode: int, t_rel: int) -> Dictionary:
	var m := _rig(cfg[0], cfg[1], cfg[2], cfg[3])
	var prev: Vector2 = m.body_pos
	var vx := PackedFloat32Array()
	var tx := PackedFloat32Array()
	var ty := PackedFloat32Array()
	var tvx := PackedFloat32Array()
	var tvy := PackedFloat32Array()
	var tipx := PackedFloat32Array()
	var still_on := 0
	var out := {}
	var lim: int = (t_rel + POST) if t_rel >= 0 else SWING
	var th_rel := 0.0
	var nc_rel := 0
	var cl_rel := 0.0
	var lk_rel := -1
	var sp_rel := 0.0
	var held := true
	for t in range(lim):
		if t == t_rel:
			th_rel = absf(m.a_theta[0])
			nc_rel = _contacts(m, 0.02)
			cl_rel = _coiled_len(m, 0.02)
			lk_rel = m.a_locked[0]
			sp_rel = ((m.body_pos - m.body_prv) / m.SDT).length()
			if mode == 2:
				m.a_pos[0] = Vector2(0.0, 5000.0)
			elif mode == 3:
				m.anchor_mu = 0.0
			elif mode == 4:
				m.anchor_mu = 0.15
		var hold: bool = (t_rel < 0 or t < t_rel)
		var cur: Vector2 = m.body_pos
		if t >= SETTLE and hold and m.a_freelen[0] >= 0.0:
			cur = PUMP.pump_cursor(m, 0, prev, 55.0)
		prev = m.body_pos
		m.step_tick(cur, hold)
		if m.a_freelen[0] < 0.0 and hold:
			held = false
		vx.append((m.body_pos.x - m.body_prv.x) / m.SDT)
		if t_rel >= 0 and t >= t_rel:
			tx.append(m.body_pos.x)
			ty.append(m.body_pos.y)
			tvx.append((m.body_pos.x - m.body_prv.x) / m.SDT)
			tvy.append((m.body_pos.y - m.body_prv.y) / m.SDT)
			tipx.append(m.pos[m.NP - 1].x)
			if mode != 2 and _contacts(m, 0.02) > 0:
				still_on = t - t_rel + 1
	out["held"] = held
	if t_rel < 0:
		var best := -1
		var bv := -1e9
		for t in range(SCAN_FROM, vx.size()):
			if vx[t] > bv:
				bv = vx[t]
				best = t
		out["t_rel"] = best
		out["vrel"] = bv
	else:
		out["x"] = tx; out["y"] = ty; out["vx"] = tvx; out["vy"] = tvy
		out["tipx"] = tipx
		out["still_on"] = still_on
		out["theta"] = th_rel
		out["nc"] = nc_rel
		out["coil"] = cl_rel
		out["locked"] = lk_rel
		out["speed"] = sp_rel
	m.free()
	return out

func _initialize() -> void:
	var env := OS.get_environment("WHIP_BUILD")
	if env != "":
		BUILD = env
	var cfgs := []
	for hang in [1.2, 2.0, 2.8]:
		for r in [0.10, 0.11, 0.20, 0.22]:
			for turns in [0.9, 1.2, 1.6, 2.0]:
				cfgs.append([hang, r, turns, 0.35])
	print("THE DISMOUNT - build %s" % BUILD)
	print("%d rigs: hang x beam radius x turns, pumped to a 55 deg swing," % cfgs.size())
	print("hand opened at the fastest forward tick, then measured for 1.5 s.")
	print("")
	var n := 0
	var s_turn := 0.0
	var s_nc := 0.0
	var s_coil := 0.0
	var s_on := 0.0
	var s15 := 0.0
	var s30 := 0.0
	var s90 := 0.0
	var s_xl := 0.0
	var s_pull := 0.0
	var w_pull := 0.0
	var w_xl := -1e9
	var w_on := 0
	var s30_0 := 0.0
	var sxl_0 := 0.0
	var s30_l := 0.0
	var sxl_l := 0.0
	var by_turns := {}
	print("  hang  r    turns | on-beam  coil | drift@30  fwd lost  beamward pull")
	for cfg in cfgs:
		var s := _run(cfg, 0, -1)
		if int(s["t_rel"]) < 0:
			continue
		var t_rel: int = s["t_rel"]
		var keep := _run(cfg, 1, t_rel)
		if not bool(keep["held"]):
			continue                       # the wrap let go before the dismount
		var ctrl := _run(cfg, 2, t_rel)
		var mu0 := _run(cfg, 3, t_rel)
		var mul := _run(cfg, 4, t_rel)
		var kx: PackedFloat32Array = keep["x"]
		var ky: PackedFloat32Array = keep["y"]
		var cx: PackedFloat32Array = ctrl["x"]
		var cy: PackedFloat32Array = ctrl["y"]
		var beam := Vector2(0.0, -40.0)
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
		s_turn += float(keep["theta"]) / TAU
		s_nc += float(keep["nc"])
		s_coil += float(keep["coil"])
		s_on += float(keep["still_on"])
		s15 += d15; s30 += d30; s90 += d90; s_xl += xl; s_pull += pull
		w_pull = maxf(w_pull, pull)
		w_xl = maxf(w_xl, xl)
		w_on = maxi(w_on, int(keep["still_on"]))
		var m0x: PackedFloat32Array = mu0["x"]
		var m0y: PackedFloat32Array = mu0["y"]
		var mlx: PackedFloat32Array = mul["x"]
		var mly: PackedFloat32Array = mul["y"]
		s30_0 += Vector2(m0x[30] - cx[30], m0y[30] - cy[30]).length()
		sxl_0 += cx[POST - 1] - m0x[POST - 1]
		s30_l += Vector2(mlx[30] - cx[30], mly[30] - cy[30]).length()
		sxl_l += cx[POST - 1] - mlx[POST - 1]
		var tk: float = cfg[2]
		if not by_turns.has(tk):
			by_turns[tk] = [0, 0.0, 0.0, 0.0, 0.0]
		var b: Array = by_turns[tk]
		b[0] += 1; b[1] += float(keep["still_on"]); b[2] += d30
		b[3] += xl; b[4] += float(keep["nc"])
		by_turns[tk] = b
		print("  %.1f  %.2f  %.1f  |  %2d tk  %.2f m |  %.3f m   %+.3f m    %.2f m/s"
			% [cfg[0], cfg[1], cfg[2], int(keep["still_on"]),
			float(keep["coil"]), d30, xl, pull])
	print("")
	print("=================================================================")
	print("  usable dismounts                               %d" % n)
	if n == 0:
		quit(0)
		return
	print("  AT THE INSTANT THE HAND OPENS")
	print("    wrap still round the beam         %.2f turns" % (s_turn / n))
	print("    particles touching the beam       %.1f of 26" % (s_nc / n))
	print("    rope lying on the beam            %.2f m of 5.25" % (s_coil / n))
	print("")
	print("  AFTER THE HAND OPENS  (vs the same world with the beam deleted)")
	print("    ticks the chain stays on the beam %.1f  (%.0f ms)  worst %d tk"
		% [s_on / n, s_on / n * 1000.0 / 60.0, w_on])
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
	print("")
	print("  IS IT THE SIZE OF THE COIL?")
	print("    turns   n   contact   on-beam   drift@30   fwd lost")
	var keys: Array = by_turns.keys()
	keys.sort()
	for k in keys:
		var b: Array = by_turns[k]
		print("     %.1f   %2d    %4.1f     %5.1f tk    %.3f m   %+.3f m"
			% [k, b[0], b[4] / b[0], b[1] / b[0], b[2] / b[0], b[3] / b[0]])
	print("=================================================================")
	quit(0)
