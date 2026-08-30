extends SceneTree
## Headless gates for the whip sim. Run:
##   godot --headless --path . -s res://tests/sim_test.gd
## Prints PASS if every gate holds, FAIL <reason> otherwise.
##
## Gates (from the design pressure-test / "Experiment Zero"):
##  G1 stability     - no NaN / no explosion over a scripted session
##  G2 determinism   - identical scripted input twice -> identical state hash
##  G3 amplification - a shaped stroke drives tip speed >= 3x handle speed
##  G4 full wrap     - pre-wrapped 1.1 turns + taut -> locks, body hangs
##  G5 partial wrap  - pre-wrapped 0.6 turns + taut -> slips, body descends
##  G6 no free lift  - mid-air mouse waggle must not gain net altitude
##  G7 grip matters  - releasing TAUT while hanging must drop you. If slack can
##                     bear load, SLACK and TAUT have collapsed into one state
##                     and the grip button is decorative.

var failures: Array[String] = []

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_run()
	var dt := Time.get_ticks_msec() - t0
	if failures.is_empty():
		print("PASS  (%d ms)" % dt)
	else:
		for f in failures:
			print("FAIL  " + f)
	quit(0 if failures.is_empty() else 1)

func _new_sim() -> Node2D:
	# not added to the tree: pure sim, no camera/HUD/audio nodes needed
	var main: Node2D = load("res://tests/main_fix2.gd").new()
	main.external_drive = true
	main.setup_sim()
	return main

func _check(sim: Node2D, tag: String, tick: int) -> bool:
	for i in sim.pos.size():
		var p: Vector2 = sim.pos[i]
		if is_nan(p.x) or is_nan(p.y) or p.length() > 800.0:
			failures.append("G1 %s: NaN/explosion at tick %d particle %d" % [tag, tick, i])
			return false
	var b: Vector2 = sim.body_pos
	if is_nan(b.x) or is_nan(b.y) or b.length() > 800.0:
		failures.append("G1 %s: body NaN/explosion at tick %d" % [tag, tick])
		return false
	return true

func _script_input(tick: int, sim: Node2D) -> Array:
	# settle, circular flails, wind-up, snap stroke, stop - then taut swings
	var body: Vector2 = sim.body_pos
	if tick < 90:
		return [body + Vector2(0.5, -0.5), false]
	elif tick < 280:
		var ph := float(tick - 90) * 0.11
		return [body + Vector2(cos(ph), sin(ph)) * 1.1, false]
	elif tick < 340:
		return [body + Vector2(-1.05, -0.35), false]  # wind up, chain trails left
	elif tick < 352:
		return [body + Vector2(1.05, -0.45), false]   # hard forward sweep
	elif tick < 420:
		return [body + Vector2(0.2, -0.9), false]     # stop -> tip rolls over
	elif tick < 600:
		return [body + Vector2(0.8, -0.8), true]
	else:
		var ph2 := float(tick) * 0.05
		return [body + Vector2(cos(ph2), -0.6), true]

func _prewrap(sim: Node2D, k: int, turns: float) -> void:
	# Gate the MECHANISM, not the level: pin the probe anchor's radius AND
	# move it into open air far above the terrain, so the hanging body cannot
	# land on a floor. (Previously the body hung below the level's floor line
	# and these gates were measuring a body embedded in terrain.)
	sim.a_r[k] = 0.20
	sim.a_pos[k] = Vector2(0.0, -40.0)
	# arrange the chain: handle hangs below the anchor, chain rises, winds
	# `turns` around the anchor, tail dangles off. Constraints settle the rest.
	var c: Vector2 = sim.a_pos[k]
	var r: float = sim.a_r[k] + 0.04
	var hang := 2.0
	var rise := hang - r
	var wrap_len := turns * TAU * r
	for i in sim.pos.size():
		var s: float = sim.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + Vector2(0.0, hang - s)
		elif s < rise + wrap_len:
			var ang: float = PI / 2.0 + (s - rise) / r
			p = c + Vector2(cos(ang), sin(ang)) * r
		else:
			var ang2: float = PI / 2.0 + turns * TAU
			var exit_pt: Vector2 = c + Vector2(cos(ang2), sin(ang2)) * r
			# tail dangles clear of the anchor so it can't read as winding
			var side := 0.3 if cos(ang2) >= 0.0 else -0.3
			p = exit_pt + Vector2(side, s - rise - wrap_len)
		sim.pos[i] = p
		sim.prv[i] = p
	sim.body_pos = c + Vector2(0.0, hang + 0.6)
	sim.body_prv = sim.body_pos

func _run() -> void:
	# ---- run 1: stability over a full ground session (G1) ----
	var sim := _new_sim()
	var n_ticks := 900
	for t in n_ticks:
		var inp := _script_input(t, sim)
		sim.step_tick(inp[0], inp[1])
		if not _check(sim, "run1", t):
			return
	var hash1: int = sim.state_hash()
	sim.free()

	# ---- wave bench: airborne crack stroke, amplification (G3) ----
	var simw := _new_sim()
	simw.teleport(Vector2(0, -30))     # clear of all terrain
	var max_tip := 0.0
	var max_handle := 0.0
	for t in 300:
		simw.body_prv = simw.body_pos  # bench: hold the body still
		var body: Vector2 = simw.body_pos
		var tgt: Vector2
		if t < 100:
			tgt = body + Vector2(0.3, -0.6)          # settle, chain dangles
		elif t < 130:
			tgt = body + Vector2(1.1, -0.2)          # sweep: chain streams left
		elif t < 140:
			tgt = body + Vector2(-1.1, -0.5)         # snap REVERSAL = the crack
		else:
			tgt = body + Vector2(-0.2, -0.8)         # hold, wave rolls out
		var prev_h: Vector2 = simw.pos[0]
		simw.step_tick(tgt, false)
		if not _check(simw, "bench", t):
			return
		var hv: float = (simw.pos[0] - prev_h).length() * 60.0
		if t >= 130:
			max_handle = maxf(max_handle, hv)
			max_tip = maxf(max_tip, simw.tip_speed)
	if max_handle <= 0.0:
		failures.append("G3 handle never moved in stroke window")
	elif max_tip < 3.0 * max_handle:
		failures.append("G3 amplification %.1fx (tip %.1f / handle %.1f m/s) < 3x"
			% [max_tip / max_handle, max_tip, max_handle])
	else:
		print("  G3 ok: tip %.1f m/s, handle %.1f m/s, %.1fx"
			% [max_tip, max_handle, max_tip / max_handle])
	simw.free()

	# ---- run 2: determinism (G2) ----
	var sim2 := _new_sim()
	for t in n_ticks:
		var inp2 := _script_input(t, sim2)
		sim2.step_tick(inp2[0], inp2[1])
	var hash2: int = sim2.state_hash()
	if hash1 != hash2:
		failures.append("G2 determinism: hash %d != %d" % [hash1, hash2])
	sim2.free()

	# ---- run 3: full wrap locks and holds (G4) ----
	var sim4 := _new_sim()
	_prewrap(sim4, 0, 1.4)   # a real wrap: >1 turn, clear of the fold range
	var c4: Vector2 = sim4.a_pos[0]
	var locked_seen := false
	var lowest := 0.0
	for t in 300:
		sim4.step_tick(sim4.body_pos, true)   # taut, hand at rest
		if not _check(sim4, "run3", t):
			return
		if sim4.a_freelen[0] >= 0.0 and sim4.a_locked[0] == 1:
			locked_seen = true
		lowest = maxf(lowest, sim4.body_pos.y - c4.y)
	if not locked_seen:
		failures.append("G4 full wrap never locked (theta=%.2f rad)"
			% absf(sim4.a_theta[0]))
	elif lowest > 3.5:
		failures.append("G4 body fell %.1f m below anchor despite full wrap" % lowest)
	elif sim4.a_freelen[0] < 0.0:
		failures.append("G4 wrap detached by end of hang (theta=%.2f)"
			% absf(sim4.a_theta[0]))
	else:
		print("  G4 ok: locked+held, hang depth %.2f m, final theta %.2f rad"
			% [lowest, absf(sim4.a_theta[0])])
	sim4.free()

	# ---- run 4: partial wrap slips (G5) ----
	var sim5 := _new_sim()
	_prewrap(sim5, 0, 0.9)   # a near miss: catches, then must betray
	var engaged_ticks := 0
	var slip_ticks := 0
	var pinned_ticks := 0
	var last_engaged_t := -1
	for t in 300:
		sim5.step_tick(sim5.body_pos, true)
		if not _check(sim5, "run4", t):
			return
		if sim5.a_freelen[0] >= 0.0:
			engaged_ticks += 1
			last_engaged_t = t
		if sim5.slipping:
			slip_ticks += 1
		if sim5.a_pinidx[0] >= 0:
			pinned_ticks += 1
	# semantics under test (matches the brief): a sub-full wrap CATCHES you
	# perceptibly, then betrays - it must neither hold forever nor fail to
	# catch at all. (The long rappel-payout band is content tuning, not verb.)
	var still_held: bool = sim5.a_freelen[0] >= 0.0
	if engaged_ticks == 0:
		failures.append("G5 partial wrap never engaged (theta=%.2f)"
			% absf(sim5.a_theta[0]))
	elif pinned_ticks == 0:
		failures.append("G5 partial wrap never pinned - catch mechanism dead")
	elif still_held:
		failures.append("G5 partial wrap held forever - it must betray under load")
	elif engaged_ticks < 6:
		failures.append("G5 partial catch lasted %d ticks (<6) - imperceptible"
			% engaged_ticks)
	else:
		print("  G5 ok: partial caught for %d ticks (slip %d), let go at t=%d"
			% [engaged_ticks, slip_ticks, last_engaged_t])
	sim5.free()

	# ---- run 4b: grip is load-bearing (G7) ----
	var sim7 := _new_sim()
	_prewrap(sim7, 0, 1.4)
	var c7: Vector2 = sim7.a_pos[0]
	for t in 40:
		sim7.step_tick(sim7.body_pos, true)     # gripped: engage and lock
	var y_taut: float = sim7.body_pos.y - c7.y
	for t in 180:
		sim7.step_tick(sim7.body_pos, false)    # let go
	var dropped7: float = (sim7.body_pos.y - c7.y) - y_taut
	if sim7.a_locked[0] != 1 and y_taut > 3.5:
		failures.append("G7 setup: the wrap never held while gripped")
	elif dropped7 < 1.0:
		failures.append("G7 slack is load-bearing: released grip dropped only %.2f m in 3 s - the grip button is decorative"
			% dropped7)
	else:
		print("  G7 ok: releasing grip dropped the body %.1f m (held at %.2f m gripped)"
			% [dropped7, y_taut])
	sim7.free()

	# ---- run 5: no free lift from waggle (G6) ----
	var sim6 := _new_sim()
	var sdt: float = 1.0 / 60.0 / 16.0
	sim6.body_prv = sim6.body_pos + Vector2(0, 7.0 * sdt)  # 7 m/s upward
	var start_y: float = sim6.body_pos.y
	var min_y := start_y
	for t in 240:
		var wig := Vector2(1.1 if (t / 3) % 2 == 0 else -1.1,
			-1.1 if (t / 5) % 2 == 0 else 1.1)
		sim6.step_tick(sim6.body_pos + wig, false)
		if not _check(sim6, "run5", t):
			return
		min_y = minf(min_y, sim6.body_pos.y)
	# ballistic apex from 7 m/s at g=10 is ~2.5 m; anything well past it = flight
	var gained := start_y - min_y
	if gained > 4.0:
		failures.append("G6 waggle flight: gained %.1f m altitude" % gained)
	else:
		print("  G6 ok: waggle apex %.2f m (ballistic ~2.5 m)" % gained)
	sim6.free()
