extends SceneTree
## DESIGN CRITIC'S OWN INSTRUMENT. Independent of tests/lab_throw.gd except for
## the bench posture (stand_at), which that file measured and I re-use.
##
##   godot --headless --path . -s res://tests/crit_lab.gd -- <mode>
## modes: time | ring | basin | regrab
const MAIN := preload("res://main.gd")

func new_lab() -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = "lab"
	m.setup_sim()
	m.save_enabled = false
	return m

func stand_at(m: Node2D, x: float, a0: float) -> void:
	m.teleport(Vector2(x, -m.BODY_R))
	for t in 90:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)

func touching(m: Node2D, k: int) -> bool:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

func band_count(m: Node2D, k: int) -> int:
	var n := 0
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			n += 1
	return n

func min_gap(m: Node2D, k: int) -> float:
	var g := 1.0e9
	for i in m.NP:
		g = minf(g, (m.pos[i] - m.a_pos[k]).length()
			- (m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02))
	return g

# ---------------------------------------------------------------- a throw ---
func throw_once(m: Node2D, k: int, c: Dictionary, policy: String) -> Dictionary:
	var grip := false
	var closes := 0
	var sd: int = int(c["sd"])
	var pull: bool = bool(c["pull"])
	var w: int = int(c["w"])
	var caught := false
	for t in w + 130:
		var ang: float
		var amp := 1.0
		if t < w:
			ang = float(c["a0"])
		elif t < w + sd:
			ang = float(c["a1"])
		elif pull and t < w + 10 + sd:
			ang = float(c["a0"]); amp = 0.7
		else:
			ang = float(c["a1"])
		var tgt: Vector2 = m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var cue := absf(float(m.a_theta[k])) >= 2.6 if policy == "wrap" \
			else touching(m, k)
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			break
	if not caught:
		return {"ok": false, "green": false, "th": 0.0, "band": 0, "lockidx": -1}
	var th_at := absf(float(m.a_theta[k]))
	var band_at := band_count(m, k)
	var li: int = int(m.a_lockidx[k])
	for t in 55:
		m.step_tick(m.body_pos, true)
		if float(m.a_freelen[k]) < 0.0:
			break
	return {"ok": float(m.a_freelen[k]) >= 0.0, "green": bool(m._holds(k)),
		"th": th_at, "band": band_at, "lockidx": li,
		"th_set": absf(float(m.a_theta[k]))}

func strip_floor(m: Node2D) -> void:
	m.t_a = PackedVector2Array(); m.t_b = PackedVector2Array()
	m.t_n = PackedVector2Array(); m.t_lo = PackedVector2Array()
	m.t_hi = PackedVector2Array(); m.world_bottom = 1.0e9

const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]

func run_cell(k: int, lead: float, ang: Array, sd: int, pull: bool,
		policy: String, jam_override: int) -> Dictionary:
	var m := new_lab()
	if jam_override >= 0:
		var j: PackedInt32Array = m.a_jam
		j[k] = jam_override
		m.a_jam = j
	stand_at(m, float(m.a_pos[k].x) - lead, float(ang[0]))
	var r := throw_once(m, k, {"a0": ang[0], "a1": ang[1], "sd": sd,
		"pull": pull, "w": 120}, policy)
	m.free()
	return r

func _initialize() -> void:
	var mode := "time"
	var av := OS.get_cmdline_user_args()
	if av.size() > 0:
		mode = av[0]
	match mode:
		"time": _time()
		"ring": _ring()
		"basin": _basin()
		"regrab": _regrab()
	quit(0)

func _time() -> void:
	var t0 := Time.get_ticks_msec()
	for i in 8:
		run_cell(2, 2.0, GRID[i % 6], 9, false, "touch", -1)
	var dt := Time.get_ticks_msec() - t0
	print("8 throws in %d ms -> %.0f ms/throw" % [dt, float(dt) / 8.0])

# ------------------------------------------------------- RING CENSUS --------
func _ring() -> void:
	print("")
	print("RING CENSUS. For every stroke in the 108-cell grid that CAUGHT, the")
	print("wrap angle |theta| at the catch tick, and then, over a 3 s hang with")
	print("the floor removed, how many held ticks draw NO instrument at all")
	print("(main.gd:2049 gates the arc on |theta| > 0.3).")
	print("")
	print(" station        cue    jam  caught green | th@catch dark/caught | hangs dark/heldticks mingap(mm)")
	var m0 := new_lab()
	var names: Array[String] = []
	var jams: Array[int] = []
	for k in m0.a_pos.size():
		names.append(String(m0.a_name[k]))
		jams.append(int(m0.a_jam[k]))
	m0.free()
	for k in names.size():
		for policy in ["wrap", "touch"]:
			var ovs: Array[int] = [-1]
			if jams[k] == 1:
				ovs = [-1, 0]
			for ov in ovs:
				var caught := 0
				var green := 0
				var ths: Array[float] = []
				var dark := 0
				var winners: Array = []
				for lead in [1.6, 2.0, 2.4]:
					for ang: Array in GRID:
						for sd in [5, 9, 14]:
							for pull in [false, true]:
								var r := run_cell(k, lead, ang, sd, pull,
									policy, ov)
								if bool(r["ok"]):
									caught += 1
									ths.append(float(r["th"]))
									if float(r["th"]) <= 0.3:
										dark += 1
									if bool(r["green"]):
										green += 1
										if winners.size() < 3:
											winners.append([lead, ang, sd, pull])
				var hangs := 0
				var darkt := 0
				var heldt := 0
				var mg := 1.0e9
				for wcfg: Array in winners:
					var m := new_lab()
					if ov >= 0:
						var j: PackedInt32Array = m.a_jam
						j[k] = ov
						m.a_jam = j
					var wa: Array = wcfg[1]
					stand_at(m, float(m.a_pos[k].x) - float(wcfg[0]), float(wa[0]))
					var rr := throw_once(m, k, {"a0": wa[0], "a1": wa[1],
						"sd": wcfg[2], "pull": wcfg[3], "w": 120}, policy)
					if not bool(rr["ok"]):
						m.free()
						continue
					strip_floor(m)
					hangs += 1
					for t in 180:
						m.step_tick(m.body_pos, true)
						if float(m.a_freelen[k]) >= 0.0:
							heldt += 1
							mg = minf(mg, min_gap(m, k))
							if absf(float(m.a_theta[k])) <= 0.3:
								darkt += 1
					m.free()
				var thmed := 0.0
				if ths.size() > 0:
					ths.sort()
					thmed = ths[ths.size() / 2]
				var tag := "on " if (jams[k] == 1 and ov != 0) else "off"
				print(" %-2d %-11s %-6s %-4s %6d %5d | %7.3f  %4d/%-4d | %4d %6d/%-6d %8.1f"
					% [k, names[k], policy, tag, caught, green, thmed, dark,
					caught, hangs, darkt, heldt,
					(mg * 1000.0) if mg < 1e8 else 0.0])

# ------------------------------------------------------------ BASIN ---------
func _basin() -> void:
	var step := 0.005
	print("")
	print("BASIN SCAN. One fixed stroke shape, lead swept 1.40 -> 2.60 m in")
	print("5 mm steps, 241 throws per row. The sim has no RNG, so a verdict")
	print("that flips between neighbouring 5 mm cells is not randomness - it")
	print("is a basin finer than a player can aim. blocks = maximal runs of")
	print("consecutive GREEN leads.")
	print("")
	print(" station        cue    jam  green/241 blocks widest(mm) med(mm)  map (5mm/char)")
	var rows := [
		[0, "wrap", -1], [0, "touch", -1],
		[1, "touch", -1],
		[2, "touch", -1], [2, "touch", 0], [2, "wrap", -1],
		[3, "touch", -1], [3, "touch", 0],
	]
	var ang: Array = GRID[4]
	var m0 := new_lab()
	var names: Array[String] = []
	for k in m0.a_pos.size():
		names.append(String(m0.a_name[k]))
	m0.free()
	for row: Array in rows:
		var k: int = row[0]
		var policy: String = row[1]
		var ov: int = row[2]
		var hits: Array[bool] = []
		var lead := 1.40
		while lead <= 2.6005:
			var r := run_cell(k, lead, ang, 9, false, policy, ov)
			hits.append(bool(r["green"]))
			lead += step
		var blocks: Array[int] = []
		var run := 0
		for h in hits:
			if h:
				run += 1
			elif run > 0:
				blocks.append(run)
				run = 0
		if run > 0:
			blocks.append(run)
		var g := 0
		for h in hits:
			if h:
				g += 1
		var widest := 0
		for b in blocks:
			widest = maxi(widest, b)
		var med := 0
		if blocks.size() > 0:
			var srt := blocks.duplicate()
			srt.sort()
			med = srt[srt.size() / 2]
		var map := ""
		for h in hits:
			map += "#" if h else "."
		print(" %-2d %-11s %-6s %-4s %4d/%-4d %5d %8d %8d  %s"
			% [k, names[k], policy, ("on " if ov != 0 else "off"), g,
			hits.size(), blocks.size(), int(widest * step * 1000.0),
			int(med * step * 1000.0), map])

# ------------------------------------------------------------ REGRAB --------
func _regrab() -> void:
	print("")
	print("RE-GRAB. Catch it, take the floor away, OPEN the hand for N ticks,")
	print("then press again and hold 60 ticks. Y = the anchor took you back")
	print("with no fresh throw.")
	print("")
	print(" station     jam   rel_tick   +1 +3 +6 +10 +20 +40   fall_by_+40(m)")
	for k in [0, 2, 3]:
		var mi := new_lab()
		var nm := String(mi.a_name[k])
		var jm := int(mi.a_jam[k])
		mi.free()
		var policy := "touch" if jm == 1 else "wrap"
		var found := {}
		for lead in [1.6, 2.0, 2.4]:
			for a: Array in GRID:
				for sd in [5, 9, 14]:
					if found.is_empty():
						var rr := run_cell(k, lead, a, sd, false, policy, -1)
						if bool(rr["green"]):
							found = {"lead": lead, "a": a, "sd": sd}
		if found.is_empty():
			print(" %-2d %-11s no green stroke" % [k, nm])
			continue
		var res: Array[String] = []
		var relt := -1
		var fall := 0.0
		var fa: Array = found["a"]
		for delay in [1, 3, 6, 10, 20, 40]:
			var m2 := new_lab()
			stand_at(m2, float(m2.a_pos[k].x) - float(found["lead"]), float(fa[0]))
			var r2 := throw_once(m2, k, {"a0": fa[0], "a1": fa[1],
				"sd": found["sd"], "pull": false, "w": 120}, policy)
			if not bool(r2["ok"]):
				m2.free()
				res.append("- ")
				continue
			strip_floor(m2)
			var y0: float = m2.body_pos.y
			var rt := -1
			for t in delay:
				m2.step_tick(m2.body_pos, false)
				if rt < 0 and float(m2.a_freelen[k]) < 0.0:
					rt = t
			relt = rt
			var back := false
			for t in 60:
				m2.step_tick(m2.body_pos, true)
				if float(m2.a_freelen[k]) >= 0.0:
					back = true
					break
			if delay == 40:
				fall = m2.body_pos.y - y0
			res.append("Y " if back else "n ")
			m2.free()
		print(" %-2d %-11s %-4s %6d     %s %s        %.2f"
			% [k, nm, ("on " if jm == 1 else "off"), relt, res[0],
			" ".join(res.slice(1)), fall])
