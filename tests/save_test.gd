extends SceneTree
## GATE: SNAPSHOT AND RESUME ARE BIT-IDENTICAL.
##
##   godot --headless --path . -s res://tests/save_test.gd
##
## The four states tested are the ones carrying the most state, and they are
## found by REPLAYING THE COMMITTED TAPES rather than by hand-laying a rig. That
## is deliberate: a probe that certifies a state no real run ever produces is
## one of the three lies this whole piece of work exists to answer, so this gate
## starts from runs that actually happened.
##
##   air      airborne with nothing engaged - pure ballistics, mid-fall
##   wrap     a wrap engaged and bearing the body
##   betray   a partial wrap paying material through the pin, right now
##   coil     more than a full turn of measured wrap on a beam
##
## At the first tick N where each occurs with 300 ticks of tape left:
##
##   A  uninterrupted: the tape from 0 to N+300                  -> H0
##   B  to N, a snapshot taken there, then on to N+300           -> H1
##   C  that snapshot restored into B, the same 300 ticks again  -> H2
##   D  the snapshot written to a FILE and loaded into a sim     -> H3
##      that never played those ticks, the same 300 ticks
##
## H0 == H1 == H2 == H3, or FAIL. B proves that taking a snapshot perturbs
## nothing. C proves the restore is exact. D is the one the game rests on: it is
## quitting and coming back, and it is why quitting mid-fall resumes the fall.
##
## PLATFORM CAVEAT: same build, same platform. There is no cross-architecture
## float guarantee and nothing here assumes one.
const TL := preload("res://tests/tapelib.gd")
const MAIN := preload("res://main.gd")
const SPAN := 300
const TMP := "user://save_test.save"

var failures: Array[String] = []
var tapes := {}

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_run()
	if failures.is_empty():
		print("PASS  (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	else:
		for f in failures:
			print("FAIL  " + f)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	var d := DirAccess.open("res://tapes")
	if d == null:
		failures.append("no res://tapes - record the corpus first: " \
			+ "godot --headless --path . -s res://tests/tape_rec.gd")
		return
	var found := {}
	for f in d.get_files():
		if not f.ends_with(".tape"):
			continue
		var t: Dictionary = MAIN.tape_load("res://tapes/" + f)
		if not bool(t.get("ok", false)):
			continue
		tapes[f] = t
		for e in _scan(t):
			# keep the cheapest example of each state
			if not found.has(e[0]) or int(e[1]) < int(found[e[0]][1]):
				found[e[0]] = [f, int(e[1])]
	for cond in ["air", "wrap", "betray", "coil"]:
		if not found.has(cond):
			# A GATE THAT NEVER REACHES ITS STATE IS A GATE THAT PASSES ON
			# NOTHING. Say so instead of reporting a pass.
			failures.append("no tape reaches '%s' - this gate would be vacuous" \
				% cond)
			continue
		var f: String = found[cond][0]
		var n: int = int(found[cond][1])
		_check(cond, f, n)

func _feed(m: Node2D, t: Dictionary, a: int, b: int) -> void:
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	for i in range(a, b):
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)

func _state(m: Node2D) -> String:
	# which of the four interesting states is the sim in RIGHT NOW
	var eng := false
	var betray := false
	var coil := false
	for k in m.a_pos.size():
		if float(m.a_freelen[k]) < 0.0:
			continue
		eng = true
		if int(m.a_locked[k]) == 0 and bool(m.slipping):
			betray = true
		# COILED, by the build's own definition of a full turn rather than an
		# invented threshold: measured winding at or past the lock bar, with the
		# material point pinned. That is the fattest state in the file - a pin
		# index, a pinned point, a wrap window, a tether and a classification,
		# all of which have to come back exactly or the resume is a lie.
		if absf(float(m.a_theta[k])) >= float(m.th_full):
			coil = true
	if betray:
		return "betray"
	if coil:
		return "coil"
	if eng:
		return "wrap"
	if not bool(m.grounded):
		return "air"
	return ""

func _scan(t: Dictionary) -> Array:
	# first tick of each state that still has SPAN ticks of tape after it
	var m := TL.new_sim()
	m.restore(t["start"])
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var out := []
	var seen := {}
	var last := cur.size() - SPAN
	for i in cur.size():
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)
		if i >= 30 and i < last:
			var s := _state(m)
			if s != "" and not seen.has(s):
				seen[s] = true
				out.append([s, i + 1])
	m.free()
	return out

func _check(cond: String, fname: String, n: int) -> void:
	var t: Dictionary = tapes[fname]
	# A - uninterrupted
	var a := TL.new_sim()
	a.restore(t["start"])
	_feed(a, t, 0, n + SPAN)
	var h0: int = a.state_hash()
	a.free()
	# B - snapshot at n, then carry on
	var b := TL.new_sim()
	b.restore(t["start"])
	_feed(b, t, 0, n)
	var got := _state(b)
	var snap: Dictionary = b.snapshot()
	var wrote: bool = b.save_to(TMP)
	_feed(b, t, n, n + SPAN)
	var h1: int = b.state_hash()
	# C - restore into the same sim and do it again
	var okc: bool = b.restore(snap)
	_feed(b, t, n, n + SPAN)
	var h2: int = b.state_hash()
	b.free()
	# D - a sim that never played those ticks, loading the FILE
	var dd := TL.new_sim()
	var okd: int = dd.load_from(TMP)
	_feed(dd, t, n, n + SPAN)
	var h3: int = dd.state_hash()
	dd.free()

	var tag := "%s (%s tick %d, +%d)" % [cond, fname, n, SPAN]
	if got != cond:
		failures.append("%s: the snapshot was not taken in that state (%s)"
			% [tag, got if got != "" else "grounded, free"])
		return
	if not wrote:
		failures.append("%s: could not write %s" % [tag, TMP])
		return
	if not okc:
		failures.append("%s: restore() refused its own snapshot" % tag)
		return
	if okd != 1:
		failures.append("%s: load_from() refused its own file (%d)" % [tag, okd])
		return
	if h1 != h0:
		failures.append("%s: taking a snapshot perturbed the run (%d != %d)"
			% [tag, h1, h0])
	if h2 != h0:
		failures.append("%s: resumed from memory diverged (%d != %d)"
			% [tag, h2, h0])
	if h3 != h0:
		failures.append("%s: resumed from disk diverged (%d != %d)"
			% [tag, h3, h0])
	if h0 == h1 and h1 == h2 and h2 == h3:
		print("  %-38s hash %d" % [tag, h0])
