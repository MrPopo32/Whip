extends SceneTree
## Real gripped press sweep against tests/main_fix2.gd (window looks both ways
## + a self-crossing also qualifies). Two decisive throws:
##   school beam med - the one with a 67 ms hole in the middle of its window
##   shallow stroke  - a throw that must NEVER lock, only ever betray
## Line-for-line comparable with tests/press_sweep.gd (shipped).

const RUN := 230
const SRC := "res://tests/main_fix2.gd"

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

func _study(name: String, c: Array, lo: int, hi: int) -> void:
	var ps := ""
	var f := -1
	var l := -1
	var nl := 0
	var nt := 0
	for tp in range(lo, hi + 1):
		var m := _rig(c[0], c[1], c[2])
		var eng := -1
		var verdict := -1
		for t in RUN:
			m.step_tick(_tgt(m, t, c), t >= tp)
			if eng < 0 and m.a_freelen[0] >= 0.0:
				eng = t
			if eng >= 0 and m.a_locked[0] >= 0 and verdict < 0:
				verdict = m.a_locked[0]
		m.free()
		if eng < 0:
			ps += "."
			continue
		nt += 1
		if f < 0:
			f = tp
		l = tp
		if verdict == 1:
			ps += "L"
			nl += 1
		else:
			ps += "p"
	var holes := 0
	for i in range(ps.length()):
		var tp: int = lo + i
		if tp > f and tp < l and ps[i] == ".":
			holes += 1
	print("")
	print("=== %s ===" % name)
	print("press->  %s" % ps)
	print("catching %d (ticks %d..%d), interior DEAD %d, LOCKS %d"
		% [nt, f, l, holes, nl])

func _initialize() -> void:
	print("REAL GRIPPED SWEEP, tests/main_fix2.gd")
	_study("school beam med r=0.20 (shipped: 4 dead ticks, 68 locks)",
		[2.0, 2.2, 0.20, 0.85 * PI, -0.42 * PI, 9, true], 92, 200)
	_study("shallow stroke r=0.20 - MUST NEVER LOCK (shipped: 0 locks)",
		[2.0, 2.2, 0.20, 0.85 * PI, -0.30 * PI, 9, true], 76, 180)
	quit(0)
