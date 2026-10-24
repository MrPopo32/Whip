extends SceneTree
## THE FLIGHT PROBE - the drop-in swing, measured.
##
## The climb's door asks for energy from nothing: stand still, catch a beam
## 2.2 m up, pump for seconds, fly for half of one. This is the other loop:
## a beam at about shoulder height a few metres past a lip. Catch it standing,
## walk off the lip, and the drop IS the swing - the body falls under the beam
## and rises up the far side on the first pass. Let go on the way up and fly.
## No pump. Where you land depends on when you let go, continuously.
##
##   -- cell bx by r [tug] [lead=0.4]
##        beam bx m past the lip, by m above the floor, radius r; the body
##        stands `lead` m behind the lip. Prints: how many of the 36 standing
##        strokes lock; for up to three of them, the tether, the first
##        far-side swing's peak angle, the swing's lowest point, and then for
##        every release tick of the first rise on the far side, where the body
##        lands: its apex above the floor, and the x (m past the lip) where its
##        feet come down through the floor's level and through 1.0 m and 2.0 m
##        below it. `tug`: one pull down the rope through the first bottom.
const DL := preload("res://tests/climb_door_lib.gd")
const TL := preload("res://tests/tapelib.gd")
const HN := preload("res://tests/hand_noise.gd")
const DROPS := [-1.5, -1.0, -0.5, 0.0, 1.0]   # feet levels below the lip (negative = above)

## shelf: [] for open air past the lip, or [x0, x1, top_up] for a ledge
static func world(bx: float, by: float, r: float, shelf: Array = []) -> Node2D:
	var m: Node2D = TL.new_sim()
	m.save_enabled = false
	m.t_a.clear(); m.t_b.clear()
	m.t_arc_c.clear(); m.t_arc_r.clear(); m.t_arc_ang.clear()
	var pts: Array = [Vector2(-14.0, -25.0), Vector2(-14.0, 0.0), Vector2(0.0, 0.0), Vector2(0.0, 9.0)]
	if shelf.size() == 3:
		pts.append(Vector2(float(shelf[0]), 9.0))
		pts.append(Vector2(float(shelf[0]), -float(shelf[2])))
		pts.append(Vector2(float(shelf[1]), -float(shelf[2])))
		pts.append(Vector2(float(shelf[1]), 9.0))
	pts.append(Vector2(30.0, 9.0))
	pts.append(Vector2(30.0, -25.0))
	for i in range(pts.size() - 1):
		m.t_a.append(pts[i]); m.t_b.append(pts[i + 1])
	assert(m._fillet(Vector2(0.0, 0.0), 0.35))
	if shelf.size() == 3:
		assert(m._fillet(Vector2(float(shelf[0]), -float(shelf[2])), 0.35))
		assert(m._fillet(Vector2(float(shelf[1]), -float(shelf[2])), 0.35))
	m._finish_terrain()
	m._clear_anchor_tables()
	m._add_anchor(Vector2(bx, -by), r, 0, "B")
	m._av_size()
	m.spawn = Vector2(-3.0, -m.BODY_R)
	m.goal_x = 999.0
	m._reset()
	return m

## hand open, cursor parked: the flight. Returns [apex_up, land_x per DROPS]
static func fly(m: Node2D) -> Array:
	var apex := -99.0
	var land: Array = []
	for d in DROPS:
		land.append(NAN)
	var prev_feet: float = -(m.body_pos.y + m.BODY_R)
	for t in 300:
		m.step_tick(m.body_pos, false)
		var feet: float = -(m.body_pos.y + m.BODY_R)
		apex = maxf(apex, feet)
		for i in DROPS.size():
			var lvl: float = -float(DROPS[i])
			if is_nan(land[i]) and prev_feet > lvl and feet <= lvl and t > 3:
				land[i] = m.body_pos.x
		prev_feet = feet
		if feet < -float(DROPS[-1]) - 1.0:
			break
	return [apex, land]

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var bx := float(a[1]); var by := float(a[2]); var r := float(a[3])
	var tug := a.has("tug")
	var lead := 0.4
	var jump_at := -1                 # jump=<k>: hop k ticks after the lock, standing
	var jv := 3.5
	for q in a:
		if String(q).begins_with("lead="):
			lead = float(String(q).substr(5))
		elif String(q).begins_with("jump="):
			jump_at = int(String(q).substr(5))
		elif String(q).begins_with("jv="):
			jv = float(String(q).substr(3))
	var t0 := Time.get_ticks_msec()
	if String(a[0]) == "pullup":
		pullup(bx, by, r, a)
		quit(0)
		return
	var m := world(bx, by, r)
	if a.has("st"):
		m.stretch_set(true)
	elif a.has("firm"):
		m.firm_set(true)
	var hn := HN.new("null", "flight", 0)
	var grid: Array = DL.grid36()
	var locks: Array = []
	for i in grid.size():
		var c: Dictionary = grid[i]
		m._reset()
		DL.stand(m, -lead, 0.0, float(c["a0"]))
		var rr: Dictionary = DL.throw(m, 0, c, hn, false)
		if bool(rr["lock"]):
			locks.append([i, float(rr["tether"])])
	m.jump_v = jv
	print("CELL beam %.1f past the lip, %.1f up, r %.2f, stance %.1f behind the lip%s%s%s | %d/36 strokes lock: %s" % [
		bx, by, r, lead, " | ONE TUG" if tug else "", " | STRETCHY ROPE" if a.has("st") else (" | FIRM" if a.has("firm") else ""),
		(" | JUMP %.1f m/s at +%d ticks" % [jv, jump_at]) if jump_at >= 0 else "",
		locks.size(), str(locks.map(func(e): return int(e[0])))])
	var pick: Array = locks
	if locks.size() > 3:
		pick = [locks[0], locks[locks.size() / 2], locks[-1]]
	for e: Array in pick:
		var c: Dictionary = grid[int(e[0])]
		m._reset()
		DL.stand(m, -lead, 0.0, float(c["a0"]))
		DL.throw(m, 0, c, hn, false)
		var jumped := false
		if jump_at >= 0:
			# stand on the lock for jump_at ticks (hand shut, cursor at the
			# beam so the rope stays taut), then hop
			for t in jump_at:
				m.step_tick(Vector2(m.a_pos[0]), true)
			m.pending_jump = true
			m.step_tick(Vector2(m.a_pos[0]), true)
			jumped = bool(m.rec_jumped)
		var hauled := DL.haul(m, 0)
		# the swing: hand shut; cursor parked, or one tug through the first bottom
		var snaps: Array = []
		var peak := 0.0
		var lowest := 99.0
		var hist: Array = []
		var tugged := false
		var passed_bottom := false
		var lost := -1
		for t in 360:
			var b: Vector2 = m.body_pos
			var th := DL.body_deg(m, 0)
			hist.append(th)
			var cur := b
			if tug and not passed_bottom and absf(th) < 45.0:
				cur = b - (Vector2(m.a_pos[0]) - b).normalized() * m.REACH
				tugged = true
			if tugged and absf(th) >= 45.0:
				passed_bottom = true
			var prev := b
			m.step_tick(cur, true)
			if float(m.a_freelen[0]) < 0.0:
				lost = t
				break
			var feet: float = -(m.body_pos.y + m.BODY_R)
			lowest = minf(lowest, feet)
			var v: Vector2 = (m.body_pos - prev) * 60.0
			var th2 := DL.body_deg(m, 0)
			# the first rise on the far side: moving +x and up, past the bottom
			if th2 > 5.0 and v.x > 0.0 and v.y < 0.0 and snaps.size() < 90:
				snaps.append([t, m.snapshot(), th2])
				peak = maxf(peak, th2)
			elif snaps.size() > 0 and (v.y >= 0.0 or th2 <= 0.0):
				break
		var jtxt := ""
		if jump_at >= 0:
			jtxt = " JUMPED" if jumped else " no jump (not on a floor)"
		var line := "  stroke %2d tether %.2f haul %d t%s | first far-side rise peaks %.0f deg, feet lowest %.2f m, lost %d | %d release ticks:" % [
			int(e[0]), float(e[1]), hauled, jtxt, peak, lowest, lost, snaps.size()]
		print(line)
		var rows := ""
		for s: Array in snaps:
			m.restore(s[1])
			var f := fly(m)
			var land: Array = f[1]
			var lx := ""
			for i in land.size():
				lx += (" %.1f" % land[i]) if not is_nan(land[i]) else " -"
			rows += "    t %3d at %+4.0f deg -> apex %+.2f m, lands x at +1.5/+1.0/+0.5/0/-1.0:%s\n" % [
				int(s[0]), float(s[2]), float(f[0]), lx]
		print(rows.strip_edges(false, true))
	print("DONE %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)

## THE PULL-UP: a beam overhead, a ledge beside it. Catch standing, haul off
## the lip, hold the hand DOWN the rope (the hoist: measured, feet to ~1.35 m
## under a 2.2 m beam), then lean the mouse toward the ledge and let go.
##   -- pullup bx by r [lx=1.9] [lt=1.2] [st]
##   the ledge runs from lx to lx+4 m past the lip, its top lt m up
func pullup(bx: float, by: float, r: float, a: Array) -> void:
	var lx := 1.9
	var lt := 1.2
	for q in a:
		if String(q).begins_with("lx="): lx = float(String(q).substr(3))
		elif String(q).begins_with("lt="): lt = float(String(q).substr(3))
	var m := world(bx, by, r, [lx, lx + 4.0, lt])
	if a.has("st"):
		m.stretch_set(true)
	var hn := HN.new("null", "pullup", 0)
	var grid: Array = DL.grid36()
	var locks: Array = []
	for i in grid.size():
		m._reset()
		DL.stand(m, bx - 1.8, 0.0, float(grid[i]["a0"]))
		if bool(DL.throw(m, 0, grid[i], hn, false)["lock"]):
			locks.append(i)
	print("PULLUP beam %.1f past the lip, %.1f up, r %.2f; ledge from %.1f, top %.1f up%s | %d/36 lock: %s" % [
		bx, by, r, lx, lt, " | STRETCHY" if a.has("st") else "", locks.size(), str(locks)])
	var pick: Array = locks
	if locks.size() > 4:
		pick = [locks[0], locks[locks.size() / 3], locks[(2 * locks.size()) / 3], locks[-1]]
	for i: int in pick:
		m._reset()
		DL.stand(m, bx - 1.8, 0.0, float(grid[i]["a0"]))
		var rr: Dictionary = DL.throw(m, 0, grid[i], hn, false)
		var hauled := DL.haul(m, 0)
		var top := -99.0
		var lost := -1
		for t in 150:
			var b: Vector2 = m.body_pos
			var u: Vector2 = (Vector2(m.a_pos[0]) - b).normalized()
			m.step_tick(b - u * m.REACH, true)
			top = maxf(top, -(m.body_pos.y + m.BODY_R))
			if float(m.a_freelen[0]) < 0.0:
				lost = t
				break
		var feet_hang: float = -(m.body_pos.y + m.BODY_R)
		var bx_hang: float = m.body_pos.x
		# lean toward the ledge for 40 ticks, hand shut, then let go
		var outcomes := ""
		for lean_t in [0, 20, 40, 60]:
			var snap: Dictionary = m.snapshot()
			for t in lean_t:
				var b2: Vector2 = m.body_pos
				var u2: Vector2 = (Vector2(m.a_pos[0]) - b2).normalized()
				# the arm is an internal pair: the cursor LEFT of the body moves
				# the body RIGHT, toward the ledge, while the hand stays down the rope
				m.step_tick(b2 - u2 * m.REACH * 0.5 + Vector2(-m.REACH * 0.8, 0.0), true)
			var still := 0
			for t in 240:
				var pb: Vector2 = m.body_pos
				m.step_tick(m.body_pos, false)
				still = still + 1 if (m.grounded and (m.body_pos - pb).length() * 60.0 < 0.25) else 0
				if still >= 20:
					break
			var fx: float = m.body_pos.x
			var ff: float = -(m.body_pos.y + m.BODY_R)
			var on_ledge := fx >= lx - 0.05 and fx <= lx + 4.05 and absf(ff - lt) < 0.25
			outcomes += "  lean %2d t -> %s (x %.2f, feet %.2f)" % [lean_t, "LEDGE" if on_ledge else ("floor" if absf(ff) < 0.25 else ("pit" if ff < -1.0 else "face")), fx, ff]
			m.restore(snap)
		print("  stroke %2d tether %.2f haul %3d | hoist: feet to %.2f m (top %.2f) at x %.2f, lost %d |%s" % [
			i, float(rr["tether"]), hauled, feet_hang, top, bx_hang, lost, outcomes])
	m.free()
