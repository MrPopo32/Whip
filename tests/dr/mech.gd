extends SceneTree
## WHERE DOES THE POST-RELEASE PULL COME FROM?
##
## tests/dr/main_inst.gd is main.gd plus pure accumulators - no physics change.
## Gate 0 proves that: identical state hash on identical input.
##
## Then one dismount is opened up tick by tick. Per tick, after the hand opens:
##   contacts   chain particles touching the beam
##   AFRIC      tangential impulse the BEAM removed from the chain this tick
##              (kg m/s per second - the beam's grip on the coil)
##   ARM        velocity the arm tether hauled INTO the body this tick, and how
##              much of that points back at the beam (the felt "pull back")
##   |v|        body speed

const PUMP := preload("res://tests/bot_pump.gd")
const SETTLE := 60
const REL := 240
const POST := 40

func _rig(path: String, hang: float, r: float, turns: float, th0: float) -> Node2D:
	var m: Node2D = load(path).new()
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

func _drive(m: Node2D, t: int, prev: Vector2) -> Vector2:
	if t >= SETTLE and t < REL and m.a_freelen[0] >= 0.0:
		return PUMP.pump_cursor(m, 0, prev, 55.0)
	return m.body_pos

func _hash_run(path: String) -> int:
	var m := _rig(path, 2.0, 0.11, 1.6, 0.35)
	var prev: Vector2 = m.body_pos
	for t in range(REL + POST):
		var cur := _drive(m, t, prev)
		prev = m.body_pos
		m.step_tick(cur, t < REL)
	var h: int = m.state_hash()
	m.free()
	return h

func _initialize() -> void:
	var h0 := _hash_run("res://main.gd")
	var h1 := _hash_run("res://tests/dr/main_inst.gd")
	print("GATE 0  instrumented build is bit-identical to main.gd:  %s"
		% ("YES" if h0 == h1 else "NO  (%d vs %d)" % [h0, h1]))
	print("")
	for cfg in [[2.0, 0.11, 1.6], [2.0, 0.22, 1.6], [2.8, 0.10, 2.0]]:
		var m := _rig("res://tests/dr/main_inst.gd", cfg[0], cfg[1], cfg[2], 0.35)
		print("hang %.1f m, beam r %.2f m, %.1f turns" % cfg)
		print("  tick | grip | contacts | beam grip on coil | rope pull on body  | beamward | |v| body | theta")
		var prev: Vector2 = m.body_pos
		for t in range(REL + POST):
			var cur := _drive(m, t, prev)
			prev = m.body_pos
			m.step_tick(cur, t < REL)
			if t < REL - 4 or t >= REL + 30:
				continue
			var beam: Vector2 = m.a_pos[0]
			var toward: Vector2 = (beam - m.body_pos).normalized()
			var arm: Vector2 = m.dbg_arm + m.dbg_spring
			var v: Vector2 = (m.body_pos - m.body_prv) / m.SDT
			print("  %4d |  %s  |    %2d    |      %8.2f     |      %8.3f      | %8.3f | %6.2f | %5.2f"
				% [t - REL, "TAUT" if t < REL else "open", _contacts(m),
				m.dbg_afric, arm.length(), arm.dot(toward), v.length(),
				absf(m.a_theta[0])])
		m.free()
		print("")
	quit(0)
