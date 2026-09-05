extends SceneTree
## THE LEVEL GATE, for ANY level: a scene the developer drew (by name, or
## as a .tscn), or one of the three hardcoded ones. Everything lab_gate and
## crag_gate ask that is not specific to the lab or the crag, asked of this
## level, through tests/level_lib.gd - the same code, so the three gates
## cannot measure different things.
##
##   godot --headless --path . -s res://tests/level_gate.gd -- level=<name | x.tscn | lab | crag> [quick]
##
##  F  the fingerprint is not the traverse's (the tapes would replay into it),
##     not the lab's, and not the crag's - unless this IS the crag exported,
##     which is allowed only under the name crag and proven by level_fidelity
##  T  every committed tape still names the shipped level and none names this
##  N  every terrain normal, ground and island, points into the air region the
##     loops enclose; the checker scores 0 on the reversed winding
##  A  an arc is never an anchor: the bench (1.5 turns on a fillet engage
##     nothing) and, on this level, no arc overlaps an anchor
##  D  the rescue depth is finite (<= half the island) behind every island face
##  S  the level's save slot is its own, a traverse save is refused, its own
##     save is accepted; the slot is not run.save / run_lab.save / run_crag.save
##     (the last unless this is the crag)
##  W  crawlable with the hand open from spawn to the flag (or, on a bench
##     with no flag, to the far wall)
##  R  every anchor LOCKS from a searched throw after a crawl-in (minutes;
##     skipped by quick)
##  and, printed but not gated: the camera table, and the contract table -
##  every anchor's height over the floor it is thrown from, the air past it,
##  and its nearest neighbour, against the README's numbers
const MAIN := preload("res://main.gd")
const LIB := preload("res://tests/level_lib.gd")

var fail: Array[String] = []

func _initialize() -> void:
	var level := ""
	var have := false
	var quick := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			level = a.substr(6)
			have = true
		elif a == "quick":
			quick = true
	if not have:
		print("usage: -s res://tests/level_gate.gd -- level=<name | x.tscn | lab | crag> [quick]")
		quit(2)
		return
	var m := LIB.new_sim(level)
	if String(m.level_err) != "":
		print("FAIL  %s" % String(m.level_err))
		m.free()
		quit(1)
		return
	var name: String = MAIN.level_name(level)
	var builtin: bool = MAIN.level_is_builtin(level)
	print("LEVEL GATE  %s  (%s)" % [level if level != "" else "the traverse",
		"hardcoded in main.gd" if builtin else MAIN.level_scene_path(level)])
	var loops := LIB.chain_loops(m.t_a, m.t_b)
	var ni := 0
	var g := PackedVector2Array()
	for l: Dictionary in loops:
		if bool(l["closed"]):
			ni += 1
		else:
			g = l["pts"]
	print("  %d segments (1 ground chain + %d islands), %d arcs, %d anchors, spawn (%.2f, %.2f), %s, world_bottom %.1f, slot %s"
		% [m.t_a.size(), ni, m.t_arc_c.size(), m.a_pos.size(), m.spawn.x, m.spawn.y,
		("goal (%.1f, %.1f)" % [m.goal_x, m.goal_y]) if float(m.goal_x) < 900.0 else "no goal (a bench)",
		m.world_bottom, m.save_path])
	var names := LIB.anchor_names(level, m)
	# ---- F
	var fp: int = m.level_fingerprint()
	var fps := {}
	for lvl: String in ["", "lab", "crag"]:
		if lvl == level:
			continue
		var o := LIB.new_sim(lvl)
		fps[lvl] = int(o.level_fingerprint())
		o.free()
	if fps.has("") and fp == int(fps[""]):
		fail.append("F this level IS the traverse (fingerprint %d): every committed tape would replay into it" % fp)
	elif fps.has("lab") and fp == int(fps["lab"]):
		fail.append("F this level IS the lab (fingerprint %d)" % fp)
	elif fps.has("crag") and fp == int(fps["crag"]):
		if name == "crag":
			print("  F ok: fingerprint %d is the hardcoded crag's: this scene is the crag, exported (tests/level_fidelity.gd proves every array)" % fp)
		else:
			fail.append("F this level IS the crag (fingerprint %d) under another name" % fp)
	else:
		var others := PackedStringArray()
		for lvl: String in fps:
			others.append("%s %d" % ["traverse" if lvl == "" else lvl, int(fps[lvl])])
		print("  F ok: fingerprint %d; %s all differ" % [fp, ", ".join(others)])
	# ---- T
	if LIB.tapes_check(fp, name, "T", fail):
		print("  T ok: 6 tapes, all still naming the shipped %d; none names %s" % [LIB.SHIPPED_FP, name])
	# ---- N A D
	LIB.normals_check(m, "N", fail)
	LIB.arcs_check(m, "A", fail)
	LIB.rescue_check(m, "D", fail)
	# ---- S
	var slot: String = m.save_path
	if slot == "user://run.save":
		fail.append("S the level writes the traverse's slot")
	elif slot == "user://run_lab.save" and level != "lab":
		fail.append("S the level writes the lab's slot")
	elif slot == "user://run_crag.save" and level != "crag" and not (fps.has("crag") and fp == int(fps["crag"])):
		fail.append("S the level writes the crag's slot without being the crag")
	if level != "":
		# a scratch save named for the level, so two gates can run at once
		LIB.slot_check(level, "", "S", fail, "user://level_gate_%s_tmp.save" % name)
	else:
		print("  S ok: the traverse owns user://run.save")
	# ---- the tables
	LIB.vols_report(m, MAIN.level_default_vols(g) == m.cam_vols)
	LIB.contract_report(m, names)
	m.free()
	# ---- W R
	var w := LIB.new_sim(level)
	LIB.walk_check(w, "W", fail)
	w.free()
	if not quick:
		LIB.reach_check(level, names, "R", fail)
	if fail.is_empty():
		print("PASS  level gate %s: F T N A D S W%s" % [level if level != "" else "traverse",
			" (R skipped: quick)" if quick else " R"])
		quit(0)
		return
	for f in fail:
		print("FAIL  %s" % f)
	quit(1)
