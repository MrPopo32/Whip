extends SceneTree
## WHAT THE GAME ACTUALLY LOOKS LIKE, through the SHIPPED camera. Puts the real
## main.gd in the tree so the real _draw runs - real HUD, real audio-visual
## twins - drives it to a chosen moment, calls main.gd's own cam_apply(), and
## photographs the frame. Then it prints a MANIFEST of what is inside that
## frame's rectangle in metres, so "the beam is on screen" is a measurement and
## not something someone thought they saw in a PNG.
##
## MUST be given --replay, exactly like tests/aud_shot:
## _ready defers to _boot_session, which turns save_enabled ON for an ordinary
## session and would then write a run the player never played over the one save
## slot. With --replay that branch returns early and the save on file is never
## touched. This script refuses to step if save_enabled came back true.
##
##   godot --path . -s res://tests/cam_view.gd -- --replay tapes/door.tape \
##         mode=door out=user://view
const MAIN := preload("res://main.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const PPM := 60.0
const DT := 1.0 / 60.0

var m: Node2D
var outdir := "user://view"
var frames := 0
var stage := 0
var plan: Array = []
var pi := 0
var tick := 0
var lst: Dictionary = {}
var lprev := Vector2.ZERO

func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		root.size = Vector2i(1600, 900)
		var args := OS.get_cmdline_user_args()
		var mode := "door"
		for a: String in args:
			if a.begins_with("out="):
				outdir = a.substr(4)
			if a.begins_with("mode="):
				mode = a.substr(5)
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(outdir))
		m = MAIN.new()
		m.external_drive = true
		m.setup_sim()
		root.add_child(m)
		if m.save_enabled:
			print("REFUSING: save_enabled is true. Pass --replay.")
			return true
		for a: String in args:
			if a == "zone=1":
				# draw the working-zone ring WITHOUT taking the OS pointer: the
				# ring is what the player sees, the grab is not, and something
				# else on this machine may be using the mouse.
				m.mouse_owned = true
		plan = _make_plan(mode)
		print("shooting %d moments into %s" % [plan.size(), outdir])
		return false
	if frames < 4:
		return false
	if pi >= plan.size():
		print("done")
		return true
	# ONE STATE PER FRAME. The canvas item is only re-drawn by the engine's own
	# idle step, so a shot has to be set up in one frame and photographed in the
	# next - the trap of photographing a frame the camera has not settled into.
	var step: Dictionary = plan[pi]
	if stage == 0:
		if m.zone != null:
			m.zone.queue_redraw()
		while tick < int(step["at"]):
			_drive()
			tick += 1
		_manifest(String(step["name"]), String(step["want"]))
		stage = 1
		return false
	_save("%s/%s.png" % [outdir, String(step["name"])])
	stage = 0
	pi += 1
	return false

func _drive() -> void:
	if m.play_on:
		m.tape_feed()
	elif not lst.is_empty():
		var cg := LEAP.leap_step(m, lst, lprev)
		lprev = m.body_pos
		m.step_tick(cg[0], cg[1])
	else:
		m.step_tick(m.body_pos, false)
	m.cam_apply(DT)        # THE SHIPPED CAMERA, called by name

func _make_plan(mode: String) -> Array:
	if mode == "leap":
		# hang on F1 (k=7), pump, and fly the 7.8 m to F2 (k=8). The tape was
		# only ever loaded to keep save_enabled false; the leap is driven by
		# bot_leap's measured policy on the real anchors.
		m.play_on = false
		LEAP._wind_on(m, 7, 1.6, 1.8, 0.0)
		m.cam_reinit()
		for t in 30:
			m.step_tick(m.body_pos, true)
			m.cam_apply(DT)
		lst = LEAP.leap_begin(m, 7, 8)
		lprev = m.body_pos
		return [
			{"at": 70, "name": "3_fastline_swing", "want": "F1,F2,tier1,tier2,lip30"},
			{"at": 118, "name": "3b_fastline_release", "want": "F1,F2,tier2,lip30"},
			{"at": 190, "name": "3c_fastline_flight", "want": "F2,tier2"},
			{"at": 216, "name": "3d_fastline_catch", "want": "F2,tier2"},
		]
	if mode == "tier4":
		m.play_on = false
		LEAP._wind_on(m, 10, 2.0, 1.8, 0.0)
		m.cam_reinit()
		var out: Array = [{"at": 60, "name": "5_tier4_hang",
			"want": "F4,D4,tier4,goal"}]
		return out
	if mode == "tier4b":
		# standing on the bottom tier, having come off the beam
		m.play_on = false
		m.teleport(Vector2(52.0, 11.6))
		m.cam_reinit()
		return [{"at": 150, "name": "5b_tier4_stand", "want": "F4,tier4,goal"}]
	# the door tape: 23 m of crawl, the catch over the first lip, the hang,
	# the 3 m fall onto tier 1.
	return [
		{"at": 4, "name": "1_spawn", "want": "k0,k1,tier0"},
		{"at": 3140, "name": "2_door_lip", "want": "D1,lip20,tier0,tier1"},
		{"at": 3320, "name": "2b_door_catch", "want": "D1,lip20,tier1"},
		{"at": 3560, "name": "2c_door_hang", "want": "D1,lip20,tier1"},
		{"at": 3880, "name": "4_drop", "want": "D1,tier1"},
		{"at": 3985, "name": "4b_land", "want": "D1,tier1,F1"},
	]

# -------------------------------------------------------------- the manifest --
const FEATURES := {
	"k0": [-2.0, -2.2], "k1": [3.6, -2.2], "k2": [15.6, -2.2],
	"D1": [21.4, -2.2], "D2": [31.4, 0.8], "D3": [41.4, 3.8], "D4": [49.4, 6.8],
	"F1": [27.2, -1.5], "F2": [35.0, 1.5], "F3": [42.8, 4.5], "F4": [50.6, 7.5],
	"goal": [59.5, 9.8],
	"lip20": [20.0, 0.0], "lip30": [30.0, 3.0], "lip40": [40.0, 6.0],
	"lip48": [48.0, 9.0],
	"tier0": [10.0, 0.0], "tier1": [25.0, 3.0], "tier2": [35.0, 6.0],
	"tier3": [44.0, 9.0], "tier4": [55.0, 12.0],
}

func _manifest(name: String, want: String) -> void:
	var z: float = m.cam.zoom.x
	var c: Vector2 = m.cam.position / PPM
	var hw: float = 1600.0 / PPM * 0.5 / z
	var hh: float = 900.0 / PPM * 0.5 / z
	var b: Vector2 = m.body_pos
	var tp: Vector2 = m.pos[m.NP - 1]
	var inn: Array = []
	var miss: Array = []
	for k: String in FEATURES:
		var p := Vector2(float(FEATURES[k][0]), float(FEATURES[k][1]))
		# a TIER is a floor LINE, so it counts as visible if its y is in frame
		# and any of it is within the horizontal span - not only its midpoint.
		var vis: bool
		if k.begins_with("tier"):
			vis = absf(p.y - c.y) <= hh
		else:
			vis = absf(p.x - c.x) <= hw and absf(p.y - c.y) <= hh
		if vis:
			inn.append(k)
	for k: String in want.split(","):
		if not inn.has(k):
			miss.append(k)
	var fx: float = 0.5 + (b.x - c.x) / (2.0 * hw)
	var fy: float = 0.5 + (b.y - c.y) / (2.0 * hh)
	var tipin: bool = absf(tp.x - c.x) <= hw and absf(tp.y - c.y) <= hh
	print("")
	print("  %s  tick %d" % [name, tick])
	print("    body (%6.2f,%6.2f) at %2.0f%% across / %2.0f%% down   v %.2f m/s"
		% [b.x, b.y, fx * 100.0, fy * 100.0, m._body_vel().length()])
	print("    frame x %6.2f .. %6.2f   y %6.2f .. %6.2f   zoom %.4f"
		% [c.x - hw, c.x + hw, c.y - hh, c.y + hh, z])
	print("    in frame: %s" % ", ".join(PackedStringArray(inn)))
	print("    tip on screen: %s" % ("yes" if tipin else "NO"))
	if miss.is_empty():
		print("    WANTED: all present (%s)" % want)
	else:
		print("    WANTED BUT MISSING: %s" % str(miss))

func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
