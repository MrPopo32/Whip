extends SceneTree
## catch_readout.gd - WHAT DOES THE PLAYER ACTUALLY SEE?
##
## Takes ONE throw that genuinely wraps the beam and runs it twice: once with
## the hand closing 250 ms early (which the shipped rule refuses) and once with
## it closing just after contact (which it accepts). Then prints, tick by tick,
## everything _draw and _events would put on screen and in the speakers.
##
## If the two columns are the same right up to the instant the catch does or
## does not happen, the player has no way to tell a refusal from a catch until
## after they have already committed to the next move.

var SCRIPT := "res://main.gd"

func _rig(dx: float, h: float, r: float) -> Node2D:
	var m: Node2D = load(SCRIPT).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -h)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

func _target(m: Node2D, t: int, s: Array) -> Vector2:
	var a0: float = s[3]
	var a1: float = s[4]
	var sd: int = s[5]
	var fin: int = s[6]
	var b: Vector2 = m.body_pos
	if t < 30:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return b + Vector2(cos(a1), sin(a1)) * m.REACH
	if fin == 2 and t < 30 + sd + 8:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
	return b + Vector2(cos(a1), sin(a1)) * m.REACH

func _probe(s: Array) -> Array:
	var m := _rig(s[0], s[1], s[2])
	var t_touch := -1
	var maxth := 0.0
	var n_qual := 0
	for t in 100:
		m.step_tick(_target(m, t, s), false)
		var th: float = absf(m.a_theta[0])
		maxth = maxf(maxth, th)
		if th >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx:
			n_qual += 1
		if t_touch < 0:
			for i in m.pos.size():
				if m.pos[i].distance_to(m.a_pos[0]) < m.a_r[0] + m.p_rad[i] + m.wrap_shell:
					t_touch = t
					break
	m.free()
	return [t_touch, maxth, n_qual]

# reproduce exactly what _draw would paint for anchor 0, and what _events
# would play, from the same state the real game reads.
func _readout(m: Node2D, half_prev: int) -> Array:
	var th: float = absf(m.a_theta[0])
	var ring := "-"
	var dots := 0
	if th > 0.3:
		var engaged: bool = m.a_freelen[0] >= 0.0
		var locked: bool = engaged and m.a_locked[0] == 1
		if locked and m.a_pinidx[0] >= 0:
			var tail: float = m.cum_len[m.NP - 1] - m.cum_len[m.a_pinidx[0]]
			if tail < m.PINCH_TURN * TAU * (m.a_r[0] + 0.02):
				locked = false
		ring = "GREY" if not engaged else ("AMBER" if not locked else "GREEN")
		dots = int(th / PI)
	var hf := int(th / PI)
	var chime := hf > half_prev and hf >= 1
	var fresh := 0.0
	if m.taut:
		fresh = clampf(1.0 - float(m.tick_count - m.grip_edge) / float(m.GRIP_WINDOW), 0.0, 1.0)
	return [ring, dots, chime, fresh, hf, th]

func _show(s: Array, press: int, tag: String) -> void:
	var m := _rig(s[0], s[1], s[2])
	var half := 0
	print("")
	print("--- %s : hand closes on tick %d ---" % [tag, press])
	print(" tick  theta  ring    half-dots  chime  hand-ring  rasp  state")
	var eng_shown := false
	for t in 100:
		m.step_tick(_target(m, t, s), t >= press)
		var r := _readout(m, half)
		half = int(r[4])
		var st := "-"
		if m.a_freelen[0] >= 0.0:
			st = "ENGAGED" if m.a_locked[0] != 1 else "LOCKED"
			eng_shown = true
		if float(r[5]) < 0.3 and not eng_shown:
			continue
		if t > 75 and not eng_shown:
			continue
		print(" %4d  %5.2f  %-6s  %6d    %-5s   %5.2f     %-4s  %s" % [
			t, r[5], r[0], r[1], "TICK!" if bool(r[2]) else "", r[3],
			"RASP" if m.slipping else "", st])
	m.free()

func _initialize() -> void:
	if "fix" in OS.get_cmdline_user_args():
		SCRIPT = "res://tests/jb/whip_arrival.gd"
	print("SIM UNDER TEST: %s" % SCRIPT)
	# find a throw that plainly wraps
	var s: Array = []
	var t_touch := -1
	for beam in [[0.11, 2.2], [0.22, 2.2], [0.11, 2.6]]:
		for dx in [1.8, 2.5]:
			for a0 in [PI * 0.85, PI * 1.10]:
				for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
					for sd in [5, 9, 14]:
						for fin in [0, 2]:
							if not s.is_empty():
								continue
							var c: Array = [dx, beam[1], beam[0], a0, a1, sd, fin]
							var r := _probe(c)
							if int(r[0]) >= 0 and int(r[2]) >= 8 and float(r[1]) >= 5.5:
								s = c
								t_touch = int(r[0])
								print("throw: dx %.1f  beam r %.2f at %.1f m  peak theta %.2f  qualifies for %d ticks"
									% [dx, beam[0], beam[1], r[1], r[2]])
	if s.is_empty():
		print("no clean wrapping throw found")
		quit(1)
		return
	print("the chain first touches the beam on tick %d" % t_touch)
	_show(s, maxi(t_touch - 15, 0), "PRESSED 250 ms EARLY (anticipating)")
	_show(s, t_touch + 5, "PRESSED JUST AFTER CONTACT")
	quit(0)
