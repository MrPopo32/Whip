extends SceneTree
## After you open your hand the wrap is freed instantly - but the rope is still
## physically coiled round the beam and has to unspool off it. This measures
## what that costs: how long the rope keeps touching, and how much launch speed
## and heading it takes, against a control where the beam vanishes at release.

func _rig(r: float, turns: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0); m.a_r[0] = r
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.04
	var hang := 2.2
	var rise: float = hang - rr
	var wl: float = turns * TAU * rr
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + Vector2(0.0, hang - s)
		elif s < rise + wl:
			var a: float = PI / 2.0 + (s - rise) / rr
			p = c + Vector2(cos(a), sin(a)) * rr
		else:
			var a2: float = PI / 2.0 + turns * TAU
			var e: Vector2 = c + Vector2(cos(a2), sin(a2)) * rr
			p = e + Vector2(0.3 if cos(a2) >= 0.0 else -0.3, s - rise - wl)
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + Vector2(0.0, hang + 0.6); m.body_prv = m.body_pos
	return m

func _touching(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + 0.05:
			n += 1
	return n

func _run(r: float, turns: float, control: bool) -> Array:
	var m := _rig(r, turns)
	for t in 60:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free(); return [-1, 0.0, 0.0, 0.0]
	# pump to a realistic launch speed
	var flen: float = m.a_freelen[0]
	var period: float = TAU * sqrt(maxf(flen + 1.15, 0.3) / 10.0)
	for t in 600:
		var ph: float = float(t) / 60.0 / period * TAU
		m.step_tick(m.body_pos + Vector2(cos(ph), -0.55).normalized() * m.REACH, true)
	var coiled := _touching(m)
	var v0: Vector2 = (m.body_pos - m.body_prv) * 960.0
	if control:
		m.a_pos[0] = Vector2(0.0, 900.0)      # beam vanishes: nothing to unspool
	# hand OPEN from here. Sample at a FIXED short horizon so gravity acts
	# equally on both runs - the only difference left is the rope.
	var clear_at := -1
	var p40 := Vector2.ZERO
	for t in 40:
		m.step_tick(m.body_pos, false)
		if clear_at < 0 and (control or _touching(m) == 0):
			clear_at = t
		if t == 39:
			p40 = m.body_pos
	var v1: Vector2 = (m.body_pos - m.body_prv) * 960.0
	var turn: float = rad_to_deg(absf(v0.angle_to(v1)))
	var res := [coiled, v0.length(), v1.length(), turn, clear_at, p40]
	m.free()
	return res

func _initialize() -> void:
	print("what the unspool costs, from the tick the hand opens")
	print("all sampled 40 ticks (0.67 s) after the hand opens")
	print("beam turns coiled  launch   real     control   held      ticks to")
	print("                    m/s    m/s 40t   m/s 40t   back      clear")
	for r in [0.22, 0.16, 0.11]:
		for turns in [1.3, 1.8]:
			var a := _run(r, turns, false)
			if a[0] < 0:
				print("%.2f  %.1f   (wrap did not hold)" % [r, turns]); continue
			var b := _run(r, turns, true)
			var held_back: float = (b[5] as Vector2).distance_to(a[5] as Vector2)
			print("%.2f  %.1f    %2d/26   %5.2f    %5.2f     %5.2f      %4.2f m      %s"
				% [r, turns, a[0], a[1], a[2], b[2], held_back,
				   str(a[4]) if a[4] >= 0 else "never"])
	quit(0)
