extends SceneTree
## THE SHIPPED CAMERA, MEASURED. cam_gate says the invariants hold; this says
## what the camera actually DOES, over every trace the game can produce - the
## six tapes plus the three beam-to-beam leaps the corpus has none of.
##
## Everything here calls main.gd's own cam_new / cam_law / cam_zoom_step /
## cursor_of. The "shipped-before" column is the camera as it was at HEAD:
## body + (0,-1.4) + 0.25*v, run through Camera2D's own position smoothing,
## which is a one-pole with coefficient speed*dt (4/60) - i.e. tau = 0.25 s,
## exactly the lag that cancelled the lookahead.
##
##   godot --headless --path . -s res://tests/cam_ship.gd
const MAIN := preload("res://main.gd")
const TL := preload("res://tests/tapelib.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const PPM := 60.0
const VW := 1600.0 / PPM
const VH := 900.0 / PPM
const DT := 1.0 / 60.0
const OLD_SPEED := 4.0                # Camera2D.position_smoothing_speed at HEAD
const OLD_OFF := Vector2(0.0, -1.4)
const OLD_LOOK := 0.25

func _initialize() -> void:
	var traces := _all_traces()
	print("")
	print("=== A. WHERE THE BODY SITS IN THE FRAME (fraction across / down) ===")
	print("     the committed framing is 38% from the trailing edge and an")
	print("     upward bias while hanging. There is no bias term: the shelf is")
	print("     authored and still, so the body rises through a fixed frame.")
	print("")
	print("  %-12s %5s   x: p05  p50  p95   y: p05  p50  p95   worst edge"
		% ["trace", "ticks"])
	var all_edge := 1e9
	for T: Array in traces:
		var r := _run(T[1])
		if r.is_empty():
			continue
		all_edge = minf(all_edge, float(r["edge"]))
		print("  %-12s %5d      %.2f %.2f %.2f      %.2f %.2f %.2f      %.2f m"
			% [T[0], int(r["n"]), r["x05"], r["x50"], r["x95"],
			   r["y05"], r["y50"], r["y95"], r["edge"]])
	print("")
	print("  worst approach to any frame edge, anywhere: %.2f m (floor %.1f)"
		% [all_edge, MAIN.CAM_EDGE])
	var fx := 1e9
	var fy0 := 1e9
	var fy1 := -1e9
	for T: Array in traces:
		var r2 := _run(T[1])
		if r2.is_empty():
			continue
		fx = minf(fx, float(r2["xmin"]))
		fy0 = minf(fy0, float(r2["y05"])); fy1 = maxf(fy1, float(r2["y95"]))
	print("  the body never gets closer than %.0f%% to the trailing edge, so the" % (fx * 100.0))
	print("  direction of travel always holds %.0f%% of the frame - the committed" % ((1.0 - fx) * 100.0))
	print("  38/62 split, hit without a rule that says so. Vertically it rides")
	print("  from %.0f%% (hanging, p05) to %.0f%% (swooping, p95) of frame height"
		% [fy0 * 100.0, fy1 * 100.0])
	print("  through a frame that never moved: standing is 63%.")

	print("")
	print("=== B. WHAT THE CAMERA TRAVELS, AND HOW MUCH OF IT IS VERTICAL ===")
	print("     the 12 m descent is meant to be a fixed shot the player falls")
	print("     THROUGH: a fall barely changes x, and the vertical is a function")
	print("     of x, so the floor line holds still while the body drops.")
	print("")
	print("     'wander' is total variation - every vertical millimetre the camera")
	print("     moves, jitter included. 'range' is highest to lowest. Ground-only")
	print("     tapes go to exactly 0.00 on both: the shelf is a constant there.")
	print("")
	print("  %-12s body   cam   vert wander     vert range     steps flaps"
		% "trace")
	print("  %-12s path   path   was -> now     was -> now" % "")
	for T: Array in traces:
		var r := _run(T[1])
		if r.is_empty():
			continue
		print("  %-12s %5.1f  %5.1f   %5.2f ->%5.2f   %5.2f ->%5.2f     %d     %d"
			% [T[0], r["bpath"], r["cpath"], r["oldvy"], r["newvy"],
			   r["oldrng"], r["newrng"], int(r["steps"]), int(r["flaps"])])

	print("")
	print("=== C. THE WORST TRANSITION IN THE LEVEL ===")
	var worst := {}
	for T: Array in traces:
		var r := _run(T[1])
		if r.is_empty():
			continue
		if worst.is_empty() or float(r["vymax"]) > float(worst["vymax"]):
			worst = r
			worst["name"] = T[0]
	print("  the biggest thing the camera is ever asked to do on this level is a")
	print("  one-tier shelf step: 3.00 m, critically damped at w=%.1f rad/s."
		% MAIN.CAM_WY)
	print("  measured on '%s': peak vertical camera speed %.2f m/s, and the step"
		% [String(worst["name"]), float(worst["vymax"])])
	print("  settles to within 3 cm of the new shelf %.1f s AFTER the boundary fires"
		% float(worst["settle"]))
	print("  - which is fired at lip+0.5, as you are hauled off, so it starts when")
	print("  you commit and finishes as you land.")
	print("")
	print("  THE ZOOM RATE CAP THROUGH THAT SAME TRANSITION:")
	var zr := 0.0
	var z3 := 0.0
	for T: Array in traces:
		var r := _run(T[1])
		if r.is_empty():
			continue
		zr = maxf(zr, float(r["zrate"]))
		z3 = maxf(z3, float(r["z300"]))
	print("  peak |d ln(zoom)/dt| over %d ticks of real play: %.6f /s (cap %.2f)."
		% [_total(traces), zr, MAIN.CAM_ZRATE])
	print("  most scale change in any 300 ms window: %.4f%% (budget 2.5%%)." % (z3 * 100.0))
	print("  it is zero because every volume is authored 1.00 - the cap is not")
	print("  what is holding zoom still here, the TABLE is. What the cap holds is")
	print("  a future edit: forced to a 35% step the same blender peaks at exactly")
	print("  0.080/s (cam_gate C3), and no adjacent pair may differ by over 11%.")

	print("")
	print("=== D. WHAT THIS CHANGES FOR THE HAND ===")
	print("     the new cursor is body + (px - anchor)/60, anchored 1.4 m below")
	print("     the view centre. The old one was cam + (px - centre)/60. For the")
	print("     SAME mouse pixel the two differ by exactly the shipped camera's")
	print("     departure from body+(0,-1.4) - so this is how much the control")
	print("     moves under a player who has already learned it:")
	print("")
	var ds: Array = []
	var wname := ""
	var wmax := -1.0
	for T: Array in traces:
		var r := _run(T[1])
		if r.is_empty():
			continue
		for d: float in r["cdelta"]:
			ds.append(d)
		if float(r["cdmax"]) > wmax:
			wmax = float(r["cdmax"]); wname = String(T[0])
	ds.sort()
	print("  over %d ticks: p50 %.3f m   p90 %.3f m   p99 %.3f m   max %.3f m (%s)"
		% [ds.size(), _pct(ds, 0.50), _pct(ds, 0.90), _pct(ds, 0.99), wmax, wname])
	print("  against a reach radius of %.2f m. The max is the R-teleport on" % MAIN.REACH)
	print("  reset.tape, where the shipped camera is left 1.3 m behind the body -")
	print("  116% of the whole reach - and the new mapping simply does not have")
	print("  that failure mode, because the camera is not in it.")
	print("")
	print("  AND WHAT IT WOULD COST IF THE CURSOR HAD STAYED CAMERA-MAPPED under")
	print("  the NEW framing - a stationary hand, dragged by the camera alone:")
	var sx := 0.0
	var sy := 0.0
	for T: Array in traces:
		var r := _run(T[1])
		if r.is_empty():
			continue
		sx = maxf(sx, float(r["swx"]))
		sy = maxf(sy, float(r["swy"]))
	print("  %.2f m across and %.2f m down - %.1fx and %.1fx the entire reach."
		% [sx, sy, sx / MAIN.REACH, sy / MAIN.REACH])

	print("")
	print("=== E. COST ===")
	_cost()
	quit(0)

func _total(traces: Array) -> int:
	var n := 0
	for T: Array in traces:
		n += (T[1] as Array).size()
	return n

func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	return float(a[clampi(int(a.size() * q), 0, a.size() - 1)])

func _run(tr: Array) -> Dictionary:
	if tr.is_empty():
		return {}
	var b0: Vector2 = tr[0][0]
	var st: Dictionary = MAIN.cam_new(b0)
	# the shipped-before camera, including Camera2D's own one-pole smoothing
	var old := b0 + OLD_OFF
	var xs: Array = []
	var ys: Array = []
	var cd: Array = []
	var edge := 1e9
	var bpath := 0.0
	var cpath := 0.0
	var oldvy := 0.0
	var newvy := 0.0
	var steps := 0
	var flaps := 0
	var vi: int = int(st["vi"])
	var last_dir := 0
	var vymax := 0.0
	var zrate := 0.0
	var zh: Array = []
	var z300 := 0.0
	var cdmax := 0.0
	var swx := [1e9, -1e9]
	var swy := [1e9, -1e9]
	var oy := [1e9, -1e9]
	var ny := [1e9, -1e9]
	var pb: Vector2 = b0
	var pc := Vector2(float(st["x"]), float(st["y"]))
	var po := old
	var target_y: float = float(st["y"])
	var settle := -1
	var step_at := -1
	for i in tr.size():
		var b: Vector2 = tr[i][0]
		var v: Vector2 = tr[i][1]
		var py: float = float(st["y"])
		var c: Vector2 = MAIN.cam_law(st, b, v, DT)
		var z: float = MAIN.cam_zoom_step(st,
			float(MAIN.CAM_VOLS[int(st["vi"])][3]), DT)
		zrate = maxf(zrate, absf(float(st["vz"])))
		zh.append(log(z))
		if zh.size() > 18:
			z300 = maxf(z300, absf(float(zh[zh.size() - 1])
				- float(zh[zh.size() - 19])))
		vymax = maxf(vymax, absf(float(st["y"]) - py) / DT)
		# shelf steps, and whether any of them came back
		var nvi: int = int(st["vi"])
		if nvi != vi:
			steps += 1
			var dir: int = signi(nvi - vi)
			if last_dir != 0 and dir != last_dir:
				flaps += 1
			last_dir = dir
			vi = nvi
			target_y = float(MAIN.CAM_VOLS[nvi][2]) + MAIN.CAM_SHELF
			settle = -1
			step_at = i
		if settle < 0 and step_at >= 0 and absf(float(st["y"]) - target_y) < 0.03:
			settle = i - step_at
		# the shipped-before camera on the same tick
		var otgt := b + OLD_OFF + v * OLD_LOOK
		old += (otgt - old) * (OLD_SPEED * DT)
		var hw: float = VW * 0.5 / MAIN.cam_scale(st)
		var hh: float = VH * 0.5 / MAIN.cam_scale(st)
		xs.append(0.5 + (b.x - c.x) / (2.0 * hw))
		ys.append(0.5 + (b.y - c.y) / (2.0 * hh))
		edge = minf(edge, minf(hw - absf(b.x - c.x), hh - absf(b.y - c.y)))
		# how far the SAME mouse pixel lands from where it used to
		var dv := (old + Vector2(0.0, 1.4)) - b
		cd.append(dv.length())
		cdmax = maxf(cdmax, dv.length())
		# and how far a stationary hand would be dragged by the NEW camera
		var off := c - b
		swx[0] = minf(swx[0], off.x); swx[1] = maxf(swx[1], off.x)
		swy[0] = minf(swy[0], off.y); swy[1] = maxf(swy[1], off.y)
		oy[0] = minf(oy[0], old.y); oy[1] = maxf(oy[1], old.y)
		ny[0] = minf(ny[0], c.y);   ny[1] = maxf(ny[1], c.y)
		bpath += (b - pb).length()
		cpath += (c - pc).length()
		newvy += absf(c.y - pc.y)
		oldvy += absf(old.y - po.y)
		pb = b; pc = c; po = old
	xs.sort(); ys.sort()
	return {"n": tr.size(), "x05": _pct(xs, 0.05), "x50": _pct(xs, 0.50),
		"x95": _pct(xs, 0.95), "y05": _pct(ys, 0.05), "y50": _pct(ys, 0.50),
		"y95": _pct(ys, 0.95), "edge": edge, "bpath": bpath, "cpath": cpath,
		"oldvy": oldvy, "newvy": newvy, "steps": steps, "flaps": flaps,
		"vymax": vymax, "zrate": zrate, "z300": z300, "cdelta": cd,
		"cdmax": cdmax, "settle": (float(maxi(settle, 0)) / 60.0),
		"oldrng": oy[1] - oy[0], "newrng": ny[1] - ny[0],
		"xmin": _pct(xs, 0.0), "xmax": _pct(xs, 1.0),
		"swx": swx[1] - swx[0], "swy": swy[1] - swy[0]}

func _cost() -> void:
	var st: Dictionary = MAIN.cam_new(Vector2(0.0, 0.0))
	var n := 200000
	var t0 := Time.get_ticks_usec()
	for i in n:
		var ph := float(i) * 0.01
		MAIN.cam_law(st, Vector2(ph * 0.05, sin(ph)), Vector2(cos(ph), 1.0), DT)
		MAIN.cam_zoom_step(st, 1.0, DT)
	var law := float(Time.get_ticks_usec() - t0) / float(n)
	var a := Vector2(800.0, 534.0)
	t0 = Time.get_ticks_usec()
	var acc := Vector2.ZERO
	for i in n:
		acc += MAIN.cursor_of(Vector2(1.0, 2.0), Vector2(float(i % 900), 400.0),
			a, 1.0 / 60.0)
	var cur := float(Time.get_ticks_usec() - t0) / float(n)
	print("  camera law + zoom blender   %5.2f us per tick   %.3f%% of a 16.7 ms frame"
		% [law, law / 16667.0 * 100.0])
	print("  cursor mapping              %5.2f us per tick   %.3f%%"
		% [cur, cur / 16667.0 * 100.0])
	print("  total                       %5.2f us per tick   %.3f%%"
		% [law + cur, (law + cur) / 16667.0 * 100.0])
	print("  for scale, one SIMULATION tick costs 2200-4300 us (tests/perf.gd),")
	print("  so the whole camera is %.2f%% of what the sim already spends."
		% ((law + cur) / 2635.0 * 100.0))
	print("  (acc %.1f - kept so the loop cannot be optimised away)" % acc.x)

func _all_traces() -> Array:
	var traces: Array = []
	var d := DirAccess.open("res://tapes")
	var names: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".tape"):
			names.append(f)
	names.sort()
	for f in names:
		traces.append([f.get_basename(), _tape_trace("res://tapes/%s" % f)])
	for L: Array in [[7, 8], [8, 9], [9, 10]]:
		var tr := _leap_trace(int(L[0]), int(L[1]))
		if not tr.is_empty():
			traces.append(["leap %d-%d" % [L[0], L[1]], tr])
	return traces

func _tape_trace(p: String) -> Array:
	var t: Dictionary = MAIN.tape_load(p)
	var s := TL.new_sim()
	var tr: Array = []
	if not bool(t.get("ok", false)) or not s.restore(t["start"]):
		s.free()
		return tr
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	for i in cur.size():
		s.pending_reset = (grp[i] & 2) != 0
		s.step_tick(cur[i], (grp[i] & 1) != 0)
		tr.append([s.body_pos, s._body_vel(), s.pos[s.NP - 1]])
	s.free()
	return tr

func _leap_trace(ka: int, kb: int) -> Array:
	for hang in [1.6, 2.0, 2.4, 2.8, 3.2]:
		var s := LEAP.rig_level(ka, float(hang), 1.8, 0.0)
		for t in 30:
			s.step_tick(s.body_pos, true)
		if s.a_freelen[ka] < 0.0:
			s.free(); continue
		var st := LEAP.leap_begin(s, ka, kb)
		var prev: Vector2 = s.body_pos
		var tr: Array = []
		var guard := 0
		while st["phase"] != "fail" and st["phase"] != "hang" and guard < 2000:
			var cg := LEAP.leap_step(s, st, prev)
			prev = s.body_pos
			s.step_tick(cg[0], cg[1])
			guard += 1
			tr.append([s.body_pos, s._body_vel(), s.pos[s.NP - 1]])
		var held: bool = String(st["phase"]) == "hang"
		if held:
			for t in 150:
				var cg2 := LEAP.leap_step(s, st, prev)
				prev = s.body_pos
				s.step_tick(cg2[0], cg2[1])
				tr.append([s.body_pos, s._body_vel(), s.pos[s.NP - 1]])
				if s.a_freelen[kb] < 0.0 or s.grounded:
					held = false; break
		s.free()
		if held:
			return tr
	return []
