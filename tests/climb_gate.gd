extends SceneTree
## THE CLIMB GATE - every door of a generated climb, measured on the level
## itself: the launch from its lip and the recovery from the far edge of its
## pit. climb_door_map measured the move on a bench; this is the move on the
## rock you shipped, other doors and all.
##
##   godot --headless --path . -s res://tests/climb_gate.gd -- level=climb [stage=<i>] [T=150] [quick] [cp]
##
## Reads levels/<level>.plan.json (tests/gen_climb.py writes it) for where
## each shelf, door, pit and target shelf is. Per stage:
##   LAUNCH    stand on the shelf 1.8 m before the door (climb_door_map's
##             catch A stance), throw the 36-stroke grid noise-free. Every
##             lock is hauled off the lip, pumped to T with bot_pump's servo,
##             snapshotted on every tick the body moves +x; the ballistic
##             picks (+/-4 ticks) are flown with the hand open and classified
##             where they come to rest. Reported: the widest run of release
##             ticks that land and stand on the target shelf, over the best
##             three locking strokes.
##   RECOVERY  stand on the floor past the pit, 1.8 m from the door, facing
##             it (strokes mirrored), and the same.
## A stage PASSES when its launch has a run >= MIN_RUN and, when the plan has
## a recovery floor ("under"), its recovery locks with a run >= MIN_RUN.
## quick = launches only. cp = only the checkpoint check: standing at each
## checkpoint of the plan moves the spawn there, and a fall past Bottom
## returns to it (and to nowhere else). A body at rest on the target's lip
## fillet (within 0.35 m of its near edge, feet within 0.30 m of its top)
## counts as landed - the 90-tick recheck throws out the ones that slide.
## Codes in the flight
## strings: L on the target, u on the floor at this shelf's level past the
## pit, 0 back on this shelf, p in the pit, K past the Bottom line (a fall to
## Spawn), s slid off the target, a still in the air at the cap.
const LIB := preload("res://tests/level_lib.gd")
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")

const MIN_RUN := 6           # ticks: 100 ms of release timing
const LEAD := 1.8            # m from the door, standing
const NPUMP := 480
const MAX_LOCKS := 2
const LAND_NEAR := -0.5      # m: a release is flown when its ballistic landing
const LAND_FAR := 3.0        # falls this far before/past the target's near edge
                             # (the bench's landings were 0.3-2.8 m past it)
const WIDEN := 2             # ticks flown either side of every forecast pick

var level := "climb"
var T := 150.0
var quick := false
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
		elif s.begins_with("T="):
			T = float(s.substr(2))
		elif s == "quick":
			quick = true
		elif s == "cp":
			cp_only = true
	var pp := "res://levels/%s.plan.json" % level
	if not FileAccess.file_exists(pp):
		print("FAIL climb gate: no %s (tests/gen_climb.py writes it)" % pp)
		quit(1)
		return
	plan = JSON.parse_string(FileAccess.get_file_as_string(pp))
	var stages: Array = plan["stages"]
	var t0 := Time.get_ticks_msec()
	var m := LIB.new_sim(level)
	if String(m.level_err) != "":
		print("FAIL climb gate: %s refused: %s" % [level, m.level_err])
		quit(1)
		return
	print("climb gate %s: %d stages, %d anchors, T %.0f%s" % [level, stages.size(),
		m.a_pos.size(), T, " (quick: launches only)" if quick else ""])
	if only < 0 or cp_only:
		checkpoints(m)
	for st: Dictionary in stages:
		var i := int(st["i"])
		if cp_only or (only >= 0 and i != only):
			continue
		var door := Vector2(float(st["door"][0]), float(st["door"][1]))
		if i >= m.a_pos.size() or Vector2(m.a_pos[i]).distance_to(door) > 0.02:
			fails.append("stage %d: anchor %d is not at the plan's door %s" % [i, i, str(door)])
			continue
		var la := probe(m, st, i, false)
		var line := "STAGE %2d %-6s h %.1f G %.2f | launch: locks %2d/36, best run %2d (stroke %s, %s)" \
			% [i, String(st["name"]), float(st["h"]), float(st["G"]), int(la["locks"]),
			int(la["widest"]), String(la["stroke"]), String(la["hist"])]
		var ok := int(la["widest"]) >= MIN_RUN
		if not quick and st.get("under") != null:
			var re := probe(m, st, i, true)
			line += " | recovery: locks %2d/36, best run %2d (stroke %s, %s)" \
				% [int(re["locks"]), int(re["widest"]), String(re["stroke"]), String(re["hist"])]
			ok = ok and int(re["locks"]) > 0 and int(re["widest"]) >= MIN_RUN
		print(line + ("   ok" if ok else "   FAIL"))
		if not ok:
			fails.append("stage %d" % i)
	m.free()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if fails.is_empty():
		print("PASS climb gate %s: every door launches with a run of >= %d ticks%s (%.0f s)" % [level, MIN_RUN,
			"" if quick else " (and recovers where the plan has a floor to recover from)", secs])
		quit(0)
	else:
		print("FAIL climb gate %s: %s (%.0f s)" % [level, ", ".join(fails), secs])
		quit(1)

## Every checkpoint of the plan: stand on it, the spawn moves there; drop the
## body past Bottom, it is back on it with one more fall. Then stand 3 m past
## it and drop: still it, not the spot you fell from.
func checkpoints(m: Node2D) -> void:
	var cps: Array = plan.get("checkpoints", [])
	var moved := 0
	var returned := 0
	var kept := 0
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
		m.teleport(Vector2(cp.x + 3.0, cp.y + 0.5 - m.BODY_R))
		for t in 30:
			m.step_tick(m.body_pos, false)
		m.teleport(Vector2(cp.x + 3.0, float(m.world_bottom) + 0.5))
		m.step_tick(m.body_pos, false)
		if m.body_pos.distance_to(cp) < 0.02:
			kept += 1
	var ok := moved == cps.size() and returned == cps.size() and kept == cps.size()
	print("   checkpoints %d: spawn moved onto %d, a fall returned to %d, and stayed theirs from 3 m on for %d   %s"
		% [cps.size(), moved, returned, kept, "ok" if ok else "FAIL"])
	if not ok:
		fails.append("checkpoints")

## One stance, 36 strokes, up to MAX_LOCKS windows. Returns the best.
func probe(m: Node2D, st: Dictionary, k: int, recovery: bool) -> Dictionary:
	var door := Vector2(float(st["door"][0]), float(st["door"][1]))
	var fy := float(st["shelf_y"])
	var x := door.x + LEAD if recovery else door.x - LEAD
	var hn := HN.new("null", "gate", 0)
	var grid: Array = DL.grid36()
	var locks: Array = []
	for j in grid.size():
		var c: Dictionary = grid[j]
		m._reset()
		DL.stand(m, x, fy, DL._ang(float(c["a0"]), recovery))
		var r: Dictionary = DL.throw(m, k, c, hn, recovery)
		if bool(r["lock"]):
			locks.append(j)
	print("   stage %d %s: %d/36 strokes lock%s" % [int(st["i"]), "recovery" if recovery else "launch",
		locks.size(), (": " + str(locks)) if locks.size() > 0 else ""])
	var best := {"locks": locks.size(), "widest": 0, "stroke": "-", "hist": "{}"}
	var pick: Array = locks
	if locks.size() > MAX_LOCKS:
		pick = []
		for j in MAX_LOCKS:
			pick.append(locks[(j * locks.size()) / MAX_LOCKS])
	for j: int in pick:
		var c: Dictionary = grid[j]
		m._reset()
		DL.stand(m, x, fy, DL._ang(float(c["a0"]), recovery))
		var r: Dictionary = DL.throw(m, k, c, hn, recovery)
		if not bool(r["lock"]):
			continue
		var w := window(m, st, k)
		print("      stroke %2d tether %.2f: run %2d of %d flown  %s" % [j, float(r["tether"]),
			int(w["widest"]), int(w["flown"]), String(w["s"])])
		if int(w["widest"]) > int(best["widest"]) or String(best["stroke"]) == "-":
			best["widest"] = w["widest"]
			best["stroke"] = "%d" % j
			best["hist"] = w["s"]
	return best

## Haul, pump, snapshot the +x ticks, fly the ballistic picks.
func window(m: Node2D, st: Dictionary, k: int) -> Dictionary:
	var tg: Dictionary = st["target"]
	DL.haul(m, k)
	var prev: Vector2 = m.body_pos
	var snaps: Array = []
	for t in NPUMP:
		var cur: Vector2 = PUMP.pump_cursor(m, k, prev, T)
		prev = m.body_pos
		m.step_tick(cur, true)
		if float(m.a_freelen[k]) < 0.0:
			break
		var v: Vector2 = (m.body_pos - prev) * 60.0
		if v.x > 0.0 and t >= 10:
			var p := Vector2(m.body_pos.x, m.body_pos.y - float(tg["y"]))
			var xl := DL.ballistic_land(p, v, 0.0, m.BODY_R)
			var cand := not is_nan(xl) and xl > float(tg["x0"]) + LAND_NEAR and xl < float(tg["x0"]) + LAND_FAR
			snaps.append([t, m.snapshot(), cand])
	var fly_idx := {}
	for i in snaps.size():
		if bool(snaps[i][2]):
			for j in range(i - WIDEN, i + WIDEN + 1):
				if j >= 0 and j < snaps.size() \
						and absi(int(snaps[j][0]) - int(snaps[i][0])) <= WIDEN:
					fly_idx[j] = true
	var keys: Array = fly_idx.keys()
	keys.sort()
	var s := ""
	var last_t := -99
	var odd := ""                # where the first "a" came to rest, for the eye
	for i: int in keys:
		if int(snaps[i][0]) - last_t > 1 and s != "":
			s += " "
		last_t = int(snaps[i][0])
		m.restore(snaps[i][1])
		var c := fly(m, st)
		if c == "a" and odd == "":
			odd = " (first a: body at %.2f, %.2f%s)" % [m.body_pos.x, m.body_pos.y,
				", on the ground" if m.grounded else ", airborne"]
		s += c
	var widest := 0
	var run := 0
	for ch in s:
		if ch == "L":
			run += 1
			widest = maxi(widest, run)
		else:
			run = 0
	return {"widest": widest, "s": s + odd, "flown": keys.size()}

## Hand open, cursor parked on the body, until still or the cap; a landing on
## the target must still be one 90 ticks later.
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
	if b.x >= float(tg["x0"]) - 0.35 and b.x <= float(tg["x1"]) + 0.05 \
			and absf(fy - float(tg["y"])) < 0.30:
		return "L"
	if absf(fy - float(st["shelf_y"])) < 0.25:
		return "0" if b.x <= float(st["lip_x"]) + 0.05 else "u"
	var pit: Dictionary = st["pit"]
	if absf(fy - float(pit["y"])) < 0.3:
		return "p"
	return "a"
