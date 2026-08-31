extends SceneTree
## STEP 1 OF PHOTOGRAPHING THE LAB: find the pictures, headlessly.
##
## Searches a real thrown catch on every station and writes the sim states out
## to a file. Nothing here is hand-laid: each state is what step_tick produced
## from (cursor, grip) alone, starting from a body standing on the lab's own
## floor. tests/lab_view.gd then restores them and takes the photographs.
##
## The split exists because a screenshot needs a real rendering device - the
## headless driver's root viewport has no texture, and get_image() comes back
## null (checked: tests/cam_view.gd fails the same way headless). So the slow
## half runs with no window and the windowed half runs for about two seconds.
##
##   godot --headless --path . -s res://tests/lab_shots.gd -- out=user://lab_shots.dat
const MAIN := preload("res://main.gd")
const DEFAULT_OUT := "user://lab_shots.dat"

func new_off() -> Node2D:
	var s: Node2D = MAIN.new()
	s.external_drive = true
	s.level_id = "lab"
	s.setup_sim()
	s.save_enabled = false
	return s

func stand_at(s: Node2D, x: float, a0: float) -> void:
	# hand held BACK while the whip settles - see tests/lab_throw.gd's table:
	# a chain piled under the body cannot throw a turn.
	s.teleport(Vector2(x, -s.BODY_R))
	for t in 90:
		s.step_tick(s.body_pos + Vector2(cos(a0), sin(a0)) * s.REACH, false)

func touching(s: Node2D, k: int) -> bool:
	for i in s.NP:
		if (s.pos[i] - s.a_pos[k]).length() \
				< s.a_r[k] + s.p_rad[i] + s.wrap_shell + 0.02:
			return true
	return false

func throw_shots(k: int, lead: float, a0: float, a1: float, sd: int,
		pull: bool, w: int, cue: String) -> Dictionary:
	var s := new_off()
	stand_at(s, float(s.a_pos[k].x) - lead, a0)
	var grip := false
	var closes := 0
	for t in w + 130:
		var ang: float
		var amp := 1.0
		if t < w:
			ang = a0
		elif t < w + sd:
			ang = a1
		elif pull and t < w + 10 + sd:
			ang = a0; amp = 0.7
		else:
			ang = a1
		var tgt: Vector2 = s.body_pos + Vector2(cos(ang), sin(ang)) * s.REACH * amp
		if grip and s.tick_count - s.grip_edge > s.GRIP_WINDOW \
				and float(s.a_freelen[k]) < 0.0:
			grip = false
		var fire := absf(float(s.a_theta[k])) >= 2.6 if cue == "wrap" \
			else touching(s, k)
		if not grip and fire and closes < 4 and float(s.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		s.step_tick(tgt, grip)
		if float(s.a_freelen[k]) >= 0.0:
			break
	if float(s.a_freelen[k]) < 0.0:
		s.free()
		return {}
	for t in 20:
		s.step_tick(s.body_pos, true)
	var catch_snap: Dictionary = s.snapshot()
	for t in 100:
		s.step_tick(s.body_pos, true)
	var out := {"catch": catch_snap, "hang": s.snapshot(),
		"hang_green": bool(s._holds(k)), "locked": int(s.a_locked[k]),
		"tether": float(s.a_freelen[k])}
	s.free()
	return out

# the same 108-stroke grid tests/lab_throw.gd measures with
const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]

func find_catch(k: int, cue: String) -> Dictionary:
	# A green catch wins outright and stops the search. If the whole grid
	# produces none, the first merely-engaged catch is kept instead and the
	# manifest says so - an amber ring is the honest picture of an anchor that
	# only ambers, and a station nothing catches gets no picture at all.
	var fallback := {}
	for lead in [1.6, 2.0, 2.4]:
		for ang: Array in GRID:
			for sd in [9, 14, 5]:
				for pull in [false, true]:
					var r := throw_shots(k, lead, ang[0], ang[1], sd, pull,
						120, cue)
					if r.is_empty():
						continue
					r["how"] = "lead %.1f  a0 %.2f  a1 %.2f  sd %d  pull %s  cue %s" % [
						lead, ang[0], ang[1], sd, str(pull), cue]
					if bool(r["hang_green"]):
						return r
					if fallback.is_empty():
						fallback = r
	return fallback

func _initialize() -> void:
	var outp := DEFAULT_OUT
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			outp = a.substr(4)
	var m := new_off()
	var shots: Array = []
	for k in m.a_pos.size():
		var nm: String = String(m.a_name[k])
		# THE CUE EACH ANCHOR OFFERS. On an ordinary beam the player shuts the
		# hand when the arc reads as a catch; on a jam, when the rope arrives.
		# Both are present-state readings off the screen.
		var cue: String = "touch" if int(m.a_jam[k]) == 1 else "wrap"
		var r := find_catch(k, cue)
		if r.is_empty():
			r = find_catch(k, "wrap" if cue == "touch" else "touch")
		if r.is_empty():
			print("  k%d %-10s  NO searched stroke caught it" % [k, nm])
			continue
		print("  k%d %-10s  %s   locked %d  tether %.2f  green %s" % [k, nm,
			String(r["how"]), int(r["locked"]), float(r["tether"]),
			str(bool(r["hang_green"]))])
		shots.append({"k": k, "name": nm, "how": String(r["how"]),
			"phase": "catch", "snap": r["catch"]})
		shots.append({"k": k, "name": nm, "how": String(r["how"]),
			"phase": "hang", "snap": r["hang"]})
	m.free()
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f == null:
		print("FAIL cannot write %s" % outp)
		quit(1)
		return
	f.store_var(shots, false)
	f.close()
	print("wrote %d states to %s" % [shots.size(), outp])
	quit(0)
