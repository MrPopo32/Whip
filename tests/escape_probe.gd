extends SceneTree
## Contract 7 audit: dropped into the bottom of every dip, can the lash gait
## alone crawl back onto a plateau? If this fails the level can strand a
## player, and no amount of anchor placement fixes it.

func _run_from(bx: float, bfy: float, secs: int) -> Array:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.body_pos = Vector2(bx, bfy - m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(bx + 0.3 - m.cum_len[i] * 0.5, bfy - m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	var maxx := bx
	var minY := bfy
	for t in secs * 60:
		var ph := t % 24
		var f := float(ph) / 24.0
		var tgt: Vector2
		var grip := false
		if f < 0.45:
			tgt = m.body_pos + Vector2(cos(2.83), sin(2.83)) * m.REACH
		else:
			tgt = m.body_pos + Vector2(cos(-0.94), sin(-0.94)) * m.REACH
			grip = f > 0.75
		m.step_tick(tgt, grip)
		maxx = maxf(maxx, m.body_pos.x)
		minY = minf(minY, m.body_pos.y)
	var res := [maxx - bx, minY]
	m.free()
	return res

func _initialize() -> void:
	print("lash-gait escape from each dip bottom (30 s, no anchors used)")
	# dip bottoms from _build_level
	var dips := [[10.6, 1.2, "dip 1"], [24.6, 1.2, "dip 2"], [38.8, 1.3, "dip 3"]]
	var bad := 0
	for d in dips:
		var r := _run_from(d[0], d[1], 30)
		var climbed: float = d[1] - (r[1] + 0.28)
		var ok: bool = climbed > d[1] - 0.15   # reached plateau level (y<=0)
		if not ok:
			bad += 1
		print("%s: travelled %.2f m, climbed %.2f m of %.2f  -> %s"
			% [d[2], r[0], climbed, d[1], "OUT" if ok else "STUCK"])
	print("stuck dips: %d" % bad)
	quit(0)
