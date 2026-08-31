extends SceneTree
## WAS THE HAND OPENED, OR DID IT SLIP? On a trackpad a physical click is easy
## to lose without noticing, and main.gd:1584 drops the wrap on ONE false tick
## with no debounce. This reads the recorded grip byte - the exact bit the sim
## consumed - and asks how the player's releases are distributed.
##
##   godot --headless --path . -s res://tests/grip_census.gd -- takes/bug1.tape
##
## A DELIBERATE release is followed by a long open hand: you let go to fly. A
## SLIP is a brief gap in the middle of a hold, with the hand closing again
## right after. The shape of the histogram tells them apart without an oracle.
const TL := preload("res://tests/tapelib.gd")

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var path: String = args[0] if args.size() > 0 else "takes/bug1.tape"
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var t: Dictionary = load("res://main.gd").tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load: %s" % t.get("err", "")); quit(1); return
	var grp: PackedByteArray = t["grip"]
	# open-hand episode lengths, but only those BETWEEN two closed episodes
	var gaps: Array[int] = []
	var holds: Array[int] = []
	var i := 0
	var n := grp.size()
	var seen_closed := false
	while i < n:
		var closed := (grp[i] & 1) != 0
		var j := i
		while j < n and (((grp[j] & 1) != 0) == closed):
			j += 1
		var run := j - i
		if closed:
			holds.append(run)
			seen_closed = true
		elif seen_closed and j < n:
			gaps.append(run)      # a gap with a hold on both sides
		i = j
	gaps.sort()
	holds.sort()
	var buckets := [1, 2, 3, 5, 8, 12, 20, 40, 100, 1000000]
	var names := ["1 tick (17 ms)", "2", "3", "4-5", "6-8", "9-12", "13-20",
		"21-40", "41-100", "over 100"]
	var counts := []
	counts.resize(buckets.size())
	counts.fill(0)
	for g in gaps:
		for b in buckets.size():
			if g <= int(buckets[b]):
				counts[b] = int(counts[b]) + 1
				break
	print("")
	print("TAPE %s   %d ticks" % [path, n])
	print("  hand-closed episodes   %d" % holds.size())
	print("  hand-open GAPS between two holds   %d" % gaps.size())
	print("")
	print("  HOW LONG THE HAND STAYED OPEN, when it re-closed after:")
	var short := 0
	for b in buckets.size():
		if int(counts[b]) == 0:
			continue
		print("    %-16s %4d" % [names[b], int(counts[b])])
	for g in gaps:
		if g <= 8:
			short += 1
	print("")
	print("  gaps of 8 ticks (133 ms) or less: %d of %d  (%.0f%%)"
		% [short, gaps.size(), 100.0 * float(short) / maxf(float(gaps.size()), 1.0)])
	print("  A DELIBERATE release is followed by a long open hand - you let go to")
	print("  fly. A gap this short, with the hand closing again straight after, is")
	print("  the shape of a grip that was lost rather than given up. Each one of")
	print("  them, if a wrap was live, ended that wrap outright.")
	if gaps.size() > 0:
		print("")
		print("  shortest gap %d ticks   median %d   longest %d"
			% [gaps[0], gaps[gaps.size() / 2], gaps[gaps.size() - 1]])
	quit(0)
