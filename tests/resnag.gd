extends SceneTree
## After you let go of a beam and press again - the press meant for the NEXT
## beam - does the one you just left take the rope again? It used to, on 25 of
## 108 attempts, almost always through the self-crossing branch while the rope
## was still draped over it.

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

func _initialize() -> void:
	var attempts := 0
	var snags := 0
	for r in [0.10, 0.11, 0.16, 0.20, 0.22]:
		for turns in [1.3, 1.8, 2.2]:
			for press_at in [2, 6, 10, 16, 24, 34]:
				var m := _rig(r, turns)
				for t in 60:
					m.step_tick(m.body_pos, true)      # settle onto it
				if m.a_freelen[0] < 0.0:
					m.free(); continue
				attempts += 1
				var snagged := false
				for t in 90:
					# let go, then press again at press_at - the press you
					# would be making at the NEXT beam
					var grip: bool = t >= press_at
					# throw the hand out ahead, as you would for a new target
					m.step_tick(m.body_pos + Vector2(1.0, -0.5).normalized() * m.REACH, grip)
					if t > press_at and m.a_freelen[0] >= 0.0:
						snagged = true
				if snagged:
					snags += 1
				m.free()
	print("presses made after letting go of a beam: %d" % attempts)
	print("times that beam took the rope again:      %d  (%.0f%%)"
		% [snags, 100.0 * float(snags) / maxf(float(attempts), 1.0)])
	quit(0)
