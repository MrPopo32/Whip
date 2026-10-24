extends SceneTree
## MOVE 4 - THE DOOR UP, end to end, mapped. World and origin: see
## tests/climb_door_lib.gd (x = 0 the F0 lip face, y = 0 the F0 floor; every
## printed height is UP metres).
##
## ONE PUMP, MANY RELEASES. Per (world, catch, pump target): the catch is
## THROWN from a standstill on F0 (never laid), the swing is pumped with
## bot_pump's servo for PUMP ticks, and the sim is snapshotted on every tick
## the body moves toward +x. Every snapshot is a release candidate: restore,
## open the hand, fly, classify. A ballistic forecast of the body centre picks
## which candidates to fly (it lands within 1.5 m of the ledge's span) and each
## pick is widened by +/-4 ticks, so every window's EDGES are flown ticks that
## failed, never forecasts. mode "full" flies every +x tick instead - the
## check that the forecast hides nothing.
##
##   -- cell G h D far catch target [pump] [groups] [full]
##   -- noise G h D far catch target tmin theta N tier
##   -- nulls
const DL := preload("res://tests/climb_door_lib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PUMP := preload("res://tests/bot_pump.gd")

# The standing locks found by climb_door_explore.gd on F0 (lead m, grid36 idx).
# 1.8 m/idx 24 (a0 1.10pi a1 -0.30pi sd 5 push) locks at tether 1.45 m and
# pumps over the top by tick 108; 1.8/idx 9 (a0 0.85pi a1 -0.30pi sd 9 pull)
# at 1.33 m, over by tick 102. The 1.76-2.03 m locks swing back onto F0 and
# stand there (1086 of 1500 ticks grounded); 2.75 m loses the beam in 85.
const CATCH := {"A": [1.8, 24], "B": [1.8, 9], "C": [2.2, 24]}

func catch_of(id: String) -> Dictionary:
	var e: Array = CATCH[id]
	return {"lead": float(e[0]), "c": DL.grid36()[int(e[1])], "id": id}

func throw_in(m: Node2D, cc: Dictionary, hn: RefCounted, never := false) -> Dictionary:
	m._reset()
	var c: Dictionary = cc["c"]
	DL.stand(m, DL.DOOR.x - float(cc["lead"]), 0.0, float(c["a0"]))
	return DL.throw(m, 0, c, hn, false, never)

static func runs_of(s: String, ch: String) -> Array:
	var out: Array = []
	var i := 0
	while i < s.length():
		if s[i] == ch:
			var j := i
			while j + 1 < s.length() and s[j + 1] == ch:
				j += 1
			out.append([i, j - i + 1])
			i = j + 1
		else:
			i += 1
	return out

func do_cell(a: Array) -> void:
	var G := float(a[1]); var h := float(a[2]); var D := float(a[3])
	var far := String(a[4])
	var cc := catch_of(String(a[5]))
	var T := float(a[6])
	var npump := 480 if a.size() < 8 else int(a[7])
	var gmax := 4 if a.size() < 9 else int(a[8])
	var full := a.size() >= 10 and String(a[9]) == "full"
	var t0 := Time.get_ticks_msec()
	var m: Node2D = DL.make(G, h, D, true, [], far)
	var hn := HN.new("null", "cell", 0)
	var r: Dictionary = throw_in(m, cc, hn)
	var tag := "G %.1f h %.1f D %.1f %s | %s T %3.0f" % [G, h, D, far,
		String(cc["id"]), T]
	if not bool(r["lock"]):
		print("CELL %s | NO LOCK (caught %s)" % [tag, str(r["caught"])])
		m.free()
		return
	DL.haul(m, 0)
	var prev: Vector2 = m.body_pos
	var snaps: Array = []        # [t, snap, deg, v, pos, cand]
	var peak := 0.0
	var over := -1
	var thu := DL.body_deg(m, 0)
	var thp := thu
	var lost := -1
	for t in npump:
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, T)
		prev = m.body_pos
		m.step_tick(cur, true)
		if float(m.a_freelen[0]) < 0.0:
			lost = t
			break
		var th := DL.body_deg(m, 0)
		var d := th - thp
		if d > 180.0: d -= 360.0
		elif d < -180.0: d += 360.0
		thp = th
		thu += d
		if absf(thu) > 180.0 and over < 0:
			over = t
		peak = maxf(peak, absf(th))
		var v: Vector2 = (m.body_pos - prev) * 60.0
		if v.x > 0.0 and t >= 10:
			var xl := DL.ballistic_land(m.body_pos, v, h, m.BODY_R)
			var cand := not is_nan(xl) and xl > G - 1.5 and xl < G + DL.LEDGE_W + 1.5
			snaps.append([t, m.snapshot(), th, v, m.body_pos, cand, peak])
	# widen every forecast pick by +/-4 consecutive stored ticks
	var fly_idx := {}
	for i in snaps.size():
		if full or bool(snaps[i][5]):
			for j in range(i - 4, i + 5):
				if j >= 0 and j < snaps.size() and absi(int(snaps[j][0]) - int(snaps[i][0])) <= 4:
					fly_idx[j] = true
	var keys: Array = fly_idx.keys()
	keys.sort()
	# groups = runs of consecutive stored ticks
	var groups: Array = []
	for i: int in keys:
		if groups.is_empty() or int(snaps[i][0]) - int(snaps[(groups[-1] as Array)[-1]][0]) > 1:
			groups.append([i])
		else:
			(groups[-1] as Array).append(i)
	var ncand := 0
	for e: Array in snaps:
		if bool(e[5]): ncand += 1
	print("CELL %s | tether %.2f | pumped %d t, over at %d, lost %d, +x ticks %d, forecast picks %d, groups %d"
		% [tag, float(r["tether"]), npump, over, lost, snaps.size(), ncand, groups.size()])
	var gi := 0
	var total_L := 0
	var best_w := 0
	for g: Array in groups:
		if gi >= gmax:
			break
		gi += 1
		var s := ""
		var fc := ""
		var outs: Array = []
		var dx := ""
		for i: int in g:
			fc += "c" if bool(snaps[i][5]) else "."
			m.restore(snaps[i][1])
			var o: Dictionary = DL.fly(m, G, h, D, true)
			s += DL.code(String(o["where"]))
			outs.append(o)
			var xl0 := DL.ballistic_land(snaps[i][4], snaps[i][3], h, m.BODY_R)
			if full and not is_nan(xl0):
				dx += "%.1f/%.1f " % [xl0, float(o["x"])]
		var rl := runs_of(s, "L")
		var bw := 0
		var bi := -1
		for q: Array in rl:
			if int(q[1]) > bw:
				bw = int(q[1]); bi = int(q[0]) + int(q[1]) / 2
		total_L += s.count("L")
		best_w = maxi(best_w, bw)
		var i0: int = g[0]
		var line := "  grp %d ticks %d..%d peak-so-far %3.0f | %s | widest L run %d" % [
			gi, int(snaps[i0][0]), int(snaps[g[-1]][0]), float(snaps[i0][6]), s, bw]
		if bi >= 0:
			var e: Array = snaps[g[bi]]
			var o: Dictionary = outs[bi]
			var v: Vector2 = e[3]
			var p: Vector2 = e[4]
			line += " | mid t %d deg %+.0f at (%.2f,%+.2f up) v %.1f m/s @ %+.0f deg, peak feet %.2f up, lands x %.2f stops x %.2f" % [
				int(e[0]), float(e[2]), p.x, -p.y, v.length(),
				rad_to_deg(atan2(-v.y, v.x)), float(o["maxup"]), float(o["x"]),
				float(o.get("x_final", o["x"]))]
			# edges in degrees, for the builder: first and last L of the run
			var q0 := -1
			var q1 := -1
			for k in s.length():
				if k <= bi and s[k] == "L" and (k == 0 or s[k - 1] != "L"):
					q0 = k
			for k in range(bi, s.length()):
				if s[k] == "L":
					q1 = k
				else:
					break
			line += " | window deg %+.0f..%+.0f" % [float(snaps[g[q0]][2]),
				float(snaps[g[q1]][2])]
		print(line)
		print("        forecast %s" % fc)
		if full and dx != "":
			print("        ballistic/actual x: %s" % dx)
	print("CELLSUM %s | L ticks %d | widest %d | %.0f s" % [tag, total_L, best_w,
		(Time.get_ticks_msec() - t0) / 1000.0])
	m.free()

## THE WHOLE SEQUENCE UNDER A HAND. Throw with the noise tier (offset, tremor,
## speed, press +/-jit), pump with that hand's tremor on the cursor, and let go
## when the body crosses theta* (deg, body angle about the beam, moving +x) at
## the first crossing after tick tmin of the pump - plus the hand's own
## release timing error, a SECOND +/-jit draw. A negative error releases from
## a buffered earlier tick: the hand opened before the crossing.
func do_noise(a: Array) -> void:
	var G := float(a[1]); var h := float(a[2]); var D := float(a[3])
	var far := String(a[4])
	var cc := catch_of(String(a[5]))
	var T := float(a[6])
	var tmin := int(a[7])
	var ths: Array = []
	for q in String(a[8]).split(","):
		ths.append(float(q))
	var N := int(a[9])
	var tier := String(a[10])
	var s0 := 0 if a.size() < 12 else int(a[11])
	var t0 := Time.get_ticks_msec()
	var m: Node2D = DL.make(G, h, D, true, [], far)
	var tag := "G %.1f h %.1f D %.1f %s | %s T %3.0f tmin %d" % [G, h, D, far,
		String(cc["id"]), T, tmin]
	var res := {}
	for th in ths:
		res[th] = {"ok": 0, "hist": {}, "pit": []}
	var nlock := 0
	for s in range(s0, s0 + N):
		var hn := HN.new(tier, "door4/" + String(cc["id"]), s)
		var r: Dictionary = throw_in(m, cc, hn)
		if not bool(r["lock"]):
			for th in ths:
				var hh: Dictionary = res[th]["hist"]
				hh["nolock"] = int(hh.get("nolock", 0)) + 1
			continue
		nlock += 1
		DL.haul(m, 0)
		var hp := HN.new(tier, "door4pump/" + String(cc["id"]), s)
		var hr := HN.new(tier, "door4rel/" + String(cc["id"]), s)
		var jit: int = int(hr.jit)
		# pump to tmin, then keep a buffer and watch for each theta* crossing
		var prev: Vector2 = m.body_pos
		for t in tmin:
			var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, T) + hp.tick()
			prev = m.body_pos
			m.step_tick(cur, true)
		var S: Dictionary = m.snapshot()
		var hps: Dictionary = hp.save_state()
		var prevS := prev
		for th in ths:
			m.restore(S)
			hp.restore_state(hps)
			prev = prevS
			var u := Vector2(sin(deg_to_rad(th)), cos(deg_to_rad(th)))
			var buf: Array = []
			var sprev := 0.0
			var fired := -1
			var extra := 0
			var released := false
			for t in 400:
				var rv: Vector2 = m.body_pos - Vector2(m.a_pos[0])
				var cr: float = rv.x * u.y - rv.y * u.x
				var v: Vector2 = (m.body_pos - prev) * 60.0
				if fired < 0 and t > 0 and rv.dot(u) > 0.0 and v.x > 0.0 \
						and signf(cr) != signf(sprev) and sprev != 0.0:
					fired = t
					if jit <= 0:
						var back := -jit
						if back > 0 and buf.size() >= back:
							m.restore(buf[buf.size() - back])
						released = true
						break
					extra = jit
				sprev = cr
				if fired >= 0:
					if extra <= 0:
						released = true
						break
					extra -= 1
				buf.append(m.snapshot())
				if buf.size() > 4:
					buf.pop_front()
				var cur2: Vector2 = PUMP.pump_cursor(m, 0, prev, T) + hp.tick()
				prev = m.body_pos
				m.step_tick(cur2, true)
				if float(m.a_freelen[0]) < 0.0:
					break
			var hh2: Dictionary = res[th]["hist"]
			if not released:
				hh2["noflash"] = int(hh2.get("noflash", 0)) + 1
				continue
			var o: Dictionary = DL.fly(m, G, h, D, false, 420)
			var w := String(o["where"])
			hh2[w] = int(hh2.get(w, 0)) + 1
			if w == "LEDGE":
				res[th]["ok"] = int(res[th]["ok"]) + 1
			elif w == "PIT":
				(res[th]["pit"] as Array).append("%.1f" % float(o["x"]))
	for th in ths:
		print("NOISE %s | %s | theta* %+.0f | P %d/%d (locks %d) | %s | pit x [%s]"
			% [tag, tier, th, int(res[th]["ok"]), N, nlock, str(res[th]["hist"]),
			",".join(res[th]["pit"])])
	print("NOISEDONE %s %.0f s" % [tag, (Time.get_ticks_msec() - t0) / 1000.0])
	m.free()

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	match String(a[0]):
		"cell":
			do_cell(a)
		"noise":
			do_noise(a)
	quit(0)
