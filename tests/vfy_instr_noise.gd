extends "res://tests/rp_repeat.gd"
## ADVERSARIAL CHECK OF THE INSTRUMENT in tests/rp_repeat.gd (and hand_noise.gd).
## Untracked verifier; modifies nothing. Modes:
##   noise            measure what class Hand actually emits (sd, lag-k autocorr,
##                    band power vs the AR(1) it claims), offset sd, speed
##                    quantisation, press-jitter histogram, seed reproducibility
##   null <station> <outdir>   8 zero-sigma replays of winner 0 -> one hash?
##                    equals the search's hash? fresh sim same? and the hold
##                    audited tick by tick (LOCKED vs HELD)
##   chaos <station> <outdir>  the same throw with a tiny constant cursor
##                    offset, in lockstep: tip separation per tick, and outcome
const HN := preload("res://tests/hand_noise.gd")

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var mode := String(args[0]) if args.size() > 0 else ""
	var t0 := Time.get_ticks_msec()
	match mode:
		"noise":
			do_noise()
		"null":
			do_null(String(args[1]), String(args[2]))
		"chaos":
			do_chaos(String(args[1]), String(args[2]))
		"hist":
			do_hist(String(args[1]), String(args[2]))
	print("  [%.0f s]" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)

func stats(a: Array) -> Array:
	var n := a.size()
	var mu := 0.0
	for v in a:
		mu += v
	mu /= n
	var va := 0.0
	for v in a:
		va += (v - mu) * (v - mu)
	return [mu, sqrt(va / (n - 1))]

func autocorr(a: Array, lag: int) -> float:
	var s := stats(a)
	var mu: float = s[0]
	var num := 0.0
	var den := 0.0
	for i in a.size():
		den += (a[i] - mu) * (a[i] - mu)
		if i + lag < a.size():
			num += (a[i] - mu) * (a[i + lag] - mu)
	return num / den

func band_power(a: Array, edges: Array) -> Array:
	# straight DFT of a demeaned series, power summed into bands (Hz)
	var n := a.size()
	var s := stats(a)
	var mu: float = s[0]
	var out: Array = []
	for b in edges.size() - 1:
		out.append(0.0)
	var tot := 0.0
	for k in range(1, n / 2):
		var f := float(k) * 60.0 / n
		var re := 0.0
		var im := 0.0
		for i in n:
			var w := TAU * k * i / n
			re += (a[i] - mu) * cos(w)
			im -= (a[i] - mu) * sin(w)
		var p := re * re + im * im
		tot += p
		for b in edges.size() - 1:
			if f >= edges[b] and f < edges[b + 1]:
				out[b] += p
	for b in out.size():
		out[b] /= tot
	return out

func ar1_band_theory(alpha: float, edges: Array) -> Array:
	var out: Array = []
	for b in edges.size() - 1:
		out.append(0.0)
	var tot := 0.0
	for k in range(1, 3000):
		var f := k * 0.01
		if f >= 30.0:
			break
		var w := TAU * f / 60.0
		var p := (1.0 - alpha * alpha) / (1.0 - 2.0 * alpha * cos(w) + alpha * alpha)
		tot += p
		for b in edges.size() - 1:
			if f >= edges[b] and f < edges[b + 1]:
				out[b] += p
	for b in out.size():
		out[b] /= tot
	return out

func do_noise() -> void:
	print("NOISE MODEL MEASUREMENT (rp_repeat.gd class Hand; then hand_noise.gd)")
	var alpha := exp(-TAU * 5.0 / 60.0)
	print("  claimed AR(1) pole alpha = %.4f; -3dB of that pole = %.2f Hz" % [alpha,
		acos((-1.0 + 4.0 * alpha - alpha * alpha) / (2.0 * alpha)) * 60.0 / TAU])
	# --- tremor: one long hand, tremor only, 16.7 mm
	var h := Hand.new("vfy/trem", 0, 16.7, 0, 0.0, false, true)
	var xs: Array = []
	var ys: Array = []
	var NT := 6000
	for t in NT:
		var v: Vector2 = h.tick()
		xs.append(v.x * 1000.0)
		ys.append(v.y * 1000.0)
	var sx := stats(xs)
	var sy := stats(ys)
	print("  tremor 16.7mm tier, %d ticks: sd x %.2f mm, sd y %.2f mm (claim 16.7); mean x %.2f y %.2f" % [
		NT, sx[1], sy[1], sx[0], sy[0]])
	var line := "  autocorr x lag k (measured / alpha^k):"
	for lag in [1, 2, 3, 4, 6, 8, 12]:
		line += "  k%d %.3f/%.3f" % [lag, autocorr(xs, lag), pow(alpha, lag)]
	print(line)
	var edges := [0.0, 2.5, 5.0, 10.0, 20.0, 30.0]
	var sub: Array = xs.slice(0, 2048)
	var bp := band_power(sub, edges)
	var th := ar1_band_theory(alpha, edges)
	line = "  band power share (measured / AR1 theory / white):"
	for b in bp.size():
		line += "  %.1f-%.1fHz %.3f/%.3f/%.3f" % [edges[b], edges[b + 1], bp[b], th[b],
			(edges[b + 1] - edges[b]) / 30.0]
	print(line)
	# --- tremor sd across many short hands (the per-throw view: 250 ticks)
	var pooled: Array = []
	var start_sd: Array = []
	for i in 400:
		var hh := Hand.new("vfy/trem2", i, 16.7, 0, 0.0, false, true)
		start_sd.append(hh.trem.x * 1000.0)
		for t in 250:
			pooled.append(hh.tick().x * 1000.0)
	print("  tremor pooled over 400 hands x 250 ticks: sd %.2f mm; initial-value sd %.2f mm (claim: stationary start, 16.7)" % [
		stats(pooled)[1], stats(start_sd)[1]])
	# --- offset
	for mm in [2.5, 8.3, 16.7, 33.3]:
		var ox: Array = []
		var oy: Array = []
		var oo: Array = []
		for i in 4000:
			var hh := Hand.new("vfy/off", i, mm, 0, 0.0, true, false)
			ox.append(hh.off.x * 1000.0)
			oy.append(hh.off.y * 1000.0)
			oo.append(hh.off.length() * 1000.0)
		var a := stats(ox)
		var b := stats(oy)
		print("  offset tier %.1f mm, 4000 hands: sd x %.2f y %.2f (mean %.2f %.2f); |off| mean %.2f mm, corr(x,y) %.3f" % [
			mm, a[1], b[1], a[0], b[0], stats(oo)[0], _corr(ox, oy)])
	# --- speed and its quantisation onto the stroke's tick counts
	var sp: Array = []
	var q := {5: {}, 9: {}, 14: {}, 10: {}}
	var clamped := 0
	for i in 10000:
		var hh := Hand.new("vfy/speed", i, 0.0, 0, 0.05)
		sp.append(hh.speed)
		if hh.speed == 0.8 or hh.speed == 1.2:
			clamped += 1
		for sd in q:
			var v := maxi(1, roundi(sd * hh.speed))
			q[sd][v] = int(q[sd].get(v, 0)) + 1
	var ss := stats(sp)
	print("  speed 10000 hands: mean %.4f sd %.4f (claim 0.05), clamped %d" % [ss[0], ss[1], clamped])
	for sd in [5, 9, 14, 10]:
		var d: Dictionary = q[sd]
		var keys := d.keys()
		keys.sort()
		line = "  roundi(%d * speed):" % sd
		for kk in keys:
			line += "  %d:%.1f%%" % [kk, 100.0 * d[kk] / 10000.0]
		print(line + "   <- fraction of throws where the 5%% speed noise changes NOTHING: %.1f%%" % (100.0 * d.get(sd, 0) / 10000.0))
	# --- press jitter
	for J in [1, 2, 3]:
		var hist := {}
		for i in 7000:
			var hh := Hand.new("vfy/jit", i, 0.0, J, 0.0)
			hist[hh.jit] = int(hist.get(hh.jit, 0)) + 1
		var keys := hist.keys()
		keys.sort()
		line = "  press jitter +/-%d, 7000 hands:" % J
		for kk in keys:
			line += "  %+d:%.1f%%" % [kk, 100.0 * hist[kk] / 7000.0]
		print(line + "  (uniform = %.1f%%)" % (100.0 / (2 * J + 1)))
	# --- reproducibility and independence of the seeding
	var h1 := Hand.new("beam/0/x", 7, 16.7, 3, 0.05)
	var h2 := Hand.new("beam/0/x", 7, 16.7, 3, 0.05)
	var same := h1.off == h2.off and h1.speed == h2.speed and h1.jit == h2.jit
	for t in 500:
		if h1.tick() != h2.tick():
			same = false
	print("  same (key, sample) twice -> identical off/speed/jit and 500 identical tremor ticks: %s" % str(same))
	var ax: Array = []
	var bx: Array = []
	for i in 3000:
		ax.append(Hand.new("beam/0/x", i, 16.7, 0, 0.0, true, false).off.x)
		bx.append(Hand.new("beam/0/x", i + 1, 16.7, 0, 0.0, true, false).off.x)
	print("  corr(off.x sample i, sample i+1) over 3000: %.3f (independent = 0)" % _corr(ax, bx))
	var cx: Array = []
	for i in 3000:
		cx.append(Hand.new("thin/0/x", i, 16.7, 0, 0.0, true, false).off.x)
	print("  corr(off.x key A, key B, same sample) over 3000: %.3f" % _corr(ax, cx))
	var seeds := {}
	var dup := 0
	for key in ["beam/0/null        0.0mm  +-0", "beam/0/trackpad   16.7mm  +-3", "thin/0/trackpad   16.7mm  +-3", "beam/1/trackpad   16.7mm  +-3"]:
		for i in 500:
			var sd_ := int(("%s#%d" % [key, i]).hash()) * 2654435761 + i
			if seeds.has(sd_):
				dup += 1
			seeds[sd_] = true
	print("  seed collisions across 4 keys x 500 samples: %d" % dup)
	# --- the null hand emits exactly zero
	var hz := Hand.new("null", 0, 0.0, 0, 0.0)
	var nz := 0
	for t in 300:
		if hz.tick() != Vector2.ZERO:
			nz += 1
	print("  null hand: non-zero cursor errors in 300 ticks: %d; speed %.3f jit %d" % [nz, hz.speed, hz.jit])
	# --- hand_noise.gd, trackpad tier, the same measurements
	var g := HN.new("trackpad", "vfy", 0)
	var gx: Array = []
	for t in NT:
		gx.append((g.tick() - g.offset).x * 1000.0)
	print("  hand_noise.gd trackpad: %s" % g.describe())
	print("    tremor sd %.2f mm (claim 33.3); lag1 %.3f lag3 %.3f (alpha %.3f, %.3f)" % [
		stats(gx)[1], autocorr(gx, 1), autocorr(gx, 3), alpha, pow(alpha, 3)])
	var gox: Array = []
	var gsp: Array = []
	var gj := {}
	for i in 3000:
		var gg := HN.new("trackpad", "vfy", i)
		gox.append(gg.offset.x * 1000.0)
		gsp.append(gg.speed)
		gj[gg.jit] = int(gj.get(gg.jit, 0)) + 1
	print("    offset sd x %.2f mm (claim 33.3), speed sd %.4f, jit hist %s" % [stats(gox)[1], stats(gsp)[1], str(gj)])
	var gn := HN.new("null", "vfy", 0)
	var gnz := 0
	for t in 300:
		if gn.tick() != Vector2.ZERO:
			gnz += 1
	print("    null tier: non-zero ticks %d, is_null %s" % [gnz, str(gn.is_null())])

func _corr(a: Array, b: Array) -> float:
	var sa := stats(a)
	var sb := stats(b)
	var s := 0.0
	for i in a.size():
		s += (a[i] - sa[0]) * (b[i] - sb[0])
	return s / ((a.size() - 1) * sa[1] * sb[1])

# ---------------------------------------------------------------- null ----
func do_null(sname: String, outdir: String) -> void:
	var st := station(sname)
	var wj := load_json("%s/winners_%s.json" % [outdir, sname])
	var wins: Array = wj.get("wins", [])
	var c: Dictionary = wins[0]
	var k := int(st["k"])
	var m := new_sim(String(st["level"]))
	var snap := stance(m, k, float(c["lead"]), float(c["a0"]))
	print("NULL %s winner 0: %s (search hash %s)" % [st["name"], cstr(c), String(c["hash"])])
	var hs := {}
	var greens := 0
	var first := {}
	for i in 8:
		var r := throw_noisy(m, snap, k, c, Hand.new("%s/0" % sname, i, 0.0, 0, 0.0), true)
		hs[int(r["hash"])] = true
		if bool(r["green"]):
			greens += 1
		if i == 0:
			first = r
	print("  8 zero-sigma replays: distinct hashes %d, green %d/8, hash == search %s, caught %s et %d cls %d cls_t %d lost_t %d held %s why %s" % [
		hs.size(), greens, str(str(int(first["hash"])) == String(c["hash"])), str(first["caught"]),
		int(first["et"]), int(first["cls"]), int(first["cls_t"]), int(first["lost_t"]), str(first["held"]), String(first["why"])])
	# the same through the cell path (hand_for on the null cell) - the identity claim
	var hs2 := {}
	for i in 8:
		var r := throw_noisy(m, snap, k, c, hand_for(main_cells()[0], "%s/0/null" % sname, i), true)
		hs2[int(r["hash"])] = true
	print("  8 replays via main_cells()[0] (the 'null' cell): distinct hashes %d, equals above %s" % [
		hs2.size(), str(hs2.keys()[0] == hs.keys()[0])])
	# fresh sim, never restored
	var m2 := new_sim(String(st["level"]))
	var snap2 := stance(m2, k, float(c["lead"]), float(c["a0"]))
	var r2 := throw_noisy(m2, snap2, k, c, Hand.new("x", 0, 0.0, 0, 0.0), true)
	print("  fresh sim (never restored): hash == %s, green %s" % [str(int(r2["hash"]) == hs.keys()[0]), str(r2["green"])])
	m2.free()
	# HELD vs LOCKED: audit the hold tick by tick on the null throw. Re-run the
	# throw without the hold, then step the hold ourselves with the floor out.
	var r3 := _throw_no_hold(m, snap, k, c)
	print("  catch at et %d (rig et %d), a_locked at catch = %d, a_freelen %.3f, theta %.3f" % [
		int(r3["et"]), int(first["et"]), int(m.a_locked[k]), float(m.a_freelen[k]), float(m.a_theta[k])])
	var keep := {}
	for kk in ["t_a", "t_b", "t_n", "t_lo", "t_hi", "t_deep", "world_bottom"]:
		keep[kk] = MAIN._dup(m.get(kk))
	strip_floor(m)
	var line := "  hold trace (t: locked/holds/freelen/theta):"
	var first_lock := -1
	var ever_lost := -1
	var lock_ticks := 0
	for t in HOLD:
		m.step_tick(m.body_pos, true)
		if int(m.a_locked[k]) == 1 and first_lock < 0:
			first_lock = t
		if int(m.a_locked[k]) == 1:
			lock_ticks += 1
		if float(m.a_freelen[k]) < 0.0 and ever_lost < 0:
			ever_lost = t
		if t % 30 == 0 or t == HOLD - 1:
			line += "  %d:%d/%s/%.2f/%.2f" % [t, int(m.a_locked[k]), "T" if m._holds(k) else "F",
				float(m.a_freelen[k]), float(m.a_theta[k])]
	print(line)
	print("  first lock tick %d, locked for %d/%d hold ticks, first lost %d, _holds at +180 = %s, grounded at end %s" % [
		first_lock, lock_ticks, HOLD, ever_lost, str(m._holds(k)), str(m.grounded)])
	for kk in keep:
		m.set(kk, keep[kk])
	# press shift: press == cue + j, and what it does to the catch
	var line2 := "  press j -> (g0, press, et, cls, green, why):"
	for jj in [-3, -2, -1, 0, 1, 2, 3]:
		var h := Hand.new("x", 0, 0.0, 0, 0.0)
		h.jit = jj
		var r := throw_noisy(m, snap, k, c, h, true)
		line2 += "\n    %+d: (%d, %d, %d, %d, %s, %s)" % [jj, int(r["g0"]), int(r["press"]), int(r["et"]),
			int(r["cls"]), "G" if r["green"] else "-", String(r["why"])]
	print(line2)
	m.free()

func _throw_no_hold(m: Node2D, snap: Dictionary, k: int, c: Dictionary) -> Dictionary:
	# identical kinematics to throw_noisy with the null hand, no hold
	m.restore(snap)
	var a0 := float(c["a0"])
	var a1 := float(c["a1"])
	var pull := bool(c["pull"])
	var sd := int(c["sd"])
	var pw := 10
	var grip := false
	var g0 := -1
	var closes := 0
	for t in WINDUP + 130:
		var cue := absf(float(m.a_theta[k])) >= CUE_RAD and float(m.a_freelen[k]) < 0.0
		if g0 < 0 and cue:
			g0 = t
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW and float(m.a_freelen[k]) < 0.0:
			grip = false
		if not grip and float(m.a_freelen[k]) < 0.0:
			if closes == 0 and g0 >= 0 and t >= g0:
				grip = true
				closes = 1
			elif closes > 0 and closes < 4 and cue:
				grip = true
				closes += 1
		var ang := a0
		var amp := 1.0
		if t < WINDUP:
			ang = a0
		elif t < WINDUP + sd:
			ang = a1
		elif pull and t < WINDUP + sd + pw:
			ang = a0
			amp = 0.7
		else:
			ang = a1
		m.step_tick(m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp, grip)
		if float(m.a_freelen[k]) >= 0.0:
			return {"et": t, "hash": m.state_hash()}
	return {"et": -1, "hash": m.state_hash()}

# --------------------------------------------------------------- chaos ----
func do_chaos(sname: String, outdir: String) -> void:
	var st := station(sname)
	var wj := load_json("%s/winners_%s.json" % [outdir, sname])
	var c: Dictionary = wj.get("wins", [])[0]
	var k := int(st["k"])
	print("CHAOS %s winner 0: %s" % [st["name"], cstr(c)])
	print("  two sims from the same stance, same stroke, NO grip (free flight, 250 ticks); B's cursor is shifted by dx")
	for dx in [1.0e-7, 1.0e-5, 1.0e-3, 1.0e-2, 0.0167]:
		var ma := new_sim(String(st["level"]))
		var mb := new_sim(String(st["level"]))
		var sa := stance(ma, k, float(c["lead"]), float(c["a0"]))
		var sb := stance(mb, k, float(c["lead"]), float(c["a0"]))
		ma.restore(sa)
		mb.restore(sb)
		var a0 := float(c["a0"])
		var a1 := float(c["a1"])
		var line := "  dx %s m: tip sep (m) at t=" % sci(dx)
		var handsep := 0.0
		var maxsep := 0.0
		for t in 250:
			var ang := a0 if t < WINDUP else a1
			var tgt_a: Vector2 = ma.body_pos + Vector2(cos(ang), sin(ang)) * ma.REACH
			var tgt_b: Vector2 = mb.body_pos + Vector2(cos(ang), sin(ang)) * mb.REACH + Vector2(dx, 0.0)
			ma.step_tick(tgt_a, false)
			mb.step_tick(tgt_b, false)
			var sep: float = (ma.pos[ma.NP - 1] - mb.pos[mb.NP - 1]).length()
			handsep = (ma.pos[0] - mb.pos[0]).length()
			if sep > maxsep:
				maxsep = sep
			if t in [WINDUP, WINDUP + 10, WINDUP + 20, WINDUP + 30, WINDUP + 45, WINDUP + 60, WINDUP + 90, WINDUP + 129]:
				line += " +%d:%s" % [t - WINDUP, sci(sep)]
		var dth: float = absf(float(ma.a_theta[k]) - float(mb.a_theta[k]))
		print(line + "  | max %.3f; handle sep at end %s; |dtheta| at end %.3f; hash same %s" % [
			maxsep, sci(handsep), dth, str(ma.state_hash() == mb.state_hash())])
		ma.free()
		mb.free()
	# and the gripped outcome under the same tiny shifts: does the CATCH flip?
	var m := new_sim(String(st["level"]))
	var snap := stance(m, k, float(c["lead"]), float(c["a0"]))
	var line2 := "  gripped throw with constant offset dx (m) -> (et, theta@catch, cls, green, why):"
	for dx in [0.0, 1.0e-7, 1.0e-5, 1.0e-3, 5.0e-3, 1.0e-2, 0.0167, 0.0333, -0.0167, -0.0333]:
		var h := Hand.new("x", 0, 0.0, 0, 0.0)
		h.off = Vector2(dx, 0.0)
		var r := throw_noisy(m, snap, k, c, h, true)
		line2 += "\n    %+.1e: (%d, %.2f, %d, %s, %s)" % [dx, int(r["et"]), float(r["th"]), int(r["cls"]),
			"G" if r["green"] else "-", String(r["why"])]
	print(line2)
	m.free()

func sci(v: float) -> String:
	if v == 0.0:
		return "0"
	var e := floori(log(absf(v)) / log(10.0))
	return "%.2fe%d" % [v / pow(10.0, e), e]

# ---------------------------------------------------------------- hist ----
# do_search reuses ONE sim for 108 cells: stance() teleports whatever whip
# configuration the previous throw left (teleport moves the chain rigidly and
# resets nothing). Does the stance depend on history?
func do_hist(sname: String, outdir: String) -> void:
	var st := station(sname)
	var wj := load_json("%s/winners_%s.json" % [outdir, sname])
	var c: Dictionary = wj.get("wins", [])[0]
	var k := int(st["k"])
	var m := new_sim(String(st["level"]))
	var s0 := stance(m, k, float(c["lead"]), float(c["a0"]))
	var h0: int = m.state_hash()
	var spread0 := _spread(m)
	print("HIST %s winner 0: %s" % [st["name"], cstr(c)])
	print("  fresh stance: hash %d, chain spread %.2f m, a_freelen %.2f" % [h0, spread0, float(m.a_freelen[k])])
	# stance again on the same untouched sim (idempotence)
	stance(m, k, float(c["lead"]), float(c["a0"]))
	print("  stance twice, no throw between: hash same %s" % str(m.state_hash() == h0))
	# now throw (null hand, hold) then stance again, like the search does
	var r := throw_noisy(m, s0, k, c, null_hand(), true)
	print("  throw from fresh stance: caught %s cls %d green %s why %s (a_freelen after hold %.2f)" % [
		str(r["caught"]), int(r["cls"]), str(r["green"]), String(r["why"]), float(m.a_freelen[k])])
	stance(m, k, float(c["lead"]), float(c["a0"]))
	var h1: int = m.state_hash()
	print("  stance after that throw: hash same as fresh %s, chain spread %.2f m, a_freelen %.2f, locked %d" % [
		str(h1 == h0), _spread(m), float(m.a_freelen[k]), int(m.a_locked[k])])
	var r1 := throw_noisy(m, m.snapshot(), k, c, null_hand(), true)
	print("  same stroke from that stance: caught %s cls %d green %s why %s" % [
		str(r1["caught"]), int(r1["cls"]), str(r1["green"]), String(r1["why"])])
	# a chain of 6 stance/throw repeats of the same stroke: outcomes sequence
	var seq := ""
	for i in 6:
		stance(m, k, float(c["lead"]), float(c["a0"]))
		var rr := throw_noisy(m, m.snapshot(), k, c, null_hand(), true)
		seq += " %s" % ("G" if rr["green"] else ("c" if rr["caught"] else "-"))
	print("  6 more stance+throw repeats on the same sim:%s   (G green, c caught not green, - miss)" % seq)
	m.free()

func _spread(m: Node2D) -> float:
	var lo := 1.0e9
	var hi := -1.0e9
	for i in m.NP:
		lo = minf(lo, m.pos[i].x)
		hi = maxf(hi, m.pos[i].x)
	return hi - lo
