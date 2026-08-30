extends SceneTree
## PHASE A of the press-timing study.
## Find throws that DEFINITELY produce a good wrap, with NO grip pressed at all,
## and report the shape of the qualifying window they leave for the player:
##   qualify = theta >= th_part AND lockidx >= pin_min_idx   (the two geometric
##   gates; the third gate, the grip window, is what we are about to measure)
## Also reports when the chain actually crosses itself (_pinch), because that
## crossing is what turns a catch into a LOCK rather than a betrayal.

const RUN := 220

func _rig(dx: float, dy: float, r: float) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -dy)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R)
	m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p
		m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

func _tgt(m: Node2D, t: int, a0: float, a1: float, sd: int, pull: bool) -> Vector2:
	if t < 30:
		return m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH
	if pull and t < 30 + sd + 10:
		return m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
	return m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH

func _baseline(dx: float, dy: float, r: float, a0: float, a1: float,
		sd: int, pull: bool) -> Dictionary:
	var m := _rig(dx, dy, r)
	var th := PackedFloat32Array()
	var qual := PackedInt32Array()
	var pinch := PackedInt32Array()
	for t in RUN:
		m.step_tick(_tgt(m, t, a0, a1, sd, pull), false)
		var x: float = absf(m.a_theta[0])
		th.append(x)
		qual.append(1 if (x >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx) else 0)
		pinch.append(1 if m._pinch(0) else 0)
	var peak := 0.0
	var q0 := -1
	var q1 := -1
	var qn := 0
	var p0 := -1
	var pn := 0
	for t in RUN:
		peak = maxf(peak, th[t])
		if qual[t] == 1:
			if q0 < 0:
				q0 = t
			q1 = t
			qn += 1
		if pinch[t] == 1:
			if p0 < 0:
				p0 = t
			pn += 1
	m.free()
	return {"peak": peak, "q0": q0, "q1": q1, "qn": qn, "p0": p0, "pn": pn,
		"th": th, "qual": qual, "pinch": pinch}

func _initialize() -> void:
	print("PHASE A - what does an ungripped good throw leave you to press at?")
	print("th_part=3.4  pin_min_idx=3  GRIP_WINDOW=15 ticks (250 ms)")
	print("")
	print("  r    dx   dy  a0/pi a1/pi sd pull | peak  qual[first..last] n  pinch@ n")
	var best_by_r := {}
	for r in [0.22, 0.20, 0.11, 0.10]:
		for dy in [2.2, 2.6]:
			for dx in [1.4, 2.0, 2.6]:
				for a0 in [0.85, 1.10]:
					for a1 in [-0.42, -0.30, -0.18, -0.05]:
						for sd in [5, 9, 14]:
							for pull in [false, true]:
								var d := _baseline(dx, dy, r, a0 * PI, a1 * PI,
									sd, pull)
								if d["qn"] < 1:
									continue
								var key := "%.2f" % r
								var score: int = d["qn"]
								if not best_by_r.has(key) or score > int(best_by_r[key]["qn"]):
									best_by_r[key] = {"qn": score, "line":
										"%.2f %4.1f %4.1f  %.2f %5.2f %2d %s | %5.2f  [%3d..%3d] %3d  %3d %3d"
										% [r, dx, dy, a0, a1, sd,
										("T" if pull else "F"), d["peak"],
										d["q0"], d["q1"], d["qn"], d["p0"], d["pn"]],
										"cfg": [dx, dy, r, a0, a1, sd, pull],
										"d": d}
								print("%.2f %4.1f %4.1f  %.2f %5.2f %2d %s | %5.2f  [%3d..%3d] %3d  %3d %3d"
									% [r, dx, dy, a0, a1, sd,
									("T" if pull else "F"), d["peak"],
									d["q0"], d["q1"], d["qn"], d["p0"], d["pn"]])
	print("")
	print("BEST PER RADIUS (longest qualifying window):")
	for k in best_by_r.keys():
		print("  ", best_by_r[k]["line"])
		var d: Dictionary = best_by_r[k]["d"]
		var th: PackedFloat32Array = d["th"]
		var qual: PackedInt32Array = d["qual"]
		var pinch: PackedInt32Array = d["pinch"]
		var s := ""
		var lo: int = maxi(int(d["q0"]) - 12, 0)
		var hi: int = mini(int(d["q1"]) + 25, RUN - 1)
		for t in range(lo, hi + 1):
			s += ("Q" if qual[t] == 1 else ("x" if pinch[t] == 1 else "."))
		print("    ticks %d..%d  %s" % [lo, hi, s])
		var s2 := ""
		for t in range(lo, hi + 1):
			s2 += "%.1f " % th[t]
		print("    theta: ", s2)
	quit(0)
