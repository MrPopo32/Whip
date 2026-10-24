extends SceneTree
## THE NULLS for the swing bench (climb_swing_lib.gd):
##  N1 a zero-noise attempt is bit-identical to bot_leap.leap_step flown from
##     the same release snapshot (same catch, same hash 55 held ticks later)
##  N2 a hand_noise "null" tier instance is bit-identical to no noise at all
##  N3 the hand never closes -> nothing is ever caught (must report 0)
##  N4 the stroke never fires -> what the swing alone catches (must be ~0)
##   godot --headless --path . -s res://tests/climb_swing_null.gd
const SW := preload("res://tests/climb_swing_lib.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const HN := preload("res://tests/hand_noise.gd")

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var b = SW.new(0.10)
	var w: Dictionary = b.pump_window(180.0, [0.0])
	var sn: Array = w["snaps"]
	print("window ok %s fwd %.0f snaps %d k0 %d" % [w["ok"], w["amp_fwd"], sn.size(), w["k0"]])
	var n := 0
	var mism := 0
	var nc := 0
	var n2 := 0
	var nc3 := 0
	var nc4 := 0
	var cells := [[7.8, 0.0], [6.0, 2.0], [5.0, 4.0]]
	for cell in cells:
		var dx: float = cell[0]
		var dy: float = cell[1]
		for ki in range(int(w["k0"]) + 3, sn.size() - 5, 6):
			var p: Dictionary = SW.stroke(-0.5, 38, 4, 18)
			var r1: Dictionary = b.attempt(w, ki, dx, dy, p)
			n += 1
			if bool(r1["caught"]): nc += 1
			var e: Dictionary = sn[ki]
			b.m.restore(e["snap"])
			b.m.a_pos[1] = Vector2(dx, -dy)
			var pp := p.duplicate()
			pp["rel"] = 0.0
			var st: Dictionary = LEAP.leap_begin(b.m, 0, 1, pp)
			st["half"] = 999
			var prev: Vector2 = e["prev"]
			var g := 0
			var rel_seen := -1
			while st["phase"] != "fail" and st["phase"] != "hang" and g < 400:
				var cg: Array = LEAP.leap_step(b.m, st, prev)
				if st["phase"] == "fly" and rel_seen < 0:
					rel_seen = g
				prev = b.m.body_pos
				b.m.step_tick(cg[0], cg[1])
				g += 1
				if st["phase"] == "fly" and b.m.body_pos.y > -dy + 6.5 and b.m.body_pos.y - prev.y > 0.0:
					break
				if st["phase"] == "fly" and int(st["closes"]) == 0 and int(st["f"]) > int(st["s0"]) + 91:
					break
			var caught2: bool = st["phase"] == "hang"
			if caught2 and b.m.a_freelen[1] >= 0.0:
				# the lib stops holding the tick the wrap is lost; so does this
				for t in 54:
					var cg2: Array = LEAP.leap_step(b.m, st, prev)
					prev = b.m.body_pos
					b.m.step_tick(cg2[0], cg2[1])
					if b.m.a_freelen[1] < 0.0:
						break
			var same: bool = rel_seen == 0 and caught2 == bool(r1["caught"]) and (not caught2 or b.m.state_hash() == int(r1["hash"]))
			if not same:
				mism += 1
				print("  N1 MISMATCH (%.1f,%.1f) ki %d lib caught %s leap caught %s rel_at %d" % [dx, dy, ki, r1["caught"], caught2, rel_seen])
			# N2
			var r2: Dictionary = b.attempt(w, ki, dx, dy, p, HN.new("null", "n2", ki), HN.new("null", "n2g", ki))
			if int(r2["hash"]) == int(r1["hash"]) and bool(r2["caught"]) == bool(r1["caught"]):
				n2 += 1
			# N3, N4
			var r3: Dictionary = b.attempt(w, ki, dx, dy, p, null, null, 0, true)
			if bool(r3["caught"]): nc3 += 1
			var r4: Dictionary = b.attempt(w, ki, dx, dy, p, null, null, 0, false, true)
			if bool(r4["caught"]): nc4 += 1
	print("N1 lib vs bot_leap.leap_step: %d attempts, %d caught, %d mismatches (must be 0)" % [n, nc, mism])
	print("N2 null-tier noise identical to no noise: %d / %d (must be all)" % [n2, n])
	print("N3 hand never closes: %d caught of %d (must be 0)" % [nc3, n])
	print("N4 stroke never fires: %d caught of %d" % [nc4, n])
	print("(%d s)" % ((Time.get_ticks_msec() - t0) / 1000))
	b.free_sim()
	quit(0)
