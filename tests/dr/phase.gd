extends SceneTree
## DOES *WHEN* YOU LET GO ALREADY CHANGE THE DRAG?
##
## The README already claims a technique: "release at the swing's dead point".
## The corpus in tests/dr/dismount.gd deliberately releases at the FASTEST
## FORWARD tick, which is the bottom of the arc - maximum speed and maximum
## rope tension at the beam. If drag is tension-driven, the dead point should
## be far cheaper, and the player would be paying for a choice rather than a
## tax.
##
## So: pump one rig to a real swing, then release at EVERY tick across a whole
## swing period. Each release is run twice from bit-identical state - beam kept
## and beam deleted - so the drag is measured, not modelled.
##
## Reported per release phase:
##   |v|      body speed at the moment of release (what the swing bought you)
##   afric    tangential impulse the beam is taking off the coil that tick
##            (the normal load on the coil - the tension proxy)
##   drift    body divergence from the beam-deleted world at +30 ticks
##   dvmax    largest velocity difference from that world over 60 ticks
##   pull     peak of that difference pointing back at the beam
##   gain     forward distance at +60 tk, keep minus control (negative = the
##            beam cost you ground)

const PUMP := preload("res://tests/bot_pump.gd")
const BUILD := "res://tests/dr/main_inst.gd"
const SETTLE := 60
const POST := 60

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

func _contacts(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in range(m.pos.size()):
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + 0.02:
			n += 1
	return n

func _run(cfg: Array, t_rel: int, ctrl: bool) -> Dictionary:
	var m := _rig(cfg[0], cfg[1], cfg[2], 0.35)
	var prev: Vector2 = m.body_pos
	var out := {}
	var tx := PackedFloat32Array()
	var ty := PackedFloat32Array()
	var vx := PackedFloat32Array()
	var vy := PackedFloat32Array()
	var lim: int = t_rel + POST
	for t in range(lim):
		if t == t_rel:
			out["speed"] = ((m.body_pos - m.body_prv) / m.SDT).length()
			out["afric"] = m.dbg_afric
			out["nc"] = _contacts(m)
			out["theta"] = absf(m.a_theta[0])
			out["held"] = m.a_freelen[0] >= 0.0
			out["ang"] = rad_to_deg(atan2((m.body_pos - m.a_pos[0]).x,
				(m.body_pos - m.a_pos[0]).y))
			if ctrl:
				m.a_pos[0] = Vector2(0.0, 5000.0)
		var hold: bool = t < t_rel
		var cur: Vector2 = m.body_pos
		if t >= SETTLE and hold and m.a_freelen[0] >= 0.0:
			cur = PUMP.pump_cursor(m, 0, prev, 55.0)
		prev = m.body_pos
		m.step_tick(cur, hold)
		if t >= t_rel:
			tx.append(m.body_pos.x); ty.append(m.body_pos.y)
			vx.append((m.body_pos.x - m.body_prv.x) / m.SDT)
			vy.append((m.body_pos.y - m.body_prv.y) / m.SDT)
	out["x"] = tx; out["y"] = ty; out["vx"] = vx; out["vy"] = vy
	m.free()
	return out

func _initialize() -> void:
	for cfg in [[2.0, 0.11, 1.6], [2.0, 0.22, 1.6], [2.8, 0.10, 2.0], [1.2, 0.20, 1.6]]:
		print("hang %.1f m | beam r %.2f m | %.1f turns wound on" % cfg)
		print("  release | body angle | held | on-beam | grip on coil | speed | drift@30 | dvmax | beamward pull | fwd gain")
		var best_ratio := -1e9
		var best := ""
		for t_rel in range(230, 290, 2):
			var k := _run(cfg, t_rel, false)
			if not bool(k["held"]):
				continue
			var c := _run(cfg, t_rel, true)
			var kx: PackedFloat32Array = k["x"]
			var ky: PackedFloat32Array = k["y"]
			var cx: PackedFloat32Array = c["x"]
			var cy: PackedFloat32Array = c["y"]
			var beam := Vector2(0.0, -40.0)
			var dvmax := 0.0
			var pull := 0.0
			for i in range(POST):
				var dv := Vector2(k["vx"][i] - c["vx"][i], k["vy"][i] - c["vy"][i])
				dvmax = maxf(dvmax, dv.length())
				var tw := beam - Vector2(cx[i], cy[i])
				if tw.length() > 0.0001:
					pull = maxf(pull, dv.dot(tw.normalized()))
			var drift := Vector2(kx[30] - cx[30], ky[30] - cy[30]).length()
			var gain: float = kx[POST - 1] - cx[POST - 1]
			var spd: float = k["speed"]
			print("   %4d   |   %+6.1f    |  %s | %2d/26   |    %6.2f    | %5.2f |  %.3f   | %5.2f |     %5.2f     |  %+.3f"
				% [t_rel, float(k["ang"]), "yes" if bool(k["held"]) else " no",
				int(k["nc"]), float(k["afric"]), spd, drift, dvmax, pull, gain])
			var ratio: float = spd - 2.0 * pull
			if ratio > best_ratio:
				best_ratio = ratio
				best = "  best speed-for-drag: release t=%d, angle %+.1f deg, speed %.2f m/s, beamward pull %.2f m/s" % [t_rel, float(k["ang"]), spd, pull]
		print(best)
		print("")
	quit(0)
