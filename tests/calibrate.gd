extends SceneTree
## Calibrate the wrap thresholds against honest geometry.
##  FOLD  = chain merely creased over a beam by gravity, no stroke, no grip.
##          Anything at or below this must NEVER be able to catch you.
##  TURN  = a genuine single turn, settled and bearing a hanging body.
## The catch threshold belongs above FOLD; the lock threshold near TURN.
## If the two overlap, the measure cannot tell a fold from a wrap at all.

func _mk(shell: float, r: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.wrap_shell = shell
	m.th_part = 99.0        # never engage: we want the raw geometry
	m.th_full = 99.0
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0); m.a_r[0] = r
	return m

# chain laid limply across the beam, released, no grip: pure gravity fold
func _fold(shell: float, r: float) -> float:
	var m := _mk(shell, r)
	var c: Vector2 = m.a_pos[0]
	var rr: float = r + 0.035
	var half: float = m.cum_len[m.NP - 1] * 0.5
	for i in m.pos.size():
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < half - rr * PI * 0.5:
			p = c + Vector2(-rr, -(half - rr * PI * 0.5 - s))
		elif s < half + rr * PI * 0.5:
			var a: float = PI + (s - (half - rr * PI * 0.5)) / rr
			p = c + Vector2(cos(a), sin(a)) * rr
		else:
			p = c + Vector2(rr, s - (half + rr * PI * 0.5))
		m.pos[i] = p; m.prv[i] = p
	m.body_pos = c + Vector2(-rr, -(half - rr * PI * 0.5) - 1.3)
	m.body_prv = m.body_pos
	var peak := 0.0
	for t in 90:
		m.step_tick(m.body_pos, false)
		peak = maxf(peak, absf(m.a_theta[0]))
	m.free()
	return peak

# a real single turn, settled under a hanging body
func _turn(shell: float, r: float, turns: float) -> float:
	var m := _mk(shell, r)
	m.th_part = 0.5     # allow it to engage so it bears load like a real wrap
	m.th_full = 0.6
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
	var lo := 99.0
	for t in 60:
		m.step_tick(m.body_pos, true)
		if t > 12:
			lo = minf(lo, absf(m.a_theta[0]))
	m.free()
	return lo

func _initialize() -> void:
	print("pi = 3.1416. A fold is a half turn and must never reach the catch bar.")
	print("")
	print("shell   beam r   FOLD peak   1.0 turn   1.3 turn   gap(turn-fold)")
	for shell in [0.025, 0.010, 0.004, 0.001]:
		for r in [0.10, 0.16, 0.22]:
			var f := _fold(shell, r)
			var t1 := _turn(shell, r, 1.0)
			var t13 := _turn(shell, r, 1.3)
			print("%.3f    %.2f      %6.2f     %6.2f     %6.2f     %+6.2f"
				% [shell, r, f, t1, t13, t1 - f])
		print("")
	quit(0)
