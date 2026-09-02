extends SceneTree
## THE RECORDER, ROUND-TRIPPED. Proves the live tape recorder and its bug
## marker are honest, in the only currency this project accepts: a hash.
##
##   godot --headless --path . -s res://tests/mark_rt.gd
##
## A recorder is the easiest instrument in the project to fool yourself with.
## It sits beside the tick and writes down what it thinks the tick was given,
## and if it writes down the CLAMPED handle target instead of the cursor, or
## the grip a frame late, or the value AFTER _update_locks has moved on, it
## still produces a plausible-looking file full of plausible-looking numbers
## and nothing anywhere says so. So none of the gates below asks the recorder
## what it recorded. They feed a KNOWN input stream in and require the bytes
## that come out to be that stream, and the state it produced to be the state
## the sim reached.
##
## R1  THE LIVE PATH, with the real F key. main.gd's own _physics_process,
##     its own cursor_now() off a real viewport, its own Input.is_key_pressed
##     for the grip, and its own _input handler taking a real InputEventKey
##     for KEY_F. Then the tape it wrote is replayed and must land on the same
##     hash. Every probe in tests/ drives step_tick directly, so not one of
##     them would notice if the line that reads the mouse had stopped working
##     - or if F had stopped reaching _input.
## R2  BYTE FIDELITY over the whole committed corpus. Replay each tape's input
##     through a recording sim and require the tape that comes out to carry
##     the SAME 8 cursor bytes and the SAME grip byte on every tick, the same
##     checkpoint hashes, the same final hash and the same census - while
##     marks are being pressed throughout. This is the strongest form of
##     "recording does not perturb the simulation" available: not a hash that
##     happens to agree, an identical input stream.
## R3  THE NEGATIVE CONTROL. R2 is worthless unless it can fail, so one cursor
##     sample in the middle of a corpus tape is moved by one micrometre and
##     the same comparison is run again. It must fail, and it must name a
##     checkpoint. A gate that passes on nothing is the failure this whole
##     corpus exists to answer, and that includes this one.
## R4  MARK NEUTRALITY AND MARK SURVIVAL. The marks pressed in R2 must come
##     back off disk on exactly the ticks they were pressed on, and the tape
##     that carries them must be byte-identical to one recorded without them.
## R5  BACKWARD COMPATIBILITY. The six tapes on disk were written before the
##     marker existed. They must still load, and read as zero marks - which is
##     a fact about those tapes, not a fault in them.
## R6  THE KEYS ARE FREE, read out of the source rather than remembered: KEY_F
##     and KEY_G must appear only inside the marker branch of _input, and the
##     project must define no input actions that could shadow them.
const MAIN := preload("res://main.gd")
const TL := preload("res://tests/tapelib.gd")
const DIR := "res://tapes"
const OUT := "user://mark_rt_live.tape"
const SCRATCH_SAVE := "user://mark_rt_scratch.save"

# How much live driving, and WHEN F is pressed - both counted in TICKS, not in
# frames. Headless runs the frame loop as fast as the machine allows and the
# physics loop off real time, so the ticks-per-frame ratio is whatever the box
# was doing at the time (measured on this one: 0.45 to 6.0 across two runs of
# this very file). A windowed 60 Hz session is 1:1. Anchoring the presses to
# recorded ticks makes the gate say the same thing on both.
const LIVE_TICKS := 420
const PRESS_TICK := [120, 240, 360]
const FRAME_CAP := 6000

var m: Node2D
var f := 0
var fails := 0
var pressed := 0
var live_press: Array = []            # [frame, tick_count, rec_cur.size()]
var live_hash := 0
var live_ticks := 0

func _ok(name: String, cond: bool, detail := "") -> void:
	if not cond:
		fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", name,
		("   " + detail) if detail != "" else ""])

# =========================================================== R1, the live path
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		print("")
		print("=== R1  THE LIVE PATH: _physics_process, cursor_now(), real F ===")
		root.size = Vector2i(1600, 900)   # headless default is 64x36; the
		                                  # cursor law divides the stretch out,
		                                  # so a real-sized window is the
		                                  # honest one to drive
		m = MAIN.new()
		# setup_sim() FIRST: it re-derives save_path from level_id (main.gd,
		# "THE LEVEL OWNS ITS SLOT"), so a redirect made before it is silently
		# undone. Then the redirect; then add_child, whose _ready skips
		# setup_sim (pos is built) and runs _boot_session against the scratch
		# path; then save_enabled is cleared the instant _ready has run, because
		# _boot_session turns saving on for an ordinary session and no test may
		# ever be the thing that writes the player's one slot.
		m.setup_sim()
		m.save_path = SCRATCH_SAVE
		root.add_child(m)
		m.save_enabled = false
		m.rec_begin("mark_rt live path")
		print("  external_drive %s   save_enabled %s   rec_on %s   headless %s"
			% [str(m.external_drive), str(m.save_enabled), str(m.rec_on),
			str(DisplayServer.get_name() == "headless")])
		return false
	if f < FRAME_CAP and (int(m.rec_cur.size()) < LIVE_TICKS
			or pressed < PRESS_TICK.size()):
		_drive(f)
		return false
	if true:
		_finish_live()
		_r7()
		_r2_r3_r4()
		_r5()
		_r6()
		print("")
		print("%s  mark_rt: %d gate(s) failed" % ["PASS" if fails == 0
			else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	return false

func _drive(i: int) -> void:
	# A MOVING MOUSE AND A TOGGLING GRIP, through the OS input path. Events
	# parsed here are flushed at the top of the next iteration, which is where
	# a real mouse's events arrive too.
	var t := int(m.rec_cur.size())
	var ph := float(t) * 0.035
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(800.0, 450.0) + Vector2(cos(ph), sin(ph)) * 260.0
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	var want := (t % 90) > 45
	if want != Input.is_key_pressed(KEY_SPACE):
		var ks := InputEventKey.new()
		ks.keycode = KEY_SPACE
		ks.physical_keycode = KEY_SPACE
		ks.pressed = want
		Input.parse_input_event(ks)
	if pressed < PRESS_TICK.size() \
			and int(m.rec_cur.size()) >= int(PRESS_TICK[pressed]):
		# the real key, through main.gd's real _input
		pressed += 1
		live_press.append([i, int(m.tick_count), int(m.rec_cur.size())])
		var kf := InputEventKey.new()
		kf.keycode = KEY_F
		kf.physical_keycode = KEY_F
		kf.pressed = true
		Input.parse_input_event(kf)
		var ku := InputEventKey.new()
		ku.keycode = KEY_F
		ku.physical_keycode = KEY_F
		ku.pressed = false
		Input.parse_input_event(ku)

func _finish_live() -> void:
	live_ticks = int(m.rec_cur.size())
	live_hash = int(m.state_hash())
	var marks: PackedInt32Array = m.rec_mark.duplicate()
	var wrote := bool(m.tape_save(OUT))
	m.rec_end()
	_ok("the live path ticked", live_ticks >= LIVE_TICKS,
		"%d ticks over %d frames (%.2f ticks/frame)"
		% [live_ticks, f, float(live_ticks) / maxf(float(f), 1.0)])
	_ok("the cursor MOVED (a constant would prove nothing)",
		_spread(m.rec_cur) > 0.5, "cursor spread %.3f m" % _spread(m.rec_cur))
	_ok("the grip was worked", _grip_edges(m.rec_grip) >= 2,
		"%d grip edges" % _grip_edges(m.rec_grip))
	_ok("the real F key reached _input and landed a mark",
		marks.size() == PRESS_TICK.size(),
		"%d presses -> marks %s" % [PRESS_TICK.size(), str(marks)])
	# THE MARK MUST NOT PRECEDE THE PRESS. It is allowed to trail it - _input
	# runs on the frame and _rec_tick spends the latch on the next tick it
	# records - but a mark stamped on a tick the player had not yet seen would
	# be pointing at the wrong moment, and pointing EARLIER is the direction
	# that would matter, since the whole report is "and THEN it unhooked".
	var lat_ok := marks.size() == live_press.size()
	var lat: Array[int] = []
	for j in mini(marks.size(), live_press.size()):
		var dl := int(marks[j]) - int(live_press[j][2])
		lat.append(dl)
		if dl < 0:
			lat_ok = false
	_ok("no mark lands before the tick it was pressed on", lat_ok,
		"latency in ticks: %s" % str(lat))
	print("       (a press and the next recorded tick; at 60 Hz windowed that")
	print("        is one tick, well inside mark_look's +/-90 window)")
	_ok("the tape was written", wrote, OUT)
	m.free()
	m = null
	var v := TL.verify(OUT)
	_ok("the live tape replays to the same hash", bool(v["ok"]) and
		int(v["h2"]) == live_hash,
		"replay %s  h %d vs live %d" % [str(v["why"]) if not bool(v["ok"])
		else "ok", int(v["h2"]), live_hash])
	var t: Dictionary = MAIN.tape_load(OUT)
	_ok("the marks survived the file", _same_i32(t["mark"], marks),
		"%s == %s" % [str(t["mark"]), str(marks)])

static func _spread(c: PackedVector2Array) -> float:
	if c.size() == 0:
		return 0.0
	var lo := c[0]
	var hi := c[0]
	for p in c:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return (hi - lo).length()

static func _grip_edges(g: PackedByteArray) -> int:
	var n := 0
	for i in range(1, g.size()):
		if (g[i] & 1) != (g[i - 1] & 1):
			n += 1
	return n

static func _same_i32(a: Variant, b: Variant) -> bool:
	var x: PackedInt32Array = a
	var y: PackedInt32Array = b
	if x.size() != y.size():
		return false
	for i in x.size():
		if x[i] != y[i]:
			return false
	return true

# ============================== R7, the exit path that actually writes the tape
const R7_SAVE := "user://mark_rt_r7_scratch.save"
const R7_TAPE := "user://mark_rt_r7.tape"

func _r7() -> void:
	# THE WAY THE PLAYER'S TAPE ACTUALLY REACHES DISK. main.gd writes it from
	# _notification, on the window closing, on Esc, and on the crash handler -
	# and it writes it BEHIND the save_enabled gate, so a recording session is
	# necessarily a real saving session. R1 called tape_save by hand and so
	# would not have noticed if that path had rotted. This one tears the node
	# out of the tree and reads the file that falls out.
	print("")
	print("=== R7  THE EXIT PATH: _notification writes the tape, with marks ===")
	# The save this exercises is a scratch file with its own name, and the
	# assert is here rather than in a comment: this test may never be the thing
	# that writes the one slot.
	if R7_SAVE == MAIN.SAVE_PATH:
		_ok("scratch save path is not the player's slot", false, R7_SAVE)
		return
	for f2 in [R7_SAVE, R7_SAVE + ".tmp", R7_TAPE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f2))
	var m2: Node2D = MAIN.new()
	m2.setup_sim()                     # FIRST: setup_sim() re-derives save_path
	m2.save_path = R7_SAVE             # from level_id (main.gd, "THE LEVEL OWNS
	                                   # ITS SLOT"), so a redirect made before it
	                                   # is silently undone - which is how this
	                                   # test wrote the player's run.save once
	_ok("the scratch path survived setup_sim and is not the player's slot",
		m2.save_path == R7_SAVE and m2.save_path != MAIN.SAVE_PATH,
		m2.save_path)
	if m2.save_path != R7_SAVE:
		m2.free()
		return
	root.add_child(m2)                 # _ready -> _boot_session (setup_sim is
	                                   # skipped: pos is already built)
	_ok("and _ready left it alone", m2.save_path == R7_SAVE, m2.save_path)
	if m2.save_path != R7_SAVE:
		m2.save_enabled = false        # never the thing that writes the slot
		root.remove_child(m2)
		m2.free()
		return
	m2.external_drive = true           # ...and this test drives the ticks
	_ok("_boot_session turned saving on (the tape write sits behind it)",
		bool(m2.save_enabled), "save_path %s" % str(m2.save_path))
	m2.rec_path = R7_TAPE
	m2.rec_begin("r7 exit path")
	for i in 40:
		m2.step_tick(m2.body_pos, false)
	m2.rec_mk = true
	for i in 11:
		m2.step_tick(m2.body_pos, false)
	var want := int(m2.rec_cur.size())
	var h := int(m2.state_hash())
	root.remove_child(m2)              # NOTIFICATION_EXIT_TREE fires here
	m2.free()
	var t: Dictionary = MAIN.tape_load(R7_TAPE)
	_ok("the tape exists and loads", bool(t.get("ok", false)),
		str(t.get("err", "")))
	if not bool(t.get("ok", false)):
		return
	_ok("it has every tick", int(t["n"]) == want,
		"%d of %d" % [int(t.get("n", 0)), want])
	_ok("it carries the mark", _same_i32(t["mark"], PackedInt32Array([40])),
		str(t["mark"]))
	_ok("and it replays to the hash the session ended on",
		int(TL.verify(R7_TAPE)["h2"]) == h, str(h))
	for f2 in [R7_SAVE, R7_SAVE + ".tmp", R7_TAPE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f2))

# ================================= R2/R3/R4, byte fidelity over the whole corpus
func _r2_r3_r4() -> void:
	print("")
	print("=== R2  BYTE FIDELITY: re-record the corpus while pressing F ===")
	for p in _tapes():
		var t: Dictionary = MAIN.tape_load(p)
		if not bool(t.get("ok", false)):
			_ok(p.get_file(), false, str(t.get("err", "unreadable")))
			continue
		var n := int(t["n"])
		var want: Array[int] = []
		for q in [0, n / 3, n / 2, n - 1]:
			if q >= 0 and q < n and not want.has(q):
				want.append(q)
		var a := _rerecord(t, want)
		var b := _rerecord(t, [])          # the same session, no marks pressed
		var why := _cmp(t, a)
		_ok("%-14s %5d ticks" % [p.get_file(), n], why == "",
			why if why != "" else "cursor+grip+chk+hash+census identical")
		if _cmp_ab(a, b) != "":
			_ok("%-14s marks are inert" % p.get_file(), false, _cmp_ab(a, b))
		if not _same_i32(a["mark"], PackedInt32Array(want)):
			_ok("%-14s marks land where pressed" % p.get_file(), false,
				"%s != %s" % [str(a["mark"]), str(want)])
	print("")
	print("=== R4  MARK NEUTRALITY AND SURVIVAL (folded into R2 above) ===")
	print("  every tape above was recorded twice, once with marks pressed on")
	print("  ticks [0, n/3, n/2, n-1] and once with none, and the two streams")
	print("  were required to be byte-identical to each other and to the tape")
	print("  they came from. A mark that reached the sim would show here.")
	print("")
	print("=== R3  THE NEGATIVE CONTROL: can R2 fail at all, and how small? ===")
	# R2 comparing byte for byte is only worth having if the REPLAY half of the
	# round trip can fail, so here is the same comparison run against streams
	# that are deliberately wrong. It is a SWEEP rather than one guess on
	# purpose: the cursor is clamped to the reach rim before it reaches the
	# handle spring (target_m = body + (cursor-body).limit_length(REACH)), so a
	# nudge along the radius is normalised straight back out and a single
	# arbitrary epsilon proves nothing either way. What the sweep reports is the
	# instrument's actual sensitivity, in metres.
	var sc: String = "%s/school.tape" % DIR
	var ts: Dictionary = MAIN.tape_load(sc)
	var n := int(ts["n"])
	var ok0 := _replay_cmp(ts, ts["cur"], ts["grip"])
	_ok("the unperturbed stream passes", bool(ok0["ok"]), str(ok0["why"]))
	var smallest := 1e9
	for at in [n / 3, n / 2]:
		for e in [[1e-6, "1 um"], [1e-5, "10 um"], [1e-4, "0.1 mm"],
				[1e-3, "1 mm"]]:
			var eps := float(e[0])
			var cur: PackedVector2Array = \
				(ts["cur"] as PackedVector2Array).duplicate()
			cur[at] = cur[at] + Vector2(0.0, eps)
			var d := _replay_cmp(ts, cur, ts["grip"])
			print("       cursor +%-7s on tick %4d : %s" % [str(e[1]), at,
				("CAUGHT at tick %d" % int(d["at"])) if not bool(d["ok"])
				else "absorbed - the reach clamp normalised it away"])
			if not bool(d["ok"]):
				smallest = minf(smallest, eps)
	_ok("a sub-millimetre cursor error is caught", smallest <= 1e-3,
		"smallest caught perturbation %.6f m" % smallest)
	var gf: PackedByteArray = (ts["grip"] as PackedByteArray).duplicate()
	var gat := n / 2
	gf[gat] = gf[gat] ^ 1
	var dg := _replay_cmp(ts, ts["cur"], gf)
	_ok("one flipped grip bit on tick %d is caught" % gat, not bool(dg["ok"]),
		"caught at tick %d" % int(dg["at"]))
	var cs: PackedVector2Array = (ts["cur"] as PackedVector2Array).duplicate()
	for i in range(1, cs.size()):
		cs[i - 1] = cs[i]              # the whole stream one tick early
	var dh := _replay_cmp(ts, cs, ts["grip"])
	_ok("the stream sampled ONE TICK OFF is caught", not bool(dh["ok"]),
		"caught at tick %d" % int(dh["at"]))

func _tapes() -> Array[String]:
	var out: Array[String] = []
	var dd := DirAccess.open(DIR)
	if dd == null:
		return out
	for fn in dd.get_files():
		if fn.ends_with(".tape"):
			out.append("%s/%s" % [DIR, fn])
	out.sort()
	return out

func _rerecord(t: Dictionary, mark_at: Array) -> Dictionary:
	# Feed a tape's own input back through a RECORDING sim. What comes out must
	# be the stream that went in - and the marks must not be in it.
	var s := TL.new_sim()
	s.restore(t["start"])
	s.rec_begin("re-record")
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	for i in cur.size():
		if mark_at.has(i):
			s.rec_mk = s.MARK_GREEN    # exactly what _input's KEY_F branch does
		s.pending_reset = (grp[i] & 2) != 0
		s.step_tick(cur[i], (grp[i] & 1) != 0)
	var out := {"cur": s.rec_cur.duplicate(), "grip": s.rec_grip.duplicate(),
		"chk": s.rec_chk.duplicate(), "h": int(s.state_hash()),
		"cen": s.rec_cen.duplicate(), "mark": s.rec_mark.duplicate()}
	s.rec_end()
	s.free()
	return out

func _cmp(t: Dictionary, a: Dictionary) -> String:
	var bad: Array[String] = []
	var c0: PackedVector2Array = t["cur"]
	var c1: PackedVector2Array = a["cur"]
	if c0.size() != c1.size():
		bad.append("cursor length %d != %d" % [c0.size(), c1.size()])
	else:
		for i in c0.size():
			# BIT comparison, not a tolerance: the recorder either wrote the
			# float it was handed or it wrote a different one.
			if c0[i].x != c1[i].x or c0[i].y != c1[i].y:
				bad.append("cursor differs at tick %d: %s vs %s"
					% [i, str(c0[i]), str(c1[i])])
				break
	var g0: PackedByteArray = t["grip"]
	var g1: PackedByteArray = a["grip"]
	if g0.size() != g1.size():
		bad.append("grip length %d != %d" % [g0.size(), g1.size()])
	else:
		for i in g0.size():
			if g0[i] != g1[i]:
				bad.append("grip byte differs at tick %d: %d vs %d"
					% [i, g0[i], g1[i]])
				break
	var k0: PackedInt64Array = t["chk"]
	var k1: PackedInt64Array = a["chk"]
	if k0.size() != k1.size():
		bad.append("checkpoints %d != %d" % [k0.size(), k1.size()])
	else:
		for i in k0.size():
			if k0[i] != k1[i]:
				bad.append("checkpoint %d (tick %d) differs"
					% [i, (i + 1) * 30])
				break
	if int(t["h"]) != int(a["h"]):
		bad.append("final hash %d != %d" % [int(t["h"]), int(a["h"])])
	var cd := TL.cen_diff(t["cen"], a["cen"])
	if cd != "":
		bad.append("census: " + cd)
	return ", ".join(bad)

func _cmp_ab(a: Dictionary, b: Dictionary) -> String:
	var t := {"cur": a["cur"], "grip": a["grip"], "chk": a["chk"],
		"h": a["h"], "cen": a["cen"]}
	return _cmp(t, b)

func _replay_cmp(t: Dictionary, cur: PackedVector2Array,
		grip: PackedByteArray) -> Dictionary:
	# tapelib.verify's loop, minus the file: restore the tape's start, feed a
	# stream, compare checkpoints as they are produced.
	var out := {"ok": false, "why": "", "at": -1}
	var s := TL.new_sim()
	if not s.restore(t["start"]):
		out["why"] = "start refused"
		s.free()
		return out
	var chk: PackedInt64Array = t["chk"]
	var j := 0
	for i in cur.size():
		s.pending_reset = (grip[i] & 2) != 0
		s.step_tick(cur[i], (grip[i] & 1) != 0)
		if (i + 1) % 30 == 0:
			if j < chk.size() and int(s.state_hash()) != int(chk[j]):
				out["at"] = i + 1
				out["why"] = "checkpoint %d diverged" % j
				s.free()
				return out
			j += 1
	var h := int(s.state_hash())
	s.free()
	if h != int(t["h"]):
		out["at"] = int(t["n"])
		out["why"] = "final hash differs"
		return out
	out["ok"] = true
	out["why"] = "identical"
	return out

# ============================================ R5, the tapes that predate marks
func _r5() -> void:
	print("")
	print("=== R5  THE SIX COMMITTED TAPES PREDATE THE MARKER ===")
	for p in _tapes():
		var t: Dictionary = MAIN.tape_load(p)
		var mk: PackedInt32Array = t.get("mark", PackedInt32Array())
		_ok("%-14s loads, %d marks" % [p.get_file(), mk.size()],
			bool(t.get("ok", false)) and mk.size() == 0,
			str(t.get("err", "")))

# ================================================= R6, the key is actually free
func _r6() -> void:
	print("")
	print("=== R6  KEY_F AND KEY_G ARE NOT BOUND TO ANYTHING ELSE ===")
	var src := FileAccess.get_file_as_string("res://main.gd")
	var keys: Dictionary = {}
	var rx := RegEx.new()
	rx.compile("KEY_[A-Z0-9_]+")
	for mm in rx.search_all(src):
		var s := mm.get_string()
		keys[s] = int(keys.get(s, 0)) + 1
	var names: Array = keys.keys()
	names.sort()
	var line: Array[String] = []
	for k: String in names:
		line.append("%s x%d" % [k, int(keys[k])])
	print("  keycodes named in main.gd: %s" % ", ".join(line))
	_ok("KEY_F and KEY_G each appear only in the marker branch",
		int(keys.get("KEY_F", 0)) == 2 and int(keys.get("KEY_G", 0)) == 1)
	_ok("and it is the marker branch",
		src.count("elif (event.keycode == KEY_F or event.keycode == KEY_G) and rec_on:") == 1
		and src.count("MARK_GREEN if event.keycode == KEY_F else MARK_NOHOOK") == 1)
	var pg := FileAccess.get_file_as_string("res://project.godot")
	_ok("project.godot defines no input actions that could shadow it",
		not pg.contains("[input]"))
