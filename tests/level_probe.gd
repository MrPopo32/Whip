extends SceneTree
## Level reachability audit: for every anchor in the real level, stand the body
## on the floor a throw-lead behind it and search a small grid of strokes.
## Reports the best wrap achieved. Anchors that no stroke can even CATCH are
## level bugs, not player skill.

func _floor_y(m: Node2D, x: float) -> float:
	var best := 99.0
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		if absf(B.x - A.x) < 0.01:
			continue
		if x < minf(A.x, B.x) or x > maxf(A.x, B.x):
			continue
		var t := (x - A.x) / (B.x - A.x)
		best = minf(best, A.y + (B.y - A.y) * t)
	return best

func _try(k: int, lead: float, a0: float, a1: float, sd: int, pull: bool) -> Array:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	var ax: float = m.a_pos[k].x
	var bx: float = ax - lead
	var fy := _floor_y(m, bx)
	m.body_pos = Vector2(bx, fy - m.BODY_R); m.body_prv = m.body_pos
	# drape the whip along the ACTUAL terrain behind the body - laying it in a
	# flat line would bury it inside a gap wall and wreck the throw
	for i in m.pos.size():
		var px: float = bx + 0.3 - m.cum_len[i] * 0.99
		var py := _floor_y(m, px)
		if py > 90.0:
			py = fy
		var p := Vector2(px, minf(py, fy) - m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	var best := 0.0
	var locked := false
	var grip := false
	for t in 150:
		var tgt: Vector2
		if t < 30:
			tgt = m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH
		elif t < 30 + sd:
			tgt = m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH
		elif pull and t < 40 + sd:
			tgt = m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
		else:
			tgt = m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH
		if not grip and absf(m.a_theta[k]) >= m.th_part:
			grip = true
		m.step_tick(tgt, grip)
		best = maxf(best, absf(m.a_theta[k]))
		if m.a_locked[k] == 1:
			locked = true
	m.free()
	return [best, locked]

func _initialize() -> void:
	var probe: Node2D = load("res://main.gd").new()
	probe.external_drive = true
	probe.setup_sim()
	var n: int = probe.a_pos.size()
	var info := []
	for k in n:
		info.append([probe.a_pos[k], probe.a_r[k]])
	probe.free()
	print("anchor  pos            r     lead  best_theta  verdict")
	var bad := 0
	for k in n:
		var best := 0.0
		var locked := false
		var bestlead := 0.0
		for lead in [1.8, 2.4, 3.0]:
			for a0 in [PI * 0.85, PI * 1.10]:
				for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
					for sd in [5, 9, 14]:
						for pull in [false, true]:
							var r := _try(k, lead, a0, a1, sd, pull)
							if r[0] > best:
								best = r[0]; bestlead = lead
							if r[1]:
								locked = true
								bestlead = lead
					if locked:
						break
				if locked:
					break
			if locked:
				break
		# FAST beams are deliberately out of reach from the ground - they are
		# the skill ceiling, caught only from the apex of a swing. A RECOVERY
		# beam must LOCK from a standstill, not merely catch: a catch that
		# cannot lock pays out and drops you, so a catch-only recovery beam
		# is an instant loss dressed up as a safety net.
		var probe2: Node2D = load("res://main.gd").new()
		probe2.external_drive = true
		probe2.setup_sim()
		var h: float = _floor_y(probe2, info[k][0].x) - info[k][0].y
		probe2.free()
		var high := h > 4.0
		var v := "LOCK" if locked else ("catch" if best >= 2.2 else "UNREACHABLE")
		if high:
			v += "  [FAST beam: by design, swing-only]"
		elif not locked:
			bad += 1
			v += "  <-- LEVEL BUG: recovery beam must LOCK"
		print("A%-2d   (%5.1f,%5.1f)  %.2f  %.1f     %5.2f     %s"
			% [k, info[k][0].x, info[k][0].y, info[k][1], bestlead, best, v])
	print("recovery beams that do not LOCK from a standstill (level bugs): %d" % bad)
	quit(0)
