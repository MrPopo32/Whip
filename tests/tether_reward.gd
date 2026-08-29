extends SceneTree
## Does a LONG-RANGE catch already pay better than a close one?
## A wrap fixes the tether at the handle-to-beam distance at the moment of the
## catch, so a far catch = long pendulum, a close catch = short one. Hang at a
## range of tether lengths, pump with an identical policy, release at the same
## phase, and measure how far the body is flung.

func _rig(hang: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()      # open air: no terrain
	var k := 0
	m.a_r[k] = 0.20
	m.a_pos[k] = Vector2(0.0, -60.0)
	var c: Vector2 = m.a_pos[k]
	var r: float = m.a_r[k] + 0.04
	var turns := 1.3
	var rise: float = hang - r
	var wrap_len: float = turns * TAU * r
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + Vector2(0.0, hang - s)
		elif s < rise + wrap_len:
			var ang: float = PI / 2.0 + (s - rise) / r
			p = c + Vector2(cos(ang), sin(ang)) * r
		else:
			var ang2: float = PI / 2.0 + turns * TAU
			var e: Vector2 = c + Vector2(cos(ang2), sin(ang2)) * r
			var side := 0.3 if cos(ang2) >= 0.0 else -0.3
			p = e + Vector2(side, s - rise - wrap_len)
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + Vector2(0.0, hang + 0.6)
	m.body_prv = m.body_pos
	return m

func _run(hang: float) -> Array:
	var m := _rig(hang)
	var c: Vector2 = m.a_pos[0]
	# settle into the hang
	for t in 40:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free()
		return [hang, -1.0, -1.0, 0.0]
	var tether: float = m.a_freelen[0]
	# pump: drive the handle across the swing at the pendulum's own period
	var period: float = TAU * sqrt(maxf(tether + 1.3, 0.3) / 10.0)
	var pk := 0.0
	var peak_speed := 0.0
	for t in 900:
		var ph: float = float(t) / 60.0 / period * TAU
		var tgt: Vector2 = m.body_pos + Vector2(cos(ph), -0.6).normalized() * m.REACH
		m.step_tick(tgt, true)
		var v: float = (m.body_pos - m.body_prv).length() * 960.0
		peak_speed = maxf(peak_speed, v)
		pk = maxf(pk, absf(m.body_pos.x - c.x))
	m.free()
	return [hang, tether, peak_speed, pk]

func _initialize() -> void:
	print("catch range -> what the swing is worth (identical pump policy)")
	print("hang(m)  tether  peak speed  max swing reach")
	for h in [1.2, 2.0, 2.8, 3.6, 4.4]:
		var r := _run(h)
		if r[1] < 0.0:
			print("%.1f      (wrap did not hold)" % r[0])
		else:
			print("%.1f      %.2f    %5.1f m/s    %5.2f m" % [r[0], r[1], r[2], r[3]])
	quit(0)
