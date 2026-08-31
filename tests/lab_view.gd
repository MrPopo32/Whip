extends SceneTree
## STEP 2: PHOTOGRAPH THE LAB, through the real main.gd. The node goes in the
## tree, so the real _draw runs - real terrain, real captions, real jam collar,
## real ring, real HUD - and the shipped camera frames it by name.
##
## MUST BE RUN WINDOWED. The headless driver's root viewport has no texture and
## get_image() returns null; tests/cam_view.gd fails the same way headless,
## which is why the frames in this repo were always taken with a window. So the
## expensive half - searching a real thrown catch on every station - is done
## first and headlessly by tests/lab_shots.gd, and this pass only restores those
## states and photographs them. It is on screen for about two seconds.
##
## NOTHING HERE IS HAND-LAID. Every state came out of step_tick on the throws
## lab_shots searched; restore() is bit-exact and both sims are the same level,
## so what is photographed is the state the throw produced.
##
## IT MUST NOT TAKE THE PLAYER'S MOUSE OR THEIR SAVE. _ready runs _boot_session,
## which turns save_enabled on for an ordinary session and then grabs the
## pointer - so both are put back the instant add_child returns, and the script
## refuses to shoot if either survives that.
##
##   godot --path . -s res://tests/lab_view.gd -- in=user://lab_shots.dat out=user://lab
const MAIN := preload("res://main.gd")
const PPM := 60.0
const DT := 1.0 / 60.0

var m: Node2D
var outdir := "user://lab"
var inp := "user://lab_shots.dat"
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
		m.level_id = "lab"
		m.setup_sim()
		root.add_child(m)                      # _ready -> _boot_session
		m.save_enabled = false
		m.play_on = false
		if m.mouse_owned:
			m.mouse_owned = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if m.save_enabled or m.mouse_owned:
			print("REFUSING: this session still owns the save or the pointer.")
			refused = true
			return true
		plan.append({"name": "0_bench", "note": "the bench, nothing thrown"})
		var f := FileAccess.open(inp, FileAccess.READ)
		if f == null:
			print("no %s - run tests/lab_shots.gd first" % inp)
		else:
			var shots: Variant = f.get_var(false)
			f.close()
			for sh: Dictionary in (shots as Array):
				var nm: String = String(sh["name"]).to_lower().replace(" ", "_")
				plan.append({"name": "%d_%s_%s" % [int(sh["k"]) + 1, nm,
					String(sh["phase"])], "snap": sh["snap"],
					"k": int(sh["k"]), "note": String(sh["how"])})
		print("shooting %d frames into %s" % [plan.size(), outdir])
		return false
	if frames < 4 or refused:
		return refused
	if pi_ >= plan.size():
		print("done: %d frames" % pi_)
		return true
	# ONE STATE PER FRAME: the canvas is only redrawn by the engine's own idle
	# step, so a shot is set up in one frame and photographed in the next.
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

# THE MANIFEST: what is inside the rectangle, in metres, and what the sim says
# about the anchor being photographed on that tick. A PNG on its own is a claim.
func _manifest(step: Dictionary) -> void:
	var z: float = m.cam.zoom.x
	var c: Vector2 = m.cam.position / PPM
	var hw: float = 1600.0 / PPM * 0.5 / z
	var hh: float = 900.0 / PPM * 0.5 / z
	var inn: Array = []
	for k in m.a_pos.size():
		if absf(m.a_pos[k].x - c.x) <= hw and absf(m.a_pos[k].y - c.y) <= hh:
			inn.append(String(m.a_name[k]))
	print("")
	print("  %-24s frame x %6.2f..%6.2f  y %6.2f..%6.2f   in view: %s"
		% [String(step["name"]), c.x - hw, c.x + hw, c.y - hh, c.y + hh,
		", ".join(PackedStringArray(inn))])
	print("      %s" % String(step["note"]))
	if not step.has("k"):
		return
	var k: int = int(step["k"])
	var td := 1e9
	for i in m.NP:
		td = minf(td, m.pos[i].distance_to(m.a_pos[k]))
	print("      %s  jam %d | theta %.2f rad  engaged %s  locked %d  RING %s"
		% [String(m.a_name[k]), int(m.a_jam[k]), absf(float(m.a_theta[k])),
		str(float(m.a_freelen[k]) >= 0.0), int(m.a_locked[k]),
		"GREEN" if m._holds(k) else "amber/none"])
	print("      tether %.2f m  nearest rope %.3f m  hand %s  body (%.2f,%.2f)"
		% [float(m.a_freelen[k]), td, "SHUT" if m.taut else "open",
		m.body_pos.x, m.body_pos.y])

func _save(path: String) -> void:
	var tex := root.get_texture()
	if tex == null:
		print("      NO FRAME: the root viewport has no texture. Run WINDOWED.")
		return
	tex.get_image().save_png(path)
