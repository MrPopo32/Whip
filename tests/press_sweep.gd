extends SceneTree
## PHASE B - THE PRESS-TIMING WINDOW.
## Take a throw that definitely produces a good wrap. Sweep the tick at which
## the hand closes, from far too early to far too late, one full deterministic
## re-run per press tick, and report exactly which presses catch.
##
## Outcome alphabet per press tick:
##   .  nothing engaged at all      (the false negative under investigation)
##   p  engaged, classified PARTIAL (catches, then betrays)
##   L  engaged, classified LOCKED
## Baseline alphabet (same throw, grip never pressed):
##   Q  theta >= th_part AND lockidx >= pin_min_idx  (geometric gates pass)
##   x  chain crosses itself at the beam (_pinch) but theta gate fails
##   -  chain is in contact with the beam but neither gate passes
##   .  nothing near the beam

const RUN := 230

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

func _tgt(m: Node2D, t: int, c: Array) -> Vector2:
	var a0: float = c[3]
	var a1: float = c[4]
	var sd: int = c[5]
	var pull: bool = c[6]
	if t < 30:
		return m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH
	if pull and t < 30 + sd + 10:
		return m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
	return m.body_pos + Vector2(cos(a1), sin(a1)) * m.REACH

## how many chain vertices sit against the beam - "is a wrap visibly there"
func _contact(m: Node2D) -> int:
	var n := 0
	var c: Vector2 = m.a_pos[0]
	for i in m.pos.size():
		if (m.pos[i] - c).length() < m.a_r[0] + m.p_rad[i] + 0.06:
			n += 1
	return n

func _baseline(c: Array) -> Dictionary:
	var m := _rig(c[0], c[1], c[2])
	var th := PackedFloat32Array()
	var qual := PackedInt32Array()
	var pinch := PackedInt32Array()
	var touch := PackedInt32Array()
	for t in RUN:
		m.step_tick(_tgt(m, t, c), false)
		th.append(absf(m.a_theta[0]))
		qual.append(1 if (absf(m.a_theta[0]) >= m.th_part
			and m.a_lockidx[0] >= m.pin_min_idx) else 0)
		pinch.append(1 if m._pinch(0) else 0)
		touch.append(_contact(m))
	m.free()
	return {"th": th, "qual": qual, "pinch": pinch, "touch": touch}

func _press(c: Array, tp: int) -> Dictionary:
	var m := _rig(c[0], c[1], c[2])
	var eng := -1
	var verdict := -1
	var held := false
	for t in RUN:
		m.step_tick(_tgt(m, t, c), t >= tp)
		if eng < 0 and m.a_freelen[0] >= 0.0:
			eng = t
		if eng >= 0 and m.a_locked[0] >= 0 and verdict < 0:
			verdict = m.a_locked[0]
	held = m.a_freelen[0] >= 0.0
	var fin: int = m.a_locked[0]
	m.free()
	return {"eng": eng, "verdict": verdict, "held": held, "fin": fin}

func _study(name: String, c: Array, lo: int, hi: int) -> void:
	var b := _baseline(c)
	var th: PackedFloat32Array = b["th"]
	var qual: PackedInt32Array = b["qual"]
	var pinch: PackedInt32Array = b["pinch"]
	var touch: PackedInt32Array = b["touch"]
	var bs := ""
	for t in range(lo, hi + 1):
		if qual[t] == 1:
			bs += "Q"
		elif pinch[t] == 1:
			bs += "x"
		elif touch[t] >= 2:
			bs += "-"
		else:
			bs += "."
	var ps := ""
	var first_catch := -1
	var last_catch := -1
	var holes := 0
	var lock_ticks := 0
	var catch_ticks := 0
	var dead_while_touching := 0
	var results := []
	for tp in range(lo, hi + 1):
		var r := _press(c, tp)
		results.append(r)
		if int(r["eng"]) >= 0:
			catch_ticks += 1
			if first_catch < 0:
				first_catch = tp
			last_catch = tp
			if int(r["verdict"]) == 1:
				ps += "L"
				lock_ticks += 1
			else:
				ps += "p"
		else:
			ps += "."
			if touch[tp] >= 3:
				dead_while_touching += 1
	for i in range(results.size()):
		var tp: int = lo + i
		if tp > first_catch and tp < last_catch and int(results[i]["eng"]) < 0:
			holes += 1
	# first tick at which the geometric gates pass at all
	var q0 := -1
	for t in range(lo, hi + 1):
		if qual[t] == 1:
			q0 = t
			break
	print("")
	print("=== %s   beam r=%.2f at (%.1f, -%.1f) ===" % [name, c[2], c[0], c[1]])
	print("tick        %d%s%d" % [lo, " ".repeat(maxi(hi - lo - 6, 1)), hi])
	print("baseline    %s" % bs)
	print("press->     %s" % ps)
	print("first qualifying tick q0 = %d" % q0)
	print("catching presses: %d of %d ticks; earliest %d (%+d vs q0, %+d ms),"
		% [catch_ticks, hi - lo + 1, first_catch, first_catch - q0,
		int(round((first_catch - q0) * 1000.0 / 60.0))])
	print("                  latest %d (%+d vs q0, %+d ms); interior DEAD ticks: %d"
		% [last_catch, last_catch - q0, int(round((last_catch - q0) * 1000.0 / 60.0)),
		holes])
	print("locking presses:  %d ticks (%d ms of the sweep)"
		% [lock_ticks, int(round(lock_ticks * 1000.0 / 60.0))])
	print("presses that failed while >=3 chain vertices were ON the beam: %d (%d ms)"
		% [dead_while_touching, int(round(dead_while_touching * 1000.0 / 60.0))])
	# reaction-time model: player sees the wrap arrive at q0, presses q0+RT
	for rt in [9, 12, 15, 18]:
		var tp: int = q0 + rt
		if tp < lo or tp > hi:
			continue
		var r: Dictionary = results[tp - lo]
		var out := "NOTHING"
		if int(r["eng"]) >= 0:
			out = "LOCK" if int(r["verdict"]) == 1 else "partial"
		print("  reaction %3d ms -> press tick %3d -> %s"
			% [int(round(rt * 1000.0 / 60.0)), tp, out])

func _initialize() -> void:
	print("PRESS-TIMING WINDOW SWEEP.  GRIP_WINDOW=15 ticks forward-only (250 ms)")
	print("th_part=3.4  th_rel=1.8  pin_min_idx=3  PINCH_RUN=2  LOCK_WINDOW=30")
	# [dx, dy, r, a0, a1, sd, pull]
	_study("school beam, fat", [2.0, 2.2, 0.22, 0.85 * PI, -0.42 * PI, 9, true], 92, 200)
	_study("school beam, med", [2.0, 2.2, 0.20, 0.85 * PI, -0.42 * PI, 9, true], 92, 200)
	_study("door beam, thin, long lead", [2.6, 2.2, 0.11, 0.85 * PI, -0.42 * PI, 9, true], 70, 180)
	_study("door beam, thin, short lead", [1.4, 2.2, 0.11, 0.85 * PI, -0.42 * PI, 9, true], 100, 210)
	_study("fast beam, thinnest, high", [2.0, 2.6, 0.10, 0.85 * PI, -0.42 * PI, 9, true], 90, 200)
	_study("fast beam, thinnest, close", [1.4, 2.6, 0.10, 0.85 * PI, -0.42 * PI, 5, true], 92, 200)
	_study("shallow stroke, med beam", [2.0, 2.2, 0.20, 0.85 * PI, -0.30 * PI, 9, true], 76, 180)
	quit(0)
