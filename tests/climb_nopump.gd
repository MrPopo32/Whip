extends SceneTree
## HOW MUCH SWING DOES EACH KIND OF HAND BUILD FROM A STANDSTILL?
##
## One door (climb_door_lib: lip at x 0, door beam at (1.4, -2.2) r 0.11, a gap
## G and a ledge h up). The catch is climb_door_map's catch A, thrown from a
## standstill; the haul is DL.haul (cursor at the beam, hand shut, until the
## feet leave the floor). Then, for PUMP_T ticks, one of these hands:
##   park   cursor on the body: do nothing
##   hold   cursor at the beam, full reach: keep hauling
##   push   cursor ACROSS the rope, the way the body is moving: the push a
##          person makes first (ALIGN refuses 75% of it, by design)
##   tug    cursor AWAY from the beam (reach down the rope: the arm pair
##          hauls the body up to the handle, bot_pump's sign check) while the
##          body is within 30 deg of the bottom, on the body otherwise: a
##          two-state tug, what a tug BUTTON would be, in the right phase
##   tugup  the same, but reaching TOWARD the beam: the gesture a person
##          makes to "pull themselves up", which lengthens the pendulum
##   servo  tests/bot_pump.gd's servo to 150 deg: the bot's parametric pump
## Printed per hand: the peak |angle| of every half-swing (deg from straight
## down), when the beam was lost, and - with `fly` - the widest run of release
## ticks that land on the ledge.
##   -- G h D [fly] [T=600]
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")

var hist: Array = []          # body angle, one entry per tick, newest last
var trace := 0                # print the state every <trace> ticks (0 = off)
var hang_damp := -1.0          # hd=<x>: main.gd's hang_damp (arm damping on a hang)
var hang_cap := 320.0          # hc=<x>: main.gd's hang_cap (arm force cap on a hang)
var hang_k := 340.0            # hk=<x>: main.gd's hang_k (arm stiffness on a hang)
var stretch := false           # st: main.gd's stretchy rope (S)
var vbody_max := 0.0
var mirror := false            # mirror: while hanging, the hand goes to the body's
                               # far side of the mouse (point reflection about the
                               # body), so the BODY follows the mouse - blended in
                               # over MIRROR_T ticks after the catch
const MIRROR_T := 6
var flat := false             # the HOIST bench: the beam 2.2 m over the middle of
                              # the long F0 floor, no lip within 4 m of it

func hand(m: Node2D, pol: String, prev: Vector2) -> Vector2:
	var b: Vector2 = m.body_pos
	if pol.begins_with("late:"):
		# late:<N>:<policy> - park for N ticks (let the swing die), then <policy>
		var cut := pol.find(":", 5)
		if hist.size() < int(pol.substr(5, cut - 5)):
			return b
		pol = pol.substr(cut + 1)
	if pol.begins_with("tug:"):
		# tug:<window deg>:<late ticks>[:up] - reach down the rope (or up, with
		# :up) while the angle seen <late> ticks ago was inside the window
		var f := pol.split(":")
		var win := float(f[1])
		var late := int(f[2])
		var th_seen: float = hist[maxi(0, hist.size() - 1 - late)] if hist.size() > 0 else 0.0
		var to_a0: Vector2 = (Vector2(m.a_pos[0]) - b).normalized()
		var sgn := 1.0 if (f.size() > 3 and f[3] == "up") else -1.0
		if f.size() > 3 and f[3] == "out":
			# PULL-UP's mapping: button down = reach down the rope, button up =
			# arms straight toward the beam (not parked)
			return b - to_a0 * m.REACH if absf(th_seen) < win else b + to_a0 * m.REACH
		return b + to_a0 * sgn * m.REACH if absf(th_seen) < win else b
	var a: Vector2 = m.a_pos[0]
	var to_a: Vector2 = (a - b).normalized()
	var th := DL.body_deg(m, 0)
	var v: Vector2 = (b - prev) * 60.0
	match pol:
		"park":
			return b
		"hold":
			return b + to_a * m.REACH
		"haul":
			return b - to_a * m.REACH       # a tug held down the whole time
		"push":
			var tn := Vector2(-to_a.y, to_a.x)
			return b + tn * signf(v.dot(tn) if absf(v.dot(tn)) > 1e-4 else 1.0) * m.REACH
		"circle":
			var ph := float(hist.size()) * TAU * 1.5 / 60.0
			return b + Vector2(cos(ph), sin(ph)) * m.REACH
		"natural":
			# what a person tries: near the bottom, pull the mouse up toward
			# the beam; out at the ends, lean the mouse the way you swing
			var tn3 := Vector2(-to_a.y, to_a.x)
			if absf(th) < 30.0:
				return b + to_a * m.REACH
			return b + tn3 * signf(v.dot(tn3) if absf(v.dot(tn3)) > 1e-4 else 1.0) * m.REACH
		"pushback":
			var tn2 := Vector2(-to_a.y, to_a.x)
			return b - tn2 * signf(v.dot(tn2) if absf(v.dot(tn2)) > 1e-4 else 1.0) * m.REACH
		"tug":
			return b - to_a * m.REACH if absf(th) < 30.0 else b
		"tugup":
			return b + to_a * m.REACH if absf(th) < 30.0 else b
		"servo":
			return PUMP.pump_cursor(m, 0, prev, 150.0)
	return b

func run(G: float, h: float, D: float, pol: String, T: int, fly: bool) -> void:
	var t0 := Time.get_ticks_msec()
	var m: Node2D = DL.make(G, h, D, not flat, [[Vector2(-4.0, -2.2), 0.11]] if flat else [], "step")
	var hn := HN.new("null", "nopump", 0)
	var c: Dictionary = DL.grid36()[24]
	m.hang_damp = hang_damp
	m.hang_cap = hang_cap
	m.hang_k = hang_k
	if stretch:
		m.stretch_set(true)
	vbody_max = 0.0
	m._reset()
	DL.stand(m, (-4.0 if flat else DL.DOOR.x) - 1.8, 0.0, float(c["a0"]))
	var r: Dictionary = DL.throw(m, 0, c, hn, false)
	if not bool(r["lock"]):
		print("%-6s NO LOCK" % pol)
		m.free()
		return
	var hauled := DL.haul(m, 0)
	hist.clear()
	var prev: Vector2 = m.body_pos
	var thp := DL.body_deg(m, 0)
	var dir := 0.0
	var peak := 0.0
	var peaks: Array = []
	var lost := -1
	var snaps: Array = []
	var feet_max := -99.0
	for t in T:
		var cur := hand(m, pol, prev)
		if mirror:
			var k := minf(1.0, float(t + 1) / float(MIRROR_T))
			cur = cur.lerp(m.body_pos * 2.0 - cur, k)
		prev = m.body_pos
		m.step_tick(cur, true)
		if float(m.a_freelen[0]) < 0.0:
			lost = t
			break
		var th := DL.body_deg(m, 0)
		hist.append(th)
		feet_max = maxf(feet_max, -(m.body_pos.y + m.BODY_R))
		vbody_max = maxf(vbody_max, (m.body_pos - prev).length() * 60.0)
		if trace > 0 and t % trace == 0:
			var tip: Vector2 = m.pos[m.NP - 1]
			print("   t %4d  body (%.2f, %.2f)  angle %+6.1f  speed %.2f m/s  grounded %s  tether %.2f  hand (%.2f, %.2f)"
				% [t, m.body_pos.x, m.body_pos.y, th, (m.body_pos - prev).length() * 60.0,
				str(m.grounded), float(m.a_freelen[0]), m.pos[0].x, m.pos[0].y])
		var d := th - thp
		if d > 180.0: d -= 360.0
		elif d < -180.0: d += 360.0
		thp = th
		if absf(th) > absf(peak):
			peak = th
		if d != 0.0 and dir != 0.0 and signf(d) != dir:
			peaks.append(roundi(peak))
			peak = th
		if d != 0.0:
			dir = signf(d)
		if fly:
			var v: Vector2 = (m.body_pos - prev) * 60.0
			if v.x > 0.0 and t >= 10:
				var xl := DL.ballistic_land(m.body_pos, v, h, m.BODY_R)
				if not is_nan(xl) and xl > G - 1.5 and xl < G + DL.LEDGE_W + 1.5:
					snaps.append([t, m.snapshot()])
	var line := "%-6s tether %.2f haul %3d t | feet highest %.2f m | body top speed %.1f m/s | half-swing peaks %s | lost %d" % [pol,
		float(r["tether"]), hauled, feet_max, vbody_max, str(peaks), lost]
	if fly:
		var s := ""
		var last_t := -99
		var widest := 0
		var run_l := 0
		var first_l := -1
		for e: Array in snaps:
			if int(e[0]) - last_t > 1:
				s += " "
				run_l = 0
			last_t = int(e[0])
			m.restore(e[1])
			var o: Dictionary = DL.fly(m, G, h, D, true)
			var ch := DL.code(String(o["where"]))
			s += ch
			if ch == "L":
				run_l += 1
				widest = maxi(widest, run_l)
				if first_l < 0:
					first_l = int(e[0])
			else:
				run_l = 0
		line += " | widest landing run %d, first landing at pump tick %d | %s" % [widest, first_l, s.strip_edges()]
	print(line + "  (%.0f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	m.free()

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var G := float(a[0]); var h := float(a[1]); var D := float(a[2])
	var fly := a.has("fly")
	var T := 600
	for q in a:
		if String(q).begins_with("T="):
			T = int(String(q).substr(2))
	flat = a.has("flat")
	mirror = a.has("mirror")
	stretch = a.has("st")
	for q in a:
		if String(q).begins_with("hd="):
			hang_damp = float(String(q).substr(3))
		elif String(q).begins_with("hc="):
			hang_cap = float(String(q).substr(3))
		elif String(q).begins_with("hk="):
			hang_k = float(String(q).substr(3))
	print("hang arm: damping %s, cap %.0f N%s" % ["17 (game)" if hang_damp < 0.0 else "%.1f" % hang_damp, hang_cap,
		"   MIRRORED: the body follows the mouse while hanging" if mirror else ""])
	for q in a:
		if String(q).begins_with("trace="):
			trace = int(String(q).substr(6))
	var only := ""
	for q in a:
		if String(q).begins_with("pol="):
			only = String(q).substr(4)
	print("door G %.2f h %.1f D %.1f, catch A (1.8 m, stroke 24), %d ticks per hand" % [G, h, D, T])
	var pols: Array = ["park", "hold", "push", "pushback", "tug", "tugup", "servo"]
	if only != "":
		pols = Array(only.split(","))
	for pol in pols:
		run(G, h, D, pol, T, fly)
	quit(0)
