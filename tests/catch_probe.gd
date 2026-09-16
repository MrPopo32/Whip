extends SceneTree
## CONTINUE EVERY HARVESTED CATCH on THIS build with the player's recorded
## inputs, and measure the catch: does it still engage on the same tick (the
## decision), the tether it was given, the fall before the tether arrests the
## body, the yank at arrest, the belly and kink after, and whether the wrap
## survives the continuation with the hand the player actually used.
##
##   godot --headless --path . -s res://tests/catch_probe.gd -- takes/bug1.tape <catchdir> [W]
const TL := preload("res://tests/tapelib.gd")
const BC := preload("res://tests/belly_census.gd")

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var path: String = args[0]
	var cdir: String = args[1]
	var W: int = int(args[2]) if args.size() > 2 else 240
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var t: Dictionary = load("res://main.gd").tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load %s: %s" % [path, t.get("err", "")])
		quit(1)
		return
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var files: Array = []
	for f in DirAccess.get_files_at(cdir):
		if f.begins_with("catch_") and f.ends_with(".bin"):
			files.append(f)
	files.sort()
	print("W = %d ticks of the recorded hand after each catch" % W)
	print(" n   tick  k  eng@c  tether  chord   slack | arrest  fall(m)  yank(m/s) maxdv30 | sag50  kink50  swing50 | engaged  locked  ended")
	var falls: Array = []
	var yanks: Array = []
	var maxdvs: Array = []
	var sags: Array = []
	var kinks: Array = []
	var swings: Array = []
	var arrests: Array = []
	var slacks: Array = []
	var tethers: Array = []
	var n_eng_c := 0
	var n_hold_w := 0
	var n_locked := 0
	var n_open := 0
	var n_ended := 0
	var eng_ticks := 0
	var sag_ticks: Array = []
	var kink_ticks: Array = []
	var swing_ticks: Array = []
	for fn: String in files:
		var f := FileAccess.open("%s/%s" % [cdir, fn], FileAccess.READ)
		var d: Dictionary = f.get_var()
		f.close()
		var c: int = int(d["tick"])
		var k: int = int(d["k"])
		var m := TL.new_sim()
		if not m.restore(d["snap"]):
			print("%s: restore refused" % fn)
			m.free()
			continue
		var y_pre: float = m.body_pos.y
		var b_prev: Vector2 = m.body_pos
		var v_prev: Vector2 = (m.body_pos - m.body_prv) / m.SDT
		var prev_pos: PackedVector2Array = m.pos.duplicate()
		var eng_c := false
		var tether := -1.0
		var chord := -1.0
		var slack := 0.0
		var arrest := -1
		var fall := 0.0
		var yank := 0.0
		var maxdv := 0.0
		var engaged := 0
		var locked := -1
		var ended := "held"
		var sg: Array = []
		var kk: Array = []
		var sw: Array = []
		for j in W:
			var i := c + j
			if i >= cur.size():
				break
			var grip := (grp[i] & 1) != 0
			m.pending_reset = (grp[i] & 2) != 0
			m.step_tick(cur[i], grip)
			var v: Vector2 = (m.body_pos - b_prev) * 60.0
			var dv := (v - v_prev).length()
			if j > 0 and j <= 30:
				maxdv = maxf(maxdv, dv)
			if j == 0:
				eng_c = m.a_freelen[k] >= 0.0
				if eng_c:
					tether = m.a_freelen[k]
					chord = m.pos[0].distance_to(m.a_pinpt[k])
					var wlo: int = m.a_pinidx[k] + m.a_wlo[k]
					slack = m.cum_len[wlo] - chord
			if m.a_freelen[k] >= 0.0:
				engaged += 1
				if locked < 0 and m.a_locked[k] >= 0:
					locked = m.a_locked[k]
				var lp := BC.load_pt(m, k)
				var taut: bool = m.pos[0].distance_to(lp) >= float(m.a_freelen[k]) - 0.002
				if arrest < 0 and taut and j > 0:
					arrest = j
					fall = m.body_pos.y - y_pre
					yank = dv
				if arrest >= 0 and j >= arrest + 10 and j <= arrest + 70 and grip and not m.grounded:
					var r := BC.measure(m, k, prev_pos)
					if int(r["fc"]) >= 1:
						sg.append(r["sag"]); kk.append(r["kink"]); sw.append(r["swing"])
			else:
				if j > 0 or not eng_c:
					ended = "hand opened" if not grip else "wrap ended"
					break
			v_prev = v
			b_prev = m.body_pos
			prev_pos = m.pos.duplicate()
		m.free()
		if eng_c:
			n_eng_c += 1
			tethers.append(tether); slacks.append(slack)
			if arrest >= 0:
				arrests.append(arrest); falls.append(fall); yanks.append(yank)
			maxdvs.append(maxdv)
			if not sg.is_empty():
				sags.append(BC.pct(sg, 0.5)); kinks.append(BC.pct(kk, 0.5))
				swings.append(BC.pct(sw, 0.5))
			sag_ticks.append_array(sg); kink_ticks.append_array(kk); swing_ticks.append_array(sw)
			eng_ticks += engaged
			if ended == "held":
				n_hold_w += 1
			elif ended == "hand opened":
				n_open += 1
			else:
				n_ended += 1
			if locked == 1:
				n_locked += 1
		print("%2d  %5d  %d  %-5s  %6.3f  %6.3f  %6.3f | %6s  %7.3f  %8.2f  %7.2f | %5s  %6s  %7s | %5d   %2d     %s"
			% [int(fn.substr(6, 2)), c, k, "yes" if eng_c else "NO", tether, chord, slack,
			("%d" % arrest) if arrest >= 0 else "-", fall, yank, maxdv,
			("%.3f" % BC.pct(sg, 0.5)) if not sg.is_empty() else "-",
			("%.1f" % BC.pct(kk, 0.5)) if not kk.is_empty() else "-",
			("%.2f" % BC.pct(sw, 0.5)) if not sw.is_empty() else "-",
			engaged, locked, ended])
	print("")
	print("SUMMARY over %d catch files: engaged on the catch tick %d, locked %d, held all %d ticks %d, hand opened %d, wrap ended %d, engaged ticks total %d"
		% [files.size(), n_eng_c, n_locked, W, n_hold_w, n_open, n_ended, eng_ticks])
	print("                                   p50      p90      max")
	for row in [["tether at catch (m)", tethers], ["slack given (m)", slacks],
			["arrest tick after catch", arrests], ["fall before arrest (m)", falls],
			["yank at arrest |dv| (m/s)", yanks], ["max |dv| ticks 1-30 (m/s)", maxdvs],
			["sag per catch, p50 of window (m)", sags],
			["kink per catch, p50 of window (deg)", kinks],
			["belly swing per catch, p50 (m/s)", swings],
			["sag, all window ticks (m)", sag_ticks],
			["kink, all window ticks (deg)", kink_ticks],
			["belly swing, all window ticks (m/s)", swing_ticks]]:
		var a: Array = row[1]
		print("  %-38s %7.3f  %7.3f  %7.3f   n=%d" % [String(row[0]), BC.pct(a, 0.5),
			BC.pct(a, 0.9), BC.pct(a, 1.0), a.size()])
	quit(0)
