extends SceneTree
## THE INSTRUMENT, REPORTING NOTHING WHERE IT MUST (climb_stand_map's controls).
##
##  N1  a beam 8 m up, 3 m ahead: out of any whip's reach. 108 grid -> 0 locks.
##  N2  the known winner at (1.5, 2.25) r 0.11 with the hand NEVER closing:
##      no catch may be reported, ever.
##  N3  the same winner with the hand OPENED the tick after the catch: the
##      oracle (held 55 ticks with the hand shut) must not call it a lock.
##  N4  the same winner, the same stroke, thrown noise-free: it DOES lock (so
##      N2/N3 are a difference of the hand alone).
##  N5  trackpad noise is live: 10 replays give more than one state hash, and
##      the null tier gives exactly one, equal to the fast path's.
##   godot --headless --path . -s res://tests/climb_stand_null.gd
const CL := preload("res://tests/climb_stand_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
func _initialize() -> void:
	var b = CL.new(3.0, 8.0, 0.11)
	var nl := 0
	var nc := 0
	for c: Dictionary in CL.grid108():
		var r: Dictionary = b.throw_fast(c)
		if bool(r["caught"]): nc += 1
		if bool(r["lock"]): nl += 1
	print("N1 beam (3.0, 8.0 up): caught %d locked %d / 108   %s" % [nc, nl, "PASS" if nl == 0 and nc == 0 else "FAIL"])
	b.free_sim()
	var w := {"a0": PI * 1.10, "a1": PI * -0.42, "sd": 5, "pull": false, "w": 120}
	b = CL.new(1.5, 2.25, 0.11)
	var r2: Dictionary = b.throw(w, HN.new("null", "n2", 0), Vector2.ZERO, 0, true)
	print("N2 never grip: caught %s lock %s   %s" % [str(r2["caught"]), str(r2["lock"]), "PASS" if not bool(r2["caught"]) else "FAIL"])
	var r3: Dictionary = b.throw(w, HN.new("null", "n3", 0), Vector2.ZERO, 0, false, true)
	print("N3 hand opened after the catch: caught %s lock %s tether %.2f   %s" % [str(r3["caught"]), str(r3["lock"]), float(r3["tether"]), "PASS" if bool(r3["caught"]) and not bool(r3["lock"]) else "FAIL"])
	var r4: Dictionary = b.throw_fast(w)
	print("N4 same stroke, hand shut: caught %s lock %s   %s" % [str(r4["caught"]), str(r4["lock"]), "PASS" if bool(r4["lock"]) else "FAIL"])
	var hs := {}
	for s in 10:
		hs[int(b.throw(w, HN.new("trackpad", "n5", s))["hash"])] = true
	var h0 := {int(r4["hash"]): true}
	for s in 3:
		h0[int(b.throw(w, HN.new("null", "n5", s))["hash"])] = true
	print("N5 trackpad 10 replays -> %d hashes (%s); null 3 + fast -> %d hash   %s" % [hs.size(), HN.new("trackpad", "x", 0).describe(), h0.size(), "PASS" if hs.size() > 1 and h0.size() == 1 else "FAIL"])
	b.free_sim()
	quit(0)
