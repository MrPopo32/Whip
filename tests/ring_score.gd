extends SceneTree
## WHICH RING PREDICATE TELLS THE TRUTH? Scored against real play, not argued.
##
##   godot --headless --path . -s res://tests/ring_score.gd -- takes/bug1.tape tapes/school.tape ...
##
## THE ORACLE, and it needs no judgement: a ring that says "it holds" is right
## if the wrap is STILL THERE a while later AND THE PLAYER NEVER OPENED THEIR
## HAND. Opening your hand is release, not betrayal - those samples are dropped
## rather than counted against the ring, which is the whole reason this can be
## scored at all.
##
## Two numbers per candidate, and they pull against each other:
##   TRUST    of the ticks it called green, how many survived N ticks
##   REACH    of the ticks that WERE locked and held, how many it called green
## A predicate that says green to nothing scores 100% trust and 0% reach; the
## shipped one is close to that. A predicate that says green to everything
## scores full reach and whatever the base rate is.
const TL := preload("res://tests/tapelib.gd")
const HORIZON := [30, 90, 240]

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if args.is_empty():
		args = ["takes/bug1.tape"]
	var names := ["A shipped: locked + tail past pin",
		"B locked (drop the tail check)",
		"C locked and (theta >= th_part or pinch)",
		"D locked and pinch right now"]
	var tot_green := []
	var tot_hold := []
	var tot_reach := []
	var locked_held := 0
	for _i in 4:
		tot_green.append([0, 0, 0]); tot_hold.append([0, 0, 0]); tot_reach.append(0)
	for a in args:
		var path: String = a
		if not path.begins_with("res://") and not path.begins_with("user://"):
			path = "res://" + path
		var t: Dictionary = load("res://main.gd").tape_load(path)
		if not bool(t.get("ok", false)):
			print("skip %s (%s)" % [path, t.get("err", "")]); continue
		var m := TL.new_sim()
		m.restore(t["start"])
		var cur: PackedVector2Array = t["cur"]
		var grp: PackedByteArray = t["grip"]
		var na: int = m.a_pos.size()
		# record, per tick, per anchor: engaged+locked, and each predicate
		var eng := []
		var pred := []
		var grip := PackedByteArray()
		for i in cur.size():
			m.pending_reset = (grp[i] & 2) != 0
			m.step_tick(cur[i], (grp[i] & 1) != 0)
			grip.append(grp[i] & 1)
			var e := PackedByteArray(); e.resize(na)
			var p := PackedByteArray(); p.resize(na * 4)
			for k in na:
				var on: bool = m.a_freelen[k] >= 0.0
				var lk: bool = on and m.a_locked[k] == 1
				e[k] = 1 if lk else 0
				var pinch: bool = m._pinch(k) if on else false
				var th: float = absf(m.a_theta[k])
				p[k * 4 + 0] = 1 if m._holds(k) else 0
				p[k * 4 + 1] = 1 if lk else 0
				p[k * 4 + 2] = 1 if (lk and (th >= m.th_part or pinch)) else 0
				p[k * 4 + 3] = 1 if (lk and pinch) else 0
			eng.append(e); pred.append(p)
		var n := eng.size()
		for i in n:
			for k in na:
				for hi in HORIZON.size():
					var h: int = HORIZON[hi]
					if i + h >= n:
						continue
					# censor: the hand must stay closed for the whole horizon
					var held := true
					for j in range(i, i + h + 1):
						if grip[j] == 0:
							held = false; break
					if not held:
						continue
					var survived: bool = (eng[i + h] as PackedByteArray)[k] == 1
					for c in 4:
						if (pred[i] as PackedByteArray)[k * 4 + c] == 1:
							tot_green[c][hi] = int(tot_green[c][hi]) + 1
							if survived:
								tot_hold[c][hi] = int(tot_hold[c][hi]) + 1
				# REACH, measured on the middle horizon only
				var h1: int = HORIZON[1]
				if i + h1 < n:
					var held2 := true
					for j in range(i, i + h1 + 1):
						if grip[j] == 0:
							held2 = false; break
					if held2 and (eng[i] as PackedByteArray)[k] == 1 \
							and (eng[i + h1] as PackedByteArray)[k] == 1:
						locked_held += 1
						for c in 4:
							if (pred[i] as PackedByteArray)[k * 4 + c] == 1:
								tot_reach[c] = int(tot_reach[c]) + 1
		m.free()
		print("scored %s (%d ticks)" % [path, n])
	print("")
	print("  %-42s %s" % ["", "TRUST: of the ticks called green, survived"])
	print("  %-42s %8s %8s %8s   REACH" % ["candidate", "0.5 s", "1.5 s", "4 s"])
	for c in 4:
		var row := "  %-42s" % names[c]
		for hi in HORIZON.size():
			var g: int = int(tot_green[c][hi])
			row += " %7s" % ("%.1f%%" % (100.0 * float(tot_hold[c][hi]) / maxf(float(g), 1.0)) if g > 0 else "-")
			row += ""
		row += "   %5.1f%%" % (100.0 * float(tot_reach[c]) / maxf(float(locked_held), 1.0))
		print(row)
	print("")
	print("  base: %d anchor-ticks were locked AND still locked 1.5 s later with" % locked_held)
	print("  the hand never opening. REACH is the share of those called green.")
	quit(0)
