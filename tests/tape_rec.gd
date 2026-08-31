extends SceneTree
## RECORDS THE TAPE CORPUS into res://tapes/.
##
##   godot --headless --path . -s res://tests/tape_rec.gd
##   godot --headless --path . -s res://tests/tape_rec.gd -- school betray
##
## Recording is slow (minutes) because the throws are SEARCHED, not hardcoded -
## see tests/tapelib.gd. Verifying is seconds. That asymmetry is the point: you
## record when the level or the corpus changes, and you verify on every edit.
##
## TWO RULES THIS FILE KEEPS, and they are the whole reason it exists rather
## than a hand-written fixture:
##
##  1. NO TAPE IS WRITTEN THAT DOES NOT VERIFY. The moment a tape is recorded it
##     is replayed in a fresh sim and must reproduce its own hash, its own
##     checkpoints and its own census. A tape that cannot verify at birth is
##     not a regression test, it is a second thing to debug.
##  2. NO TAPE IS WRITTEN THAT IS VACUOUS. Every tape declares what it is
##     supposed to contain - a catch, a lock, a wrap that pays out, a dismount,
##     a fall of so many metres, so many metres of crawl - and the recorder
##     refuses to keep one whose measured census does not meet it. A gate that
##     passes on nothing is exactly the failure this corpus exists to answer:
##     three of them were found in a single session, and every one needed an
##     oracle to catch. A tape needs none - but a tape OF nothing tests nothing,
##     and only this check stands between the two.
##
## PLATFORM CAVEAT: a tape verifies on the SAME BUILD on the SAME PLATFORM.
## There is no cross-architecture float guarantee (x86 vs ARM) and nothing here
## pretends there is.
const TL := preload("res://tests/tapelib.gd")
const DIR := "res://tapes"

var made: Array[String] = []
var bad: Array[String] = []

func _initialize() -> void:
	var want := Array(OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var t0 := Time.get_ticks_msec()
	for name in ["hashrun", "crawl", "reset", "school", "betray", "door"]:
		if want.is_empty() or want.has(name):
			_one(name)
	print("")
	print("recorded %d tape(s) in %.0f s%s" % [made.size(),
		(Time.get_ticks_msec() - t0) / 1000.0,
		"" if bad.is_empty() else "   REFUSED: " + ", ".join(bad)])
	quit(1 if not bad.is_empty() else 0)

func _one(name: String) -> void:
	var t0 := Time.get_ticks_msec()
	var m := TL.new_sim()
	var spec: Dictionary = call("_tape_" + name, m)
	m.rec_end()
	var path := "%s/%s.tape" % [DIR, name]
	var cen: Dictionary = m.rec_cen.duplicate()
	var n: int = m.rec_cur.size()
	# 2. is it vacuous?
	var miss: Array[String] = []
	for k: String in (spec["need"] as Dictionary):
		var got: float = float(cen.get(k, 0))
		var lo: float = float(spec["need"][k])
		if got < lo:
			miss.append("%s %.2f < %.2f" % [k, got, lo])
	if spec.has("hash") and m.state_hash() != int(spec["hash"]):
		miss.append("final hash %d != the %d this tape exists to pin"
			% [m.state_hash(), int(spec["hash"])])
	if not miss.is_empty():
		print("%-8s REFUSED - the run did not contain what the tape claims: %s"
			% [name, ", ".join(miss)])
		print("         census: %s" % TL.census_line(cen))
		bad.append(name)
		m.free()
		return
	if not m.tape_save(path):
		print("%-8s REFUSED - could not write %s" % [name, path])
		bad.append(name)
		m.free()
		return
	m.free()
	# 1. does it verify, right now, in a sim that never played it?
	var v := TL.verify(path)
	if not bool(v["ok"]):
		print("%-8s REFUSED - it does not replay: %s" % [name, str(v["why"])])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		bad.append(name)
		return
	print("%-8s %5d ticks  %6.1f KB  %5.0f s   %s" % [name, n,
		FileAccess.open(path, FileAccess.READ).get_length() / 1024.0,
		(Time.get_ticks_msec() - t0) / 1000.0, TL.short_cen(cen)])
	print("         %s" % str(spec["note"]))
	made.append(name)

# ------------------------------------------------------------- the corpus --
# Each _tape_* drives a sim from its spawn state and returns what the tape is
# for and what it must be shown to contain. Recording starts before the first
# tick, so a tape's start state IS the reset state - nothing is hand-laid.

func _tape_hashrun(m: Node2D) -> Dictionary:
	# The 900-tick determinism session from tests/hashrun.gd, verbatim. Its
	# final state hash is this project's golden number, so this tape ties the
	# whole tape mechanism to a constant that predates it: if the tape passes
	# and hashrun.gd prints something else, the tape system is what is broken.
	m.rec_begin("hashrun: settle, flails, wind-up, crack, taut swings (900)")
	for t in 900:
		var cg := TL.hashrun_inp(m, t)
		m.step_tick(cg[0], cg[1])
	# It wraps nothing and catches nothing - it is a wave-and-crack session, and
	# the other tapes carry the wrap verbs. What it pins is the number.
	return {"note": "the golden session - its final hash is the project's own",
		"need": {"crack": 1}, "hash": 2762505307938286422}

func _tape_crawl(m: Node2D) -> Dictionary:
	# The lash gait on flat ground, the only locomotion that is not the whip.
	m.rec_begin("crawl: the lash gait on the home tier (660)")
	TL.run(m, [{"kind": "still", "n": 60}, {"kind": "gait", "n": 600}])
	return {"note": "the gait: ~0.4 m/s of flat ground and no beam involved",
		"need": {"crawl": 1.0}}

func _tape_reset(m: Node2D) -> Dictionary:
	# R IS AN INPUT, and it is the only one that is not (cursor, grip). It is
	# carried in bit 1 of the grip byte and applied at the top of the tick, so
	# this tape is the only thing that exercises that channel: without it a
	# recorded session containing an R press would replay as a session that
	# never restarted, and nothing would say so.
	m.rec_begin("reset: crawl, R, crawl again from the spawn")
	TL.run(m, [{"kind": "still", "n": 30}, {"kind": "gait", "n": 240}])
	m.pending_reset = true                     # R, consumed by the next tick
	TL.run(m, [{"kind": "gait", "n": 240}, {"kind": "still", "n": 30}])
	return {"note": "the restart verb, in the input stream where it belongs",
		"need": {"reset": 1, "crawl": 0.5}}

func _tape_school(m: Node2D) -> Dictionary:
	# The opening beam. Lead ladder, throw, catch, lock, hang, pump, let go.
	m.rec_begin("school: throw A0, lock, hang, pump, dismount")
	TL.run(m, [{"kind": "still", "n": 60}])
	var plan := TL.plan_capture(m, 0, "lock")
	if plan.is_empty():
		return {"note": "no throw found", "need": {"lock": 1}}
	TL.do_capture(m, 0, plan)
	TL.run(m, [
		{"kind": "hold", "k": 0, "n": 60, "until": "free", "after": 5},
		{"kind": "pump", "k": 0, "n": 180, "until": "free", "after": 5},
		{"kind": "slack", "n": 120, "ang": PI * 1.10},
		{"kind": "still", "n": 60},
	])
	return {"note": "catch and lock a 2.2 m beam from a standstill, then leave it",
		"need": {"catch": 1, "lock": 1, "dismount": 1, "wrapped": 200}}

func _tape_betray(m: Node2D) -> Dictionary:
	# The briefed "it catches, then betrays": a wrap that is not a self-pinch
	# takes your weight, ratchets material through the pin one segment at a
	# time, and slides off its own tail.
	m.rec_begin("betray: a partial wrap catches, pays out, slides off")
	TL.run(m, [{"kind": "still", "n": 60}])
	var plan := TL.plan_capture(m, 0, "pay")
	if plan.is_empty():
		return {"note": "no throw found", "need": {"pay": 1}}
	TL.do_capture(m, 0, plan)
	TL.run(m, [
		{"kind": "hold", "k": 0, "n": 400, "until": "free", "after": 10},
		# and the tail: dropped, back on the floor, crawling on. It is not
		# padding - tests/save_test.gd snapshots this tape mid-payout and needs
		# 300 ticks of run left after that instant to compare against.
		{"kind": "still", "n": 90},
		{"kind": "gait", "n": 300},
	])
	return {"note": "a wrap that takes you and then gives you back",
		"need": {"catch": 1, "pay": 1, "slide": 1}}

func _tape_door(m: Node2D) -> Dictionary:
	# A WHOLE LEG OF THE REAL LEVEL, and the most valuable tape here. Crawl the
	# home tier 23 m to the first lip, throw at the door beam hung 1.4 m past
	# it, get hauled off the edge by the catch, hang over a 5.2 m drop, pump,
	# let go, and fall onto tier 1. Every verb in the game in one run.
	m.rec_begin("door: crawl 23 m, catch A3 over the lip, hang, pump, fall to tier 1")
	TL.run(m, [{"kind": "still", "n": 60}])
	TL.walk_to(m, 18.5)
	var plan := TL.plan_capture(m, 3, "lock")
	if plan.is_empty():
		return {"note": "no throw found", "need": {"lock": 1}}
	TL.do_capture(m, 3, plan)
	TL.run(m, [
		{"kind": "hold", "k": 3, "n": 90, "until": "free", "after": 5},
		{"kind": "pump", "k": 3, "n": 120, "until": "free", "after": 5},
		{"kind": "slack", "n": 240, "ang": -PI * 0.30, "until": "ground",
			"after": 20},
		{"kind": "still", "n": 60},
	])
	return {"note": "the traverse's own step: crawl, catch over a lip, hang, drop",
		"need": {"catch": 1, "lock": 1, "dismount": 1, "crawl": 4.0,
			"maxdrop": 2.0, "airrun": 40}}
