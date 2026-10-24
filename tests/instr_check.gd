extends "res://tests/learn_probe.gd"
## ADVERSARIAL CHECK OF THE INSTRUMENT in tests/learn_probe.gd + hand_noise.gd.
## Extends the probe so the reproducibility checks go through ITS one().
##
##   godot --headless --path . -s res://tests/instr_check.gd -- [noise|sim|hold|tip|all] [N]
##
## noise: the emitted cursor's sd, lag autocorrelation and periodogram vs the
##        AR(1) theory; the POST-CLAMP noise the sim actually sees at REACH
## sim:   same (tier,tag,sample) twice, interleaved with other throws, and
##        again from a brand-new MAIN instance -> one hash; null unchanged
##        after noisy throws
## hold:  the verdict at 55 ticks vs 120 vs 240 ticks of hold; LOCKED at the
##        catch tick vs HELD-and-locked later
## tip:   a 1e-6 m cursor offset -> tip separation over the stroke (chaos)

const BEAM_C := {"a0": PI * 1.10, "a1": -PI * 0.42, "sd": 9, "pull": false,
	"w": 120, "lead": 1.6}
const THIN_C := {"a0": PI * 0.85, "a1": -PI * 0.42, "sd": 9, "pull": true,
	"w": 120, "lead": 1.6}

# ------------------------------------------------------------------ noise ---
func check_noise() -> void:
	print("")
	print("NOISE MODEL - what hand_noise.gd actually emits (no sim)")
	var alpha := exp(-2.0 * PI * 5.0 / 60.0)
	print("  AR(1) pole claimed %.4f" % alpha)
	for tn in ["mouse03", "mouse1", "trackpad"]:
		var L := 4096
		var S := 10
		var sx := 0.0
		var n := 0
		var lags := [1, 2, 3, 6, 12, 30]
		var acc := {}
		for l in lags:
			acc[l] = 0.0
		var xs: Array = []
		var ox := 0.0
		var oy := 0.0
		var ox2 := 0.0
		var oy2 := 0.0
		var big := 0
		var nb := 0
		# offset distribution over 2000 draws
		for i in 2000:
			var h := HN.new(tn, "ospec", i)
			ox += h.offset.x
			oy += h.offset.y
			ox2 += h.offset.x * h.offset.x
			oy2 += h.offset.y * h.offset.y
			var sig := float(h.tier["off"]) * HN.M_PER_PX
			if absf(h.offset.x) > 2.0 * sig:
				big += 1
			if absf(h.offset.y) > 2.0 * sig:
				big += 1
			nb += 2
		# tremor streams
		for s in S:
			var h := HN.new(tn, "tspec", s)
			var seq := PackedFloat64Array()
			for t in L:
				var e: Vector2 = h.tick() - h.offset
				seq.push_back(e.x)
				sx += e.x * e.x + e.y * e.y
				n += 2
			xs.append(seq)
		var v := sx / float(n)
		for l in lags:
			var c := 0.0
			var cn := 0
			for seq in xs:
				for t in range(l, L):
					c += seq[t] * seq[t - l]
					cn += 1
			acc[l] = c / float(cn) / v
		print("  %-9s tremor sd %.2f mm/axis (set %.2f)  offset sd x %.2f y %.2f mm mean %.2f %.2f  |off|>2sd %.1f%% (gauss 4.6%%)" % [
			tn, sqrt(v) * 1000.0, float(HN.TIERS[tn]["trem"]) * HN.M_PER_PX * 1000.0,
			sqrt(ox2 / 2000.0) * 1000.0, sqrt(oy2 / 2000.0) * 1000.0,
			ox / 2000.0 * 1000.0, oy / 2000.0 * 1000.0,
			100.0 * float(big) / float(nb)])
		var s1 := "    autocorr lag:"
		var s2 := "    measured    :"
		var s3 := "    AR(1) theory:"
		for l in lags:
			s1 += "%7d" % l
			s2 += "%7.3f" % float(acc[l])
			s3 += "%7.3f" % pow(alpha, l)
		print(s1)
		print(s2)
		print(s3)
		# periodogram: 512-sample blocks, Hann window, averaged; relative to
		# theory S(f)/S(0) = (1-a)^2 / (1 - 2a cos w + a^2)
		var B := 512
		var freqs := [0.0, 1.0, 2.0, 3.0, 5.0, 7.5, 10.0, 15.0, 20.0, 30.0]
		var pw := {}
		for f in freqs:
			pw[f] = 0.0
		var nblk := 0
		for seq in xs:
			var b0 := 0
			while b0 + B <= L:
				for f in freqs:
					var re := 0.0
					var im := 0.0
					var w := 2.0 * PI * float(f) / 60.0
					for t in B:
						var win := 0.5 - 0.5 * cos(2.0 * PI * float(t) / float(B))
						var x: float = seq[b0 + t] * win
						re += x * cos(w * float(t))
						im -= x * sin(w * float(t))
					pw[f] = float(pw[f]) + re * re + im * im
				nblk += 1
				b0 += B
		var p0 := float(pw[0.0])
		var f1 := "    Hz          :"
		var f2 := "    measured dB :"
		var f3 := "    AR(1) dB    :"
		for f in freqs:
			var w := 2.0 * PI * float(f) / 60.0
			var th := (1.0 - alpha) * (1.0 - alpha) / (1.0 - 2.0 * alpha * cos(w) + alpha * alpha)
			f1 += "%7.1f" % float(f)
			f2 += "%7.1f" % (10.0 * log(float(pw[f]) / p0) / log(10.0))
			f3 += "%7.1f" % (10.0 * log(th) / log(10.0))
		print(f1)
		print(f2)
		print(f3)
		print("    (%d blocks of %d; Hann windowed; -3 dB at 5 Hz is the claim)" % [nblk, B])
	# THE CLAMP. main.gd: target_m = body + (cursor - body).limit_length(REACH).
	# The stroke commands the hand AT REACH (amp 1.0), so noise pointing OUT is
	# thrown away. What is the sd of the noise the sim actually sees?
	print("")
	print("POST-CLAMP NOISE - the stroke commands |hand| = REACH exactly; main.gd")
	print("limit_length(REACH) clips everything outward. Noise the sim sees, mouse1:")
	var R := 1.15
	for amp in [1.0, 0.7]:
		var dir := Vector2(cos(-PI * 0.42), sin(-PI * 0.42))
		var base := dir * R * float(amp)
		var rr := 0.0
		var rr_c := 0.0
		var tt := 0.0
		var tt_c := 0.0
		var mr := 0.0
		var clipped := 0
		var cnt := 0
		for s in 20:
			var h := HN.new("mouse1", "clamp", s)
			for t in 300:
				var e: Vector2 = h.tick()
				var cl: Vector2 = (base + e).limit_length(R) - base
				var er := e.dot(dir)
				var et := e.dot(Vector2(-dir.y, dir.x))
				var cr := cl.dot(dir)
				var ct := cl.dot(Vector2(-dir.y, dir.x))
				rr += er * er
				rr_c += cr * cr
				tt += et * et
				tt_c += ct * ct
				mr += cr
				if (base + e).length() > R + 1e-9:
					clipped += 1
				cnt += 1
		print("  amp %.1f: raw radial sd %.1f mm -> seen %.1f mm (mean %+.1f); tangential raw %.1f -> seen %.1f mm; clipped %.0f%% of ticks" % [
			float(amp), sqrt(rr / cnt) * 1000.0, sqrt(rr_c / cnt) * 1000.0,
			mr / cnt * 1000.0, sqrt(tt / cnt) * 1000.0, sqrt(tt_c / cnt) * 1000.0,
			100.0 * float(clipped) / float(cnt)])

# -------------------------------------------------------------------- sim ---
func check_sim() -> void:
	print("")
	print("REPRODUCIBILITY / ORDER - through learn_probe.one() itself")
	var st := station("beam")
	var c := BEAM_C
	var n0 := one(st, 1.6, c, "null", "z", 0)
	var r1 := one(st, 1.6, c, "mouse1", "rep", 7)
	var x1 := one(st, 1.6, c, "trackpad", "rep", 3)
	var x2 := one(st, 1.6, c, "mouse1", "rep", 8)
	var r2 := one(st, 1.6, c, "mouse1", "rep", 7)
	var n1 := one(st, 1.6, c, "null", "z", 0)
	print("  mouse1 rep#7 first : hash %d green %s caught %s j %d speed %.3f off %s" % [
		int(r1["hash"]), str(r1["green"]), str(r1["caught"]), int(r1["j"]), float(r1["speed"]), str(r1["off"])])
	print("  mouse1 rep#7 again : hash %d green %s  (after trackpad#3, mouse1#8)  %s" % [
		int(r2["hash"]), str(r2["green"]), "SAME" if int(r1["hash"]) == int(r2["hash"]) else "DIFFERENT"])
	print("  null before %d / after noisy throws %d  %s" % [int(n0["hash"]), int(n1["hash"]),
		"SAME" if int(n0["hash"]) == int(n1["hash"]) else "DIFFERENT"])
	print("  distinct among {rep#7, tp#3, rep#8, null}: %d (expect 4)" % [
		{int(r1["hash"]): 1, int(x1["hash"]): 1, int(x2["hash"]): 1, int(n0["hash"]): 1}.size()])
	# brand-new MAIN instance instead of the restored one
	for lv in sims:
		sims[lv].free()
	sims.clear()
	fresh.clear()
	var r3 := one(st, 1.6, c, "mouse1", "rep", 7)
	var n2 := one(st, 1.6, c, "null", "z", 0)
	print("  fresh MAIN.new(): rep#7 hash %d %s; null hash %d %s" % [int(r3["hash"]),
		"SAME" if int(r3["hash"]) == int(r1["hash"]) else "DIFFERENT",
		int(n2["hash"]), "SAME" if int(n2["hash"]) == int(n0["hash"]) else "DIFFERENT"])
	# negative-j rewind: is the state at the press tick the same one the
	# forward path would have had? Compare j=-2 vs a forward run that presses
	# at the same absolute tick with jfix... (the forward path cannot press
	# before the cue, so compare j=-2 vs j=-2 twice and j=-2 vs j=0 differ)
	var a := one(st, 1.6, c, "mouse1", "rw", 4, -2)
	var b := one(st, 1.6, c, "mouse1", "rw", 4, -2)
	var d := one(st, 1.6, c, "mouse1", "rw", 4, 0)
	print("  rewind j=-2 twice: %s; j=-2 vs j=0 press %d vs %d hash %s" % [
		"SAME" if int(a["hash"]) == int(b["hash"]) else "DIFFERENT",
		int(a["press"]), int(d["press"]),
		"differ" if int(a["hash"]) != int(d["hash"]) else "IDENTICAL(!)"])

# ------------------------------------------------------------------- hold ---
# one() with the hold extended and the lock state traced
func one_long(st: Dictionary, c: Dictionary, tier: String, tag: String,
		sample: int, hold_max: int, force_off: Vector2 = Vector2(9e9, 9e9),
		tip_trace: Array = []) -> Dictionary:
	var hn := HN.new(tier, tag, sample)
	if force_off.x < 1e9:
		hn.offset = force_off
	var m := new_sim(String(st["level"]))
	var k := int(st["k"])
	var lead := float(c["lead"])
	var x := float(m.a_pos[k].x) - lead
	m.teleport(Vector2(x, TL.floor_y(m, x) - m.BODY_R))
	var j: int = hn.jit
	var sp: float = hn.speed
	var a0 := float(c["a0"])
	var a1 := float(c["a1"])
	var pull := bool(c["pull"])
	var w := maxi(1, roundi(int(c.get("w", 120)) * sp))
	var sd := maxi(1, roundi(int(c["sd"]) * sp))
	var pw := maxi(1, roundi(10.0 * sp))
	var ring: Array = []
	var T := SETTLE + w + 130
	var t := 0
	var g0 := -1
	var press := -1
	var grip := false
	var closes := 0
	var caught := false
	while t < T:
		if g0 < 0 and j < 0:
			ring.push_back({"s": m.snapshot(), "h": hn.save_state(), "t": t})
			if ring.size() > -j + 1:
				ring.pop_front()
		var cue := absf(float(m.a_theta[k])) >= CUE_RAD \
			and float(m.a_freelen[k]) < 0.0
		if g0 < 0 and cue and t >= SETTLE:
			g0 = t
			if j < 0:
				var e: Dictionary = ring[0]
				m.restore(e["s"])
				hn.restore_state(e["h"])
				t = int(e["t"])
				ring.clear()
				cue = absf(float(m.a_theta[k])) >= CUE_RAD \
					and float(m.a_freelen[k]) < 0.0
			press = maxi(g0 + j, SETTLE)
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		if not grip and float(m.a_freelen[k]) < 0.0:
			if closes == 0 and press >= 0 and t >= press:
				grip = true
				closes = 1
			elif closes > 0 and closes < 4 and cue:
				grip = true
				closes += 1
		var ts := t - SETTLE
		var ang := a0
		var amp := 1.0
		if ts < w:
			ang = a0
		elif ts < w + sd:
			ang = a1
		elif pull and ts < w + sd + pw:
			ang = a0
			amp = 0.7
		else:
			ang = a1
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(ang), sin(ang)) * m.REACH * amp + hn.tick()
		m.step_tick(tgt, grip)
		tip_trace.append(m.pos[m.NP - 1])
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			break
		t += 1
	var r := {"caught": caught, "lock0": -9, "g55": false, "h55": false,
		"g120": false, "g240": false, "held_end": false, "lost_at": -1,
		"hash55": 0, "first_lock": -1, "last_unlock": -1, "catch_t": t - SETTLE}
	if not caught:
		return r
	r["lock0"] = int(m.a_locked[k])
	var lost := -1
	for i in hold_max:
		m.step_tick(m.body_pos, true)
		var fl := float(m.a_freelen[k]) >= 0.0
		var lk := int(m.a_locked[k])
		if fl and lk == 1 and int(r["first_lock"]) < 0:
			r["first_lock"] = i + 1
		if fl and lk != 1 and int(r["first_lock"]) >= 0:
			r["last_unlock"] = i + 1
		if not fl and lost < 0:
			lost = i + 1
		if i + 1 == 55:
			r["g55"] = bool(m._holds(k))
			r["h55"] = fl
			r["hash55"] = m.state_hash()
		if i + 1 == 120:
			r["g120"] = bool(m._holds(k))
		if i + 1 == 240:
			r["g240"] = bool(m._holds(k))
		if not fl:
			break
	r["lost_at"] = lost
	r["held_end"] = float(m.a_freelen[k]) >= 0.0
	if lost > 0 and lost < 55:
		r["g55"] = false
	if lost > 0 and lost < 120:
		r["g120"] = false
	if lost > 0 and lost < 240:
		r["g240"] = false
	return r

func check_hold(n: int) -> void:
	print("")
	print("HOLD LENGTH - is the 55-tick verdict the settled one? N %d per tier, beam winner" % n)
	var st := station("beam")
	var c := BEAM_C
	# consistency with one(): same key -> hash at hold tick 55 equal
	var agree := 0
	for i in 5:
		var a := one(st, 1.6, c, "mouse1", "tier", i)
		var b := one_long(st, c, "mouse1", "tier", i, 55)
		if bool(a["caught"]) == bool(b["caught"]) and (not bool(a["caught"])
				or (int(a["hash"]) == int(b["hash55"]) and bool(a["green"]) == bool(b["g55"]))):
			agree += 1
	print("  one_long agrees with learn_probe.one() on 5 keys (caught, hash@55, green): %d/5" % agree)
	for tn in ["null", "mouse1", "trackpad"]:
		var nn := 3 if tn == "null" else n
		var caught := 0
		var lock0 := 0
		var g55 := 0
		var g120 := 0
		var g240 := 0
		var held := 0
		var flip_55_240 := 0
		var lost_after_55 := 0
		var lost_hist := {}
		var unlock_after_55 := 0
		for i in nn:
			var r := one_long(st, c, tn, "tier", i, 240)
			if not bool(r["caught"]):
				continue
			caught += 1
			if int(r["lock0"]) == 1:
				lock0 += 1
			if bool(r["g55"]):
				g55 += 1
			if bool(r["g120"]):
				g120 += 1
			if bool(r["g240"]):
				g240 += 1
			if bool(r["held_end"]):
				held += 1
			if bool(r["g55"]) != bool(r["g240"]):
				flip_55_240 += 1
			var la := int(r["lost_at"])
			if la > 55:
				lost_after_55 += 1
			if la > 0:
				var bucket := "%d-%d" % [int(la / 30) * 30, int(la / 30) * 30 + 29]
				lost_hist[bucket] = int(lost_hist.get(bucket, 0)) + 1
			if int(r["last_unlock"]) > 55:
				unlock_after_55 += 1
		print("  %-9s n %3d caught %3d  locked@catch %3d  GREEN@55 %3d  @120 %3d  @240 %3d  held@240 %3d  flips55->240 %d  lost after 55: %d  unlock after 55: %d  lost-tick hist %s" % [
			tn, nn, caught, lock0, g55, g120, g240, held, flip_55_240,
			lost_after_55, unlock_after_55, str(lost_hist)])

# -------------------------------------------------------------------- tip ---
func check_tip() -> void:
	print("")
	print("TIP CHAOS - beam winner, null tier, whole-hand offset 0 vs 1e-6 m")
	var st := station("beam")
	var ta: Array = []
	var tb: Array = []
	var ra := one_long(st, BEAM_C, "null", "tip", 0, 55, Vector2.ZERO, ta)
	var rb := one_long(st, BEAM_C, "null", "tip", 0, 55, Vector2(1e-6, 0.0), tb)
	var line := "  tick(after settle):sep mm  "
	for k in [0, 30, 60, 90, 120, 125, 129, 135, 150, 170, 190, 210]:
		var i: int = SETTLE + int(k)
		if i < ta.size() and i < tb.size():
			line += " %d:%.1f" % [k, (ta[i] - tb[i]).length() * 1000.0]
	print(line)
	print("  verdicts: 0 -> caught %s g55 %s at %d ; 1e-6 -> caught %s g55 %s at %d ; traces %d / %d ticks" % [
		str(ra["caught"]), str(ra["g55"]), int(ra["catch_t"]), str(rb["caught"]),
		str(rb["g55"]), int(rb["catch_t"]), ta.size(), tb.size()])

# -------------------------------------------------------------------- run ---
func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var mode := String(args[0]) if args.size() > 0 else "all"
	var n := int(args[1]) if args.size() > 1 else 30
	print("instr_check mode %s N %d" % [mode, n])
	if mode == "noise" or mode == "all":
		check_noise()
	if mode == "sim" or mode == "all":
		check_sim()
	if mode == "tip" or mode == "all":
		check_tip()
	if mode == "hold" or mode == "all":
		check_hold(n)
	for lv in sims:
		sims[lv].free()
	quit(0)
