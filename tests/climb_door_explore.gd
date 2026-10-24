extends SceneTree
## Exploration for MOVE 4: which standing throws lock the door from F0, and
## what swing each lock can pump in the gap. Prints; decides nothing.
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var G := 6.0 if a.size() < 1 else float(a[0])
	var h := 1.0 if a.size() < 2 else float(a[1])
	var t0 := Time.get_ticks_msec()
	var m: Node2D = DL.make(G, h)
	var ticks0: int = m.tick_count
	var locks: Array = []
	for lead in [1.8, 2.2, 2.6, 3.0]:
		var nl := 0
		var nc := 0
		for c: Dictionary in DL.grid36():
			m._reset()
			DL.stand(m, DL.DOOR.x - lead, 0.0, float(c["a0"]))
			var r: Dictionary = DL.throw(m, 0, c, HN.new("null", "x", 0))
			if bool(r["caught"]): nc += 1
			if bool(r["lock"]):
				nl += 1
				locks.append({"lead": lead, "c": c, "tether": r["tether"],
					"grounded": r["grounded"], "hash": r["hash"]})
		print("lead %.1f: caught %d locked %d / 36" % [lead, nc, nl])
	print("throw search %.1f s, %d ticks" % [(Time.get_ticks_msec() - t0) / 1000.0,
		m.tick_count - ticks0])
	for L: Dictionary in locks:
		m._reset()
		var c: Dictionary = L["c"]
		DL.stand(m, DL.DOOR.x - float(L["lead"]), 0.0, float(c["a0"]))
		DL.throw(m, 0, c, HN.new("null", "x", 0))
		var ht := DL.haul(m, 0)
		var prev: Vector2 = m.body_pos
		var pk := 0.0
		var pkb := 0.0
		var gnd := 0
		var minx := 99.0
		var lost := -1
		var peaks: Array = []
		var sgn := 0.0
		var cur_pk := 0.0
		var over := -1
		var thu := DL.body_deg(m, 0)
		var thp := thu
		for t in 1500:
			var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 0.0)
			prev = m.body_pos
			m.step_tick(cur, true)
			if float(m.a_freelen[0]) < 0.0:
				lost = t
				break
			var th := DL.body_deg(m, 0)
			var d := th - thp
			if d > 180.0: d -= 360.0
			elif d < -180.0: d += 360.0
			thp = th
			thu += d
			if absf(thu) > 180.0 and over < 0: over = t
			if m.grounded: gnd += 1
			minx = minf(minx, m.body_pos.x)
			cur_pk = maxf(cur_pk, absf(th))
			if signf(th) != sgn and th != 0.0:
				if sgn != 0.0:
					peaks.append("%s%.0f" % ["+" if sgn > 0 else "-", cur_pk])
				sgn = signf(th)
				cur_pk = 0.0
		print("lead %.1f %s tether %.2f gnd@lock %s haul %d | lost %d over %d gnd %d minx %.2f | %s"
			% [float(L["lead"]), String(c["name"]), float(L["tether"]),
			str(L["grounded"]), ht, lost, over, gnd, minx, " ".join(peaks.slice(0, 24))])
	print("total %.1f s" % [(Time.get_ticks_msec() - t0) / 1000.0])
	m.free()
	quit(0)
