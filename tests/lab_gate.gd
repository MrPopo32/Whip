extends SceneTree
## THE LAB'S OWN GATES. Everything here is about the bench existing WITHOUT
## disturbing the shipped traverse, and about the instruments that measure it
## being made to fail on a case where they must report nothing.
##
##   godot --headless --path . -s res://tests/lab_gate.gd
##
##  L1 the shipped level is byte-identical      (fingerprint + the golden hash)
##  L2 every committed tape still names it      (and none of them names the lab)
##  L3 the lab's terrain normals point into air (and the checker fails reversed)
##  L4 the two levels do not share a save slot  (and each refuses the other's)
##  L5 the bench is walkable and its stations are in isolation
##  L6 the jam flag is the ONLY thing that changed about an ordinary anchor,
##     and the arc floor jam_min_th is a real gate in BOTH directions
##  L7 G7 asked of the jam: a THROWN catch holds with the hand shut, goes
##     green, and drops the body in one frame when the hand opens
const MAIN := preload("res://main.gd")

const SHIPPED_FP := 8896234646103814336
const SHIPPED_HASH := 2762505307938286422
const TMP := "user://lab_gate_tmp.save"

var fail: Array[String] = []

func new_sim(lvl: String) -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = lvl
	m.setup_sim()
	m.save_enabled = false
	return m

# --------------------------------------------------------------------- L1 ---
func l1() -> void:
	var d := new_sim("")
	if d.level_fingerprint() != SHIPPED_FP:
		fail.append("L1 shipped level_fingerprint %d != %d"
			% [d.level_fingerprint(), SHIPPED_FP])
	if d.t_a.size() != 11 or d.a_pos.size() != 11:
		fail.append("L1 shipped level has %d segments / %d anchors, want 11/11"
			% [d.t_a.size(), d.a_pos.size()])
	if d.save_path != "user://run.save":
		fail.append("L1 shipped save slot moved to %s" % d.save_path)
	for k in d.a_pos.size():
		if int(d.a_jam[k]) != 0 or String(d.a_name[k]) != "":
			fail.append("L1 shipped anchor %d gained a jam flag or a caption" % k)
	d.free()
	# hashrun.gd's own scripted session, inline, so this gate stands alone.
	var m := new_sim("")
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
		m.step_tick(tgt, grip)
	var h: int = m.state_hash()
	if h != SHIPPED_HASH:
		fail.append("L1 golden hash %d != %d - the sim's BEHAVIOUR moved" % [h, SHIPPED_HASH])
	else:
		print("  L1 ok: shipped fp %d, golden hash %d, 11 segs / 11 beams, slot user://run.save"
			% [SHIPPED_FP, h])
	m.free()

# --------------------------------------------------------------------- L2 ---
func l2() -> void:
	var lab := new_sim("lab")
	var lab_fp: int = lab.level_fingerprint()
	lab.free()
	if lab_fp == SHIPPED_FP:
		fail.append("L2 the lab fingerprints the same as the traverse")
	var dir := DirAccess.open("res://tapes")
	if dir == null:
		fail.append("L2 no tapes/ directory")
		return
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".tape"):
			continue
		var t := MAIN.tape_load("res://tapes/" + f)
		if not bool(t.get("ok", false)):
			fail.append("L2 %s unreadable: %s" % [f, str(t.get("err", ""))])
			continue
		n += 1
		if int(t["lvl"]) != SHIPPED_FP:
			fail.append("L2 %s names level %d, not the shipped %d"
				% [f, int(t["lvl"]), SHIPPED_FP])
		if int(t["lvl"]) == lab_fp:
			fail.append("L2 %s would replay into the LAB" % f)
	if n != 6:
		fail.append("L2 found %d tapes, expected 6" % n)
	elif fail.is_empty():
		print("  L2 ok: 6 tapes, all still naming %d; the lab is %d"
			% [SHIPPED_FP, lab_fp])

# --------------------------------------------------------------------- L3 ---
# The lab's air is the box its own walls and floor enclose. DERIVED from the
# terrain, never written down here: a hardcoded -8 in this checker went stale
# the moment the left wall moved to -12 and reported 2 of 3 normals wrong on a
# level that was fine - which is exactly the failure the stuck-in-floor probe
# had (it carried the OLD level geometry and reported a bug 0.79 m in mid-air).
# A stored normal is correct when a point a hair along it is INSIDE that box
# and a point a hair against it is outside. Winding is the thing that gets this
# wrong, and it is the winding bug that once pushed the whip through the floor,
# so the counter-check is to run the same checker on the REVERSED walk and
# demand that it fail every segment.
var box_lo := Vector2.ZERO
var box_hi := Vector2.ZERO

func in_air(q: Vector2) -> bool:
	return q.x > box_lo.x and q.x < box_hi.x \
		and q.y > box_lo.y and q.y < box_hi.y

func normals_score(ta: PackedVector2Array, tb: PackedVector2Array) -> int:
	var ok := 0
	for i in ta.size():
		var n := Vector2((tb[i] - ta[i]).y, -(tb[i] - ta[i]).x).normalized()
		var mid := (ta[i] + tb[i]) * 0.5
		if in_air(mid + n * 0.002) and not in_air(mid - n * 0.002):
			ok += 1
	return ok

func l3() -> void:
	var m := new_sim("lab")
	box_lo = Vector2(1e9, 1e9)
	box_hi = Vector2(-1e9, -1e9)
	for i in m.t_a.size():
		for q: Vector2 in [m.t_a[i], m.t_b[i]]:
			box_lo = Vector2(minf(box_lo.x, q.x), minf(box_lo.y, q.y))
			box_hi = Vector2(maxf(box_hi.x, q.x), maxf(box_hi.y, q.y))
	var good := normals_score(m.t_a, m.t_b)
	# the same walk, backwards
	var ra := PackedVector2Array()
	var rb := PackedVector2Array()
	for i in range(m.t_a.size() - 1, -1, -1):
		ra.append(m.t_b[i])
		rb.append(m.t_a[i])
	var bad := normals_score(ra, rb)
	if good != m.t_a.size():
		fail.append("L3 %d of %d lab normals point into the air"
			% [good, m.t_a.size()])
	elif bad != 0:
		fail.append("L3 the normal checker scores %d on a REVERSED winding - it cannot fail, so it cannot pass" % bad)
	else:
		print("  L3 ok: air box (%.0f,%.0f)..(%.0f,%.0f); %d/%d lab normals into it; reversed winding scores 0/%d"
			% [box_lo.x, box_lo.y, box_hi.x, box_hi.y, good, m.t_a.size(),
			m.t_a.size()])
	m.free()

# --------------------------------------------------------------------- L4 ---
func l4() -> void:
	var d := new_sim("")
	var l := new_sim("lab")
	if d.save_path == l.save_path:
		fail.append("L4 both levels write %s" % d.save_path)
	if l.save_path != "user://run_lab.save":
		fail.append("L4 the lab writes %s" % l.save_path)
	# a TRAVERSE save must be refused by a LAB sim, and the other way round.
	d.body_pos = Vector2(3.0, -1.0)
	if not d.save_to(TMP):
		fail.append("L4 could not write the temp save")
	var r_wrong: int = l.load_from(TMP)
	var d2 := new_sim("")
	var r_right: int = d2.load_from(TMP)
	l.save_to(TMP)
	var d3 := new_sim("")
	var r_wrong2: int = d3.load_from(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + ".tmp"))
	if r_wrong != -1:
		fail.append("L4 a lab session ACCEPTED a traverse save (load_from -> %d)" % r_wrong)
	if r_wrong2 != -1:
		fail.append("L4 a traverse session ACCEPTED a lab save (load_from -> %d)" % r_wrong2)
	if r_right != 1:
		fail.append("L4 a traverse save was refused by its OWN level (load_from -> %d) - the refusal above proves nothing if nothing is ever accepted" % r_right)
	if fail.is_empty():
		print("  L4 ok: slots user://run.save / user://run_lab.save; cross-load -1 both ways, own-load 1")
	d.free(); d2.free(); d3.free(); l.free()

# --------------------------------------------------------------------- L5 ---
func l5() -> void:
	var m := new_sim("lab")
	var minh := 1e9
	var maxh := -1e9
	var mingap := 1e9
	for k in m.a_pos.size():
		var h: float = -float(m.a_pos[k].y)
		minh = minf(minh, h)
		maxh = maxf(maxh, h)
		if String(m.a_name[k]) == "":
			fail.append("L5 lab anchor %d has no caption" % k)
		for j in range(k + 1, m.a_pos.size()):
			mingap = minf(mingap, m.a_pos[k].distance_to(m.a_pos[j]))
	# THE ENVELOPE, from tests/throw_probe.gd: a 5.25 m whip locks about 3 m
	# above the floor it is thrown from.
	if maxh > 3.0:
		fail.append("L5 a station is %.2f m up, past the 3 m throw envelope" % maxh)
	# THE ISOLATION: the whole rope lives inside 5.25 + 1.15 = 6.40 m of the
	# body, so two anchors further apart than that cannot both be in reach.
	if mingap <= 6.40:
		fail.append("L5 two stations are %.2f m apart, inside the 6.40 m rope circle - they are not in isolation" % mingap)
	# THE CAMERA: CAM_VOLS[0] ends at x 19 with 1.5 m of hysteresis, so a body
	# that never passes 20.5 never steps the shelf and the bench is one shot.
	var right := -1e9
	for i in m.t_a.size():
		right = maxf(right, maxf(m.t_a[i].x, m.t_b[i].x))
	if right - m.BODY_R > 20.5:
		fail.append("L5 the body can reach x %.2f, past the volume-0 boundary at 20.5 - the camera would step 3 m down to a tier the lab does not have" % (right - m.BODY_R))
	# WALKABLE END TO END: crawl from spawn to the far wall with the lash gait
	# and check it actually gets there. No number is assumed - it is walked.
	# tests/ground_probe.gd's OWN best gait, taken from its printed winner rather
	# than invented here: period 24, back 2.83 rad for the first 45%, forward
	# -0.94 rad for the rest, and the hand never closes (its taut phase begins
	# at 1.10 of a period, which never arrives). That last clause matters for
	# this gate: with the hand open no beam can engage, so what is measured is
	# WALKING and not walking-with-accidental-catches.
	var x0: float = m.body_pos.x
	var t := 0
	while t < 60 * 180 and m.body_pos.x < right - 1.0:
		var f := float(t % 24) / 24.0
		var tgt: Vector2
		if f < 0.45:
			tgt = m.body_pos + Vector2(cos(2.83), sin(2.83)) * m.REACH
		else:
			tgt = m.body_pos + Vector2(cos(-0.94), sin(-0.94)) * m.REACH
		m.step_tick(tgt, false)
		t += 1
	if m.body_pos.x < right - 1.0:
		fail.append("L5 the bench is not walkable: 120 s of gait moved the body from %.2f to %.2f (wall at %.2f)"
			% [x0, m.body_pos.x, right])
	elif fail.is_empty():
		print("  L5 ok: stations %.2f-%.2f m up, closest pair %.2f m apart, body reaches x %.2f in %.1f s of gait"
			% [minh, maxh, mingap, m.body_pos.x, t / 60.0])
	m.free()

# --------------------------------------------------------------------- L6 ---
# THE JAM FLAG IS ONE BIT AND IT HAD BETTER DO ONE THING. This one is a UNIT
# test of the predicate and says so: a single particle is placed by hand, on
# the anchor's surface and then a metre off it, because what is under test is
# _pinch's answer and not the physics that would put a rope there. The thrown
# question - can a real stroke reach it - is tests/lab_throw.gd's, and it is
# measured there with nothing hand-laid.
#
# Three readings, and all three have to come out for the flag to mean anything:
# it must say YES on contact, NO at a distance (a jam that fired at range would
# be a magnet, not an anchor), and NO when it is off - that last one is what
# proves the flag is what is doing it and not the geometry.
func l6() -> void:
	var m := new_sim("lab")
	var k := 2                                   # JAM
	if int(m.a_jam[k]) != 1:
		fail.append("L6 station 2 is not the jam")
		m.free()
		return
	# TWO inputs now decide a jam, not one: the rope has to be touching AND the
	# arc has to be worth drawing. _pinch reads a_theta, which the tick computes
	# and a hand-laid rig does not, so it is set here explicitly - that is the
	# point of the test rather than a shortcut around it. Both sides of the floor
	# are asserted, because a floor only tested from above is a floor that could
	# be zero and nobody would know.
	var i := 20
	var p: PackedVector2Array = m.pos
	var touch_d: float = m.a_r[k] + m.p_rad[i]
	p[i] = m.a_pos[k] + Vector2(0.0, -touch_d)
	m.pos = p
	var th: PackedFloat32Array = m.a_theta
	var pass_th: float = float(m.jam_min_th) + 0.10
	var fail_th: float = float(m.jam_min_th) - 0.10
	th[k] = pass_th
	m.a_theta = th
	var on_pinch: bool = m._pinch(k)
	th[k] = fail_th
	m.a_theta = th
	var dark_pinch: bool = m._pinch(k)
	th[k] = pass_th
	m.a_theta = th
	var j: PackedInt32Array = m.a_jam
	j[k] = 0
	m.a_jam = j
	var off_pinch: bool = m._pinch(k)
	j[k] = 1
	m.a_jam = j
	p[i] = m.a_pos[k] + Vector2(0.0, -1.0)
	m.pos = p
	var far_pinch: bool = m._pinch(k)
	if not on_pinch:
		fail.append("L6 the jam did NOT pinch on its surface (%.3f m, r %.2f) at theta %.2f"
			% [touch_d, m.a_r[k], pass_th])
	if dark_pinch:
		fail.append("L6 the jam pinched at theta %.2f, under the %.2f floor - it can hold what it cannot draw (the arc starts at 0.3)"
			% [fail_th, float(m.jam_min_th)])
	if off_pinch:
		fail.append("L6 the SAME contact pinches with the jam flag off - the flag is not what is doing it")
	if far_pinch:
		fail.append("L6 the jam pinched with the nearest rope 1.00 m away - that is a magnet, not an anchor")
	if fail.is_empty():
		print("  L6 ok: jam pinches at %.3f m and theta %.2f; refuses at theta %.2f (floor %.2f), refuses at 1.00 m, refuses with the flag off"
			% [touch_d, pass_th, fail_th, float(m.jam_min_th)])
	m.free()

# --------------------------------------------------------------------- L7 ---
# G7, ASKED OF THE JAM. sim_test's G7 says: releasing TAUT while hanging must
# drop you, and if slack can bear load then SLACK and TAUT have collapsed into
# one state and the grip button is decorative. That is the gate every geometry
# the probes found FAILED - an hourglass chockstone and a two-circle throat
# both hold with the hand open, bit-identically to holding it shut. So the jam
# has to answer it here, on the shipped lab anchor, from a thrown catch.
#
# Nothing is hand-laid: the throw is searched on the lab's own floor and the
# catch is whatever step_tick produced. Then the floor is taken away - by
# REBUILDING the arrays and assigning them back, because a packed array reached
# through a property is a copy and remove_at() on one silently does nothing -
# and the same snapshot is run twice, hand shut and hand open.
func l7() -> void:
	var k := 2                                   # JAM
	var best := {}
	for lead in [1.6, 2.0, 2.4]:
		for ang: Array in [[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30],
				[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30]]:
			for sd in [9, 14]:
				for pull in [false, true]:
					if not best.is_empty():
						continue
					var mm := _throw(k, lead, float(ang[0]), float(ang[1]), sd,
						pull)
					if mm == null:
						continue
					if bool(mm._holds(k)):
						best = {"m": mm, "how": "lead %.1f a0 %.2f a1 %.2f sd %d pull %s"
							% [lead, ang[0], ang[1], sd, str(pull)]}
					else:
						mm.free()
	if best.is_empty():
		fail.append("L7 no searched stroke caught the JAM green - nothing to test")
		return
	var m: Node2D = best["m"]
	# take the floor away: the stations are 2.2 m up, so a body that "hangs"
	# with the floor in is a body standing on the floor
	m.t_a = PackedVector2Array()
	m.t_b = PackedVector2Array()
	m.t_n = PackedVector2Array()
	m.t_lo = PackedVector2Array()
	m.t_hi = PackedVector2Array()
	m.world_bottom = 1.0e9
	var snap: Dictionary = m.snapshot()
	var y0: float = m.body_pos.y
	var green := 0
	for t in 180:
		m.step_tick(m.body_pos, true)
		if bool(m._holds(k)):
			green += 1
	var d_shut: float = m.body_pos.y - y0
	m.restore(snap)
	var y1: float = m.body_pos.y
	var rel := -1
	for t in 180:
		m.step_tick(m.body_pos, false)
		if rel < 0 and float(m.a_freelen[k]) < 0.0:
			rel = t
	var d_open: float = m.body_pos.y - y1
	# THE NEGATIVE CONTROL, and it is the one this whole gate needs: the same
	# state, the same hand-SHUT input, with the catch dropped. If a body that is
	# holding nothing still reads as "held", then the shut column above measures
	# the rig and not the anchor. This is the shape of the fault that made a
	# previous probe report 36/36 holds for geometries that cannot hold
	# anything - it was measuring a floor it thought it had removed.
	m.restore(snap)
	m.clear_anchors()
	var y2: float = m.body_pos.y
	for t in 180:
		m.step_tick(m.body_pos, true)
	var d_none: float = m.body_pos.y - y2
	if d_none < 1.0:
		fail.append("L7 CONTROL FAILED: with the catch dropped the body still only moved %.3f m in 3 s with the hand shut - the rig is holding it, not the anchor"
			% d_none)
	if absf(d_shut) > 0.50:
		fail.append("L7 the jam did not hold with the hand SHUT: %.3f m in 3 s"
			% d_shut)
	if green < 170:
		fail.append("L7 the ring was green on only %d of 180 held ticks - the whip is carrying the player and the arc is not saying so" % green)
	if d_open < 1.0:
		fail.append("L7 SLACK IS LOAD-BEARING at the jam: opening the hand dropped the body %.3f m in 3 s against %.3f m gripped. The grip button is decorative here."
			% [d_open, d_shut])
	if rel != 0:
		fail.append("L7 the jam took %d ticks to let go, not one frame" % rel)
	if fail.is_empty():
		print("  L7 ok: thrown catch (%s)" % String(best["how"]))
		print("         hand SHUT %+.3f m over 3 s, ring green %d/180" % [d_shut, green])
		print("         hand OPEN falls %.1f m, released on tick %d" % [d_open, rel])
		print("         control (catch dropped, hand still shut) falls %.1f m" % d_none)
	m.free()

# one searched stroke, returning the sim at the moment of the catch (or null)
func _throw(k: int, lead: float, a0: float, a1: float, sd: int,
		pull: bool) -> Node2D:
	var m := new_sim("lab")
	m.teleport(Vector2(float(m.a_pos[k].x) - lead, -m.BODY_R))
	for t in 90:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
	var grip := false
	var closes := 0
	for t in 250:
		var ang: float = a0
		var amp := 1.0
		if t >= 120 and t < 120 + sd:
			ang = a1
		elif t >= 120 + sd:
			ang = a1
			if pull and t < 130 + sd:
				ang = a0; amp = 0.7
		# the cue a jam offers the player: shut the hand when the rope arrives
		var touch := false
		for i in m.NP:
			if (m.pos[i] - m.a_pos[k]).length() \
					< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
				touch = true
				break
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		if not grip and touch and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		m.step_tick(m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp,
			grip)
		if float(m.a_freelen[k]) >= 0.0:
			for u in 55:
				m.step_tick(m.body_pos, true)
				if float(m.a_freelen[k]) < 0.0:
					break
			if float(m.a_freelen[k]) < 0.0:
				m.free()
				return null
			return m
	m.free()
	return null

func _initialize() -> void:
	l1(); l2(); l3(); l4(); l5(); l6(); l7()
	if fail.is_empty():
		print("PASS  lab gates L1-L7")
		quit(0)
		return   # the last quit() wins: without this the exit code was 1
	for f in fail:
		print("FAIL  %s" % f)
	quit(1)
