extends SceneTree
## Same seven throws as tests/press_sweep.gd, same ranges, run against the
## patched copy tests/main_fix.gd (symmetric press window). Directly comparable
## line for line with the shipped output.

const RUN := 230
const SRC := "res://tests/main_fix.gd"

func _rig(dx: float, dy: float, r: float) -> Node2D:
	var m: Node2D = load(SRC).new()
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

func _tgt(m: Node2D, t: int, c: Array) -> Vector2:
	if t < 30:
		return m.body_pos + Vector2(cos(c[3]), sin(c[3])) * m.REACH
	if t < 30 + int(c[5]):
		return m.body_pos + Vector2(cos(c[4]), sin(c[4])) * m.REACH
	if bool(c[6]) and t < 30 + int(c[5]) + 10:
		return m.body_pos + Vector2(cos(c[3]), sin(c[3])) * m.REACH * 0.7
	return m.body_pos + Vector2(cos(c[4]), sin(c[4])) * m.REACH

func _press(c: Array, tp: int) -> Dictionary:
	var m := _rig(c[0], c[1], c[2])
	var eng := -1
	var verdict := -1
	var qual_at_eng := 0.0
	var lag := 0
	for t in RUN:
		m.step_tick(_tgt(m, t, c), t >= tp)
		if eng < 0 and m.a_freelen[0] >= 0.0:
			eng = t
			qual_at_eng = absf(m.a_theta[0])
			lag = m.tick_count - m.a_qtick[0]
		if eng >= 0 and m.a_locked[0] >= 0 and verdict < 0:
			verdict = m.a_locked[0]
	m.free()
	return {"eng": eng, "verdict": verdict, "th": qual_at_eng, "lag": lag}

func _study(name: String, c: Array, lo: int, hi: int) -> void:
	var ps := ""
	var first := -1
	var last := -1
	var nt := 0
	var nlock := 0
	var back := 0        # catches that only a BACKWARD look could have made
	var back_th := []
	for tp in range(lo, hi + 1):
		var r := _press(c, tp)
		if int(r["eng"]) < 0:
			ps += "."
			continue
		nt += 1
		if first < 0:
			first = tp
		last = tp
		if int(r["lag"]) > 0:
			back += 1
			back_th.append(absf(float(r["th"])))
		if int(r["verdict"]) == 1:
			ps += "L"
			nlock += 1
		else:
			ps += "p"
	var holes := 0
	for i in range(ps.length()):
		var tp: int = lo + i
		if tp > first and tp < last and ps[i] == ".":
			holes += 1
	print("")
	print("=== %s   r=%.2f at (%.1f,-%.1f) ===" % [name, c[2], c[0], c[1]])
	print("press->     %s" % ps)
	print("catching presses %d (first %d, last %d), interior DEAD ticks %d, locks %d"
		% [nt, first, last, holes, nlock])
	var lo_th := 99.0
	for v in back_th:
		lo_th = minf(lo_th, float(v))
	print("catches that needed the backward look: %d; lowest measured theta at any"
		% back)
	print("  such engagement: %.2f rad (th_rel=1.80, th_part=3.40)"
		% (lo_th if back > 0 else 0.0))

func _initialize() -> void:
	print("SYMMETRIC PRESS WINDOW (tests/main_fix.gd): +-15 ticks (+-250 ms)")
	_study("school beam, fat", [2.0, 2.2, 0.22, 0.85 * PI, -0.42 * PI, 9, true], 92, 200)
	_study("school beam, med", [2.0, 2.2, 0.20, 0.85 * PI, -0.42 * PI, 9, true], 92, 200)
	_study("door beam, thin, long lead", [2.6, 2.2, 0.11, 0.85 * PI, -0.42 * PI, 9, true], 70, 180)
	_study("door beam, thin, short lead", [1.4, 2.2, 0.11, 0.85 * PI, -0.42 * PI, 9, true], 100, 210)
	_study("fast beam, thinnest, high", [2.0, 2.6, 0.10, 0.85 * PI, -0.42 * PI, 9, true], 90, 200)
	_study("fast beam, thinnest, close", [1.4, 2.6, 0.10, 0.85 * PI, -0.42 * PI, 5, true], 92, 200)
	_study("shallow stroke, med beam", [2.0, 2.2, 0.20, 0.85 * PI, -0.30 * PI, 9, true], 76, 180)
	quit(0)
