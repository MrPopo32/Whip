extends SceneTree
## STEP 1 OF PHOTOGRAPHING THE CRAG: find the pictures, headlessly.
##
## For every feature, the same searched throw tests/crag_gate.gd C6 uses - a
## body that crawled to the standing spot with the lash gait, wound up, and
## threw the 108-stroke grid until one LOCKED - and the sim's state at the
## catch and after 100 ticks of holding on, written to a file for
## tests/crag_view.gd to restore and photograph through the real _draw.
## Nothing is hand-laid: each state is what step_tick produced from (cursor,
## grip) alone.
##
##   godot --headless --path . -s res://tests/crag_shots.gd -- [out=user://crag_shots.dat] [k=3,5,7]
const LIB := preload("res://tests/crag_lib.gd")
const DEFAULT_OUT := "user://crag_shots.dat"

func _initialize() -> void:
	var outp := DEFAULT_OUT
	var which: Array = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			outp = a.substr(4)
		if a.begins_with("k="):
			for s in a.substr(2).split(","):
				which.append(int(s))
	var m := LIB.new_crag()
	var names := LIB.feat_names(m)
	if which.is_empty():
		for k in m.a_pos.size():
			which.append(k)
	m.free()
	var shots: Array = []
	for k: int in which:
		var r: Dictionary = LIB.search(k, "wrap")
		if not r.has("m"):
			r = LIB.search(k, "touch")
		if not r.has("m"):
			r = LIB.search(k, "wrap", false, true)
		if not r.has("m"):
			r = LIB.search(k, "touch", false, true)
		if not r.has("m"):
			print("  k%d %-14s NO searched stroke locked it (%d strokes, %d caught)"
				% [k, names[k], int(r["att"]), int(r["caught"])])
			continue
		var s: Node2D = r["m"]
		var catch_snap: Dictionary = s.snapshot()
		# hold on, hand toward the anchor, and let the haul happen
		for t in 100:
			s.step_tick(s.body_pos + (Vector2(s.a_pos[k]) - s.body_pos).normalized() * s.REACH, true)
		var hang_snap: Dictionary = s.snapshot()
		print("  k%d %-14s stroke %3d  tether %.2f  hang: body (%.2f,%.2f) grounded %s locked %d ring %s"
			% [k, names[k], int(r["att"]), float(r["tether"]), s.body_pos.x,
			s.body_pos.y, str(s.grounded), int(s.a_locked[k]),
			"GREEN" if s._holds(k) else "amber/none"])
		print("       %s" % String(r["how"]))
		shots.append({"k": k, "name": names[k], "how": String(r["how"]),
			"phase": "catch", "snap": catch_snap})
		shots.append({"k": k, "name": names[k], "how": String(r["how"]),
			"phase": "hang", "snap": hang_snap})
		s.free()
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f == null:
		print("FAIL cannot write %s" % outp)
		quit(1)
		return
	f.store_var(shots, false)
	f.close()
	print("wrote %d states to %s" % [shots.size(), outp])
	quit(0)
