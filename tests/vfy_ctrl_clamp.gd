extends SceneTree
## VERIFIER (lens: instrument), part 2. Two questions the skill probes did not
## ask of themselves:
##
##  A. THE CLAMP. main.gd step_tick does target_m = body + (cursor - body)
##     .limit_length(REACH), and every skill probe puts its intention ON that
##     circle (amp 1.0). So what does the sim actually receive of the noise
##     that hand_noise.gd emits? Measured as target_m minus the noise-free
##     target, per tick, split into the radial (along the arm) and tangential
##     components, at amp 1.0 (the stroke) and amp 0.7 (the pull).
##
##  B. THE CHAOS. lab_throw's BEAM winner (k0, L1.6, a0 PI*1.10, a1 -PI*0.42,
##     sd 9, nopull) thrown noise-free and again with a constant hand offset of
##     0.1 mm, 1 mm and 33 mm in x: tip position at FIXED ticks after the
##     stroke (not at peak speed, so timing cannot inflate it), and the
##     verdict. Also the same with the offset applied only during the windup
##     (removed at t = w), to see if the pre-stroke lie of the rope is the
##     carrier.
##
##   godot --headless --path . -s res://tests/vfy_ctrl_clamp.gd
const MAIN := preload("res://main.gd")
const HN := preload("res://tests/hand_noise.gd")

var m: Node2D

func new_lab() -> Node2D:
	var s: Node2D = MAIN.new()
	s.external_drive = true
	s.level_id = "lab"
	s.setup_sim()
	s.save_enabled = false
	return s

func stand_at(x: float, a0: float) -> void:
	m.teleport(Vector2(x, -m.BODY_R))
	for t in 90:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)

func clamp_probe(tier: String, amp: float, N: int) -> void:
	var a0 := PI * 1.10
	var dir := Vector2(cos(a0), sin(a0))
	var sr := 0.0
	var srr := 0.0
	var stt := 0.0
	var sn := 0.0
	var snn := 0.0
	var n := 0
	var sr_pos := 0
	for s in N:
		m = new_lab()
		stand_at(float(m.a_pos[0].x) - 1.6, a0)
		var hn: RefCounted = HN.new(tier, "clamp", s)
		for t in 250:
			var base: Vector2 = m.body_pos + dir * m.REACH * amp
			var e: Vector2 = hn.tick()
			m.step_tick(base + e, false)
			var recv: Vector2 = m.target_m - base
			var r := recv.dot(dir)
			var tg := recv.dot(Vector2(-dir.y, dir.x))
			sr += r
			srr += r * r
			stt += tg * tg
			sn += e.length_squared()
			snn += e.dot(dir) * e.dot(dir)
			if e.dot(dir) > 0.0:
				sr_pos += 1
			n += 1
		m.free()
	var mean_r := sr / n
	print("  CLAMP tier %-9s amp %.1f: emitted rms %.1f mm (radial sd %.1f)  RECEIVED radial mean %+.1f mm sd %.1f mm, tangential sd %.1f mm, total rms %.1f mm  (outward-radial ticks %.0f%%)" % [
		tier, amp, sqrt(sn / n) * 1000.0, sqrt(snn / n) * 1000.0, mean_r * 1000.0,
		sqrt(maxf(0.0, srr / n - mean_r * mean_r)) * 1000.0, sqrt(stt / n) * 1000.0,
		sqrt((srr + stt) / n) * 1000.0, 100.0 * sr_pos / n])

func throw(off: Vector2, windup_only: bool) -> Dictionary:
	var k := 0
	var c := {"a0": PI * 1.10, "a1": -PI * 0.42, "sd": 9, "pull": false, "w": 120}
	m = new_lab()
	stand_at(float(m.a_pos[k].x) - 1.6, float(c["a0"]))
	var grip := false
	var closes := 0
	var sd: int = int(c["sd"])
	var w: int = int(c["w"])
	var caught := false
	var et := -1
	var tips := {}
	var peak := -1.0
	var tip_pk := Vector2.ZERO
	for t in w + 130:
		var ang: float = float(c["a0"]) if t < w else float(c["a1"])
		var e := off if (not windup_only or t < w) else Vector2.ZERO
		var tgt: Vector2 = m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH + e
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW and float(m.a_freelen[k]) < 0.0:
			grip = false
		var cue := absf(float(m.a_theta[k])) >= 2.6
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		m.step_tick(tgt, grip)
		if t >= w and m.tip_speed > peak:
			peak = m.tip_speed
			tip_pk = m.pos[m.NP - 1]
		if t - w in [10, 20, 30, 45, 60]:
			tips[t - w] = m.pos[m.NP - 1]
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	var green := false
	if caught:
		for t in 55:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		green = bool(m._holds(k))
	var h: int = m.state_hash()
	m.free()
	return {"caught": caught, "green": green, "et": et, "tips": tips, "peak": tip_pk, "hash": h}

func _initialize() -> void:
	print("")
	print("A. WHAT THE SIM RECEIVES OF THE NOISE (limit_length(REACH) in step_tick), 20 throws x 250 ticks, standing at the BEAM winner's stance:")
	for tier in ["mouse03", "mouse1", "trackpad"]:
		clamp_probe(tier, 1.0, 20)
	clamp_probe("trackpad", 0.7, 20)
	print("")
	print("B. TIP CHAOS AT FIXED TICKS, BEAM winner, constant hand offset in x:")
	var ref := throw(Vector2.ZERO, false)
	var ref2 := throw(Vector2.ZERO, false)
	print("  null twice: hash equal %s  verdict %s et %d" % [ref["hash"] == ref2["hash"], "GREEN" if ref["green"] else ("caught" if ref["caught"] else "miss"), ref["et"]])
	for spec in [[0.0001, false], [0.001, false], [0.0333, false], [0.0001, true], [0.001, true], [0.0333, true]]:
		var r := throw(Vector2(float(spec[0]), 0.0), bool(spec[1]))
		var line := "  off %6.1f mm %-11s verdict %-6s et %3d | tip |d| vs null at t-w=" % [
			float(spec[0]) * 1000.0, "windup-only" if bool(spec[1]) else "whole-throw",
			"GREEN" if r["green"] else ("caught" if r["caught"] else "miss"), r["et"]]
		for tk in [10, 20, 30, 45, 60]:
			if (r["tips"] as Dictionary).has(tk) and (ref["tips"] as Dictionary).has(tk):
				line += " %d:%.3f" % [tk, (r["tips"][tk] as Vector2).distance_to(ref["tips"][tk])]
			else:
				line += " %d:-" % tk
		line += " | peak-tip |d| %.3f" % (r["peak"] as Vector2).distance_to(ref["peak"])
		print(line)
	quit(0)
