extends SceneTree
## catch_window.gd - WHEN COULD THE PLAYER HAVE PRESSED?
##
## The existing probes grip with perfect information ("close the hand the tick
## a_theta crosses th_part"), which is an oracle no human has. This one sweeps
## the tick the hand closes across the whole flight of a large grid of realistic
## strokes, and reports, per throw:
##   - whether the whip genuinely wound the beam at all (scout pass, hand never
##     closes: deterministic, so every gripped run is bit-identical up to its
##     own press tick)
##   - which press ticks catch, which lock, which do nothing
##   - where that band sits relative to the cues the PLAYER actually has:
##     the chain touching the beam, and the wrap ring going up.
##
## Outcome vocabulary:
##   LOCK    caught and held
##   BETRAY  caught, classified partial, pays out (a legible near-miss)
##   MISS+   the whip wound the beam past the engage geometry, nothing engaged
##   miss-   the whip never wound the beam; correctly refused
## MISS+ is the reported defect. A catch on a miss- throw is a FALSE POSITIVE
## and the design forbids creating any.

const NT := 115
const LO := -18        # press offsets swept, relative to first beam contact
const HI := 27
const STEP := 3

var SCRIPT := "res://main.gd"

func _rig(dx: float, h: float, r: float) -> Node2D:
	var m: Node2D = load(SCRIPT).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	m.t_a.append(Vector2(-60.0, 0.0)); m.t_b.append(Vector2(60.0, 0.0))
	m.t_n.append(Vector2(0.0, -1.0))
	for k in m.a_pos.size():
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(dx, -h)
	m.a_r[0] = r
	m.clear_anchors()
	m.body_pos = Vector2(0.0, -m.BODY_R); m.body_prv = m.body_pos
	for i in m.pos.size():
		var p := Vector2(-0.3 - m.cum_len[i] * 0.99, -m.p_rad[i])
		m.pos[i] = p; m.prv[i] = p
	m.tick_count = 0
	m.grip_edge = -999
	return m

# stroke: wind up behind -> drive forward for sd ticks -> finish.
# fin 0 = hold the drive pose, 1 = high finish (hand up), 2 = snap reversal
# (the crack: yank back toward the wind-up for 8 ticks, then hold).
func _target(m: Node2D, t: int, s: Array) -> Vector2:
	var a0: float = s[3]
	var a1: float = s[4]
	var sd: int = s[5]
	var fin: int = s[6]
	var b: Vector2 = m.body_pos
	if t < 30:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH
	if t < 30 + sd:
		return b + Vector2(cos(a1), sin(a1)) * m.REACH
	if fin == 2 and t < 30 + sd + 8:
		return b + Vector2(cos(a0), sin(a0)) * m.REACH * 0.7
	if fin == 1:
		return b + Vector2(cos(-PI * 0.60), sin(-PI * 0.60)) * m.REACH
	return b + Vector2(cos(a1), sin(a1)) * m.REACH

# ------------------------------------------------------------------ scout ---
func _scout(s: Array) -> Dictionary:
	var m := _rig(s[0], s[1], s[2])
	var t_qual := -1
	var t_qual_last := -1
	var n_qual := 0
	var maxth := 0.0
	var t_touch := -1
	var t_ring := -1
	var t_see := -1
	var half := 0
	var n_tick_sfx := 0
	var c: Vector2 = m.a_pos[0]
	for t in NT:
		m.step_tick(_target(m, t, s), false)
		var th: float = absf(m.a_theta[0])
		maxth = maxf(maxth, th)
		if th >= m.th_part and m.a_lockidx[0] >= m.pin_min_idx:
			if t_qual < 0:
				t_qual = t
			t_qual_last = t
			n_qual += 1
		if t_see < 0 and th >= 1.6:
			t_see = t
		if t_ring < 0 and th > 0.3:
			t_ring = t
		var hf := int(th / PI)
		if hf > half and hf >= 1:
			n_tick_sfx += 1
		half = hf
		if t_touch < 0:
			for i in m.pos.size():
				if m.pos[i].distance_to(c) < m.a_r[0] + m.p_rad[i] + m.wrap_shell:
					t_touch = t
					break
	m.free()
	return {"maxth": maxth, "t_qual": t_qual, "t_qual_last": t_qual_last,
		"n_qual": n_qual, "t_touch": t_touch, "t_ring": t_ring, "t_see": t_see,
		"n_tick_sfx": n_tick_sfx}

# 0 = nothing, 1 = caught then betrayed, 2 = caught and locked
func _trial(s: Array, press: int) -> int:
	var m := _rig(s[0], s[1], s[2])
	var out := 0
	for t in NT:
		m.step_tick(_target(m, t, s), t >= press)
		if m.a_freelen[0] >= 0.0:
			out = 1
			if m.a_locked[0] == 1:
				out = 2
				break
			if m.a_locked[0] == 0:
				break        # verdict is in: partial, it will pay out
	m.free()
	return out

func _strokes() -> Array:
	var out: Array = []
	var beams: Array = [[0.22, 2.2], [0.11, 2.2], [0.11, 2.6]]
	var dxs: Array = [1.8, 2.5]
	var a0s: Array = [PI * 0.85, PI * 1.10]
	var a1s: Array = [-PI * 0.42, -PI * 0.30, -PI * 0.18]
	var sds: Array = [5, 9, 14]
	var fins: Array = [0, 2]
	if "small" in OS.get_cmdline_user_args():
		beams = [[0.11, 2.2]]
		dxs = [2.5]
		a0s = [PI * 0.85]
	for beam in beams:
		for dx in dxs:
			for a0 in a0s:
				for a1 in a1s:
					for sd in sds:
						for fin in fins:
							out.append([dx, beam[1], beam[0], a0, a1, sd, fin])
	return out

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	if "arrival" in OS.get_cmdline_user_args():
		SCRIPT = "res://tests/jb/whip_arrival.gd"
	print("SIM UNDER TEST: %s" % SCRIPT)
	var strokes := _strokes()
	var offs: Array = []
	var d := LO
	while d <= HI:
		offs.append(d)
		d += STEP
	# --- scout every stroke -------------------------------------------------
	var scouts: Array = []
	var good: Array = []
	var bad: Array = []
	for i in strokes.size():
		var sc := _scout(strokes[i])
		scouts.append(sc)
		if int(sc["n_qual"]) > 0 and int(sc["t_touch"]) >= 0:
			good.append(i)
		elif float(sc["maxth"]) < 3.4:
			bad.append(i)
	print("=== THE THROWS ===============================================")
	print("%d scripted strokes. %d wind the beam past the engage geometry" % [
		strokes.size(), good.size()])
	print("(a GOOD throw: a player watching would say that wrapped).")
	print("%d never come near it (miss- material, used as the false-positive" % bad.size())
	print("control). The remainder graze the threshold and are excluded.")
	var qs := 0
	var qmin := 9999
	var lead := 0
	var sfx := 0
	var strong := 0
	for i in good:
		var sc: Dictionary = scouts[i]
		qs += int(sc["n_qual"])
		qmin = mini(qmin, int(sc["n_qual"]))
		lead += int(sc["t_qual"]) - int(sc["t_touch"])
		sfx += int(sc["n_tick_sfx"])
		if float(sc["maxth"]) >= 5.5:
			strong += 1
	if good.size() > 0:
		var n := good.size()
		print("")
		print("QUALIFYING WINDOW - how long the geometry stays catchable:")
		print("  mean %.1f ticks (%.0f ms); tightest %d ticks (%.0f ms)" % [
			float(qs) / n, 1000.0 * qs / n / 60.0, qmin, 1000.0 * qmin / 60.0])
		print("LEAD - chain first touches the beam -> geometry qualifies:")
		print("  mean %.1f ticks (%.0f ms). That is all the warning there is." % [
			float(lead) / n, 1000.0 * lead / n / 60.0])
		print("%d of %d good throws reach th_full (5.5) - unambiguous full turn." % [strong, n])
		print("A good throw rings the half-turn chime %.1f times on average," % [
			float(sfx) / n])
		print("whether or not anything ever engages.")
	# --- sweep the press tick ----------------------------------------------
	print("")
	print("=== CATCH vs PRESS TICK ======================================")
	print("press offset is relative to the chain first touching the beam.")
	print("negative = pressed in anticipation; positive = pressed in reaction.")
	print("")
	print(" offset    ms     GOOD throws: LOCK BETRAY  MISS+   caught%%   BAD throws caught (false positives)")
	# subsample the false-positive control: every 4th non-wrapping throw
	var bad_ctl: Array = []
	for bi in bad.size():
		if bi % 8 == 0:
			bad_ctl.append(bad[bi])
	var hits: Array = []          # hits[i][oi] -> 0/1/2, reused for the band
	for i in good.size():
		var row := PackedInt32Array()
		row.resize(offs.size())
		hits.append(row)
	var best_pct := -1.0
	var best_off := 0
	for oi in offs.size():
		var nl := 0
		var nb := 0
		var nm := 0
		for gi in good.size():
			var i: int = good[gi]
			var sc: Dictionary = scouts[i]
			var p: int = maxi(int(sc["t_touch"]) + int(offs[oi]), 0)
			var r := _trial(strokes[i], p)
			hits[gi][oi] = r
			if r == 2: nl += 1
			elif r == 1: nb += 1
			else: nm += 1
		var fp := 0
		for i in bad_ctl:
			var sc2: Dictionary = scouts[i]
			var base: int = int(sc2["t_touch"])
			if base < 0:
				base = 45
			var p2: int = maxi(base + int(offs[oi]), 0)
			if _trial(strokes[i], p2) > 0:
				fp += 1
		var pct := 100.0 * (nl + nb) / maxi(good.size(), 1)
		if pct > best_pct:
			best_pct = pct
			best_off = int(offs[oi])
		print(" %+4d   %+5.0f            %5d %6d %6d   %5.1f%%          %d of %d" % [
			offs[oi], 1000.0 * float(offs[oi]) / 60.0, nl, nb, nm, pct, fp, bad_ctl.size()])
	print("")
	print("BEST FIXED POLICY: press %+d ticks from contact -> %.1f%% of good" % [
		best_off, best_pct])
	print("throws catch. A player with PERFECT consistency who has found the one")
	print("best moment still loses %.1f%% of the throws they judged good." % (100.0 - best_pct))
	# what a human with timing scatter gets: average the curve over +-6 ticks
	print("")
	print("WITH HUMAN SCATTER (aim for the best moment, land within +-100 ms):")
	var scat := 0.0
	var ns := 0
	for oi in offs.size():
		if absi(int(offs[oi]) - best_off) <= 6:
			var c := 0
			for gi in good.size():
				if hits[gi][oi] > 0:
					c += 1
			scat += 100.0 * c / maxi(good.size(), 1)
			ns += 1
	if ns > 0:
		print("  %.1f%% catch, so %.1f%% of good throws silently fail." % [
			scat / ns, 100.0 - scat / ns])
	# --- per-throw band -----------------------------------------------------
	print("")
	print("=== THE BAND, PER THROW ======================================")
	print("(width measured on a %d-tick grid, so it is a lower bound)" % STEP)
	var wsum := 0
	var wmin := 9999
	var losum := 0
	var hisum := 0
	var never := 0
	for gi in good.size():
		var lo := 9999
		var hi := -9999
		var w := 0
		for oi in offs.size():
			if hits[gi][oi] > 0:
				w += 1
				lo = mini(lo, int(offs[oi]))
				hi = maxi(hi, int(offs[oi]))
		if w == 0:
			never += 1
			continue
		wsum += w * STEP
		wmin = mini(wmin, w * STEP)
		losum += lo
		hisum += hi
	var ng := good.size() - never
	if ng > 0:
		print("mean usable press band %.1f ticks (%.0f ms); narrowest %d ticks (%.0f ms)" % [
			float(wsum) / ng, 1000.0 * wsum / ng / 60.0, wmin, 1000.0 * wmin / 60.0])
		print("mean band opens %+.1f ticks and shuts %+.1f ticks after first contact" % [
			float(losum) / ng, float(hisum) / ng])
	print("good throws that catch at NO press tick at all: %d" % never)
	print("")
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
