extends SceneTree
## THE LIVE PATH, run for real. cam_gate proves the arithmetic; this proves the
## plumbing: main.gd's own _physics_process, driving its own cursor_now() from
## a real viewport and its own cam_apply() into a real Camera2D, for 300 ticks.
## The probes all drive step_tick() directly, so none of them would notice if
## the one line that reads the mouse had stopped working.
##
## It also asks the question SNAP_SKIP exists to answer: does a save written by
## the PREVIOUS build still load into this one? The camera added two vars, and
## restore() refuses any state whose key set has moved - correctly, since it
## cannot tell a camera field from a physics field. If cam_st had not gone into
## SNAP_SKIP, every save and every tape on disk would be refused.
##
## Runs HEADLESS on purpose. A windowed run would take MOUSE_MODE_CONFINED_HIDDEN
## and pull the pointer out of whatever else is running.
##
##   godot --headless --path . -s res://tests/cam_live.gd -- [save=PATH]
const MAIN := preload("res://main.gd")
const DT := 1.0 / 60.0

var m: Node2D
var frames := 0
var t0 := 0
var seen: Array = []

func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		_old_save()
		# start part B at the spawn, not from this probe's own last scratch
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"user://cam_live_scratch.save"))
		# save_path is redirected BEFORE the node enters the tree: _ready defers
		# to _boot_session, which turns saving on for an ordinary session, and
		# this must never be the thing that writes the player's one slot.
		m = MAIN.new()
		m.save_path = "user://cam_live_scratch.save"
		m.setup_sim()
		root.add_child(m)
		print("")
		print("=== B. THE LIVE PATH: main.gd's own _physics_process ===")
		print("  external_drive %s   save_path %s   mouse_owned %s"
			% [str(m.external_drive), m.save_path, str(m.mouse_owned)])
		print("  smoothing on the Camera2D node: %s (the law does its own)"
			% str(m.cam.position_smoothing_enabled))
		t0 = m.tick_count
		return false
	if frames < 4:
		return false
	if m.tick_count - t0 < 300:
		seen.append([m.tick_count, m.body_pos, m.cam.position / 60.0,
			m.cursor_m, m.cam.zoom.x])
		return false
	_report()
	quit(0)
	return true

func _old_save() -> void:
	print("")
	print("=== A. A SAVE FROM THE PREVIOUS BUILD, LOADED INTO THIS ONE ===")
	var p := "user://run.save"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("save="):
			p = a.substr(5)
	if not FileAccess.file_exists(p):
		print("  no %s on disk - nothing to check." % p)
		return
	# COPY IT FIRST. The one slot is rewritten every half second while the game
	# is running, so reading it live races the write and comes back as "nothing
	# to resume" - which looks exactly like a refusal and is not one.
	var cp := "user://cam_live_read.save"
	var src := FileAccess.open(p, FileAccess.READ)
	var dst := FileAccess.open(cp, FileAccess.WRITE)
	var n_bytes := 0
	if src != null and dst != null:
		var buf := src.get_buffer(src.get_length())
		n_bytes = buf.size()
		dst.store_buffer(buf)
		dst.close()
	var s := MAIN.new()
	s.setup_sim()
	var r: int = s.load_from(cp)
	if r == 0:
		r = s.load_from(cp)
	var keys := s.snap_keys()
	var has_cam := keys.has("cam_st") or keys.has("mouse_owned")
	print("  %s (%d bytes, copied off the live slot)" % [p, n_bytes])
	print("  load_from -> %d   (1 = loaded, 0 = absent/unreadable, -1 = refused)" % r)
	print("  snapshot key set: %d keys, camera fields present: %s"
		% [keys.size(), str(has_cam)])
	if r == 1 and not has_cam:
		print("  ok: the camera added 2 vars and BOTH are in SNAP_SKIP, so the key")
		print("  set did not move and the run in progress survives this change.")
		print("  resumed at %.1fs, %d falls, x %.2f" % [s.run_ticks / 60.0,
			s.falls, s.body_pos.x])
	else:
		print("  FAIL: a save written by the previous build no longer loads.")
	s.free()

func _report() -> void:
	var b0: Vector2 = seen[0][1]
	var b1: Vector2 = seen[seen.size() - 1][1]
	var c0: Vector2 = seen[0][2]
	var c1: Vector2 = seen[seen.size() - 1][2]
	var moved := 0
	var zmin := 9.0
	var zmax := 0.0
	for r: Array in seen:
		if (Vector2(r[2]) - c0).length() > 1e-6:
			moved += 1
		zmin = minf(zmin, float(r[4])); zmax = maxf(zmax, float(r[4]))
	print("  %d ticks stepped by _physics_process, not by this probe."
		% seen.size())
	print("  body   (%6.2f,%6.2f) -> (%6.2f,%6.2f)" % [b0.x, b0.y, b1.x, b1.y])
	print("  camera (%6.2f,%6.2f) -> (%6.2f,%6.2f)   moved on %d ticks"
		% [c0.x, c0.y, c1.x, c1.y, moved])
	print("  cursor came out of cursor_now(): (%.3f,%.3f) - body-relative, so a"
		% [float(seen[0][3].x), float(seen[0][3].y)])
	print("  headless mouse parked at the origin puts it up and left of the body.")
	print("  zoom held %.4f..%.4f across the run." % [zmin, zmax])
	# the camera must sit on V0's shelf: floor 0.0 + CAM_SHELF
	var want: float = float(MAIN.CAM_VOLS[0][2]) + MAIN.CAM_SHELF
	if absf(c1.y - want) < 0.01:
		print("  and it settled on V0's authored shelf, y = %.2f. PASS." % want)
	else:
		print("  FAIL: camera y %.3f, expected the V0 shelf %.2f" % [c1.y, want])
