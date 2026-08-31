extends SceneTree
## THE ONE COMMAND. Replays every tape in res://tapes/ and fails loudly if the
## game no longer does what it did when they were recorded.
##
##   godot --headless --path . -s res://tests/tape_verify.gd
##   godot --headless --path . -s res://tests/tape_verify.gd -- tapes/door.tape
##
## Prints PASS or FAIL per tape and exits 1 if any tape diverged.
##
## WHY THIS AND NOT ANOTHER PROBE. A probe needs an ORACLE - a statement of what
## the sim ought to do - and an oracle can be wrong without anyone noticing. In
## one session three separate gates here were found to be quietly lying: a drape
## test that passed a build which caught drapes on every beam radius in the
## level, a stuck-in-floor probe carrying the OLD level geometry hardcoded so it
## reported a bug 0.79 m in mid-air, and a level probe certifying the safety
## contract from a hand-laid chain state no real run ever produces. Each needed
## an oracle to catch. A replay has none to get wrong: it asks only whether the
## game still does what it did yesterday, from a start state and an input stream
## that both came from a run that actually happened.
##
## WHAT A FAILURE MEANS. A divergence is not automatically a bug - a deliberate
## change to the sim diverges every tape, and that is correct. It means: the
## behaviour changed, here is the half-second it changed in, go and say whether
## you meant it. If you did, re-record (tests/tape_rec.gd) and commit the new
## tapes in the same change as the sim edit, so the diff shows both.
##
## PLATFORM CAVEAT: a tape verifies on the SAME BUILD on the SAME PLATFORM. The
## sim is deterministic - no RNG, fixed tick, fixed substeps - but IEEE 754 does
## not oblige two architectures to agree on sin/cos/sqrt/acos, and x86 and ARM
## measurably do not. A tape recorded on one and replayed on the other will
## diverge, and that divergence says nothing about the game. Nothing here
## assumes otherwise.
const TL := preload("res://tests/tapelib.gd")
const DIR := "res://tapes"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	if args.is_empty():
		var d := DirAccess.open(DIR)
		if d == null:
			print("FAIL  no %s directory - record the corpus first:" % DIR)
			print("      godot --headless --path . -s res://tests/tape_rec.gd")
			quit(1)
			return
		for f in d.get_files():
			if f.ends_with(".tape"):
				paths.append("%s/%s" % [DIR, f])
		paths.sort()
	else:
		for a: String in args:
			if a.begins_with("res://") or a.begins_with("user://") \
					or a.is_absolute_path():
				paths.append(a)
			else:
				paths.append("res://" + a)  # a bare path means the project
	if paths.is_empty():
		print("FAIL  no tapes to verify - record the corpus first:")
		print("      godot --headless --path . -s res://tests/tape_rec.gd")
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	var fails := 0
	var ticks := 0
	for p in paths:
		var v := TL.verify(p)
		ticks += int(v["n"])
		if bool(v["ok"]):
			print("PASS  %-24s %5d ticks   %s" % [p.get_file(), int(v["n"]),
				TL.short_cen(v["cen"])])
		else:
			fails += 1
			print("FAIL  %-24s %s" % [p.get_file(), str(v["why"])])
			if int(v["at"]) >= 0:
				print("      the tape and this build agree up to tick %d " % \
					maxi(int(v["at"]) - 30, 0) + "and part company by tick %d" \
					% int(v["at"]))
				print("      (that is %.2fs-%.2fs into '%s')" % [
					maxi(int(v["at"]) - 30, 0) / 60.0, int(v["at"]) / 60.0,
					str(v["note"])])
			elif str(v["why"]).begins_with("recorded on a different level"):
				print("      the level moved, so the tape's cursor no longer " \
					+ "points at anything. Re-record; do not read this as a " \
					+ "physics change.")
	print("")
	if fails == 0:
		print("PASS  %d tapes, %d ticks replayed, %.1f s" % [paths.size(),
			ticks, (Time.get_ticks_msec() - t0) / 1000.0])
	else:
		print("FAIL  %d of %d tapes diverged. If the sim change was " % [fails,
			paths.size()] + "deliberate, re-record and commit the tapes with it:")
		print("      godot --headless --path . -s res://tests/tape_rec.gd")
	quit(1 if fails > 0 else 0)
