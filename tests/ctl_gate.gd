extends SceneTree
## THE CONTROL-MODE GATE - main.gd's CONTROL MODES played the way a player
## plays them: buttons and a mouse into ctl_input, its (cursor, grip) into
## step_tick, on the first door of the climb (tests/climb_door_lib.gd, G 3.5
## h 2.0 D 2.0, catch A: 1.8 m, stroke 24).
##
##   godot --headless --path . -s res://tests/ctl_gate.gd
##
## C0 CLASSIC IS THE GAME  the golden session fed through ctl_input in CLASSIC,
##                         on SPACE and again on LMB, ends on the golden hash
## C1 PULL-UP              after the catch the hand stays shut with every
##                         button up and the arms straight haul you off the
##                         lip; a clicked rhythm grows the swing; a one-tick
##                         click gap and a one-tick all-up do not drop the
##                         beam; SPACE lets go; the same held SPACE does not
##                         re-catch; a one-tick tap closes the hand for the
##                         whole catch window; and a SPACE let-go lands the
##                         ledge on a run of >= 6 release ticks
## C2 PULL & REACH         the mouse held down the rope no longer hauls you up
##                         (it does in CLASSIC - the control); a clicked rhythm
##                         grows the swing; letting SPACE go lands the ledge on
##                         a run of >= 6 release ticks
## C3 FLIPPED LEAN         "push the way you swing" dies at align_w 0.75 and
##                         grows at 1.25
## F1 CRACK AT 45          a 0.8 m wiggle at 2 Hz cracks at 24 m/s and not at 45;
##                         a real standing throw cracks at both
## F2 SENSITIVITY          [ and ] step 60 75 90 120 px per metre and stop at the
##                         ends; nothing in the tick reads it (golden hash, C0)
## F3 SPRINGY STICK        a 3 m fall onto a planted stick bounces higher with P
##                         on, re-planting for 15 s stays under 1.8 m, and a
##                         session recorded with C and P on replays to its hash
##                         and its census only when bits 5 and 6 are honoured
## M1 MOUSE FLIP           in CLASSIC with M on, the gestures a person makes
##                         while hanging (mouse up toward the beam at the bottom,
##                         leaning the way you swing at the ends) grow the swing
##                         past 100 deg; the pull-up alone lands the ledge on a
##                         run of >= 6 release ticks letting go with the mouse
##                         parked AND letting go still pulling up (the flip held
##                         through the flight, unwinding after the landing)
## M2 FLIP IS ONLY A HANG    with no wrap, 300 ticks of waggling with the hand shut
##                         end on the same hash with M on and off
## H1 HAMMER STICK         planted, the Getting Over It walk crosses 8 m at >= 1.8
##                         m/s; a snap-hop stays under 1.7 m (a 2 m rise still
##                         needs a door); a held stick stands still (< 5 mm); the
##                         old lash gait is untouched; the first door still locks
##                         7 of 36 standing strokes; and a hammer session replays
##                         to its hash and census only with bit 7 honoured
## H2 FIRM HANG            after the first door's catch, hand shut and still,
##                         the arm stays within 0.12 m (the game's bounces to
##                         0.68) and the swing holds >= 8 deg more over six
##                         half-swings than the game arm; reaching down the rope still
##                         pumps and lands the ledge on a run of >= 6; a blind
##                         circling crank is no faster than on the game's arm
##                         (+0.5 m/s); and a firm session saved to disk loads its
##                         options byte back and verifies through tapelib, and
##                         replays to its hash only with that byte honoured
## S1 STRETCHY ROPE        after the first door's catch, hand shut and still, the
##                         rope runs 2-25 cm past its free length (rigid: 0) with
##                         the grip firm (arm < 0.15 m); the door still locks 7 of
##                         36 standing strokes; reaching down the rope still pumps
##                         and lands; and a stretchy session replays to its hash
##                         only with options bit 1 honoured
## J1 JUMP                 a press on the floor hops the feet 0.4-1.0 m; a press
##                         in the air, against a wall, or with the hammer planted
##                         does nothing; a session with jumps saves its options
##                         byte with bit 2 set on exactly those ticks and
##                         replays to its hash only when the bit is honoured
## C4 TAPES CARRY IT       a session recorded with the lean flipped replays to
##                         its own hash when bit 2 is honoured and does NOT
##                         when it is ignored (the control), and bits 3-4 name
##                         the mode it was played in
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
const LIB := preload("res://tests/level_lib.gd")
const TL := preload("res://tests/tapelib.gd")
const MAIN_T := preload("res://main.gd")
const G := 3.5
const H := 2.0
const D := 2.0
const MIN_RUN := 6

var fails: Array[String] = []
var hist: Array = []

func ok(tag: String, cond: bool, msg: String) -> void:
	print("  %-4s %s  %s" % ["ok" if cond else "FAIL", tag, msg])
	if not cond:
		fails.append(tag)

func caught() -> Node2D:
	var m: Node2D = DL.make(G, H, D, true, [], "step")
	var c: Dictionary = DL.grid36()[24]
	m._reset()
	DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
	var r: Dictionary = DL.throw(m, 0, c, HN.new("null", "ctl", 0), false)
	assert(bool(r["lock"]))
	return m

func tick(m: Node2D, cur: Vector2, sp: bool, lmb: bool, rmb: bool) -> void:
	var io: Array = m.ctl_input(cur, sp, lmb, rmb)
	m.step_tick(io[0], io[1])
	hist.append(DL.body_deg(m, 0))

func late_angle(late: int) -> float:
	return float(hist[maxi(0, hist.size() - 1 - late)]) if hist.size() > 0 else 0.0

func engaged(m: Node2D) -> bool:
	return float(m.a_freelen[0]) >= 0.0

## the widest run of release ticks that land, from a pumped swing: every +x
## tick whose ballistic forecast comes down near the ledge is restored, let go
## the way the mode lets go, and flown with the hand open
func landings(m: Node2D, snaps: Array, let_go: Callable) -> Array:
	var s := ""
	var last := -99
	var widest := 0
	var run := 0
	for e: Array in snaps:
		if int(e[0]) - last > 1:
			s += " "
			run = 0
		last = int(e[0])
		m.restore(e[1])
		let_go.call(m)
		var o: Dictionary = DL.fly(m, G, H, D, true)
		var ch := DL.code(String(o["where"]))
		s += ch
		if ch == "L":
			run += 1
			widest = maxi(widest, run)
		else:
			run = 0
	return [widest, s.strip_edges()]

func pump_rhythm(m: Node2D, n: int, sp: bool, snaps: Array) -> float:
	var peak := 0.0
	var prev: Vector2 = m.body_pos
	for t in n:
		var lmb := absf(late_angle(3)) < 45.0
		prev = m.body_pos
		tick(m, m.body_pos, sp, lmb, false)
		peak = maxf(peak, absf(float(hist[-1])))
		var v: Vector2 = (m.body_pos - prev) * 60.0
		if v.x > 0.0 and t >= 10:
			var xl := DL.ballistic_land(m.body_pos, v, H, m.BODY_R)
			if not is_nan(xl) and xl > G - 1.5 and xl < G + DL.LEDGE_W + 1.5:
				snaps.append([t, m.snapshot()])
	return peak

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("control-mode gate: door G %.1f h %.1f, catch A" % [G, H])
	c0()
	c1()
	c2()
	c3()
	c4()
	f1()
	f2()
	f3()
	m1()
	m2()
	h1()
	h2()
	s1()
	j1()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if fails.is_empty():
		print("PASS  control modes: classic is the game, pull-up, pull & reach and the flipped lean each do what they say, and tapes carry them (%.0f s)" % secs)
		quit(0)
	else:
		print("FAIL  control modes: %s (%.0f s)" % [", ".join(fails), secs])
		quit(1)

# ------------------------------------------------------------------ C0 --
func golden_via_ctl(use_lmb: bool) -> int:
	var m := LIB.new_sim("")
	m.ctl_set(m.Ctl.CLASSIC, false, false)
	for t in 900:
		var b: Vector2 = m.body_pos
		var tgt: Vector2
		var grip := false
		if t < 90:
			tgt = b + Vector2(0.5, -0.5)
		elif t < 280:
			var ph := float(t - 90) * 0.11
			tgt = b + Vector2(cos(ph), sin(ph)) * 1.1
		elif t < 340:
			tgt = b + Vector2(-1.05, -0.35)
		elif t < 352:
			tgt = b + Vector2(1.05, -0.45)
		elif t < 600:
			tgt = b + Vector2(0.8, -0.8); grip = t > 420
		else:
			var p2 := float(t) * 0.05
			tgt = b + Vector2(cos(p2), -0.6); grip = true
		var io: Array = m.ctl_input(tgt, grip and not use_lmb, grip and use_lmb, false)
		m.step_tick(io[0], io[1])
	var h: int = m.state_hash()
	m.free()
	return h

func c0() -> void:
	var a := golden_via_ctl(false)
	var b := golden_via_ctl(true)
	ok("C0", a == LIB.SHIPPED_HASH and b == LIB.SHIPPED_HASH,
		"golden session through ctl_input in CLASSIC: SPACE %d, LMB %d, shipped %d" % [a, b, LIB.SHIPPED_HASH])

# ------------------------------------------------------------------ C1 --
func c1() -> void:
	var m := caught()
	m.ctl_set(m.Ctl.PULL_UP, false, false)
	hist.clear()
	# every button up: the latch holds and the arms straight carry you off
	var held := true
	for t in 120:
		tick(m, m.body_pos, false, false, false)
		held = held and bool(m.taut) and engaged(m)
	var off: bool = not bool(m.grounded)
	# a clicked rhythm, with a one-tick click gap and a one-tick all-up in it
	var snaps: Array = []
	var peak := pump_rhythm(m, 240, false, snaps)
	var slip_ok := true
	tick(m, m.body_pos, false, false, false)
	slip_ok = slip_ok and bool(m.taut) and engaged(m)
	tick(m, m.body_pos, false, true, false)
	tick(m, m.body_pos, false, false, false)
	tick(m, m.body_pos, false, true, false)
	slip_ok = slip_ok and bool(m.taut) and engaged(m)
	peak = maxf(peak, pump_rhythm(m, 360, false, snaps))
	# SPACE lets go; still holding SPACE does not catch again
	tick(m, m.body_pos, true, false, false)
	var dropped: bool = not bool(m.taut)
	var stay_open := true
	for t in 20:
		tick(m, m.body_pos, true, false, false)
		stay_open = stay_open and not bool(m.taut)
	tick(m, m.body_pos, false, false, false)
	# a one-tick tap closes the hand for the whole catch window - on a floor
	# with no beam in reach, so nothing is caught and the window is all it is
	var e: Node2D = DL.make(G, H, D, false, [], "step")
	e.ctl_set(e.Ctl.PULL_UP, false, false)
	e._reset()
	var shut := 0
	var tio: Array = e.ctl_input(e.body_pos, false, true, false)
	e.step_tick(tio[0], tio[1])
	if bool(e.taut): shut += 1
	for t in e.GRIP_WINDOW + 5:
		tio = e.ctl_input(e.body_pos, false, false, false)
		e.step_tick(tio[0], tio[1])
		if bool(e.taut): shut += 1
	e.free()
	ok("C1a", held and off, "PULL-UP: 120 ticks with every button up, the hand stayed shut on the beam %s and the feet left the lip %s" % [str(held), str(off)])
	ok("C1b", peak > 100.0, "PULL-UP: a click held within 45 deg of the bottom grew the swing from 44 to %.0f deg" % peak)
	ok("C1c", slip_ok, "PULL-UP: a one-tick click gap and a one-tick all-up kept the beam")
	ok("C1d", dropped and stay_open, "PULL-UP: a SPACE press let go %s, and 20 more ticks of the same SPACE stayed open %s" % [str(dropped), str(stay_open)])
	ok("C1e", shut >= m.GRIP_WINDOW and shut <= m.GRIP_WINDOW + 1, "PULL-UP: a one-tick click kept the hand shut %d ticks (catch window %d)" % [shut, m.GRIP_WINDOW])
	var lg := func(mm: Node2D) -> void:
		mm.ctl_prev = 0
		var io: Array = mm.ctl_input(mm.body_pos, true, false, false)
		mm.step_tick(io[0], io[1])
	var w: Array = landings(m, snaps, lg)
	ok("C1f", int(w[0]) >= MIN_RUN, "PULL-UP: a SPACE let-go from the clicked swing lands on a run of %d ticks: %s" % [int(w[0]), String(w[1]).left(90)])
	m.free()

# ------------------------------------------------------------------ C2 --
func hauled_by_mouse(mode: int) -> float:
	# 300 ticks, SPACE held, mouse held DOWN the rope, no click; how close the
	# body sits to the beam at the end (m from the beam's centre)
	var m := caught()
	m.ctl_set(mode, false, false)
	hist.clear()
	var dmin := 99.0
	for t in 300:
		var u: Vector2 = (m.body_pos - Vector2(m.a_pos[0])).normalized()
		tick(m, m.body_pos + u * m.REACH, true, false, false)
		if t > 200:
			dmin = minf(dmin, m.body_pos.distance_to(Vector2(m.a_pos[0])))
	m.free()
	return dmin

func c2() -> void:
	var classic := hauled_by_mouse(0)
	var pr := hauled_by_mouse(1)
	ok("C2a", pr > classic + 0.4, "PULL & REACH: mouse held down the rope, body at %.2f m from the beam (CLASSIC hauls it to %.2f m)" % [pr, classic])
	var m := caught()
	m.ctl_set(m.Ctl.PULL_REACH, false, false)
	hist.clear()
	for t in 30:
		tick(m, m.body_pos, true, false, false)
	var snaps: Array = []
	var peak := pump_rhythm(m, 600, true, snaps)
	ok("C2b", peak > 100.0, "PULL & REACH: SPACE held, a click within 45 deg of the bottom grew the swing to %.0f deg" % peak)
	var lg := func(mm: Node2D) -> void:
		mm.ctl_prev = 1
		var io: Array = mm.ctl_input(mm.body_pos, false, false, false)
		mm.step_tick(io[0], io[1])
	var w: Array = landings(m, snaps, lg)
	ok("C2c", int(w[0]) >= MIN_RUN, "PULL & REACH: letting SPACE go from the clicked swing lands on a run of %d ticks: %s" % [int(w[0]), String(w[1]).left(90)])
	m.free()

# ------------------------------------------------------------------ C3 --
func push_peak(lean: bool) -> float:
	var m := caught()
	m.ctl_set(m.Ctl.CLASSIC, lean, false)
	hist.clear()
	var prev: Vector2 = m.body_pos
	var late := 0.0
	for t in 600:
		var a: Vector2 = m.a_pos[0]
		var to_a: Vector2 = (a - m.body_pos).normalized()
		var tn := Vector2(-to_a.y, to_a.x)
		var v: Vector2 = (m.body_pos - prev) * 60.0
		var sg := signf(v.dot(tn)) if absf(v.dot(tn)) > 1e-4 else 1.0
		prev = m.body_pos
		tick(m, m.body_pos + tn * sg * m.REACH, true, false, false)
		if t >= 480:
			late = maxf(late, absf(float(hist[-1])))
	m.free()
	return late

func c3() -> void:
	var off := push_peak(false)
	var on := push_peak(true)
	ok("C3", off < 25.0 and on > 60.0, "FLIPPED LEAN: pushing the way you swing, the swing in its last 2 s is %.0f deg at align_w 0.75 and %.0f deg at 1.25" % [off, on])

# ------------------------------------------------------------------ C4 --
func c4() -> void:
	var m := caught()
	m.ctl_set(m.Ctl.PULL_REACH, true, false)
	hist.clear()
	m.rec_begin("ctl_gate")
	var start: Dictionary = m.rec_start
	var prev: Vector2 = m.body_pos
	for t in 400:
		var to_a: Vector2 = (Vector2(m.a_pos[0]) - m.body_pos).normalized()
		var tn := Vector2(-to_a.y, to_a.x)
		var v: Vector2 = (m.body_pos - prev) * 60.0
		var sg := signf(v.dot(tn)) if absf(v.dot(tn)) > 1e-4 else 1.0
		prev = m.body_pos
		tick(m, m.body_pos + tn * sg * m.REACH, true, absf(late_angle(3)) < 45.0, false)
	m.rec_end()
	var h_rec: int = m.state_hash()
	var cur: PackedVector2Array = m.rec_cur
	var grp: PackedByteArray = m.rec_grip
	var modes_ok := true
	for b in grp:
		modes_ok = modes_ok and ((b >> 3) & 3) == m.Ctl.PULL_REACH and (b & 4) != 0
	var hashes: Array = []
	for honour in [true, false]:
		m.restore(start)
		for i in cur.size():
			m.pending_reset = (grp[i] & 2) != 0
			if honour:
				m.align_w = m.ALIGN_W_FLIP if (grp[i] & 4) != 0 else m.ALIGN_W
			else:
				m.align_w = m.ALIGN_W
			m.step_tick(cur[i], (grp[i] & 1) != 0)
		hashes.append(m.state_hash())
	ok("C4", int(hashes[0]) == h_rec and int(hashes[1]) != h_rec and modes_ok,
		"TAPES: a flipped-lean PULL & REACH session replays to its hash with bit 2 honoured %s, diverges without it %s, and every tick names its mode %s" % [
			str(int(hashes[0]) == h_rec), str(int(hashes[1]) != h_rec), str(modes_ok)])
	m.free()

# ------------------------------------------------------------------ F1-F3 --
func standing() -> Node2D:
	var m: Node2D = DL.make(G, H, D, false, [], "step", -6.0)
	m._reset()
	DL.stand(m, -6.0, 0.0, PI)
	return m

func cracks_of_wiggle(hi: bool) -> int:
	var m := standing()
	m.crack_speed = m.CRACK_SPEED_HI if hi else m.CRACK_SPEED
	for t in 120:
		var k := minf(1.0, float(t) / 60.0)
		m.step_tick(m.body_pos + Vector2(-m.REACH, 0.0).lerp(Vector2(0.0, -0.5), k), false)
	var n := 0
	for t in 180:
		m.step_tick(m.body_pos + Vector2(0.8 * sin(TAU * 2.0 * float(t) / 60.0), -0.5), false)
		if float(m.crack_flash) >= 0.999:
			n += 1
	m.free()
	return n

func cracks_of_throw(hi: bool) -> int:
	var m: Node2D = DL.make(G, H, D, true, [], "step")
	m.crack_speed = m.CRACK_SPEED_HI if hi else m.CRACK_SPEED
	var c: Dictionary = DL.grid36()[24]
	m._reset()
	DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
	var n := 0
	for t in 180:
		var ang := float(c["a0"]) if t < 120 else float(c["a1"])
		m.step_tick(m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH, false)
		if float(m.crack_flash) >= 0.999:
			n += 1
	m.free()
	return n

func f1() -> void:
	var w24 := cracks_of_wiggle(false)
	var w45 := cracks_of_wiggle(true)
	var t24 := cracks_of_throw(false)
	var t45 := cracks_of_throw(true)
	ok("F1", w24 > 0 and w45 == 0 and t24 > 0 and t45 > 0,
		"CRACK AT 45: a 0.8 m wiggle cracks %d times at 24 m/s and %d at 45; a standing throw %d and %d" % [w24, w45, t24, t45])

func f2() -> void:
	var m := standing()
	var seen: Array = [m.ppm_input]
	for i in 5:
		m.feel_sens_step(1, false)
		seen.append(m.ppm_input)
	for i in 5:
		m.feel_sens_step(-1, false)
		seen.append(m.ppm_input)
	m.free()
	ok("F2", seen == [60.0, 75.0, 90.0, 120.0, 120.0, 120.0, 90.0, 75.0, 60.0, 60.0, 60.0],
		"SENSITIVITY: [ then ] walk %s" % str(seen))

func fall_apex(on: bool, pol: String, T: int) -> float:
	var m := standing()
	m.stick_on = on
	if pol == "fall":
		m.teleport(m.body_pos + Vector2(0.0, -3.0))
	var best := 0.0
	var touched := false
	for t in T:
		var b: Vector2 = m.body_pos
		var cur := b + Vector2(0.0, m.REACH)
		if pol == "cycle":
			cur = b + Vector2(0.0, -m.REACH) if (t % 70) < 20 else cur
		m.step_tick(cur, false)
		var f: float = -(m.body_pos.y + m.BODY_R)
		if m.grounded or f < 0.9:
			touched = true
		if touched:
			best = maxf(best, f)
	m.free()
	return best

func f3() -> void:
	var off := fall_apex(false, "fall", 360)
	var on := fall_apex(true, "fall", 360)
	var pogo := fall_apex(true, "cycle", 900)
	# a session with C and P on: a standing snap-hop, then a wiggle
	var m := standing()
	m.crack_speed = m.CRACK_SPEED_HI
	m.stick_on = true
	m.rec_begin("ctl_gate feel")
	var start: Dictionary = m.rec_start
	for t in 360:
		var b: Vector2 = m.body_pos
		var cur := b + Vector2(0.0, -m.REACH) if t < 40 else b + Vector2(0.0, m.REACH)
		if t >= 200:
			cur = b + Vector2(0.9 * sin(TAU * 2.5 * float(t) / 60.0), -0.6)
		m.step_tick(cur, false)
	m.rec_end()
	var h_rec: int = m.state_hash()
	var cen: Dictionary = m.rec_cen.duplicate()
	var cur_t: PackedVector2Array = m.rec_cur
	var grp: PackedByteArray = m.rec_grip
	var res: Array = []
	for honour in [true, false]:
		m.restore(start)
		m.crack_speed = m.CRACK_SPEED
		m.stick_on = false
		m.rec_begin("replay")
		for i in cur_t.size():
			m.pending_reset = (grp[i] & 2) != 0
			if honour:
				m.crack_speed = m.CRACK_SPEED_HI if (grp[i] & 32) != 0 else m.CRACK_SPEED
				m.stick_on = (grp[i] & 64) != 0
			m.step_tick(cur_t[i], (grp[i] & 1) != 0)
		m.rec_end()
		res.append([m.state_hash() == h_rec, TL.cen_diff(cen, m.rec_cen) == ""])
	m.free()
	ok("F3", on > off + 0.2 and pogo < 1.8 and res[0] == [true, true] and res[1] != [true, true],
		"SPRINGY STICK: a 3 m fall onto the stick bounces to %.2f m with P on, %.2f off; 15 s of re-planting peaks at %.2f m; a C+P tape replays hash/census %s honoured, %s ignored" % [
			on, off, pogo, str(res[0]), str(res[1])])

# ------------------------------------------------------------------ M1 M2 --
func natural_cursor(m: Node2D, prev: Vector2) -> Vector2:
	var b: Vector2 = m.body_pos
	var to_a: Vector2 = (Vector2(m.a_pos[0]) - b).normalized()
	var th := DL.body_deg(m, 0)
	if absf(th) < 30.0:
		return b + to_a * m.REACH
	var tn := Vector2(-to_a.y, to_a.x)
	var v: Vector2 = (b - prev) * 60.0
	return b + tn * (signf(v.dot(tn)) if absf(v.dot(tn)) > 1e-4 else 1.0) * m.REACH

func pullup_cursor(m: Node2D) -> Vector2:
	# the flip's pump: pull the mouse up toward the beam as you pass under it
	var b: Vector2 = m.body_pos
	if absf(DL.body_deg(m, 0)) < 30.0:
		return b + (Vector2(m.a_pos[0]) - b).normalized() * m.REACH
	return b

func m1_fly(m: Node2D, e: Array, held: bool) -> String:
	m.restore(e[1])
	m.mirror_k = 1.0
	m.ctl_prev = 1
	var off: Vector2 = (Vector2(m.a_pos[0]) - m.body_pos).normalized() * m.REACH if held else Vector2.ZERO
	var falls0: int = m.falls
	var still := 0
	for t in 420:
		var pb: Vector2 = m.body_pos
		if m.grounded:
			off *= 0.9            # landed: the mouse settles back
		var io: Array = m.ctl_input(m.body_pos + off, false, false, false)
		m.step_tick(io[0], io[1])
		still = still + 1 if (m.grounded and (m.body_pos - pb).length() * 60.0 < 0.25) else 0
		if still >= 20 or m.falls > falls0:
			break
	var c := DL.code(String(DL.classify(m, G, H, D)["where"]))
	if c == "L":
		for t in 90:
			m.step_tick(m.body_pos, false)
		c = DL.code(String(DL.classify(m, G, H, D)["where"]))
	return c

func m1() -> void:
	# the swing the two natural gestures together grow (growth only)
	var n := caught()
	n.ctl_set(n.Ctl.CLASSIC, false, false)
	n.mirror_on = true
	hist.clear()
	var prev: Vector2 = n.body_pos
	var peak_nat := 0.0
	for t in 600:
		var cur := natural_cursor(n, prev)
		prev = n.body_pos
		tick(n, cur, true, false, false)
		peak_nat = maxf(peak_nat, absf(float(hist[-1])))
	n.free()
	# the pull-up pump, and its releases two ways
	var m := caught()
	m.ctl_set(m.Ctl.CLASSIC, false, false)
	m.mirror_on = true
	hist.clear()
	prev = m.body_pos
	var peak := 0.0
	var snaps: Array = []
	for t in 900:
		var cur := pullup_cursor(m)
		prev = m.body_pos
		tick(m, cur, true, false, false)
		peak = maxf(peak, absf(float(hist[-1])))
		var v: Vector2 = (m.body_pos - prev) * 60.0
		if v.x > 0.0 and t >= 10:
			var xl := DL.ballistic_land(m.body_pos, v, H, m.BODY_R)
			if not is_nan(xl) and xl > G - 1.5 and xl < G + DL.LEDGE_W + 1.5:
				snaps.append([t, m.snapshot()])
	var runs: Array = []
	var strs: Array = []
	for held in [false, true]:
		var s2 := ""
		var last := -99
		var widest := 0
		var run := 0
		for e: Array in snaps:
			if int(e[0]) - last > 1:
				s2 += " "
				run = 0
			last = int(e[0])
			var c := m1_fly(m, e, held)
			s2 += c
			if c == "L":
				run += 1
				widest = maxi(widest, run)
			else:
				run = 0
		runs.append(widest)
		strs.append(s2.strip_edges())
	m.free()
	ok("M1", peak_nat > 100.0 and peak > 100.0 and int(runs[0]) >= MIN_RUN and int(runs[1]) >= MIN_RUN,
		"MOUSE FLIP: both natural gestures grow the swing to %.0f deg; pulling up toward the beam alone to %.0f deg, and letting go lands on a run of %d ticks with the mouse parked, %d still pulling up" % [
			peak_nat, peak, int(runs[0]), int(runs[1])])

func m2() -> void:
	var hs: Array = []
	for on in [false, true]:
		var m := standing()
		m.ctl_set(m.Ctl.CLASSIC, false, false)
		m.mirror_on = on
		for t in 300:
			var io: Array = m.ctl_input(m.body_pos + Vector2(0.9 * sin(float(t) * 0.2), -0.4), true, false, false)
			m.step_tick(io[0], io[1])
		hs.append(m.state_hash())
		m.free()
	ok("M2", hs[0] == hs[1], "MOUSE FLIP: with no wrap, 300 ticks of a waggle with the hand shut end on %d with M off and %d with M on" % [hs[0], hs[1]])

# ------------------------------------------------------------------ H1 --
func hoff(m: Node2D, deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * m.REACH

func h1() -> void:
	# the walk
	var w := standing()
	w.hammer_on = true
	w.teleport(Vector2(-11.0, w.body_pos.y))
	for t in 30:
		w.step_tick(w.body_pos + hoff(w, 140.0), false)
	var x0: float = w.body_pos.x
	var tw := 0
	for t in 600:
		var f := float(t % 30) / 30.0
		var deg := lerpf(140.0, 400.0, f / 0.30) if f < 0.30 else (40.0 if f < 0.40 else lerpf(40.0, 140.0, (f - 0.40) / 0.60))
		w.step_tick(w.body_pos + hoff(w, deg), false)
		tw = t
		if w.body_pos.x - x0 >= 8.0:
			break
	var speed: float = (w.body_pos.x - x0) / (float(tw + 1) / 60.0)
	w.free()
	# the snap-hop and the held stick
	var hp := standing()
	hp.hammer_on = true
	var top := 0.0
	for t in 300:
		hp.step_tick(hp.body_pos + (hoff(hp, 270.0) if t < 40 else hoff(hp, 90.0)), false)
		top = maxf(top, -(hp.body_pos.y + hp.BODY_R))
	var ys: Array = []
	for t in 180:
		hp.step_tick(hp.body_pos + hoff(hp, 90.0), false)
		ys.append(hp.body_pos.y)
	var wob: float = (float(ys.max()) - float(ys.min())) * 1000.0
	hp.free()
	# the lash gait, on and off
	var gd: Array = []
	for on in [false, true]:
		var g := standing()
		g.hammer_on = on
		g.teleport(Vector2(-11.0, g.body_pos.y))
		var gx: float = g.body_pos.x
		TL.run(g, [{"kind": "gait", "n": 600}])
		gd.append(g.state_hash())
		g.free()
	# the first door
	var locks := 0
	for i in 36:
		var c: Dictionary = DL.grid36()[i]
		var dm: Node2D = DL.make(G, H, D, true, [], "step")
		dm.hammer_on = true
		dm._reset()
		DL.stand(dm, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
		var r: Dictionary = DL.throw(dm, 0, c, HN.new("null", "hm", 0), false)
		if bool(r["lock"]):
			locks += 1
		dm.free()
	# the tape
	var m := standing()
	m.hammer_on = true
	m.rec_begin("ctl_gate hammer")
	var start: Dictionary = m.rec_start
	for t in 300:
		var f2 := float(t % 30) / 30.0
		var deg2 := lerpf(140.0, 400.0, f2 / 0.30) if f2 < 0.30 else (40.0 if f2 < 0.40 else lerpf(40.0, 140.0, (f2 - 0.40) / 0.60))
		m.step_tick(m.body_pos + hoff(m, deg2), false)
	m.rec_end()
	var h_rec: int = m.state_hash()
	var cen: Dictionary = m.rec_cen.duplicate()
	var cur_t: PackedVector2Array = m.rec_cur
	var grp: PackedByteArray = m.rec_grip
	var res: Array = []
	for honour in [true, false]:
		m.restore(start)
		m.hammer_on = false
		m.rec_begin("replay")
		for i in cur_t.size():
			m.pending_reset = (grp[i] & 2) != 0
			if honour:
				m.hammer_on = (grp[i] & 128) != 0
			m.step_tick(cur_t[i], (grp[i] & 1) != 0)
		m.rec_end()
		res.append([m.state_hash() == h_rec, TL.cen_diff(cen, m.rec_cen) == ""])
	m.free()
	ok("H1", speed >= 1.8 and top < 1.7 and wob < 5.0 and gd[0] == gd[1] and locks == 7
			and res[0] == [true, true] and res[1] != [true, true],
		"HAMMER: walks 8 m at %.2f m/s, snap-hop %.2f m, held stick moves %.1f mm, lash gait same %s, door %d/36, tape honoured %s ignored %s" % [
			speed, top, wob, str(gd[0] == gd[1]), locks, str(res[0]), str(res[1])])

# ------------------------------------------------------------------ H2 --
func firm_caught(on: bool) -> Node2D:
	var m := caught()
	m.firm_set(on)
	return m

func h2_arm_and_swing(on: bool) -> Array:
	var m := firm_caught(on)
	hist.clear()
	var amax := 0.0
	var dir := 0.0
	var peak := 0.0
	var peaks: Array = []
	var thp := DL.body_deg(m, 0)
	for t in 600:
		m.step_tick(m.body_pos, true)
		if t >= 20 and t < 260:
			amax = maxf(amax, m.pos[0].distance_to(m.body_pos))
		var th := DL.body_deg(m, 0)
		var d := th - thp
		thp = th
		if absf(th) > absf(peak):
			peak = th
		if d != 0.0 and dir != 0.0 and signf(d) != dir:
			peaks.append(absf(peak))
			peak = th
		if d != 0.0:
			dir = signf(d)
	m.free()
	return [amax, float(peaks[mini(5, peaks.size() - 1)]) if peaks.size() > 0 else 0.0]

func h2_crank(on: bool) -> float:
	var m := firm_caught(on)
	var prev: Vector2 = m.body_pos
	var vmax := 0.0
	for t in 600:
		var ph := float(t) * TAU * 1.5 / 60.0
		prev = m.body_pos
		m.step_tick(m.body_pos + Vector2(cos(ph), sin(ph)) * m.REACH, true)
		vmax = maxf(vmax, (m.body_pos - prev).length() * 60.0)
	m.free()
	return vmax

func h2() -> void:
	var game: Array = h2_arm_and_swing(false)
	var firm: Array = h2_arm_and_swing(true)
	# the pump: reach down the rope near the bottom, 3 ticks late
	var m := firm_caught(true)
	hist.clear()
	var prev: Vector2 = m.body_pos
	var snaps: Array = []
	for t in 900:
		var b: Vector2 = m.body_pos
		var cur: Vector2 = b - (Vector2(m.a_pos[0]) - b).normalized() * m.REACH if absf(late_angle(3)) < 45.0 else b
		prev = m.body_pos
		m.step_tick(cur, true)
		hist.append(DL.body_deg(m, 0))
		var v: Vector2 = (m.body_pos - prev) * 60.0
		if v.x > 0.0 and t >= 10:
			var xl := DL.ballistic_land(m.body_pos, v, H, m.BODY_R)
			if not is_nan(xl) and xl > G - 1.5 and xl < G + DL.LEDGE_W + 1.5:
				snaps.append([t, m.snapshot()])
	var w: Array = landings(m, snaps, func(mm: Node2D) -> void: mm.step_tick(mm.body_pos, false))
	m.free()
	var crank_game := h2_crank(false)
	var crank_firm := h2_crank(true)
	# the options byte on disk, through tapelib's own verify, on the traverse
	var tm := LIB.new_sim("")
	tm.rec_begin("ctl_gate firm")
	for t in 240:
		if t == 60:
			tm.firm_set(true)
		if t == 180:
			tm.firm_set(false)
		tm.step_tick(tm.body_pos + Vector2(0.8, -0.6), t > 30)
	tm.rec_end()
	var path := "user://_ctl_gate_opt.tape"
	tm.tape_save(path)
	var want: PackedByteArray = tm.rec_opt
	tm.free()
	var back: Dictionary = MAIN_T.tape_load(path)
	var disk_ok: bool = bool(back.get("ok", false)) and back.get("opt", PackedByteArray()) == want and want.count(1) == 120
	var vr: Dictionary = TL.verify(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# honoured vs ignored, on the door
	var r := firm_caught(true)
	r.rec_begin("ctl_gate firm door")
	var start: Dictionary = r.rec_start
	for t in 300:
		var ph := float(t) * 0.12
		r.step_tick(r.body_pos + Vector2(cos(ph), sin(ph)) * 0.9, true)
	r.rec_end()
	var h_rec: int = r.state_hash()
	var cur_t: PackedVector2Array = r.rec_cur
	var grp: PackedByteArray = r.rec_grip
	var opt: PackedByteArray = r.rec_opt
	var hs: Array = []
	for honour in [true, false]:
		r.restore(start)
		for i in cur_t.size():
			r.pending_reset = (grp[i] & 2) != 0
			r.firm_set(honour and (opt[i] & 1) != 0)
			r.step_tick(cur_t[i], (grp[i] & 1) != 0)
		hs.append(r.state_hash() == h_rec)
	r.free()
	ok("H2", float(firm[0]) < 0.12 and float(game[0]) > 0.4 and float(firm[1]) >= float(game[1]) + 8.0 and int(w[0]) >= MIN_RUN
			and crank_firm <= crank_game + 0.5 and disk_ok and bool(vr.get("ok", false)) and hs == [true, false],
		"FIRM HANG: arm reach from the hand %.2f m (game %.2f), swing at six half-swings %.0f deg (game %.0f), the pump lands on a run of %d, crank %.1f m/s (game %.1f), options byte on disk %s, tapelib verify %s, replay honoured/ignored %s" % [
			float(firm[0]), float(game[0]), float(firm[1]), float(game[1]), int(w[0]), crank_firm, crank_game,
			str(disk_ok), str(vr.get("ok", false)) + ("" if bool(vr.get("ok", false)) else " (" + str(vr.get("why", "")) + ")"), str(hs)])

# ------------------------------------------------------------------ S1 --
func s1() -> void:
	var m := caught()
	m.stretch_set(true)
	var emax := 0.0
	var esum := 0.0
	var n := 0
	var amax := 0.0
	for t in 240:
		m.step_tick(m.body_pos, true)
		var lp: Vector2 = m.ctl_load_point()
		if not is_nan(lp.x) and t >= 30:
			var e: float = m.pos[0].distance_to(lp) - float(m.a_freelen[0])
			emax = maxf(emax, e)
			esum += maxf(e, 0.0)
			n += 1
			amax = maxf(amax, m.pos[0].distance_to(m.body_pos))
	m.free()
	var locks := 0
	for i in 36:
		var c: Dictionary = DL.grid36()[i]
		var dm: Node2D = DL.make(G, H, D, true, [], "step")
		dm.stretch_set(true)
		dm._reset()
		DL.stand(dm, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
		if bool(DL.throw(dm, 0, c, HN.new("null", "st", 0), false)["lock"]):
			locks += 1
		dm.free()
	var pm := caught()
	pm.stretch_set(true)
	hist.clear()
	var prev: Vector2 = pm.body_pos
	var snaps: Array = []
	for t in 900:
		var b: Vector2 = pm.body_pos
		var cur: Vector2 = b - (Vector2(pm.a_pos[0]) - b).normalized() * pm.REACH if absf(late_angle(3)) < 45.0 else b
		prev = pm.body_pos
		pm.step_tick(cur, true)
		hist.append(DL.body_deg(pm, 0))
		var v: Vector2 = (pm.body_pos - prev) * 60.0
		if v.x > 0.0 and t >= 10:
			var xl := DL.ballistic_land(pm.body_pos, v, H, pm.BODY_R)
			if not is_nan(xl) and xl > G - 1.5 and xl < G + DL.LEDGE_W + 1.5:
				snaps.append([t, pm.snapshot()])
	var w: Array = landings(pm, snaps, func(mm: Node2D) -> void: mm.step_tick(mm.body_pos, false))
	pm.free()
	var r := caught()
	r.stretch_set(true)
	r.rec_begin("ctl_gate stretch")
	var start: Dictionary = r.rec_start
	for t in 300:
		var ph := float(t) * 0.12
		r.step_tick(r.body_pos + Vector2(cos(ph), sin(ph)) * 0.9, true)
	r.rec_end()
	var h_rec: int = r.state_hash()
	var cur_t: PackedVector2Array = r.rec_cur
	var grp: PackedByteArray = r.rec_grip
	var opt: PackedByteArray = r.rec_opt
	var hs: Array = []
	for honour in [true, false]:
		r.restore(start)
		for i in cur_t.size():
			r.pending_reset = (grp[i] & 2) != 0
			r.firm_set(honour and (opt[i] & 1) != 0)
			r.stretch_set(honour and (opt[i] & 2) != 0)
			r.step_tick(cur_t[i], (grp[i] & 1) != 0)
		hs.append(r.state_hash() == h_rec)
	r.free()
	var mean := esum / maxf(float(n), 1.0)
	ok("S1", emax > 0.02 and emax <= 0.25 + 0.005 and amax < 0.15 and locks == 7 and int(w[0]) >= MIN_RUN and hs == [true, false],
		"STRETCHY ROPE: the rope runs %.1f cm past its free length on average, %.1f at most, grip %.2f m, door %d/36, the pump lands on a run of %d, replay honoured/ignored %s" % [
			mean * 100.0, emax * 100.0, amax, locks, int(w[0]), str(hs)])

# ------------------------------------------------------------------ J1 --
func j1() -> void:
	# on the floor
	var m := standing()
	for t in 30:
		m.step_tick(m.body_pos, false)
	var f0: float = -(m.body_pos.y + m.BODY_R)
	m.pending_jump = true
	var top := f0
	var jumped_floor := false
	var jumped_air := false
	for t in 90:
		if t == 1 or t == 10:
			m.pending_jump = true          # pressed again one tick on, and mid-hop
		m.step_tick(m.body_pos, false)
		if t == 0:
			jumped_floor = bool(m.rec_jumped)
		elif t == 1 or t == 10:
			jumped_air = jumped_air or bool(m.rec_jumped)
		top = maxf(top, -(m.body_pos.y + m.BODY_R))
	var hop := top - f0
	m.free()
	# against a wall: the body pressed to the lip's face from the pit side
	var w := standing()
	w.teleport(Vector2(0.0 + w.BODY_R + 0.005, 1.5))
	for t in 20:
		w.step_tick(w.body_pos + Vector2(-0.8, 0.0), false)   # lean into the wall
	w.pending_jump = true
	w.step_tick(w.body_pos + Vector2(-0.8, 0.0), false)
	var jumped_wall := bool(w.rec_jumped)
	w.free()
	# with the hammer planted
	var h := standing()
	h.hammer_on = true
	for t in 60:
		h.step_tick(h.body_pos + Vector2(0.0, h.REACH), false)
	var planted: bool = h._hammer_planted()
	h.pending_jump = true
	h.step_tick(h.body_pos + Vector2(0.0, h.REACH), false)
	var jumped_planted := bool(h.rec_jumped)
	h.free()
	# the tape
	var r := standing()
	r.rec_begin("ctl_gate jump")
	var start: Dictionary = r.rec_start
	var jump_ticks: Array = [40, 140, 141, 260]
	for t in 360:
		if jump_ticks.has(t):
			r.pending_jump = true
		r.step_tick(r.body_pos + Vector2(0.3, -0.2), false)
	r.rec_end()
	var h_rec: int = r.state_hash()
	var opt: PackedByteArray = r.rec_opt
	var set_ticks: Array = []
	for i in opt.size():
		if (opt[i] & 4) != 0:
			set_ticks.append(i)
	var cur_t: PackedVector2Array = r.rec_cur
	var grp: PackedByteArray = r.rec_grip
	var hs: Array = []
	for honour in [true, false]:
		r.restore(start)
		for i in cur_t.size():
			r.pending_reset = (grp[i] & 2) != 0
			r.pending_jump = honour and (opt[i] & 4) != 0
			r.step_tick(cur_t[i], (grp[i] & 1) != 0)
		hs.append(r.state_hash() == h_rec)
	r.free()
	ok("J1", jumped_floor and hop >= 0.4 and hop <= 1.0 and not jumped_air and not jumped_wall and planted and not jumped_planted
			and set_ticks == [40, 140, 260] and hs == [true, false],
		"JUMP: floor hop %.2f m (%s); in the air %s, on a wall %s, hammer planted %s/%s; tape bit 2 on ticks %s; replay honoured/ignored %s" % [
			hop, str(jumped_floor), str(jumped_air), str(jumped_wall), str(planted), str(jumped_planted), str(set_ticks), str(hs)])
