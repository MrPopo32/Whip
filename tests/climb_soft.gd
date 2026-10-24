extends SceneTree
## THE SOFT WORLD - the fall-recovery bench for the climb.
##
## The climb is a staircase of SLABS: every shelf above the first is an
## overhanging slab with a walkable floor under it, and that floor is the pit
## of the door on the slab's far end. Fall short of slab i and you land in the
## pit of door i-1; overshoot it and you land in the pit of door i, which is
## the floor UNDER slab i - walk back under the slab to the edge of gap i-1
## and the door you just failed on hangs 2.2 m over your head, G-1.4 m out,
## over the pit: catch it from THIS side, pump, and launch back up. So a miss
## costs one launch, never the level. That recovery is what this bench
## measures; climb_door_map measured the launch itself against a solid face.
##
## Frame as tests/climb_door_lib.gd: x = 0 is the F0 lip face, y = 0 the F0
## floor, y DOWN in the sim, every printed height is UP metres. World:
##   left wall x -12 | F0 floor y 0, x -12..0 | lip face x 0 down to the pit
##   floor y D | pit floor x 0..G | step face x G up to y 0 | UNDER-FLOOR
##   y 0, x G..G+W+6 | far wall x G+W+6 up to -25.
##   SLAB, a closed island: x G..G+W, y -h..-h+t (top at h up, t thick).
##   Door (1.4, -2.2) r 0.11 - the shipped door.
##   Fillets 0.35 at the two ground lips (0,0) and (G,0); 0.10 at all four
##   slab corners, the level's island default.
##
##   -- far G h D W t T [leads]   THE RECOVERY. Stand on the under-floor at
##        x = G + lead facing -x, throw the 36-stroke grid mirrored at the
##        door (noise-free), and for every lock: haul off, pump to T with
##        bot_pump's servo, snapshot every +x tick, fly the forecast picks
##        (+/-4) and print the widest run of LEDGE landings - the same number
##        climb_door_map prints for the launch from the lip.
##        leads: comma list of standing distances from the step edge
##        (default 0.4,0.8,1.2,1.8).
##   -- lip G h D W t T           THE CONTROL. Catch A from the lip side
##        (climb_door_map's stance and stroke), same pump and flight, in this
##        world. Must reproduce climb_door_map's window for the same G h, or
##        the slab's underside is in the way.
const DL := preload("res://tests/climb_door_lib.gd")
const TL := preload("res://tests/tapelib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")

## P = the pit's width (default G: the pit is the whole gap). gen_climb's
## levels use P = 2.8 whatever G is, so the recovery catch is a 1.8 m throw.
static func make_soft(G: float, h: float, D: float, W: float, t: float,
		P := -1.0) -> Node2D:
	if P <= 0.0:
		P = G
	var m: Node2D = TL.new_sim()
	m.save_enabled = false
	m.t_a.clear(); m.t_b.clear()
	m.t_arc_c.clear(); m.t_arc_r.clear(); m.t_arc_ang.clear()
	var pts: Array = [Vector2(-12.0, -25.0), Vector2(-12.0, 0.0),
		Vector2(0.0, 0.0), Vector2(0.0, D), Vector2(P, D), Vector2(P, 0.0),
		Vector2(G + W + 6.0, 0.0), Vector2(G + W + 6.0, -25.0)]
	for i in range(pts.size() - 1):
		m.t_a.append(pts[i]); m.t_b.append(pts[i + 1])
	# the slab, wound like steps.tscn's islands: top-left, top-right,
	# bottom-right, bottom-left, closed
	var sl: Array = [Vector2(G, -h), Vector2(G + W, -h),
		Vector2(G + W, -h + t), Vector2(G, -h + t)]
	for i in 4:
		m.t_a.append(sl[i]); m.t_b.append(sl[(i + 1) % 4])
	assert(m._fillet(Vector2(0.0, 0.0), 0.35))
	assert(m._fillet(Vector2(P, 0.0), 0.35))
	# the slab is an island: every corner 0.10, the level's island default
	# (0.35 on a 0.4 m side would eat the side)
	assert(m._fillet(Vector2(G, -h), 0.10))
	assert(m._fillet(Vector2(G + W, -h), 0.10))
	assert(m._fillet(Vector2(G + W, -h + t), 0.10))
	assert(m._fillet(Vector2(G, -h + t), 0.10))
	m._finish_terrain()
	m._clear_anchor_tables()
	m._add_anchor(DL.DOOR, DL.DOOR_R, 0, "DOOR")
	m._av_size()
	m.spawn = Vector2(-3.0, -m.BODY_R)
	m.goal_x = 999.0
	m._reset()
	return m

static func where_soft(m: Node2D, G: float, h: float, D: float, W: float) -> String:
	var b: Vector2 = m.body_pos
	var up: float = -(b.y + m.BODY_R)
	if b.x >= G - 0.05 and b.x <= G + W + 0.05 and absf(up - h) < 0.25:
		return "LEDGE"
	if b.x > 0.0 and absf(up) < 0.25:
		return "UNDER"
	if b.x < 0.0 and absf(up) < 0.25:
		return "F0"
	if b.x > 0.0 and absf(up + D) < 0.3:
		return "PIT"
	return "AIR"

## Hand open, cursor parked on the body, until still for 20 ticks or cap.
## A LEDGE must still be a LEDGE 90 ticks later.
static func fly_soft(m: Node2D, G: float, h: float, D: float, W: float,
		cap := 420) -> Dictionary:
	var still := 0
	var prev: Vector2 = m.body_pos
	var maxup: float = -m.body_pos.y - m.BODY_R
	for t in cap:
		prev = m.body_pos
		m.step_tick(m.body_pos, false)
		maxup = maxf(maxup, -m.body_pos.y - m.BODY_R)
		var sp: float = (m.body_pos - prev).length() * 60.0
		still = still + 1 if (m.grounded and sp < 0.25) else 0
		if still >= 20:
			break
	var w := where_soft(m, G, h, D, W)
	if w == "LEDGE":
		for t in 90:
			m.step_tick(m.body_pos, false)
		var w2 := where_soft(m, G, h, D, W)
		if w2 != "LEDGE":
			w = "SLID-" + w2
	return {"where": w, "x": m.body_pos.x, "maxup": maxup}

static func code(w: String) -> String:
	match w:
		"LEDGE": return "L"
		"UNDER": return "u"
		"PIT": return "p"
		"F0": return "0"
		"AIR": return "a"
	return "s" if w.begins_with("SLID") else "?"

## After a lock: haul, pump, and fly the forecast picks. Returns
## {"widest": ticks, "L": total L ticks, "hist": {code: n}, "lost": t}.
static func window(m: Node2D, T: float, G: float, h: float, D: float,
		W: float, npump := 480) -> Dictionary:
	DL.haul(m, 0)
	var prev: Vector2 = m.body_pos
	var snaps: Array = []
	var lost := -1
	for t in npump:
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, T)
		prev = m.body_pos
		m.step_tick(cur, true)
		if float(m.a_freelen[0]) < 0.0:
			lost = t
			break
		var v: Vector2 = (m.body_pos - prev) * 60.0
		if v.x > 0.0 and t >= 10:
			var xl := DL.ballistic_land(m.body_pos, v, h, m.BODY_R)
			var cand := not is_nan(xl) and xl > G - 1.5 and xl < G + W + 1.5
			snaps.append([t, m.snapshot(), cand])
	var fly_idx := {}
	for i in snaps.size():
		if bool(snaps[i][2]):
			for j in range(i - 4, i + 5):
				if j >= 0 and j < snaps.size() \
						and absi(int(snaps[j][0]) - int(snaps[i][0])) <= 4:
					fly_idx[j] = true
	var keys: Array = fly_idx.keys()
	keys.sort()
	var s := ""
	var last_t := -99
	var hist := {}
	for i: int in keys:
		if int(snaps[i][0]) - last_t > 1 and s != "":
			s += " "
		last_t = int(snaps[i][0])
		m.restore(snaps[i][1])
		var o := fly_soft(m, G, h, D, W)
		var c := code(String(o["where"]))
		s += c
		hist[c] = int(hist.get(c, 0)) + 1
	var widest := 0
	var total := 0
	var run := 0
	for ch in s:
		if ch == "L":
			run += 1; total += 1
			widest = maxi(widest, run)
		else:
			run = 0
	return {"widest": widest, "L": total, "hist": hist, "lost": lost,
		"flown": keys.size(), "s": s}

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var mode := String(a[0])
	var G := float(a[1]); var h := float(a[2]); var D := float(a[3])
	var W := float(a[4]); var t := float(a[5]); var T := float(a[6])
	var P := -1.0
	if mode == "lip" and a.size() > 7:
		P = float(a[7])
	var t0 := Time.get_ticks_msec()
	var m := make_soft(G, h, D, W, t, P)
	var hn := HN.new("null", "soft", 0)
	var tag := "G %.1f h %.1f D %.1f W %.1f t %.1f T %.0f P %.1f" % [G, h, D, W, t, T, P if P > 0.0 else G]
	if mode == "lip":
		# every stroke of the grid from the lip stance; windows for the first two locks
		var grid: Array = DL.grid36()
		var locks: Array = []
		for i in grid.size():
			var c: Dictionary = grid[i]
			m._reset()
			DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
			var r: Dictionary = DL.throw(m, 0, c, hn, false)
			if bool(r["lock"]):
				locks.append([i, float(r["tether"])])
		print("LIP %s | locks %d/36 | %s" % [tag, locks.size(), str(locks)])
		for e: Array in locks.slice(0, 2):
			var c: Dictionary = grid[int(e[0])]
			m._reset()
			DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
			DL.throw(m, 0, c, hn, false)
			var w := window(m, T, G, h, D, W)
			print("LIPWIN %s | stroke %2d tether %.2f | widest %d | L %d of %d flown | %s | %s"
				% [tag, int(e[0]), float(e[1]), int(w["widest"]), int(w["L"]),
				int(w["flown"]), str(w["hist"]), String(w["s"])])
		print("LIPDONE %s | %d s" % [tag, (Time.get_ticks_msec() - t0) / 1000.0])
	else:
		var leads: Array = [0.4, 0.8, 1.2, 1.8]
		if a.size() > 7:
			leads = []
			for q in String(a[7]).split(","):
				leads.append(float(q))
		var grid: Array = DL.grid36()
		var locks: Array = []
		for lead: float in leads:
			var n := 0
			var names := ""
			for i in grid.size():
				var c: Dictionary = grid[i]
				m._reset()
				DL.stand(m, G + lead, 0.0, DL._ang(float(c["a0"]), true))
				var r: Dictionary = DL.throw(m, 0, c, hn, true)
				if bool(r["lock"]):
					n += 1
					names += " %d" % i
					locks.append([lead, i, float(r["tether"])])
			print("FAR %s | lead %.1f | locks %d/36 |%s" % [tag, lead, n, names])
		# windows for up to 6 locks, spread over the list
		var pick: Array = []
		if locks.size() <= 6:
			pick = locks
		else:
			for j in 6:
				pick.append(locks[(j * locks.size()) / 6])
		for e: Array in pick:
			var c: Dictionary = grid[int(e[1])]
			m._reset()
			DL.stand(m, G + float(e[0]), 0.0, DL._ang(float(c["a0"]), true))
			var r: Dictionary = DL.throw(m, 0, c, hn, true)
			if not bool(r["lock"]):
				print("   lead %.1f stroke %d: lock did not repeat" % [e[0], e[1]])
				continue
			var w := window(m, T, G, h, D, W)
			print("FARWIN %s | lead %.1f stroke %2d (%s) tether %.2f | widest %d | L %d of %d flown | %s | lost %d | %s"
				% [tag, float(e[0]), int(e[1]), String(c["name"]), float(r["tether"]),
				int(w["widest"]), int(w["L"]), int(w["flown"]), str(w["hist"]),
				int(w["lost"]), String(w["s"])])
		print("FARDONE %s | %d locks over %d leads | %.0f s" % [tag, locks.size(),
			leads.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	m.free()
	quit(0)
