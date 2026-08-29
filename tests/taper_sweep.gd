extends SceneTree
## What does taper buy? Runs the airborne wave bench at several handle:tip mass
## ratios and reports tip-speed amplification (the "snap") plus how high the
## tip is thrown by one stroke (the "can I clear the beam" number).

func _bench(tp: float) -> Array:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.taper = tp
	m.setup_sim()
	m.teleport(Vector2(0, -30))
	var max_tip := 0.0
	var max_handle := 0.0
	var rise := 0.0
	var bad := false
	for t in 300:
		m.body_prv = m.body_pos
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		if t < 100:
			tgt = b + Vector2(0.3, -0.6)
		elif t < 130:
			tgt = b + Vector2(1.1, -0.2)
		elif t < 140:
			tgt = b + Vector2(-1.1, -0.5)
		else:
			tgt = b + Vector2(-0.2, -0.8)
		var ph: Vector2 = m.pos[0]
		m.step_tick(tgt, false)
		var hv: float = (m.pos[0] - ph).length() * 60.0
		if t >= 130:
			max_handle = maxf(max_handle, hv)
			max_tip = maxf(max_tip, m.tip_speed)
			# how far ABOVE the hand does the tip get thrown?
			rise = maxf(rise, m.pos[0].y - m.pos[m.NP - 1].y)
		for i in m.pos.size():
			if is_nan(m.pos[i].x) or m.pos[i].length() > 900.0:
				bad = true
	m.free()
	return [max_tip, max_handle, rise, bad]

func _initialize() -> void:
	print("taper   tip m/s  handle  amp    tip rise above hand   stable")
	for tp in [22.0, 35.0, 50.0, 70.0, 100.0, 150.0]:
		var r := _bench(tp)
		print("%5.0f:1  %6.1f  %6.1f  %4.1fx  %5.2f m                %s"
			% [tp, r[0], r[1], r[0] / maxf(r[1], 0.001), r[2],
			   "NO" if r[3] else "yes"])
	quit(0)
