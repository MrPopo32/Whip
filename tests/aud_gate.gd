extends SceneTree
## THE AUDIO GATE. Sound is allowed to render the past and the present and
## nothing else, it must have a visual twin at the same resolution, and it must
## not be able to touch the simulation. Those are three checkable claims, so
## they are checked here rather than asserted in a comment.
##
##   godot --headless --path . -s res://tests/aud_gate.gd
##
## A1 INERT HEADLESS   the probes build the sim with new() and never enter the
##                     tree, so _ready never fires: no audio node is created,
##                     av_on stays false, and the whole audio pass is one bool.
## A2 INERT PERIOD     force av_on true - so every line of the audio pass runs
##                     against a real session's inputs - and the golden hash
##                     must be unchanged. This is the one that proves audio
##                     cannot feed back, because it runs the code rather than
##                     reasoning about it.
## A3 PARITY           every audible one-shot raises its visual burst on the
##                     SAME tick, at the same beam. Counted over the corpus.
## A4 NO PROPHECY      no voice fires before the state it describes exists: the
##                     verdict never precedes the simulation's classification,
##                     and nothing at all is said while a wrap is pending.
## A5 DRIVERS LIVE     the continuous voices are actually driven - a gate that
##                     passes on silence would be the failure this file exists
##                     to catch.
## A6 COST             the audio pass, measured with it forced on, against the
##                     same ticks with it off.
const TL := preload("res://tests/tapelib.gd")
const MAIN := preload("res://main.gd")
const GOLDEN := 2762505307938286422

var fails := 0

func _initialize() -> void:
	_a1()
	_a2()
	_corpus()
	_a6()
	print("")
	if fails == 0:
		print("PASS  audio is instrumentation: inert, twinned, and about now")
	else:
		print("FAIL  %d audio gate(s)" % fails)
	quit(1 if fails > 0 else 0)

func _bad(s: String) -> void:
	fails += 1
	print("  FAIL %s" % s)

# ---------------------------------------------------------------- A1 + A2 --
func _a1() -> void:
	var m: Node2D = TL.new_sim()
	for t in 120:
		m.step_tick(m.body_pos + Vector2(cos(t * 0.1), sin(t * 0.1)) * 1.1,
			t > 60)
	var names := ["sfx_crack", "sfx_tick", "sfx_rasp", "sfx_air", "sfx_load",
		"sfx_grit", "sfx_catch", "sfx_lock", "sfx_part", "sfx_ratch",
		"sfx_off", "sfx_let"]
	var live := 0
	for n in names:
		if m.get(n) != null:
			live += 1
	if bool(m.av_on):
		_bad("A1 av_on is true in a headless sim")
	elif live > 0:
		_bad("A1 %d audio node(s) exist headlessly" % live)
	else:
		print("  A1 ok: headless, av_on false, 0 of %d audio nodes created"
			% names.size())
	if m.get_child_count() != 0:
		_bad("A1 the headless sim has %d children" % m.get_child_count())
	m.free()

func _a2() -> void:
	# hashrun.gd's session, run twice: audio pass off, then fully on.
	var h := []
	for on in [false, true]:
		var m: Node2D = TL.new_sim()
		m.av_on = on
		for t in 900:
			var b: Vector2 = m.body_pos
			var tgt: Vector2
			var grip := false
			if t < 90:
				tgt = b + Vector2(0.5, -0.5)
			elif t < 280:
				var ph := float(t - 90) * 0.11
				tgt = b + Vector2(cos(ph), sin(ph)) * 1.1
			elif t < 340:
				tgt = b + Vector2(-1.05, -0.35)
			elif t < 352:
				tgt = b + Vector2(1.05, -0.45)
			elif t < 600:
				tgt = b + Vector2(0.8, -0.8); grip = t > 420
			else:
				var p2 := float(t) * 0.05
				tgt = b + Vector2(cos(p2), -0.6); grip = true
			m.step_tick(tgt, grip)
		h.append(m.state_hash())
		m.free()
	if int(h[0]) != GOLDEN:
		_bad("A2 audio OFF diverged from the golden hash: %d" % int(h[0]))
	elif int(h[1]) != GOLDEN:
		_bad("A2 running the audio pass CHANGED the simulation: %d" % int(h[1]))
	else:
		print("  A2 ok: 900 ticks with the audio pass forced ON still hash %d"
			% GOLDEN)

# ------------------------------------------------------------- A3 + A4 + A5 --
func _corpus() -> void:
	var d := DirAccess.open("res://tapes")
	var paths: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".tape"):
			paths.append("res://tapes/%s" % f)
	paths.sort()

	var ev := {"catch": 0, "hold": 0, "drop": 0, "pay": 0, "let": 0,
		"unwind": 0, "off": 0, "wind": 0}
	var twinned := 0
	var untwinned := 0
	var prophecy := 0
	var pending_noise := 0
	var air_n := 0
	var load_n := 0
	var grit_n := 0
	var load_min := 1e9
	var load_max := 0.0
	var air_max := 0.0
	var grit_max := 0.0
	var scrape_wrong := 0

	for p in paths:
		var t: Dictionary = MAIN.tape_load(p)
		var m: Node2D = TL.new_sim()
		m.av_on = true
		if not m.restore(t["start"]):
			_bad("A3 %s would not restore" % p)
			m.free()
			continue
		m.av_on = true          # restore() must not have been able to clear it
		var cur: PackedVector2Array = t["cur"]
		var grp: PackedByteArray = t["grip"]
		var pe := PackedByteArray(); pe.resize(m.a_pos.size())
		var ph := PackedByteArray(); ph.resize(m.a_pos.size())
		var pp := PackedInt32Array(); pp.resize(m.a_pos.size())
		var pw := PackedInt32Array(); pw.resize(m.a_pos.size())
		var plk := PackedInt32Array(); plk.resize(m.a_pos.size())
		for k in m.a_pos.size():
			pp[k] = -1
			plk[k] = -1
		for i in int(t["n"]):
			m.pending_reset = (grp[i] & 2) != 0
			m.step_tick(cur[i], (grp[i] & 1) != 0)
			# continuous drivers
			if m.av_lvl_t[m.AV_AIR] > 0.0:
				air_n += 1
				air_max = maxf(air_max, m.av_lvl_t[m.AV_AIR])
			if m.av_lvl_t[m.AV_GRIT] > 0.0:
				grit_n += 1
				grit_max = maxf(grit_max, m.av_lvl_t[m.AV_GRIT])
			if m.av_tension > 0.0:
				load_n += 1
				load_min = minf(load_min, m.av_tension)
				load_max = maxf(load_max, m.av_tension)
			# the grit driver must come from real resolved contacts
			var touched := false
			for j in m.NP:
				if m.av_touch[j] != 0:
					touched = true
					break
			if not touched and not m.grounded and m.av_scrape > 0.0:
				scrape_wrong += 1
			for k in m.a_pos.size():
				var eng := 1 if m.a_freelen[k] >= 0.0 else 0
				var hold := 1 if m._holds(k) else 0
				var half := int(absf(m.a_theta[k]) / PI)
				var fired := ""
				if half > pw[k] and half >= 1:
					ev["wind"] = int(ev["wind"]) + 1
					fired = "wind"
				if eng == 1 and pe[k] == 0:
					ev["catch"] = int(ev["catch"]) + 1
					fired = "catch"
				elif eng == 0 and pe[k] == 1:
					if not m.taut:
						ev["let"] = int(ev["let"]) + 1
					elif m.a_armed[k] == 1:
						ev["unwind"] = int(ev["unwind"]) + 1
					else:
						ev["off"] = int(ev["off"]) + 1
					fired = "end"
				elif eng == 1:
					var res: bool = m.a_locked[k] != -1 and plk[k] == -1
					if res or hold != ph[k]:
						var key := "hold" if hold == 1 else "drop"
						ev[key] = int(ev[key]) + 1
						fired = "verdict"
					if pp[k] >= 0 and m.a_pinidx[k] > pp[k]:
						ev["pay"] = int(ev["pay"]) + 1
						fired = "pay"
				# A3: an event that made a noise must have raised its ring
				if fired != "" and fired != "wind":
					if m.av_burst[k] >= 0.999:
						twinned += 1
					else:
						untwinned += 1
						if untwinned <= 3:
							print("      untwinned '%s' at beam %d, tick %d of %s"
								% [fired, k, i, p.get_file()])
				# A4: the verdict may not run ahead of the classification
				if hold == 1 and m.a_locked[k] != 1:
					prophecy += 1
				# A4: a pending wrap is silent - nothing is said about how the
				# classification is going to come out
				if eng == 1 and m.a_locked[k] == -1 and pe[k] == 1 \
						and m.av_burst[k] >= 0.999:
					pending_noise += 1
				pe[k] = eng
				ph[k] = hold
				pw[k] = half
				plk[k] = m.a_locked[k] if eng == 1 else -1
				pp[k] = m.a_pinidx[k] if eng == 1 else -1
		m.free()

	print("  corpus events: %s" % str(ev))
	if untwinned > 0:
		_bad("A3 %d audible event(s) with no visual twin (%d twinned)"
			% [untwinned, twinned])
	elif twinned == 0:
		_bad("A3 no events at all - this gate would pass on silence")
	else:
		print("  A3 ok: %d audible events, %d with their ring on the same tick"
			% [twinned, twinned])
	if prophecy > 0:
		_bad("A4 the ring/voice said 'holds' on %d ticks the sim had not "
			% prophecy + "classified as locked")
	elif pending_noise > 0:
		_bad("A4 %d burst(s) fired while the wrap was still pending"
			% pending_noise)
	else:
		print("  A4 ok: no verdict ran ahead of the sim, nothing said while "
			+ "pending")
	if scrape_wrong > 0:
		_bad("A5 the ground voice was driven on %d tick(s) with no contact"
			% scrape_wrong)
	elif air_n == 0 or grit_n == 0 or load_n == 0:
		_bad("A5 a continuous voice was never driven (air %d grit %d load %d)"
			% [air_n, grit_n, load_n])
	else:
		print("  A5 ok: air on %d ticks (peak %.2f), ground on %d (peak %.2f), "
			% [air_n, air_max, grit_n, grit_max]
			+ "load on %d (%.1f-%.1f N)" % [load_n, load_min, load_max])

# -------------------------------------------------------------------- A6 --
func _a6() -> void:
	var out := []
	for on in [false, true]:
		var m: Node2D = TL.new_sim()
		m.av_on = on
		for t in 90:
			m.step_tick(m.body_pos + Vector2(0.5, -0.9), false)
		var best := 1e18
		for rep in 3:
			var t0 := Time.get_ticks_usec()
			var n := 400
			for t in n:
				var p := float(t) * 0.05
				m.step_tick(m.body_pos + Vector2(cos(p), sin(p)) * m.REACH, true)
			best = minf(best, float(Time.get_ticks_usec() - t0) / float(n))
		out.append(best)
		m.free()
	var off: float = out[0]
	var on2: float = out[1]
	print("  A6 tick cost: audio off %.0f us, audio on %.0f us  (+%.0f us, %+.2f%%"
		% [off, on2, on2 - off, (on2 - off) / off * 100.0]
		+ ", %.2f%% of a 16.7 ms frame)" % ((on2 - off) / 16667.0 * 100.0))
	if on2 - off > 400.0:
		_bad("A6 the audio pass costs %.0f us a tick" % (on2 - off))
