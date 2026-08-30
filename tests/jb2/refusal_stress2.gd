extends SceneTree
## THE PROPERTY THAT MUST SURVIVE: it never catches when it should not.
##
## The first cut of this probe just asked "did anything catch", and that turned
## out to measure nothing: a hand that swings and yanks for four seconds winds
## the chain genuinely onto the beam (peak wrap 12-21 rad, a real self-crossing
## on thousands of ticks), so a catch there is EARNED, not false. Both builds
## caught, and neither was wrong to.
##
## So the question has to be asked against the oracle instead: at the instant a
## catch fires, was the rope wrapped? That is the only definition of a false
## catch that means anything.
##
## PART A - the honest drape. Hand still, 90 ticks, so the chain stays the
## shape it was laid in. The number to watch is the peak measured wrap: a limp
## drape is pi of wrap by definition, and th_part sits at 3.4.
##
## PART B - the adversarial version. Hand closing and reopening every six ticks
## so a catch window is live throughout, and stirring hard enough to wind the
## rope on for real. Every catch is judged: WAS the rope wrapped at that tick?

const ORC := preload("res://tests/orc_lib.gd")

func _rig(path: String, r: float) -> Node2D:
	var m: Node2D = load(path).new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()      # open air
	for k in range(m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0)
	m.a_r[0] = r
	m.clear_anchors()
	return m

func _drape(m: Node2D, f: float, lean: float) -> void:
	var c: Vector2 = m.a_pos[0]
	var r: float = m.a_r[0] + 0.035
	var head: float = m.cum_len[m.NP - 1] * f
	var quarter: float = r * PI * 0.5
	for i in range(m.pos.size()):
		var s: float = m.cum_len[i]
		var p: Vector2
		if s < head - quarter:
			p = c + Vector2(-r + lean, -(head - quarter - s))
		elif s < head + quarter:
			var a: float = PI + (s - (head - quarter)) / r
			p = c + Vector2(cos(a), sin(a)) * r
		else:
			p = c + Vector2(r + lean, s - (head + quarter))
		m.pos[i] = p
		m.prv[i] = p
	m.body_pos = m.pos[0] + Vector2(0.0, 0.55)
	m.body_prv = m.body_pos

func _initialize() -> void:
	var radii := [0.10, 0.11, 0.14, 0.16, 0.20, 0.24]
	print("=== PART A: an honest drape. Hand still and closed, 90 ticks. ===")
	print("A limp drape is a half turn (pi = 3.142) of wrap. th_part = 3.400.")
	print("")
	print("  beam |   peak wrap MEASURED, shipped / patched   | caught? ship / patch")
	for r in radii:
		var pk := [0.0, 0.0]
		var got := [false, false]
		var judged := ["", ""]
		var att := [0.0, 0.0]
		var ct := [-1, -1]
		var trueA := 0.0
		for pi in range(2):
			var path: String = ["res://main.gd", "res://tests/main_wrap.gd"][pi]
			for f in [0.35, 0.45, 0.50, 0.55, 0.65]:
				for lean in [-0.05, 0.0, 0.05]:
					var m := _rig(path, r)
					_drape(m, f, lean)
					for t in range(90):
						m.step_tick(m.body_pos, true)
						pk[pi] = maxf(pk[pi], absf(m.a_theta[0]))
						if pi == 0:
							var mm: Dictionary = ORC.measure(m.pos, m.p_rad,
								m.a_pos[0], m.a_r[0])
							trueA = maxf(trueA, float(mm["A"]))
						if m.a_freelen[0] >= 0.0 and not got[pi]:
							got[pi] = true
							var mc: Dictionary = ORC.measure(m.pos, m.p_rad,
								m.a_pos[0], m.a_r[0])
							var wr: bool = (float(mc["A"]) >= m.th_part
								and bool(mc["near"])) or m._pinch(0)
							judged[pi] = "on a WRAP" if wr else "on a DRAPE"
							att[pi] = float(mc["A"])
							ct[pi] = t
					m.free()
		print("  %.2f |      %6.2f      /     %6.2f            |   %s  /  %s"
			% [r, pk[0], pk[1],
			("CAUGHT t%d %s A=%.2f" % [ct[0], judged[0], att[0]]) if got[0] else "no catch",
			("CAUGHT t%d %s A=%.2f" % [ct[1], judged[1], att[1]]) if got[1] else "no catch"])
	print("")
	print("=== PART B: stirred. Hand closes and reopens every 6 ticks, 240 ticks. ===")
	print("The rope really does wind on, so a catch here can be earned. Each one")
	print("is judged against the oracle AT THE TICK IT FIRED.")
	print("")
	print("  build          runs  catches  EARNED  FALSE  (false = the rope was")
	print("                                                not wrapped that tick)")
	for path in ["res://main.gd", "res://tests/main_wrap.gd"]:
		var runs := 0
		var catches := 0
		var earned := 0
		var false_ := 0
		var worst_false := 0.0
		for r in radii:
			for f in [0.35, 0.45, 0.50, 0.55, 0.65]:
				for lean in [-0.05, 0.0, 0.05]:
					for mode in range(3):
						runs += 1
						var m := _rig(path, r)
						_drape(m, f, lean)
						var was := false
						for t in range(240):
							var b: Vector2 = m.body_pos
							var tgt := b
							if mode == 1:
								tgt = b + Vector2(cos(t * 0.09),
									sin(t * 0.09) * 0.5) * m.REACH
							elif mode == 2:
								tgt = b + (Vector2(0.0, -1.0) if (t / 7) % 2 == 0
									else Vector2(0.9, 0.4)) * m.REACH
							m.step_tick(tgt, (t % 6) < 3)
							var e: bool = m.a_freelen[0] >= 0.0
							if e and not was:
								catches += 1
								var mm: Dictionary = ORC.measure(m.pos, m.p_rad,
									m.a_pos[0], m.a_r[0])
								var wrapped: bool = (float(mm["A"]) >= m.th_part
									and bool(mm["near"])) or m._pinch(0)
								if wrapped:
									earned += 1
								else:
									false_ += 1
									worst_false = maxf(worst_false, float(mm["A"]))
							was = e
						m.free()
		print("  %-14s %4d    %4d     %4d   %4d   (worst taut wrap on a false one: %.2f rad)"
			% [path.get_file(), runs, catches, earned, false_, worst_false])
	quit(0)
