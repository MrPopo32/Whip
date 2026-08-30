extends SceneTree
## How long does it take to get OFF a beam, and is that time predictable?
## Releasing does not detach you: the wrap pays material through the pin one
## index at a time until the whip slides off its own tail. So the time to
## dismount should scale with how far the pin sits from the tip - something the
## player can neither see nor choose. Measures that directly.

func _rig(r: float, turns: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()          # open air
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0); m.a_r[0] = r
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.04
	var hang := 2.0
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

func _run(r: float, turns: float) -> Array:
	var m := _rig(r, turns)
	for t in 60:                                # settle into the hang
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free()
		return [-1, -1, 0, 0.0]
	var pin: int = m.a_pinidx[0]
	var locked: int = m.a_locked[0]
	var y0: float = m.body_pos.y
	var free_at := -1
	for t in 600:                               # hand OPEN from here on
		m.step_tick(m.body_pos, false)
		if m.a_freelen[0] < 0.0:
			free_at = t
			break
	var fell: float = m.body_pos.y - y0
	m.free()
	return [pin, free_at, locked, fell]

func _initialize() -> void:
	print("time to get off a beam after opening the hand")
	print("beam r  turns   pin idx  ticks to free   seconds   locked  fell(m)")
	var lo := 9999
	var hi := -1
	for r in [0.10, 0.16, 0.22]:
		for turns in [0.9, 1.2, 1.6, 2.0]:
			var res := _run(r, turns)
			if res[0] < 0:
				print("%.2f    %.1f     (wrap did not hold)" % [r, turns])
				continue
			var tf: int = res[1]
			if tf >= 0:
				lo = mini(lo, tf); hi = maxi(hi, tf)
			print("%.2f    %.1f      %2d        %s      %s     %d     %5.2f"
				% [r, turns, res[0],
				   ("%4d" % tf) if tf >= 0 else "NEVER",
				   ("%5.2f" % (tf / 60.0)) if tf >= 0 else " -- ",
				   res[2], res[3]])
	print("")
	if hi > 0:
		print("fastest %d ticks (%.2f s), slowest %d ticks (%.2f s) - ratio %.1fx"
			% [lo, lo / 60.0, hi, hi / 60.0, float(hi) / maxf(float(lo), 1.0)])
	quit(0)
