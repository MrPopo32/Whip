extends SceneTree
## Grip is a trigger: the catch window opens when the hand CLOSES and lasts
## GRIP_WINDOW ticks. This sweeps the press moment against the tick the wrap
## actually qualifies, to see how much EARLY margin a player gets versus LATE.
## A human watching the whip arrive cannot press before they see it, and human
## reaction is ~200 ms (12 ticks) on top - so if the window is forward-only,
## anticipating is punished and reacting is the only option.

func _rig(r: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60, 0)); m.t_b.append(Vector2(60, 0))
	m.t_n.append(Vector2(0, -1))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(2.2, -2.2); m.a_r[0] = r
	m.body_pos = Vector2(0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	return m

var A0 := PI * 0.95
var A1 := -PI * 0.30
var SD := 30

func _stroke(m: Node2D, t: int) -> Vector2:
	var b: Vector2 = m.body_pos
	if t < SD:
		return b + Vector2(cos(A0), sin(A0)) * m.REACH
	return b + Vector2(cos(A1), sin(A1)) * m.REACH

# find a stroke that genuinely wraps this beam, with grip never pressed
func _find_stroke(r: float) -> bool:
	var best := 0.0
	for a0 in [PI * 0.85, PI * 0.95, PI * 1.10]:
		for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18, -PI * 0.05]:
			for sd in [20, 25, 30, 36, 44]:
				A0 = a0; A1 = a1; SD = sd
				var m := _rig(r)
				var peak := 0.0
				for t in 150:
					m.step_tick(_stroke(m, t), false)
					peak = maxf(peak, absf(m.a_theta[0]))
				m.free()
				if peak > best:
					best = peak
				if peak >= 3.4:
					return true
	print("   (best winding found was only %.2f rad, needs 3.4)" % best)
	return false

# when does the wrap first qualify, with grip never pressed?
func _qualify_tick(r: float) -> int:
	var m := _rig(r)
	var q := -1
	for t in 150:
		m.step_tick(_stroke(m, t), false)
		if q < 0 and absf(m.a_theta[0]) >= m.th_part:
			q = t
	m.free()
	return q

func _try(r: float, press: int) -> String:
	var m := _rig(r)
	var caught := false
	var locked := false
	for t in 150:
		m.step_tick(_stroke(m, t), t >= press)
		if m.a_freelen[0] >= 0.0:
			caught = true
			if m.a_locked[0] == 1:
				locked = true
	m.free()
	return "LOCK" if locked else ("catch" if caught else ".")

func _initialize() -> void:
	print("catch outcome vs the tick the hand closes (. = nothing at all)")
	print("window = %d ticks (%.0f ms). human reaction ~12 ticks." % [
		12, 12 * 16.7])
	for r in [0.22, 0.16, 0.11]:
		if not _find_stroke(r):
			print("r=%.2f  no stroke in the grid wrapped this beam" % r); continue
		var q := _qualify_tick(r)
		if q < 0:
			print("r=%.2f  the stroke never qualified" % r); continue
		var line := ""
		var offs := []
		for d in range(-30, 22, 2):
			offs.append(d)
			line += "%6s" % _try(r, q + d)
		var hdr := ""
		for d in offs:
			hdr += "%6d" % d
		print("")
		print("r=%.2f  wrap qualifies at tick %d" % [r, q])
		print("  press offset:%s" % hdr)
		print("  outcome:    %s" % line)
	print("")
	print("negative offset = pressed EARLY (in anticipation)")
	print("positive offset = pressed LATE (reacting to what you saw)")
	quit(0)
