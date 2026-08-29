extends SceneTree
## stuck_probe - hunt for whip particles that become, and STAY, embedded in
## terrain ("the whip got stuck in the floor").
##
##   godot --headless --path . -s res://tests/stuck_probe.gd
##
## Part 1 (U) unit-tests the collision routines directly with hand-set state:
##            sidedness, the thin-shell blind spot, the swept one-way valve,
##            the friction cap magnitude, the per-index tunnel threshold.
## Part 2 (E,a-d) drives the REAL sim through violent strokes at every terrain
##            feature, then holds the hand still (or hauls it away, or keeps
##            cracking) and watches for a particle that stays on the solid side.
## Part 3 (T) substep-resolution trace of one reproduction.
##
## The inside-test is an INDEPENDENT oracle built from the level's known solid
## regions - it does NOT reuse main.gd's collision code, so it cannot inherit
## the same blind spot.

const SIM := "res://main.gd"
const SDT := 1.0 / 60.0 / 16.0
const STUCK_TICKS := 30            # consecutive embedded ticks == "stuck"

var repros: Array = []
var entries: Array = []            # first-crossing records

# ------------------------------------------------------------------ oracle --
# solid regions of _build_level():
#   upper tier : x in [-14,20], y > 0      lower tier : x in [20,62], y > 3
#   left wall  : x < -14, y in [-8,0]      far seal   : x > 62,  y in [-4,3]
func _depth(p: Vector2) -> float:
	var d := -1e9
	if p.x >= -14.0 and p.x <= 20.0:
		d = maxf(d, p.y)
	if p.x >= 20.0 and p.x <= 62.0:
		d = maxf(d, p.y - 3.0)
	if p.x <= -14.0 and p.y >= -8.0 and p.y <= 0.0:
		d = maxf(d, -14.0 - p.x)
	if p.x >= 62.0 and p.y >= -4.0 and p.y <= 3.0:
		d = maxf(d, p.x - 62.0)
	return d

func _near_seg(m: Node2D, p: Vector2) -> String:
	var best := 1e9
	var bi := -1
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		var ab := B - A
		var tt := clampf((p - A).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var dd := (A + ab * tt).distance_to(p)
		if dd < best:
			best = dd
			bi = s
	if bi < 0:
		return "none"
	return "S%d (%.0f,%.0f)->(%.0f,%.0f) dist %.4f" % [bi,
		m.t_a[bi].x, m.t_a[bi].y, m.t_b[bi].x, m.t_b[bi].y, best]

func _floor_y(m: Node2D, x: float) -> float:
	var best := 99.0
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		if absf(B.x - A.x) < 0.01:
			continue
		if x < minf(A.x, B.x) or x > maxf(A.x, B.x):
			continue
		var t := (x - A.x) / (B.x - A.x)
		best = minf(best, A.y + (B.y - A.y) * t)
	return best

# ------------------------------------------------------------------- setup --
func _new() -> Node2D:
	var m: Node2D = load(SIM).new()
	m.external_drive = true
	m.setup_sim()
	return m

func _stand(m: Node2D, bx: float, trail := -1.0) -> void:
	var fy := _floor_y(m, bx)
	m.body_pos = Vector2(bx, fy - m.BODY_R)
	m.body_prv = m.body_pos
	for i in m.pos.size():
		var px: float = bx + 0.3 + trail * m.cum_len[i] * 0.99
		var py := _floor_y(m, px)
		if py > 90.0:
			py = fy
		var p := Vector2(px, minf(py, fy) - m.p_rad[i])
		m.pos[i] = p
		m.prv[i] = p

func _target(m: Node2D, t: int, a0: float, a1: float, a_hold: float,
		wind: int, sd: int, settle: int, mode: String) -> Vector2:
	var body: Vector2 = m.body_pos
	if t < settle:
		return body + Vector2(0.35, -0.55)
	if t < settle + wind:
		return body + Vector2.from_angle(a0) * m.REACH
	if t < settle + wind + sd:
		return body + Vector2.from_angle(a1) * m.REACH
	if mode == "yank":
		return body + Vector2.from_angle(a_hold) * m.REACH
	if mode == "recrack":
		var ph := (t - settle - wind - sd) % 70
		return body + Vector2.from_angle(a0 if ph < 40 else a1) * m.REACH
	return body + Vector2.from_angle(a_hold) * m.REACH * 0.7

# ================================================== PART 1: unit the code ==
func _unit_tests() -> void:
	var m := _new()
	var i := 25
	var pr: float = m.p_rad[i]
	print("")
	print("########### PART 1 - unit tests on the collision routines ###########")
	print("  sim under test: %s" % SIM)
	print("  tip p_rad = %.4f m, SDT = 1/%d s, 1 m/s = %.5f m per substep"
		% [pr, int(1.0 / SDT), SDT])

	# --- U1: which side does _collide_point resolve to? ---
	print("")
	print("=== U1  _collide_point sidedness (flat floor y=0, particle %d) ===" % i)
	print("   start_y (+ = inside)  ->  end_y      resolved to")
	var u1: Array[float] = [-0.010, -0.001, 0.001, 0.005, 0.010, 0.019,
		0.021, 0.050, 0.120]
	for sy in u1:
		var start := Vector2(0.0, sy)
		m.pos[i] = start
		m.prv[i] = start
		var check: Vector2 = m.pos[i]
		if absf(check.y - sy) > 1e-6:
			print("   !! probe could not stage the state (got %.4f)" % check.y)
			break
		m._collide_point(i, pr)
		var ey: float = m.pos[i].y
		var side := "UNTOUCHED - collision code blind at this depth"
		if absf(ey - sy) > 1e-6:
			side = "pushed ABOVE floor (correct)" if ey < 0.0 \
				else "pushed BELOW floor (WRONG SIDE)"
		print("   %+9.4f              ->  %+9.4f  %s" % [sy, ey, side])

	# --- U2: _swept_terrain as a one-way valve ---
	print("")
	print("=== U2  _swept_terrain on a particle ESCAPING upward through the floor ===")
	print("  prv is BELOW the floor, pos is ABOVE it: the particle is on its way OUT")
	print("   from_y    to_y      up m/s  ->  end_y     verdict")
	var u2d: Array[float] = [0.05, 0.15, 0.40]
	var u2v: Array[float] = [10.0, 25.0, 60.0, 120.0, 400.0]
	for d0 in u2d:
		for up in u2v:
			var p0 := Vector2(0.0, d0)
			var p1 := Vector2(0.0, d0 - up * SDT)
			if p1.y > 0.0:
				continue                # did not reach the floor this substep
			m.prv[i] = p0
			m.pos[i] = p1
			m._swept_terrain(i)
			var ey: float = m.pos[i].y
			var vy: float = (m.pos[i].y - m.prv[i].y) / SDT
			var verdict := "let out (escapes)"
			if ey > 0.0:
				verdict = "SHOVED BACK UNDER (vel now %+.2f m/s)" % vy
			print("   %+8.4f  %+8.4f  %6.0f  ->  %+8.4f  %s"
				% [p0.y, p1.y, up, ey, verdict])

	# --- U3: friction cap magnitude ---
	print("")
	print("=== U3  _friction cap, in m/s of tangential velocity killed per substep ===")
	var g: float = 10.0 * SDT * SDT
	print("  cap = mu*(|vn| + pen + g*SDT*SDT);  mu = 0.30")
	print("  g*SDT*SDT = %.9f m  (utterly negligible next to pen)" % g)
	print("   caller                      pen      vn m/s  cap (m)   kills up to m/s")
	var u3v: Array[float] = [0.0, 5.0, 20.0, 80.0]
	for vn in u3v:
		var cap_pt: float = 0.30 * (absf(vn * SDT) + 0.002 + g)
		print("   _collide_point pen~0.002   %-8.4f %-7.0f %-9.5f %.2f"
			% [0.002, vn, cap_pt, cap_pt / SDT])
	for vn in u3v:
		var cap_sw: float = 0.30 * (absf(vn * SDT) + pr + g)
		print("   _swept_terrain pen=p_rad   %-8.4f %-7.0f %-9.5f %.2f"
			% [pr, vn, cap_sw, cap_sw / SDT])

	# --- U4/U5: the danger band ---
	print("")
	print("=== U4  the DANGER BAND: particle resting at -p_rad, driven straight down ===")
	print("  stages prv at the resting height -p_rad and pos one substep of travel")
	print("  lower, then runs exactly what _collide() runs for that index.")
	print("  band = the downward speeds that leave the particle on the SOLID side.")
	print("  idx  p_rad   swept?  p_rad/SDT  2p_rad/SDT  measured bad band (m/s)")
	var u4i: Array[int] = [0, 4, 8, 11, 13, 14, 16, 20, 22, 25]
	for idx in u4i:
		var prr: float = m.p_rad[idx]
		var swept: bool = idx >= m.pos.size() - 12
		var lo := -1.0
		var hi := -1.0
		var v := 1.0
		while v <= 400.0:
			m.prv[idx] = Vector2(0.0, -prr)
			m.pos[idx] = Vector2(0.0, -prr + v * SDT)
			m._collide_point(idx, prr)
			if swept:
				m._swept_terrain(idx)
			var bad := _depth(m.pos[idx]) > 0.0
			if bad and lo < 0.0:
				lo = v
			if bad:
				hi = v
			v += 1.0
		var band := "none up to 400"
		if lo > 0.0:
			band = "%.0f .. %.0f%s" % [lo, hi, (" (open-ended)" if hi >= 400.0 else "")]
		print("  %-4d %-7.4f %-7s %-10.1f %-11.1f %s"
			% [idx, prr, ("yes" if swept else "NO"), prr / SDT, 2.0 * prr / SDT,
			band])

	print("")
	print("=== U5  where does _collide_point put it, per overshoot depth? (tip) ===")
	print("  overshoot = how far past the floor plane the substep landed it")
	print("   overshoot  ->  end depth   what happened")
	var u5: Array[float] = [0.00005, 0.0002, 0.002, 0.010, 0.0199, 0.0201,
		0.030, 0.100]
	for ov in u5:
		m.prv[i] = Vector2(0.0, ov)
		m.pos[i] = Vector2(0.0, ov)
		m._collide_point(i, pr)
		var ed := _depth(m.pos[i])
		var what := "left where it was (blind)"
		if absf(ed - ov) > 1e-6:
			what = "moved to %+.4f" % ed
			what += "  = -p_rad, CORRECT" if ed < 0.0 else "  = +p_rad, WRONG SIDE"
		print("   %-10.5f ->  %+9.5f  %s" % [ov, ed, what])
	m.free()

# ============================================== PART 2: drive the real sim ==
func _watch(m: Node2D, tag: String, ticks: int, a0: float, a1: float,
		a_hold: float, wind: int, sd: int, settle: int,
		mode: String) -> Dictionary:
	var run := PackedInt32Array()
	run.resize(m.pos.size())
	var best := {"n": 0, "still": []}
	var logged := false
	for t in ticks:
		var pre := PackedVector2Array(m.pos)
		m.step_tick(_target(m, t, a0, a1, a_hold, wind, sd, settle, mode), false)
		for i in m.pos.size():
			var p: Vector2 = m.pos[i]
			if is_nan(p.x) or is_nan(p.y):
				return {"n": 9999, "i": i, "tag": tag + " [NaN]", "pos": p,
					"dep": 0.0, "spd": 0.0, "seg": "nan", "t": t,
					"hand": m.pos[0], "body": m.body_pos, "still": []}
			var dep := _depth(p)
			if dep > 0.0:
				if run[i] == 0 and not logged and _depth(pre[i]) <= 0.0:
					logged = true
					entries.append({"tag": tag, "i": i, "t": t,
						"tick_move": (p - pre[i]).length(),
						"sub_v": (p - m.prv[i]).length() / SDT,
						"swept": i >= m.pos.size() - 12,
						"seg": _near_seg(m, p), "dep": dep})
				run[i] += 1
				if run[i] > int(best["n"]):
					var v: Vector2 = (p - m.prv[i]) / SDT
					best = {"n": run[i], "i": i, "tag": tag, "pos": p,
						"dep": dep, "spd": v.length(),
						"seg": _near_seg(m, p), "t": t,
						"hand": m.pos[0], "body": m.body_pos, "still": []}
			else:
				run[i] = 0
	var still: Array = []
	for i in m.pos.size():
		if _depth(m.pos[i]) > 0.0:
			still.append(i)
	best["still"] = still
	return best

func _report(name: String, count: int, best: Dictionary, still_runs: int) -> void:
	print("")
	print("=== %s ===" % name)
	print("  %d runs; %d ended with a particle STILL embedded" % [count, still_runs])
	if int(best["n"]) == 0:
		print("  no particle ever crossed to the solid side of the terrain")
		return
	print("  worst: particle %d embedded for %d consecutive ticks (%.2f s)"
		% [best["i"], best["n"], float(best["n"]) / 60.0])
	print("    case      : %s" % best["tag"])
	print("    pos       : (%.4f, %.4f)   depth %.4f m   speed %.3f m/s"
		% [best["pos"].x, best["pos"].y, best["dep"], best["spd"]])
	print("    terrain   : %s" % best["seg"])
	print("    at tick   : %d   hand (%.2f,%.2f)  body (%.2f,%.2f)"
		% [best["t"], best["hand"].x, best["hand"].y,
		best["body"].x, best["body"].y])
	print("    still embedded at end of run: %s" % str(best["still"]))

func _sweep(name: String, runs: Array, mode: String) -> void:
	# each run: [bx, trail, a0, a1, a_hold, wind, sd, settle, ticks]
	var best := {"n": 0, "still": []}
	var still_runs := 0
	for r: Array in runs:
		var m := _new()
		_stand(m, r[0], r[1])
		var tag := "bx=%.1f a0=%.2f a1=%.2f sd=%d" % [r[0], r[2], r[3], r[6]]
		var res := _watch(m, tag, r[8], r[2], r[3], r[4], r[5], r[6], r[7], mode)
		m.free()
		if int(res["n"]) >= STUCK_TICKS:
			repros.append(res)
		if not (res["still"] as Array).is_empty():
			still_runs += 1
		if int(res["n"]) > int(best["n"]):
			best = res
	_report(name, runs.size(), best, still_runs)

func _case_crack_floor() -> void:
	var runs: Array = []
	var A0: Array[float] = [PI * 0.88, PI * 1.08]
	var A1: Array[float] = [PI * 0.30, PI * 0.42, PI * 0.50, PI * 0.20]
	var SD: Array[int] = [7, 11]
	for a0 in A0:
		for a1 in A1:
			for sd in SD:
				runs.append([0.0, -1.0, a0, a1, -PI * 0.5, 22, sd, 40, 400])
	_sweep("(a) hard downward cracks into the flat floor, hand then held still",
		runs, "hold")

func _case_yank() -> void:
	var runs: Array = []
	var A1: Array[float] = [PI * 0.30, PI * 0.42, PI * 0.50]
	var SD: Array[int] = [4, 7, 11]
	for a1 in A1:
		for sd in SD:
			runs.append([0.0, -1.0, PI * 0.88, a1, -PI * 0.75, 22, sd, 40, 460])
	_sweep("(a2) crack into the floor, then haul the hand hard away for 6 s",
		runs, "yank")

func _case_recrack() -> void:
	var runs: Array = []
	var A1: Array[float] = [PI * 0.30, PI * 0.42, PI * 0.50]
	var SD: Array[int] = [4, 7, 11]
	for a1 in A1:
		for sd in SD:
			runs.append([0.0, -1.0, PI * 0.88, a1, -PI * 0.5, 22, sd, 40, 640])
	_sweep("(a3) crack into the floor, then KEEP CRACKING ~10 s to shake it free",
		runs, "recrack")

func _case_left_wall() -> void:
	var runs: Array = []
	var BX: Array[float] = [-12.6, -11.4, -13.2]
	var A1: Array[float] = [PI * 0.95, PI * 1.10]
	var SD: Array[int] = [5, 9]
	for bx in BX:
		for a1 in A1:
			for sd in SD:
				runs.append([bx, 1.0, PI * 0.10, a1, -PI * 0.15, 22, sd, 40, 400])
	_sweep("(b) tip whipped into the left wall (x=-14)", runs, "hold")

func _case_seal() -> void:
	var runs: Array = []
	var BX: Array[float] = [60.4, 61.2]
	var A1: Array[float] = [-PI * 0.05, PI * 0.10, PI * 0.25]
	var SD: Array[int] = [5, 9]
	for bx in BX:
		for a1 in A1:
			for sd in SD:
				runs.append([bx, -1.0, PI * 0.90, a1, PI * 0.9, 22, sd, 40, 400])
	_sweep("(b2) tip whipped into the far seal (x=62)", runs, "hold")

func _case_corner() -> void:
	var runs: Array = []
	var BX: Array[float] = [18.4, 19.2, 17.2]
	var A1: Array[float] = [PI * 0.10, PI * 0.28, PI * 0.45]
	var SD: Array[int] = [5, 9]
	for bx in BX:
		for a1 in A1:
			for sd in SD:
				runs.append([bx, -1.0, PI * 0.90, a1, PI * 0.95, 22, sd, 40, 420])
	_sweep("(c) strokes over the tier-drop corner at x=20", runs, "hold")

func _case_drag() -> void:
	var best := {"n": 0, "still": []}
	var still_runs := 0
	var count := 0
	var V: Array[float] = [4.0, 8.0, 14.0]
	var BX: Array[float] = [0.0, 16.0]
	for v in V:
		for bx in BX:
			var m := _new()
			_stand(m, bx)
			m.body_prv = m.body_pos - Vector2(v * SDT, 0.0)
			for i in m.pos.size():
				m.prv[i] = m.pos[i] - Vector2(v * SDT, 0.0)
			var r := _watch(m, "drag v=%.0f bx=%.0f" % [v, bx], 400,
				PI * 0.95, PI * 0.35, -PI * 0.5, 20, 8, 0, "hold")
			m.free()
			count += 1
			if int(r["n"]) >= STUCK_TICKS:
				repros.append(r)
			if not (r["still"] as Array).is_empty():
				still_runs += 1
			if int(r["n"]) > int(best["n"]):
				best = r
	_report("(d) dragging the chain along the ground at speed", count, best,
		still_runs)

# ------------------------------------------------- how deep does it settle --
func _case_settle_depth() -> void:
	print("")
	print("=== (E) equilibrium: where does a particle that fell through settle? ===")
	print("  seed one particle 0.002 m under the floor, hold the hand still 3.3 s")
	print("  idx  p_rad   rest[i-1]  depth@3.3s  hanging one rest-length down =")
	var IDX: Array[int] = [25, 22, 20, 13]
	for idx in IDX:
		var m := _new()
		_stand(m, 0.0)
		var p := Vector2(m.pos[idx].x, 0.002)
		m.pos[idx] = p
		m.prv[idx] = p
		for t in 200:
			m.step_tick(m.body_pos + Vector2(0.3, -0.6), false)
		var rl: float = m.rest[idx - 1]
		var prn: float = m.p_rad[idx - 1]
		print("  %-4d %-7.4f %-10.4f %-11.4f %.4f"
			% [idx, m.p_rad[idx], rl, _depth(m.pos[idx]), rl - prn])
		m.free()

# ================================================ PART 3: substep trace ==
func _trace(bx: float, a0: float, a1: float, wind: int, sd: int, settle: int,
		ticks: int, idx: int) -> void:
	print("")
	print("=== (T) substep trace of one reproduction: bx=%.1f a1=%.2f sd=%d p%d ==="
		% [bx, a1, sd, idx])
	var m := _new()
	_stand(m, bx)
	var entry := -1
	for t in ticks:
		var tgt := _target(m, t, a0, a1, -PI * 0.5, wind, sd, settle, "hold")
		if entry < 0 and _depth(m.pos[idx]) <= 0.0:
			# run this tick substep-by-substep so we can see the crossing
			m.taut = false
			m.cursor_m = tgt
			m.target_m = m.body_pos + (tgt - m.body_pos).limit_length(m.REACH)
			var printed := false
			for s in 16:
				var before: Vector2 = m.pos[idx]
				m._substep()
				var after: Vector2 = m.pos[idx]
				if _depth(after) > 0.0 and not printed:
					printed = true
					entry = t
					print("  CROSSED at tick %d substep %d" % [t, s])
					print("    before substep : y=%+.5f  (depth %+.5f)"
						% [before.y, _depth(before)])
					print("    after  substep : y=%+.5f  (depth %+.5f)"
						% [after.y, _depth(after)])
					print("    prv after      : y=%+.5f  -> implied v = %+.2f m/s"
						% [m.prv[idx].y, (after.y - m.prv[idx].y) / SDT])
					print("    one substep of travel = %.5f m; p_rad = %.4f m"
						% [(after - before).length(), m.p_rad[idx]])
					print("    swept test covers this index? %s"
						% ("yes" if idx >= 14 else "NO (idx < 14)"))
			m._measure_wraps()
			m._update_locks()
			m._events()
		else:
			m.step_tick(tgt, false)
		if entry >= 0 and (t - entry) % 60 == 0:
			print("    t=%d (%.1f s after crossing): y=%+.5f depth %+.5f speed %.3f m/s"
				% [t, float(t - entry) / 60.0, m.pos[idx].y,
				_depth(m.pos[idx]), ((m.pos[idx] - m.prv[idx]) / SDT).length()])
	if entry < 0:
		print("  (no crossing in this run)")
	m.free()

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("THE WHIP - stuck-in-the-floor reproduction probe")
	_unit_tests()
	print("")
	print("############ PART 2 - drive the real sim ############")
	_case_settle_depth()
	_case_crack_floor()
	_case_yank()
	_case_recrack()
	_case_left_wall()
	_case_seal()
	_case_corner()
	_case_drag()

	print("")
	print("=== FIRST-CROSSING census (how the particle got in) ===")
	print("  idx  swept?  tick  move/tick  substep m/s  depth   terrain")
	var shown := 0
	for e in entries:
		if shown < 18:
			print("  %-4d %-7s %-5d %-10.4f %-12.1f %-7.4f %s"
				% [e["i"], ("yes" if e["swept"] else "NO"), e["t"],
				e["tick_move"], e["sub_v"], e["dep"], e["seg"]])
		shown += 1
	if entries.size() > 18:
		print("  ... and %d more" % (entries.size() - 18))
	var non_swept := 0
	for e in entries:
		if not e["swept"]:
			non_swept += 1
	print("  entries by a particle with NO swept test (idx < 14): %d / %d"
		% [non_swept, entries.size()])

	print("")
	print("############ PART 3 - substep trace ############")
	if not repros.is_empty():
		var r: Dictionary = repros[0]
		print("  tracing the first reproduction: %s (particle %d)"
			% [r["tag"], r["i"]])
	_trace(0.0, PI * 1.08, PI * 0.20, 22, 11, 40, 400, 22)

	print("")
	print("================ SUMMARY ================")
	print("reproductions (>= %d consecutive embedded ticks): %d"
		% [STUCK_TICKS, repros.size()])
	shown = 0
	for r in repros:
		if shown < 16:
			print("  p%-3d %5d ticks  depth %.4f  spd %.3f  @ (%.3f,%.3f)  [%s]"
				% [r["i"], r["n"], r["dep"], r["spd"], r["pos"].x, r["pos"].y,
				r["tag"]])
		shown += 1
	if repros.size() > 16:
		print("  ... and %d more" % (repros.size() - 16))
	print("elapsed %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)
