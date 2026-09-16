extends SceneTree
## HARVEST THE CATCHES off a recorded session: replay the tape, and at every
## tick on which an anchor engages, write the state as it was at the END of the
## PREVIOUS tick (var_to_bytes of snapshot()) to <outdir>/catch_NN.bin with the
## catch tick and the anchor. Another build can then restore that state and
## step the same recorded inputs: same catch, same hand, different tether.
##
##   godot --headless --path . -s res://tests/catch_dump.gd -- takes/bug1.tape <outdir>
const TL := preload("res://tests/tapelib.gd")

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var path: String = args[0]
	var outdir: String = args[1]
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var t: Dictionary = load("res://main.gd").tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load %s: %s" % [path, t.get("err", "")])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(outdir)
	var m := TL.new_sim()
	m.restore(t["start"])
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var was := PackedByteArray()
	was.resize(m.a_pos.size())
	var n := 0
	print("catch  tick   k  pin  wlo  freelen  chord    arc(wlo)  slack   grounded  hand-shut-for")
	for i in cur.size():
		var snap: Dictionary = m.snapshot()
		var grip := (grp[i] & 1) != 0
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], grip)
		for k in m.a_pos.size():
			var e := 1 if m.a_freelen[k] >= 0.0 else 0
			if e == 1 and was[k] == 0:
				var f := FileAccess.open("%s/catch_%02d.bin" % [outdir, n], FileAccess.WRITE)
				f.store_var({"tick": i, "k": k, "snap": snap})
				f.close()
				var wlo: int = m.a_pinidx[k] + m.a_wlo[k]
				var d: float = m.pos[0].distance_to(m.a_pinpt[k])
				print("%3d  %6d  %2d  %3d  %3d  %6.3f  %6.3f  %7.3f  %6.3f   %s   %d"
					% [n, i, k, m.a_pinidx[k], wlo, m.a_freelen[k], d, m.cum_len[wlo],
					m.cum_len[wlo] - d, "yes" if m.grounded else "no",
					m.tick_count - m.grip_edge])
				n += 1
			was[k] = e
	m.free()
	print("%d catches written to %s" % [n, outdir])
	quit(0)
