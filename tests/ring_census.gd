extends SceneTree
## DOES THE RING TELL THE TRUTH? Replays a tape and counts, over every wrap the
## player actually made, how often the LOCK the sim granted was ever shown as
## the GREEN the player was told to read.
##
##   godot --headless --path . -s res://tests/ring_census.gd -- takes/bug1.tape
##
## _holds() is stricter than a_locked == 1: it also demands enough tail past the
## pin for the crossing to be real. So a catch made near the TIP locks, carries
## the player, and is drawn amber the whole time. This counts that.
const TL := preload("res://tests/tapelib.gd")

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var path: String = args[0] if args.size() > 0 else "takes/bug1.tape"
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var t: Dictionary = load("res://main.gd").tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load %s: %s" % [path, t.get("err", "")])
		quit(1); return
	var m := TL.new_sim()
	m.restore(t["start"])
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var na: int = m.a_pos.size()
	var was_lk := PackedByteArray(); was_lk.resize(na)
	var ever_green := PackedByteArray(); ever_green.resize(na)
	var lk_ticks := PackedInt32Array(); lk_ticks.resize(na)
	var gr_ticks := PackedInt32Array(); gr_ticks.resize(na)
	var pin_at_lock := PackedInt32Array(); pin_at_lock.resize(na)
	# per lock episode
	var locks := 0
	var locks_green := 0
	var silent: Array = []          # locks that were NEVER drawn green
	var lk_tick_total := 0
	var gr_tick_total := 0
	for i in cur.size():
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)
		for k in na:
			var lk: bool = m.a_freelen[k] >= 0.0 and m.a_locked[k] == 1
			var hd: bool = m._holds(k)
			if lk:
				lk_ticks[k] += 1
				lk_tick_total += 1
			if hd:
				gr_ticks[k] += 1
				gr_tick_total += 1
			if lk and was_lk[k] == 0:
				locks += 1
				ever_green[k] = 0
				pin_at_lock[k] = int(m.a_pinidx[k])
			if lk and hd:
				ever_green[k] = 1
			if not lk and was_lk[k] == 1:
				if ever_green[k] == 1:
					locks_green += 1
				else:
					silent.append([i, k, float(m.a_r[k]), int(pin_at_lock[k])])
			was_lk[k] = 1 if lk else 0
	for k in na:
		if was_lk[k] == 1:
			if ever_green[k] == 1:
				locks_green += 1
			else:
				silent.append([cur.size(), k, float(m.a_r[k]), int(pin_at_lock[k])])
	print("")
	print("TAPE %s   %d ticks" % [path, cur.size()])
	print("  lock episodes                     %d" % locks)
	print("  ...ever drawn GREEN               %d" % locks_green)
	print("  ...NEVER drawn green (amber)      %d   <- the ring said 'it will betray'"
		% (locks - locks_green))
	print("  ticks held LOCKED                 %d" % lk_tick_total)
	print("  ticks drawn GREEN                 %d  (%.0f%% of locked ticks)"
		% [gr_tick_total, 100.0 * float(gr_tick_total) / maxf(float(lk_tick_total), 1.0)])
	if silent.size() > 0:
		print("")
		print("  THE SILENT LOCKS - held the player, never went green:")
		print("    ended    beam   r      pin at lock   tail      green needs")
		for s in silent:
			var p: int = int(s[3])
			var tail := 0.0
			for j in range(p, m.NP - 1):
				tail += float(m.rest[j])
			var need: float = m.PINCH_TURN * TAU * (float(s[2]) + 0.02)
			print("    %6d   A%-4d  %.2f   %2d            %.3f m   %.3f m"
				% [int(s[0]), int(s[1]), float(s[2]), p, tail, need])
	m.free()
	quit(0)
