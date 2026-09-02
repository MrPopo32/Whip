extends SceneTree
## HOW LONG DOES A HANG ACTUALLY LAST, on real recorded human play?
##
##   godot --headless --path . -s res://tests/hang_census.gd -- takes/bug1.tape
##
## A bot rig reported "40 of 41 aims lose the wrap within 5 s", which would mean
## every hang is temporary. The player says he hung past 20 s. A bot throws and
## then holds a synthetic cursor policy; a player keeps working the hand. This
## reads the DURATION of every lock episode in a recorded session, so the claim
## is checked against the only play that is not synthetic.
const TL := preload("res://tests/tapelib.gd")

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var paths: Array = args if args.size() > 0 else ["takes/bug1.tape"]
	for a in paths:
		var path: String = a
		if not path.begins_with("res://") and not path.begins_with("user://"):
			path = "res://" + path
		var t: Dictionary = load("res://main.gd").tape_load(path)
		if not bool(t.get("ok", false)):
			print("cannot load %s: %s" % [path, t.get("err", "")]); continue
		var m := TL.new_sim()
		m.restore(t["start"])
		var cur: PackedVector2Array = t["cur"]
		var grp: PackedByteArray = t["grip"]
		var na: int = m.a_pos.size()
		var lk_start := PackedInt32Array(); lk_start.resize(na); lk_start.fill(-1)
		# THE PLAYER'S OWN HYPOTHESIS, tested: more turns on the beam means more
		# margin above th_part, so the demotion branch never gets near firing.
		var th_lock := PackedFloat32Array(); th_lock.resize(na)
		var th_min := PackedFloat32Array(); th_min.resize(na)
		var th_max := PackedFloat32Array(); th_max.resize(na)
		var was := PackedByteArray(); was.resize(na)
		var eps: Array = []          # [len_ticks, anchor, how_it_ended]
		for i in cur.size():
			var grip := (grp[i] & 1) != 0
			m.pending_reset = (grp[i] & 2) != 0
			m.step_tick(cur[i], grip)
			for k in na:
				var lk: bool = m.a_freelen[k] >= 0.0 and m.a_locked[k] == 1
				var th: float = absf(m.a_theta[k])
				if lk and was[k] == 0:
					lk_start[k] = i
					th_lock[k] = th; th_min[k] = th; th_max[k] = th
				elif lk:
					th_min[k] = minf(th_min[k], th); th_max[k] = maxf(th_max[k], th)
				elif not lk and was[k] == 1:
					var how := "demoted"
					if not grip:
						how = "hand opened"
					elif m.a_freelen[k] < 0.0:
						how = "wrap ended"
					eps.append([i - lk_start[k], k, how, th_lock[k], th_min[k], th_max[k]])
				was[k] = 1 if lk else 0
		for k in na:
			if was[k] == 1:
				eps.append([cur.size() - lk_start[k], k, "still held at end",
					th_lock[k], th_min[k], th_max[k]])
		m.free()
		eps.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
		var tot := 0
		for e in eps:
			tot += int(e[0])
		print("")
		print("TAPE %s   %d ticks   %d lock episodes" % [path, cur.size(), eps.size()])
		if eps.is_empty():
			continue
		print("  longest holds:")
		for i in mini(8, eps.size()):
			var e: Array = eps[i]
			print("    %6.2f s   anchor %-2d  theta at lock %5.2f  min %5.2f  max %6.2f   ended: %s"
				% [float(e[0]) / 60.0, int(e[1]), float(e[3]), float(e[4]), float(e[5]),
				String(e[2])])
		var over5 := 0
		var over10 := 0
		var over20 := 0
		for e in eps:
			if float(e[0]) / 60.0 >= 5.0: over5 += 1
			if float(e[0]) / 60.0 >= 10.0: over10 += 1
			if float(e[0]) / 60.0 >= 20.0: over20 += 1
		print("  median %.2f s   mean %.2f s   total locked %.1f s"
			% [float(eps[eps.size() / 2][0]) / 60.0,
			float(tot) / 60.0 / float(eps.size()), float(tot) / 60.0])
		print("  holds lasting >= 5 s: %d of %d      >= 10 s: %d      >= 20 s: %d"
			% [over5, eps.size(), over10, over20])
		var ends := {}
		for e in eps:
			var h := String(e[2])
			ends[h] = int(ends.get(h, 0)) + 1
		print("  how they ended: %s" % str(ends))
		# turns on the beam, for the long holds against the ones that betrayed
		var long_th := 0.0; var long_n := 0
		var dem_th := 0.0; var dem_n := 0
		for e in eps:
			if String(e[2]) == "demoted" or String(e[2]) == "wrap ended":
				dem_th += float(e[3]); dem_n += 1
			elif float(e[0]) / 60.0 >= 3.0:
				long_th += float(e[3]); long_n += 1
		if long_n > 0:
			print("  MEAN THETA AT LOCK: holds over 3 s = %.2f rad (%.2f turns), n=%d"
				% [long_th / float(long_n), long_th / float(long_n) / TAU, long_n])
		if dem_n > 0:
			print("                      ones that BETRAYED  = %.2f rad (%.2f turns), n=%d"
				% [dem_th / float(dem_n), dem_th / float(dem_n) / TAU, dem_n])
	quit(0)
