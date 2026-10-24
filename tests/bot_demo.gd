extends SceneTree
## THE DEMO BOT - plays levels/demo.tscn through real inputs and records the
## run as a tape, so the replay (and a GIF of it) is the game, not a cutscene.
##
##   godot --headless --path . -s res://tests/bot_demo.gd [-- out=levels/demo.tape stages=9 v]
##
## Per stage, from levels/demo.plan.json: walk to a stance short of the lip
## (the hammer stick to 2.5 m out, then the lash crawl), lay the whip back,
## throw a stroke from the grid, haul off the lip, swing (parked, or a pull on
## every pass under the beam), let go on the first tick whose ballistic
## forecast lands on the shelf, fly, land, settle. Everything is through
## step_tick: no teleports after the start.
##
## PLANNING IS OFF-TAPE, tapelib's plan_capture idiom: each stage is tried
## from a snapshot (a ladder of stances x three lay-backs x the stroke list)
## with recording off,
## the snapshot is restored, and only the stance and stroke that LANDED are
## played again, on tape. The sim is bit-deterministic, so the second playing
## is the first one. A tape that contained the rejected tries would be a tape
## of a bot flailing, and the point of the recording is a run a person could
## have made. The tape lives BESIDE THE LEVEL, not in tapes/: that folder is
## the shipped level's corpus and four gates count on it (lab L2, crag C2,
## save_test, mark_rt); tape_verify sweeps levels/*.tape as well.
const LIB := preload("res://tests/level_lib.gd")
const TL := preload("res://tests/tapelib.gd")
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")

## strokes tried first per stage kind (the gates' winners), then the grid
const STROKES := {"glide": [6, 5, 3, 0, 24, 27], "hold": [27, 6, 5, 24, 30, 23], "rise": [30, 23, 27, 24, 6, 5]}
const LEADS := [0.45, 0.65, 0.85, 0.30]   # the stance ladder: metres short of the lip
const LAYS := [150, 90, 220]              # ticks of lay-back tried per stance
const CAP := 36                           # strokes flown per stance and lay before the next
const RELEASE_DEG := 15.0                 # the earliest the aim is read, deg past the bottom

var m: Node2D
var hn: RefCounted
var plan := {}
var grid: Array = []
var lay := 150                   # ticks of lay-back before a stroke
var verbose := false
var stance := "gait"             # gait (the lash crawl, whip behind), hammer
                                 # (the stick walk all the way), tele (teleport:
                                 # only before the tape starts)

func feet() -> float:
	return -(m.body_pos.y + m.BODY_R)

func tick(cur: Vector2, grip: bool) -> void:
	m.step_tick(cur, grip)

func settle(n: int) -> void:
	for t in n:
		tick(m.body_pos, false)

func ang_off(deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * m.REACH

## the Getting Over It walk, planted hammer, until the body is past x. The
## stick is off while the hammer is on, as the P cycle leaves them: a tape
## with both bits set would replay, but no hand on the keys could make it.
func walk_to(x: float, cap := 1200) -> bool:
	var stick_was: bool = m.stick_on
	m.stick_on = false
	m.hammer_on = true
	var t := 0
	while m.body_pos.x < x and t < cap:
		var f := float(t % 30) / 30.0
		var deg := lerpf(140.0, 400.0, f / 0.30) if f < 0.30 else (40.0 if f < 0.40 else lerpf(40.0, 140.0, (f - 0.40) / 0.60))
		tick(m.body_pos + ang_off(deg), false)
		t += 1
	m.hammer_on = false
	m.stick_on = stick_was
	settle(30)
	return m.body_pos.x >= x

## get the body to x and standing: the stick walk to 2.5 m short of it, then
## the crawl; true only if it stands within 0.3 m of x without having fallen
func approach(x: float) -> bool:
	var f0: int = m.falls
	if stance == "tele" and not m.rec_on:
		# a teleport is not a tick, so it cannot be on the tape: once the
		# recording has begun, tele walks like gait
		m.teleport(Vector2(x, m.body_pos.y))
		settle(30)
		return true
	if stance == "hammer":
		walk_to(x)
	else:
		if m.body_pos.x < x - 2.5:
			walk_to(x - 2.5)
		TL.walk_to(m, x, 1500)
		settle(30)
		if m.body_pos.x > x + 0.2:
			TL.walk_to(m, x, 600)            # the back gait
			settle(30)
	var ok: bool = m.falls == f0 and absf(m.body_pos.x - x) <= 0.3
	if verbose:
		print("      approach %.2f: body x %.2f feet %.2f falls %d   %s" % [x, m.body_pos.x, feet(), m.falls - f0, "ok" if ok else "NO"])
	return ok

## a standing throw: drag the whip out behind (hand low and back, then at the
## stroke's own wind-up angle), then the stroke (DL.throw's own press rule),
## through real ticks; returns the lock. A fall during the lay-back is a miss.
func throw(k: int, c: Dictionary) -> bool:
	var f0: int = m.falls
	for t in lay / 2:
		tick(m.body_pos + ang_off(160.0), false)
	for t in lay / 2:
		tick(m.body_pos + Vector2(cos(float(c["a0"])), sin(float(c["a0"]))) * m.REACH, false)
	if m.falls > f0:
		return false
	var r: Dictionary = DL.throw(m, k, c, hn, false)
	return bool(r["lock"])

func swing_and_fly(k: int, kind: String, st: Dictionary) -> String:
	DL.haul(m, k)
	var tug := kind != "glide"
	var want := 2 if tug else 1
	var rise := 0
	var rising := false
	var released := false
	var tg: Dictionary = st["target"]
	for t in 900:
		var b: Vector2 = m.body_pos
		var th := DL.body_deg(m, k)
		var cur := b
		if tug and absf(th) < 45.0:
			cur = b - (Vector2(m.a_pos[k]) - b).normalized() * m.REACH
		var prev := b
		tick(cur, true)
		if float(m.a_freelen[k]) < 0.0:
			return "lost the beam"
		var v: Vector2 = (m.body_pos - prev) * 60.0
		var th2 := DL.body_deg(m, k)
		var up_far := th2 > 5.0 and v.x > 0.0 and v.y < 0.0
		if up_far and not rising:
			rising = true
			rise += 1
		elif not up_far and rising:
			rising = false
		if up_far and rise >= want and th2 >= RELEASE_DEG:
			# AIM: let go on the first tick whose ballistic flight comes down
			# inside the shelf (the body centre through the shelf top), the
			# forecast the gates prefilter with - a player reads it off the
			# arc; the bot reads it off the numbers
			var xl := DL.ballistic_land(Vector2(m.body_pos.x, m.body_pos.y - float(tg["y"])), v, 0.0, m.BODY_R)
			if not is_nan(xl) and xl >= float(tg["x0"]) + 0.4 and xl <= float(tg["x1"]) - 0.5:
				released = true
				break
	if not released:
		return "never released"
	# fly: hand open, cursor parked, until standing still or past the bottom
	var falls0: int = m.falls
	var still := 0
	for t in 600:
		var pb: Vector2 = m.body_pos
		tick(m.body_pos, false)
		still = still + 1 if (m.grounded and (m.body_pos - pb).length() * 60.0 < 0.25) else 0
		if still >= 20 or m.falls > falls0:
			break
	if m.falls > falls0:
		return "fell"
	var on: bool = m.body_pos.x >= float(tg["x0"]) - 0.35 and absf(m.body_pos.y + m.BODY_R - float(tg["y"])) < 0.3
	return "landed at x %.1f" % m.body_pos.x if on else "down at x %.1f, feet %.2f" % [m.body_pos.x, feet()]

func stroke_order(kind: String) -> Array:
	var order: Array = STROKES[kind].duplicate()
	for j in grid.size():
		if not order.has(j):
			order.append(j)
	return order

## try the stage off-tape from the current state; {} or {"lead", "j"}
func plan_stage(i: int, kind: String, st: Dictionary) -> Dictionary:
	var was: bool = m.rec_on
	m.rec_on = false
	var s0: Dictionary = m.snapshot()
	var h0: Dictionary = hn.save_state()
	var found := {}
	var locks := 0
	for lead: float in LEADS:
		m.restore(s0)
		hn.restore_state(h0)
		if not approach(float(st["lip_x"]) - lead):
			continue
		var s1: Dictionary = m.snapshot()
		var h1: Dictionary = hn.save_state()
		# the lay-back is the other half of the stance: how the whip lies
		# behind decides which strokes lock, so each stance is tried at
		# three of them before the next rung
		for lay_t: int in LAYS:
			lay = lay_t
			var tried := 0
			for j: int in stroke_order(kind):
				if tried >= CAP:
					break
				tried += 1
				m.restore(s1)
				hn.restore_state(h1)
				if not throw(i, grid[j]):
					continue
				locks += 1
				var o := swing_and_fly(i, kind, st)
				if verbose:
					print("      lead %.2f lay %3d stroke %2d: %s" % [lead, lay, j, o])
				if o.begins_with("landed"):
					found = {"lead": lead, "lay": lay, "j": j}
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break
	if found.is_empty():
		print("      (stage %d: %d locks over the ladder, none landed)" % [i, locks])
	m.restore(s0)
	hn.restore_state(h0)
	m.rec_on = was
	return found

func _initialize() -> void:
	var out := "levels/demo.tape"
	var nstages := 99
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("out="):
			out = s.substr(4)
		elif s.begins_with("stages="):
			nstages = int(s.substr(7))
		elif s.begins_with("lay="):
			lay = int(s.substr(4))
		elif s == "v":
			verbose = true
		elif s.begins_with("stance="):
			stance = s.substr(7)
	plan = JSON.parse_string(FileAccess.get_file_as_string("res://levels/demo.plan.json"))
	grid = DL.grid36()
	m = LIB.new_sim("demo")
	m.ctl_set(m.Ctl.CLASSIC, true, false)
	m.stretch_set(true)
	m.crack_speed = m.CRACK_SPEED_HI
	m.stick_on = true
	hn = HN.new("null", "demo", 0)
	settle(30)
	var stages: Array = plan["stages"]
	var done := 0
	for st: Dictionary in stages:
		var i := int(st["i"])
		if i >= nstages:
			break
		var kind := String(st["kind"])
		var lip := float(st["lip_x"])
		var p := plan_stage(i, kind, st)
		if p.is_empty():
			print("stage %d %-5s: nothing lands from any stance" % [i, kind])
			break
		approach(lip - float(p["lead"]))
		lay = int(p["lay"])
		if i == 0:
			# the first stance is walked to BEFORE the tape starts: the tape's
			# start state is the body at the lip, so a replay opens on the
			# first throw
			m.rec_begin("the demo: nine beams, played by tests/bot_demo.gd")
		var locked := throw(i, grid[int(p["j"])])
		var outcome := swing_and_fly(i, kind, st) if locked else "no lock on the replay"
		print("stage %d %-5s lead %.2f lay %3d stroke %2d: %s   (tick %d)" % [i, kind, float(p["lead"]), int(p["lay"]), int(p["j"]), outcome, m.rec_cur.size()])
		if outcome.begins_with("landed"):
			done += 1
		else:
			break
	if done == stages.size():
		# the summit: walk to the flag
		var gx: float = float(plan["goal"][0]) + 1.6
		TL.walk_to(m, gx, 1500)
		settle(90)
		print("goal: body x %.1f, finished %s" % [m.body_pos.x, str(m.finished)])
	m.rec_end()
	if m.rec_start.is_empty():
		# rec_begin never ran (the first stage did not plan, or stages=0): a
		# tape with no start state cannot be replayed, and saving it would
		# overwrite the good one
		print("no tape: the first stage never recorded, %d of %d stages landed" % [done, stages.size()])
	else:
		var ok: bool = m.tape_save(out)
		print("tape %s: %s, %d ticks (%.1f s), %d of %d stages landed" % [out, str(ok), m.rec_cur.size(), m.rec_cur.size() / 60.0, done, stages.size()])
	m.free()
	quit(0)
