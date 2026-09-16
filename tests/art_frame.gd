extends SceneTree
## ONE STILL FRAME OF A LEVEL, through the real main.gd in the tree - real
## _draw, real HUD, real camera - photographed and md5'd. The instrument
## tests/art_gate.gd A4 uses to say "byte-identical": the same command run
## against two builds of main.gd must print the same md5, or the frame moved.
##
## MUST BE RUN WINDOWED: the headless root viewport has no texture (see
## tests/lab_view.gd). It is on screen for well under a second.
##
##   godot --path . -s res://tests/art_frame.gd -- level=steps out=user://art_frame [name=steps] [ticks=60]
##
## The body stands at spawn with the hand open for `ticks` ticks (the rope
## settles onto the floor, the camera onto its shelf), then the frame is taken.
## Nothing is hand-laid and nothing is random, so the picture is a function of
## (level, main.gd, ticks) and of nothing else.
##
## IT MUST NOT TAKE THE PLAYER'S SAVE OR MOUSE: setup_sim() first, then a
## scratch save_path, then add_child (whose _ready runs _boot_session against
## the scratch), then save_enabled off and the scratch removed - the
## tests/crag_view.gd pattern.
const MAIN := preload("res://main.gd")
const DT := 1.0 / 60.0

var m: Node2D
var outdir := "user://art_frame"
var pname := ""
var ticks := 60
var frames := 0
var refused := false

func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		root.size = Vector2i(1600, 900)
		var lvl := "steps"
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("out="):
				outdir = a.substr(4)
			if a.begins_with("level="):
				lvl = a.substr(6)
			if a.begins_with("name="):
				pname = a.substr(5)
			if a.begins_with("ticks="):
				ticks = int(a.substr(6))
		if pname == "":
			pname = MAIN.level_name(lvl)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
		m = MAIN.new()
		m.external_drive = true
		m.level_id = lvl
		m.setup_sim()
		if String(m.level_err) != "":
			print("REFUSING: %s" % String(m.level_err))
			refused = true
			return true
		m.save_path = "user://art_frame_scratch.save"
		root.add_child(m)                      # _ready -> _boot_session
		m.save_enabled = false
		m.play_on = false
		if m.mouse_owned:
			m.mouse_owned = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
		if m.save_enabled or m.mouse_owned or m.save_path.begins_with("user://run"):
			print("REFUSING: this session still owns a save slot or the pointer.")
			refused = true
			return true
		return false
	if refused:
		return true
	if frames < 4:
		return false
	if frames == 4:
		m._reset()                              # spawn, whatever the scratch held
		m.cam_reinit()
		for t in ticks:
			m.step_tick(m.body_pos, false)
			m.cam_apply(DT)
		m.queue_redraw()
		return false
	# the canvas is redrawn by the engine's own idle step: set up in one frame,
	# photograph the next
	var tex := root.get_texture()
	if tex == null:
		print("NO FRAME: the root viewport has no texture. Run WINDOWED.")
		return true
	var path := "%s/%s.png" % [outdir, pname]
	tex.get_image().save_png(path)
	# art_on / greybox / the node count are read with get() so this harness
	# also runs against a main.gd from before the art layer existed
	var art_n: int = int(m.call("art_node_count")) if m.has_method("art_node_count") else 0
	print("frame %s  %dx%d  ticks %d  body (%.2f, %.2f)  cam (%.0f, %.0f) px  art_on %s  greybox %s  art nodes %d  md5 %s"
		% [path, tex.get_width(), tex.get_height(), ticks, m.body_pos.x, m.body_pos.y,
		m.cam.position.x, m.cam.position.y, str(m.get("art_on")), str(m.get("greybox")),
		art_n, FileAccess.get_md5(path)])
	return true
