extends SceneTree
## THE TWO MARKER KEYS, AND THE KIND THAT TELLS THEM APART.
##
##   godot --headless --path . -s res://tests/mark_kind.gd
##
## tests/mark_rt.gd proves the recorder does not lie: a mark lands on the tick
## it was pressed on and the tape replays to the same hash. It was written for a
## build with ONE key, so it says nothing about G and nothing about the kind
## field - and a key that is never tested is a key that quietly does nothing on
## the one night it matters. This gate covers exactly that gap:
##
##   K1  the _input branch maps F -> MARK_GREEN and G -> MARK_NOHOOK
##   K2  rec_on is the whole opt-in: neither key latches without it
##   K3  _rec_tick spends the latch into rec_mark AND rec_mkind, in step
##   K4  the kinds survive tape_save -> tape_load
##   K5  a tape with no kinds (every committed tape) loads with kinds padded to
##       the length of its marks, so a reader can index one by the other
const TL := preload("res://tests/tapelib.gd")

var fails := 0

func _ok(what: String, cond: bool, detail := "") -> void:
	if not cond:
		fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", what,
		"   " + detail if detail != "" else ""])

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e

func _initialize() -> void:
	var m := TL.new_sim()

	print("=== K1  F AND G LATCH DIFFERENT KINDS ===")
	m.rec_on = true
	m.rec_mk = 0
	m._input(_key(KEY_F))
	var got_f: int = m.rec_mk
	m.rec_mk = 0
	m._input(_key(KEY_G))
	var got_g: int = m.rec_mk
	_ok("F latches MARK_GREEN", got_f == m.MARK_GREEN,
		"got %d, want %d" % [got_f, m.MARK_GREEN])
	_ok("G latches MARK_NOHOOK", got_g == m.MARK_NOHOOK,
		"got %d, want %d" % [got_g, m.MARK_NOHOOK])
	_ok("and they are not the same kind", got_f != got_g)
	_ok("both name themselves", str(m.MARK_NAME[got_f]) != ""
		and str(m.MARK_NAME[got_g]) != "",
		"%s / %s" % [m.MARK_NAME[got_f], m.MARK_NAME[got_g]])

	print("")
	print("=== K2  THE NEGATIVE CONTROL: no --record, no marks ===")
	# If this passed with rec_on false the keys would be live in an ordinary
	# session, which is the one thing the opt-in exists to prevent.
	m.rec_on = false
	m.rec_mk = 0
	m._input(_key(KEY_F))
	m._input(_key(KEY_G))
	_ok("neither key latches while rec_on is false", m.rec_mk == 0,
		"rec_mk %d" % m.rec_mk)
	m.rec_mk = 0

	print("")
	print("=== K3  THE LATCH IS SPENT INTO BOTH ARRAYS, IN STEP ===")
	m.rec_begin("mark_kind")
	var want_at := {7: m.MARK_NOHOOK, 19: m.MARK_GREEN, 33: m.MARK_NOHOOK}
	var order: Array[int] = []
	for i in 60:
		if want_at.has(int(m.rec_cur.size())):
			var kind: int = want_at[int(m.rec_cur.size())]
			m._input(_key(KEY_F if kind == m.MARK_GREEN else KEY_G))
			order.append(kind)
		m.step_tick(m.body_pos + Vector2(0.6, -0.4), false)
	var marks: PackedInt32Array = m.rec_mark.duplicate()
	var kinds: PackedInt32Array = m.rec_mkind.duplicate()
	_ok("one mark per press", marks.size() == 3, "marks %s" % str(marks))
	_ok("kinds run in step with marks", kinds.size() == marks.size(),
		"%d kinds for %d marks" % [kinds.size(), marks.size()])
	_ok("the marks landed on the ticks pressed",
		Array(marks) == [7, 19, 33], "%s" % str(marks))
	_ok("and each carries the kind that was pressed",
		Array(kinds) == order, "%s vs %s" % [str(kinds), str(order)])

	print("")
	print("=== K4  THE KINDS SURVIVE THE FILE ===")
	var out := "user://mark_kind.tape"
	_ok("tape written", bool(m.tape_save(out)))
	var t: Dictionary = load("res://main.gd").tape_load(out)
	_ok("tape loads", bool(t.get("ok", false)), str(t.get("err", "")))
	_ok("marks survive", Array(t.get("mark", PackedInt32Array())) == Array(marks),
		"%s" % str(t.get("mark", PackedInt32Array())))
	_ok("kinds survive", Array(t.get("mkind", PackedInt32Array())) == Array(kinds),
		"%s" % str(t.get("mkind", PackedInt32Array())))
	m.rec_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))

	print("")
	print("=== K5  A TAPE WITH NO KINDS STILL INDEXES ===")
	var checked := 0
	for f in DirAccess.get_files_at("res://tapes"):
		if not f.ends_with(".tape"):
			continue
		var ot: Dictionary = load("res://main.gd").tape_load("res://tapes/" + f)
		if not bool(ot.get("ok", false)):
			continue
		checked += 1
		var mk: PackedInt32Array = ot.get("mark", PackedInt32Array())
		var mi: PackedInt32Array = ot.get("mkind", PackedInt32Array())
		if mk.size() != mi.size():
			_ok("%s indexes" % f, false, "%d marks, %d kinds" % [mk.size(), mi.size()])
	_ok("every committed tape loads with kinds as long as its marks",
		checked >= 6, "%d tapes checked" % checked)

	m.free()
	print("")
	print("%s  mark_kind: %d gate(s) failed" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
