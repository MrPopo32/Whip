extends SceneTree
const MAIN := preload("res://main.gd")
func _initialize() -> void:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.setup_sim()
	m.save_enabled = false
	var fp: int = m.level_fingerprint()
	print("   shipped fingerprint %d" % fp)
	var d := DirAccess.open("res://tapes")
	var names := d.get_files()
	for n in names:
		var t: Dictionary = MAIN.tape_load("res://tapes/" + n)
		print("   tapes/%-14s ok=%s lvl=%d match=%s n=%d" % [n, t.get("ok",false), int(t.get("lvl",0)), int(t.get("lvl",0))==fp, int(t.get("n",0))])
	var b: Dictionary = MAIN.tape_load("res://takes/bug1.tape")
	print("   takes/bug1.tape  ok=%s lvl=%d match=%s n=%d err=%s" % [b.get("ok",false), int(b.get("lvl",0)), int(b.get("lvl",0))==fp, int(b.get("n",0)), b.get("err","")])
	var began: bool = m.tape_begin_play(b)
	var fed := 0
	while fed < 600 and m.tape_feed():
		fed += 1
	var bad := false
	for i in m.NP:
		var v: Vector2 = m.pos[i]
		if is_nan(v.x) or is_nan(v.y): bad = true
	print("   bug1 begin_play=%s  fed %d ticks  body %.3f %.3f  nan=%s" % [began, fed, m.body_pos.x, m.body_pos.y, bad])
	m.free()
	quit(0)
