extends SceneTree
## STEP 2: PHOTOGRAPH THE CRAG, through the real main.gd - real backdrop,
## real terrain and arcs, real anchors and ring, real HUD, the shipped camera
## on the crag's own volume table. tests/lab_view.gd's pattern, unchanged in
## what matters:
##
## MUST BE RUN WINDOWED (the headless root viewport has no texture).
## IT MUST NOT TAKE THE PLAYER'S MOUSE OR ANY SAVE: setup_sim() first, then
## the slot is redirected, _ready runs _boot_session against the redirected
## slot (which finds nothing: --fresh is not passed and the scratch file does
## not exist), and save_enabled and the pointer are put back the instant
## add_child returns. The script refuses to shoot if either survives.
##
##   godot --path . -s res://tests/crag_view.gd -- --level crag in=user://crag_shots.dat out=DIR
const MAIN := preload("res://main.gd")
const PPM := 60.0
const DT := 1.0 / 60.0

var m: Node2D
var outdir := "user://crag"
var inp := "user://crag_shots.dat"
var frames := 0
var stage := 0
var plan: Array = []
var pi_ := 0
var refused := false

func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		root.size = Vector2i(1600, 900)
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("out="):
				outdir = a.substr(4)
			if a.begins_with("in="):
				inp = a.substr(3)
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(outdir))
		m = MAIN.new()
		m.external_drive = true
		m.level_id = "crag"
		m.setup_sim()
		m.save_path = "user://crag_view_scratch.save"
		root.add_child(m)                      # _ready -> _boot_session
		m.save_enabled = false
		m.play_on = false
		if m.mouse_owned:
			m.mouse_owned = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
		if m.save_enabled or m.mouse_owned or m.save_path == "user://run_crag.save":
			print("REFUSING: this session still owns a save slot or the pointer.")
			refused = true
			return true
		plan.append({"name": "0_spawn", "note": "the home tier, nothing thrown"})
		# in= may be a comma-separated list: crag_shots is run one feature per
		# process to use the cores, and each writes its own file
		var shots: Array = []
		for one: String in inp.split(","):
			var f := FileAccess.open(one, FileAccess.READ)
			if f == null:
				print("no %s - run tests/crag_shots.gd first" % one)
				continue
			var got: Variant = f.get_var(false)
			f.close()
			shots.append_array(got as Array)
		if true:
			for sh: Dictionary in shots:
				var nm: String = String(sh["name"]).to_lower().replace(" ", "_") \
					.replace("(", "").replace(")", "")
				plan.append({"name": "%d_%s_%s" % [int(sh["k"]), nm,
					String(sh["phase"])], "snap": sh["snap"],
					"k": int(sh["k"]), "note": String(sh["how"])})
		print("shooting %d frames into %s" % [plan.size(), outdir])
		return false
	if frames < 4 or refused:
		return refused
	if pi_ >= plan.size():
		print("done: %d frames" % pi_)
		return true
	var step: Dictionary = plan[pi_]
	if stage == 0:
		if step.has("snap"):
			m.restore(step["snap"])
		m.cam_reinit()
		m.cam_apply(DT)
		m.queue_redraw()
		_manifest(step)
		stage = 1
		return false
	_save("%s/%s.png" % [outdir, String(step["name"])])
	stage = 0
	pi_ += 1
	return false

func _manifest(step: Dictionary) -> void:
	var z: float = m.cam.zoom.x
	var c: Vector2 = m.cam.position / PPM
	var hw: float = 1600.0 / PPM * 0.5 / z
	var hh: float = 900.0 / PPM * 0.5 / z
	var inn: Array = []
	for k in m.a_pos.size():
		if absf(m.a_pos[k].x - c.x) <= hw and absf(m.a_pos[k].y - c.y) <= hh:
			inn.append("k%d" % k)
	print("")
	print("  %-26s frame x %6.2f..%6.2f  y %6.2f..%6.2f   anchors in view: %s"
		% [String(step["name"]), c.x - hw, c.x + hw, c.y - hh, c.y + hh,
		", ".join(PackedStringArray(inn))])
	print("      %s" % String(step["note"]))
	if not step.has("k"):
		return
	var k: int = int(step["k"])
	var td := 1e9
	for i in m.NP:
		td = minf(td, m.pos[i].distance_to(m.a_pos[k]))
	print("      k%d theta %.2f rad  engaged %s  locked %d  RING %s  tether %.2f  hand %s  body (%.2f,%.2f) grounded %s"
		% [k, absf(float(m.a_theta[k])), str(float(m.a_freelen[k]) >= 0.0),
		int(m.a_locked[k]), "GREEN" if m._holds(k) else "amber/none",
		float(m.a_freelen[k]), "SHUT" if m.taut else "open",
		m.body_pos.x, m.body_pos.y, str(m.grounded)])

func _save(path: String) -> void:
	var tex := root.get_texture()
	if tex == null:
		print("      NO FRAME: the root viewport has no texture. Run WINDOWED.")
		return
	tex.get_image().save_png(path)
