extends SceneTree
## WHERE WAS THE TIP WHEN THE BELL RANG. Replays a tape with the audio pass
## forced on (aud_gate's idiom: av_touch is populated, the hash is untouched,
## A2 asserts it) and characterises every crack event.
##
##   godot --headless --path . -s res://tests/crack_census.gd -- takes/bug1.tape
const TL := preload("res://tests/tapelib.gd")
const LOOK := 5

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var paths: Array = args if args.size() > 0 else ["takes/bug1.tape"]
	for a in paths:
		_one(String(a))
	quit(0)

func _one(path: String) -> void:
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var t: Dictionary = load("res://main.gd").tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load %s: %s" % [path, t.get("err", "")]); return
	var m := TL.new_sim()
	m.av_on = true
	if not m.restore(t["start"]):
		print("restore refused"); m.free(); return
	m.av_on = true
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var n := cur.size()
	var NP: int = m.NP
	# per-tick records
	var touch: Array = []          # PackedByteArray per tick
	var tips: PackedFloat64Array = PackedFloat64Array()   # sim tip_speed
	var tipv: PackedFloat64Array = PackedFloat64Array()   # tip end-of-tick v
	var fast_i := PackedInt32Array()
	var fast_v := PackedFloat64Array()
	var height := PackedFloat64Array()  # tip clearance over floor_y
	var bang := PackedByteArray()
	var flash0 := 0.0
	var cnt := PackedInt32Array()
	for i in n:
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)
		var tb := PackedByteArray()
		tb.resize(NP)
		var c := 0
		var fi := -1
		var fv := -1.0
		for j in NP:
			tb[j] = m.av_touch[j]
			if tb[j] != 0:
				c += 1
			var v: float = (m.pos[j] - m.prv[j]).length() / m.SDT
			if v > fv:
				fv = v; fi = j
		touch.append(tb)
		cnt.append(c)
		tips.append(m.tip_speed)
		tipv.append((m.pos[NP - 1] - m.prv[NP - 1]).length() / m.SDT)
		fast_i.append(fi)
		fast_v.append(fv)
		var tp: Vector2 = m.pos[NP - 1]
		height.append(TL.floor_y(m, tp.x) - tp.y - m.p_rad[NP - 1])
		var b := 1 if (m.crack_flash >= 1.0 and flash0 < 1.0) else 0
		# parity: the sound edge and the flash edge are the same variable
		bang.append(b)
		flash0 = m.crack_flash
	m.free()

	var nb := 0
	for i in n:
		nb += bang[i]
	var floor20 := 0
	var floor20_bang := 0
	for i in n:
		if cnt[i] >= 20:
			floor20 += 1
			floor20_bang += bang[i]
	print("")
	print("TAPE %s  %d ticks  %d bangs   ticks with >=20 of %d touching: %d (%.0f%%), bangs on those: %d"
		% [path, n, nb, NP, floor20, 100.0 * floor20 / n, floor20_bang])

	# classify each bang
	var kind := {"air": 0, "tip-down-stays": 0, "tip-down-rises": 0,
		"tip-clear-other-down": 0}
	var pass_k := PackedInt32Array()
	pass_k.resize(LOOK + 1)
	var silenced_k := []          # per k: list of ticks silenced
	for k in LOOK + 1:
		silenced_k.append([])
	print("  tick   tip%-4s fast(i,v,touch)  nfloor  h(m)   tipspd  tipv   next5 tip-touch  next5 h        kind" % "tch")
	var rows: Array = []
	for i in n:
		if bang[i] == 0:
			continue
		var tt: int = touch[i][NP - 1]
		var fi := fast_i[i]
		var ft: int = touch[i][fi]
		var nxt := ""
		var nh := ""
		var down_all := true
		var rises := false
		for d in range(1, LOOK + 1):
			if i + d < n:
				var tdn: int = touch[i + d][NP - 1]
				nxt += str(tdn)
				nh += "%.2f " % height[i + d]
				if tdn == 0:
					down_all = false
				if tdn == 0 and height[i + d] > 0.05:
					rises = true
		var kd := ""
		if tt == 0 and cnt[i] == 0:
			kd = "air"
		elif tt == 0:
			kd = "tip-clear-other-down"
		elif down_all:
			kd = "tip-down-stays"
		else:
			kd = "tip-down-rises"
		kind[kd] = int(kind[kd]) + 1
		# what a k-clause (tip clear for the last k ticks incl. this one) does
		for k in range(1, LOOK + 1):
			var clear := true
			for d in k:
				if i - d < 0 or touch[i - d][NP - 1] != 0:
					clear = false
			if clear:
				pass_k[k] += 1
			else:
				silenced_k[k].append(i)
		rows.append([i, tt, fi, fast_v[i], ft, cnt[i], height[i], tips[i],
			tipv[i], nxt, nh, kd])
	for r in rows:
		print("  %5d   %d     %2d %5.1f %d      %2d    %6.2f  %5.1f  %5.1f   %-6s %-30s %s"
			% [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9],
			r[10], r[11]])
	print("  kinds: %s" % str(kind))
	var line := "  clause 'tip clear of terrain for the last k ticks' passes: "
	for k in range(1, LOOK + 1):
		line += "k=%d -> %d/%d   " % [k, pass_k[k], nb]
	print(line)
	# which AIR bangs (tip clear this tick) would k>1 silence
	for k in range(2, LOOK + 1):
		var lost: Array = []
		for i in silenced_k[k]:
			if touch[i][NP - 1] == 0:
				lost.append(i)
		print("  k=%d additionally silences tip-clear bangs at ticks %s" % [k, str(lost)])
	# among tip-down bangs: was any particle the fastest one?
	var fast_is_tip := 0
	for r in rows:
		if r[2] == NP - 1:
			fast_is_tip += 1
	print("  fastest particle at the bang was the tip on %d of %d bangs" % [fast_is_tip, nb])
	# distribution of sim tip_speed vs tip end-of-tick v for the down bangs
	var dn := 0
	var dsum := 0.0
	for r in rows:
		if r[1] == 1:
			dn += 1
			dsum += r[7]
	if dn > 0:
		print("  tip-down bangs: %d, mean sim tip_speed at bang %.1f m/s" % [dn, dsum / dn])
