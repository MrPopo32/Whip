extends SceneTree
## MOVE 4, THE PIT: is the gap under a door-up re-entrant?
##
##   -- door5 G h D         NULL: stand on the pit floor, throw at the door
##                          (5.2 m up at D = 3). 36 strokes x leads, both
##                          throwing directions. Must report no lock.
##   -- pitdoor G h D xp lead dir T [pump] [full]
##                          a SECOND beam in the pit at (xp, D - 2.2) r 0.11,
##                          2.2 m over the pit floor. Stand on the pit floor
##                          at xp + dir*lead... (dir -1 = stand right of it and
##                          throw toward -x, mirrored strokes), catch it
##                          standing, pump flat out, and fly every release
##                          (full) or every forecast pick +/-4 toward BOTH
##                          F0 (up D) and the ledge (up D + h). Reports where
##                          each lands.
## Origin as climb_door_lib: F0 lip corner, up metres.
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")

func do_door5(a: Array) -> void:
	var G := float(a[1]); var h := float(a[2]); var D := float(a[3])
	var m: Node2D = DL.make(G, h, D)
	var t0 := Time.get_ticks_msec()
	for side in [-1, 1]:
		for lead in [1.2, 1.8, 2.4, 3.0]:
			var x: float = DL.DOOR.x - float(side) * lead
			if x < 0.35 or x > G - 0.35:
				continue
			var nc := 0
			var nl := 0
			var tipmin := 99.0
			for c: Dictionary in DL.grid36():
				m._reset()
				DL.stand(m, x, D, float(c["a0"]) if side > 0 else PI - float(c["a0"]))
				# watch the tip's closest approach to the door on this throw
				var r: Dictionary = DL.throw(m, 0, c, HN.new("null", "p", 0), side < 0)
				if bool(r["caught"]): nc += 1
				if bool(r["lock"]): nl += 1
			print("DOOR5 G %.1f D %.1f | standing on the pit floor at x %.2f (door %.1f m up, lead %.1f, throwing %s) | caught %d locked %d / 36"
				% [G, D, x, D + 2.2, lead, "+x" if side > 0 else "-x", nc, nl])
	# the positive control: the SAME function, the SAME strokes, standing on
	# F0 instead (door 2.2 m up, lead 1.8) - must report locks
	var nl2 := 0
	for c: Dictionary in DL.grid36():
		m._reset()
		DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
		var r2: Dictionary = DL.throw(m, 0, c, HN.new("null", "p", 0), false)
		if bool(r2["lock"]): nl2 += 1
	print("DOOR5 CONTROL standing on F0 at x %.2f (door 2.2 m up) | locked %d / 36"
		% [DL.DOOR.x - 1.8, nl2])
	print("DOOR5DONE %.0f s" % [(Time.get_ticks_msec() - t0) / 1000.0])
	m.free()

func ballistic_hits(p: Vector2, v: Vector2, x0: float, x1: float, top: float,
		br: float) -> bool:
	var xl := DL.ballistic_land(p, v, -top, br)
	return not is_nan(xl) and xl > x0 - 1.5 and xl < x1 + 1.5

func do_pitdoor(a: Array) -> void:
	var G := float(a[1]); var h := float(a[2]); var D := float(a[3])
	var xp := float(a[4]); var lead := float(a[5]); var dir := int(a[6])
	var T := float(a[7])
	var npump := 720 if a.size() < 9 else int(a[8])
	var full := a.size() >= 10 and String(a[9]) == "full"
	var t0 := Time.get_ticks_msec()
	var bp := Vector2(xp, D - 2.2)
	var m: Node2D = DL.make(G, h, D, true, [[bp, 0.11]])
	var K := 1
	var tag := "G %.1f h %.1f D %.1f | pit beam (%.1f, %.1f up) | stand %.2f (lead %.1f, throw %s) T %.0f" % [
		G, h, D, xp, -bp.y, xp - float(dir) * lead, lead, "+x" if dir > 0 else "-x", T]
	var sx: float = xp - float(dir) * lead
	if sx < 0.35 or sx > G - 0.35:
		print("PITDOOR %s | stance off the pit floor" % tag)
		m.free()
		return
	# the throw search: 36 strokes, keep the SHORTEST lock (short tether is
	# what swings on a beam 2.2 m over its own floor)
	var best := {}
	var bt := 99.0
	var nl := 0
	for c: Dictionary in DL.grid36():
		m._reset()
		DL.stand(m, sx, D, float(c["a0"]) if dir > 0 else PI - float(c["a0"]))
		var r: Dictionary = DL.throw(m, K, c, HN.new("null", "q", 0), dir < 0)
		if bool(r["lock"]):
			nl += 1
			if float(r["tether"]) < bt:
				bt = float(r["tether"])
				best = c
	print("PITDOOR %s | locks %d / 36, shortest tether %.2f %s" % [tag, nl, bt,
		String(best.get("name", "-"))])
	if best.is_empty():
		m.free()
		return
	for pass_i in 1:
		m._reset()
		DL.stand(m, sx, D, float(best["a0"]) if dir > 0 else PI - float(best["a0"]))
		DL.throw(m, K, best, HN.new("null", "q", 0), dir < 0)
		DL.haul(m, K)
		var prev: Vector2 = m.body_pos
		var snaps: Array = []
		var gnd := 0
		var peak := 0.0
		for t in npump:
			var cur: Vector2 = PUMP.pump_cursor(m, K, prev, T)
			prev = m.body_pos
			m.step_tick(cur, true)
			if float(m.a_freelen[K]) < 0.0:
				print("   lost the pit beam at tick %d" % t)
				break
			if m.grounded: gnd += 1
			var p: Vector2 = m.body_pos - Vector2(m.a_pos[K])
			peak = maxf(peak, absf(rad_to_deg(atan2(p.x, p.y))))
			var v: Vector2 = (m.body_pos - prev) * 60.0
			if t < 10:
				continue
			var tgt := ""
			if v.x < 0.0 and (full or ballistic_hits(m.body_pos, v, -12.0, 0.0, 0.0, m.BODY_R)):
				tgt = "F0"
			elif v.x > 0.0 and (full or ballistic_hits(m.body_pos, v, G, G + 3.0, -h, m.BODY_R)):
				tgt = "LEDGE"
			snaps.append([t, m.snapshot() if tgt != "" or full else {}, tgt, v,
				m.body_pos, rad_to_deg(atan2(p.x, p.y))])
		print("   pumped %d ticks: peak swing %.0f deg, feet on the pit floor %d ticks, stored %d"
			% [npump, peak, gnd, snaps.size()])
		# fly every pick +/-4 (neighbours need their own snapshots: re-pump)
		var want := {}
		for i in snaps.size():
			if String(snaps[i][2]) != "":
				for j in range(i - 4, i + 5):
					if j >= 0 and j < snaps.size():
						want[j] = true
		var line := ""
		var hist := {}
		var wins: Array = []
		var keys: Array = want.keys()
		keys.sort()
		# neighbours without snapshots: replay the pump to them (deterministic)
		var need: Array = []
		for j: int in keys:
			if (snaps[j][1] as Dictionary).is_empty():
				need.append(int(snaps[j][0]))
		if not need.is_empty():
			m._reset()
			DL.stand(m, sx, D, float(best["a0"]) if dir > 0 else PI - float(best["a0"]))
			DL.throw(m, K, best, HN.new("null", "q", 0), dir < 0)
			DL.haul(m, K)
			prev = m.body_pos
			var ni := 0
			var bytick := {}
			for t in npump:
				var cur: Vector2 = PUMP.pump_cursor(m, K, prev, T)
				prev = m.body_pos
				m.step_tick(cur, true)
				if need.has(t):
					bytick[t] = m.snapshot()
			for j: int in keys:
				if bytick.has(int(snaps[j][0])):
					snaps[j][1] = bytick[int(snaps[j][0])]
		var lastt := -99
		for j: int in keys:
			var e: Array = snaps[j]
			if int(e[0]) != lastt + 1:
				line += " |%d:" % int(e[0])
			lastt = int(e[0])
			m.restore(e[1])
			var o: Dictionary = DL.fly(m, G, h, D, false, 300, 60)
			var w := String(o["where"])
			hist[w] = int(hist.get(w, 0)) + 1
			line += DL.code(w)
			if w == "F0" or w == "LEDGE":
				wins.append("t%d %s deg %+.0f v %.1f@%+.0f" % [int(e[0]), w,
					float(e[5]), (e[3] as Vector2).length(),
					rad_to_deg(atan2(-(e[3] as Vector2).y, (e[3] as Vector2).x))])
		print("   flown %d: %s" % [keys.size(), str(hist)])
		print("   ticks%s" % line)
		print("   wins: %s" % "; ".join(wins.slice(0, 12)))
	print("PITDONE %s %.0f s" % [tag, (Time.get_ticks_msec() - t0) / 1000.0])
	m.free()

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	match String(a[0]):
		"door5":
			do_door5(a)
		"pitdoor":
			do_pitdoor(a)
	quit(0)
