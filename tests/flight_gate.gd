extends SceneTree
## THE FLIGHT GATE - every beam of a flight level, played on the level itself.
##
##   godot --headless --path . -s res://tests/flight_gate.gd -- level=flight [stage=<i>] [cp]
##
## Reads levels/<level>.plan.json (tests/gen_flight.py writes it). Per stage,
## with the shipped feel (lean, crack 45, springy stick, stretchy rope): stand 0.4 m behind
## the lip, throw the 36-stroke grid. Every lock is hauled off the lip and
## swung: cursor parked for a "park" stage (one rise is flown), or a pull
## down the rope through EVERY pass under the beam for a "tug" stage (the
## first two rises on the far side are flown: one pull, then two). Every tick
## of a flown rise is a release: restore, open the hand, fly, and see where
## the body stands. Reported per locking stroke: the run of release ticks that
## land on the target shelf (L; K = fell past Bottom, s = slid off, 0 = back
## on the lip's floor, a = somewhere else), the two rises separated by "|". A
## stage PASSES when at least MIN_STROKES locking strokes land with a run >=
## MIN_RUN and the best run is >= BEST_RUN. cp = only the checkpoint check.
const LIB := preload("res://tests/level_lib.gd")
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")

const MIN_RUN := 6
const BEST_RUN := 12
const MIN_STROKES := 3
const LEAD := 0.4

var level := "flight"
var only := -1
var cp_only := false
var plan := {}
var fails: Array[String] = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("level="):
			level = s.substr(6)
		elif s.begins_with("stage="):
			only = int(s.substr(6))
		elif s == "cp":
			cp_only = true
	var pp := "res://levels/%s.plan.json" % level
	if not FileAccess.file_exists(pp):
		print("FAIL flight gate: no %s (tests/gen_flight.py writes it)" % pp)
		quit(1)
		return
	plan = JSON.parse_string(FileAccess.get_file_as_string(pp))
	var stages: Array = plan["stages"]
	var t0 := Time.get_ticks_msec()
	var m := LIB.new_sim(level)
	if String(m.level_err) != "":
		print("FAIL flight gate: %s refused: %s" % [level, m.level_err])
		quit(1)
		return
	# THE SHIPPED FEEL. A certificate is about the game a player boots into,
	# so the gate plays with ctl_boot's defaults: classic controls with the
	# flipped lean (align_w inside the tick), the 45 m/s crack, the springy
	# stick and the stretchy rope - the same four tests/bot_demo.gd sets.
	m.ctl_set(m.Ctl.CLASSIC, true, false)
	m.crack_speed = m.CRACK_SPEED_HI
	m.stick_on = true
	m.stretch_set(true)
	print("flight gate %s: %d stages, %d anchors, the shipped feel (lean, crack 45, springy stick, stretchy rope)" % [level, stages.size(), m.a_pos.size()])
	if only < 0 or cp_only:
		checkpoints(m)
	for st: Dictionary in stages:
		var i := int(st["i"])
		if cp_only or (only >= 0 and i != only):
			continue
		var beam := Vector2(float(st["beam"][0]), float(st["beam"][1]))
		if i >= m.a_pos.size() or Vector2(m.a_pos[i]).distance_to(beam) > 0.02:
			fails.append("stage %d: anchor %d is not at the plan's beam %s" % [i, i, str(beam)])
			continue
		var r := probe(m, st, i)
		var landed: int = r["landed"]
		var ok := landed >= MIN_STROKES and int(r["best"]) >= BEST_RUN
		print("STAGE %2d %-5s %-4s | locks %2d/36, %d land with a run >= %d, best run %2d (stroke %s: %s)%s   %s" % [
			i, String(st["kind"]), String(st["policy"]), int(r["locks"]), landed, MIN_RUN, int(r["best"]),
			String(r["best_stroke"]), String(r["best_s"]).left(110), String(r["note"]), "ok" if ok else "FAIL"])
		if not ok:
			fails.append("stage %d" % i)
	m.free()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if fails.is_empty():
		print("PASS flight gate %s: every beam catches and every first swing lands its shelf (%.0f s)" % [level, secs])
		quit(0)
	else:
		print("FAIL flight gate %s: %s (%.0f s)" % [level, ", ".join(fails), secs])
		quit(1)

func checkpoints(m: Node2D) -> void:
	var cps: Array = plan.get("checkpoints", [])
	var moved := 0
	var returned := 0
	for c: Dictionary in cps:
		var cp := Vector2(float(c["x"]), float(c["y"]))
		m._reset()
		m.teleport(Vector2(cp.x, cp.y + 0.5 - m.BODY_R))
		for t in 30:
			m.step_tick(m.body_pos, false)
		if m.spawn.distance_to(cp) < 0.02:
			moved += 1
		var f0: int = m.falls
		m.teleport(Vector2(cp.x + 1.0, float(m.world_bottom) + 0.5))
		m.step_tick(m.body_pos, false)
		if m.falls == f0 + 1 and m.body_pos.distance_to(cp) < 0.02:
			returned += 1
	var ok := moved == cps.size() and returned == cps.size()
	print("   checkpoints %d: spawn moved onto %d, a fall returned to %d   %s" % [cps.size(), moved, returned, "ok" if ok else "FAIL"])
	if not ok:
		fails.append("checkpoints")

func probe(m: Node2D, st: Dictionary, k: int) -> Dictionary:
	var lip := float(st["lip_x"])
	var fy := float(st["shelf_y"])
	var tug := String(st["policy"]) == "tug"
	var hn := HN.new("null", "flight", 0)
	var grid: Array = DL.grid36()
	var locks: Array = []
	for j in grid.size():
		var c: Dictionary = grid[j]
		m._reset()
		DL.stand(m, lip - LEAD, fy, float(c["a0"]))
		if bool(DL.throw(m, k, c, hn, false)["lock"]):
			locks.append(j)
	var landed := 0
	var best := 0
	var best_stroke := "-"
	var best_s := ""
	var note := ""
	var tried := 0
	var cap := 14 if tug else 8
	for j: int in locks:
		if tried >= cap:
			note = " (first %d of %d locks flown)" % [cap, locks.size()]
			break
		tried += 1
		var c: Dictionary = grid[j]
		m._reset()
		DL.stand(m, lip - LEAD, fy, float(c["a0"]))
		DL.throw(m, k, c, hn, false)
		DL.haul(m, k)
		var snaps: Array = []        # [t, snapshot, rise index]
		var rise := 0                # which far-side rise we are on
		var rising := false
		var want := 2 if tug else 1
		for t in 600:
			var b: Vector2 = m.body_pos
			var th := DL.body_deg(m, k)
			var cur := b
			if tug and absf(th) < 45.0:
				cur = b - (Vector2(m.a_pos[k]) - b).normalized() * m.REACH
			var prev := b
			m.step_tick(cur, true)
			if float(m.a_freelen[k]) < 0.0:
				break
			var v: Vector2 = (m.body_pos - prev) * 60.0
			var th2 := DL.body_deg(m, k)
			var up_far := th2 > 5.0 and v.x > 0.0 and v.y < 0.0
			if up_far and not rising:
				rising = true
				rise += 1
			elif not up_far and rising:
				rising = false
				if rise >= want:
					break
			if up_far and snaps.size() < 180:
				snaps.append([t, m.snapshot(), rise])
		var s := ""
		var run := 0
		var widest := 0
		var last_rise := 1
		for e: Array in snaps:
			if int(e[2]) != last_rise:
				s += "|"
				run = 0
				last_rise = int(e[2])
			m.restore(e[1])
			var cc := fly(m, st)
			s += cc
			if cc == "L":
				run += 1
				widest = maxi(widest, run)
			else:
				run = 0
		if widest >= MIN_RUN:
			landed += 1
		if widest > best:
			best = widest
			best_stroke = "%d" % j
			best_s = s
	return {"locks": locks.size(), "landed": landed, "best": best, "best_stroke": best_stroke,
		"best_s": best_s, "note": note}

func fly(m: Node2D, st: Dictionary) -> String:
	var falls0: int = m.falls
	var still := 0
	for t in 480:
		var prev: Vector2 = m.body_pos
		m.step_tick(m.body_pos, false)
		var sp: float = (m.body_pos - prev).length() * 60.0
		still = still + 1 if (m.grounded and sp < 0.25) else 0
		if still >= 20 or m.falls > falls0:
			break
	if m.falls > falls0:
		return "K"
	var w := where(m, st)
	if w == "L":
		for t in 90:
			m.step_tick(m.body_pos, false)
		if where(m, st) != "L":
			return "s"
	return w

func where(m: Node2D, st: Dictionary) -> String:
	var b: Vector2 = m.body_pos
	var fy: float = b.y + m.BODY_R
	var tg: Dictionary = st["target"]
	if b.x >= float(tg["x0"]) - 0.35 and b.x <= float(tg["x1"]) + 0.05 and absf(fy - float(tg["y"])) < 0.30:
		return "L"
	if absf(fy - float(st["shelf_y"])) < 0.25 and b.x <= float(st["lip_x"]) + 0.05:
		return "0"
	return "a"
