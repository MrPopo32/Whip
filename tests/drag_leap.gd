extends SceneTree
## THE DRAG ON A REAL LEG OF THE LEVEL.
##
## Everything above is a rigged wrap. This one uses the validated leap policy in
## tests/bot_leap.gd on the level's own beams: pump on beam A, open the hand at
## the policy's release angle, throw at beam B, close on it.
##
## Method: run the policy once and RECORD its (cursor, grip) input tape. Then
## replay that identical tape through four sims that differ only in what happens
## at the release tick. Same input, different physics - so any divergence is the
## beam's doing and nothing else.
##
##   A  shipped                       (control tape is recorded from this arm)
##   D  pin + static-mu window cleared before the release tick's substeps
##   B  D, plus anchor_mu = 0 on the beam being left
##   C  the beam being left is teleported clear at the release instant
##
## The outcome that matters: does the leap still LAND on beam B?

const LEAP := preload("res://tests/bot_leap_drag.gd")
const EPS := 0.06
const HORIZON := 30      # 500 ms after the hand opens

func _contacts(m: Node2D, k: int) -> int:
	var c: Vector2 = m.a_pos[k]
	var n := 0
	for i in m.pos.size():
		if (m.pos[i] - c).length() < m.a_r[k] + m.p_rad[i] + EPS:
			n += 1
	return n

func _static_pop(m: Node2D, k: int) -> int:
	if m.a_freelen[k] < 0.0 or m.a_pinidx[k] < 0:
		return 0
	var lo: int = m.a_pinidx[k] + m.a_wlo[k]
	var hi: int = m.a_pinidx[k] + m.a_whi[k]
	var c: Vector2 = m.a_pos[k]
	var n := 0
	for i in m.pos.size():
		if i >= lo and i <= hi and (m.pos[i] - c).length() < m.a_r[k] + m.p_rad[i] + EPS:
			n += 1
	return n

## Record the policy's input tape and find the release tick.
func _record(ka: int, kb: int, hang: float, turns: float, th0: float,
		maxt: int) -> Dictionary:
	var m: Node2D = LEAP.rig_level(ka, hang, turns, th0)
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[ka] < 0.0:
		m.free()
		return {"ok": false, "why": "the rig never caught beam A"}
	var st: Dictionary = LEAP.leap_begin(m, ka, kb)
	var prev: Vector2 = m.body_pos
	var cx := PackedFloat32Array()
	var cy := PackedFloat32Array()
	var gr := PackedInt32Array()
	var rel := -1
	for t in maxt:
		var cg: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		var cur: Vector2 = cg[0]
		var g: bool = cg[1]
		cx.append(cur.x); cy.append(cur.y); gr.append(1 if g else 0)
		if rel < 0 and not g:
			rel = t
		m.step_tick(cur, g)
		if rel >= 0 and t > rel + 100:
			break
	var res := {"ok": rel >= 0, "rel": rel, "cx": cx, "cy": cy, "gr": gr,
		"phase": st["phase"], "n": cx.size(), "falls": m.falls}
	m.free()
	return res

## mode 0 A | 1 D | 2 B | 3 C
func _replay(ka: int, kb: int, hang: float, turns: float, th0: float,
		tape: Dictionary, mode: int) -> Dictionary:
	var m: Node2D = LEAP.rig_level(ka, hang, turns, th0)
	for t in 30:
		m.step_tick(m.body_pos, true)
	var rel: int = tape["rel"]
	var n: int = tape["n"]
	var vx := PackedFloat32Array(); var vy := PackedFloat32Array()
	var bx := PackedFloat32Array(); var by := PackedFloat32Array()
	var con := PackedInt32Array()
	var caught := -1
	var last_touch := -1
	var resnag := -1
	var cont_rel := 0
	var stat_rel := 0
	var th_rel := 0.0
	var v_rel := 0.0
	var dir := Vector2.ZERO
	for t in n:
		if t == rel:
			cont_rel = _contacts(m, ka)
			stat_rel = _static_pop(m, ka)
			th_rel = absf(m.a_theta[ka])
			var bv: Vector2 = m.body_pos - m.body_prv
			v_rel = bv.length() / m.SDT
			dir = bv.normalized()
			if mode == 1 or mode == 2:
				m.a_freelen[ka] = -1.0; m.a_pinidx[ka] = -1
				m.a_locked[ka] = -1; m.a_armed[ka] = 0
			if mode == 2:
				m.anchor_mu = 0.0
			if mode == 3:
				m.a_freelen[ka] = -1.0; m.a_pinidx[ka] = -1
				m.a_locked[ka] = -1; m.a_armed[ka] = 0
				m.a_pos[ka] = Vector2(0.0, 900.0)
		m.step_tick(Vector2(tape["cx"][t], tape["cy"][t]), tape["gr"][t] == 1)
		var v: Vector2 = (m.body_pos - m.body_prv) / m.SDT
		vx.append(v.x); vy.append(v.y)
		bx.append(m.body_pos.x); by.append(m.body_pos.y)
		if t >= rel:
			var c := 0 if mode == 3 else _contacts(m, ka)
			con.append(c)
			if c > 0:
				last_touch = t - rel
			if resnag < 0 and m.a_freelen[ka] >= 0.0:
				resnag = t - rel
			if caught < 0 and m.a_freelen[kb] >= 0.0:
				caught = t - rel
	var out := {"vx": vx, "vy": vy, "bx": bx, "by": by, "con": con,
		"caught": caught, "last_touch": last_touch, "resnag": resnag,
		"cont_rel": cont_rel, "stat_rel": stat_rel, "th_rel": th_rel,
		"v_rel": v_rel, "dir": dir, "falls": m.falls,
		"beam": m.a_pos[ka] if mode != 3 else Vector2.ZERO,
		"held": m.a_freelen[kb] >= 0.0, "locked": m.a_locked[kb]}
	m.free()
	return out

func _leg(ka: int, kb: int, hang: float, turns: float, th0_deg: float) -> void:
	var th0: float = deg_to_rad(th0_deg)
	var tape := _record(ka, kb, hang, turns, th0, 3000)
	if not tape["ok"]:
		print("  A%d -> A%d  h%.1f t%.1f a%.0f  (%s)"
			% [ka, kb, hang, turns, th0_deg,
			   tape.get("why", "the pump never reached the policy release angle")])
		return
	var rel: int = tape["rel"]
	var n: int = tape["n"]
	if rel + HORIZON + 5 >= n:
		print("  A%d -> A%d  (window too short)" % [ka, kb])
		return
	var A := _replay(ka, kb, hang, turns, th0, tape, 0)
	var C := _replay(ka, kb, hang, turns, th0, tape, 3)
	var D := _replay(ka, kb, hang, turns, th0, tape, 1)
	var B := _replay(ka, kb, hang, turns, th0, tape, 2)
	if A["falls"] > 0 or C["falls"] > 0:
		print("  A%d -> A%d  DROPPED: main.gd's y>6 safety net fired inside the leg"
			% [ka, kb])
		return
	var h := rel + HORIZON
	var dir: Vector2 = A["dir"]
	var beam: Vector2 = A["beam"]
	var vA := Vector2(A["vx"][h], A["vy"][h])
	var vC := Vector2(C["vx"][h], C["vy"][h])
	var dv := vA - vC
	var pA := Vector2(A["bx"][h], A["by"][h])
	var pC := Vector2(C["bx"][h], C["by"][h])
	var tob := (beam - pA).normalized()
	print("  A%d(%.1f,%.1f) -> A%d   rig h%.1f t%.1f a%.0f   released at tick %d, %.2f m/s"
		% [ka, beam.x, beam.y, kb, hang, turns, th0_deg, rel, A["v_rel"]])
	print("     at release: %.2f turns of taut wrap, %d of 26 particles on the beam, %d of them under STATIC mu"
		% [A["th_rel"] / TAU, A["cont_rel"], A["stat_rel"]])
	print("     rope leaves the beam after %d ticks (%.0f ms)"
		% [A["last_touch"] + 1, (A["last_touch"] + 1) * 1000.0 / 60.0])
	print("     at 500 ms: %.2f m/s of speed missing (%.0f%% of the launch), heading bent %+.1f deg,"
		% [vC.length() - vA.length(),
		   100.0 * (vC.length() - vA.length()) / maxf(A["v_rel"], 0.01),
		   rad_to_deg(vC.angle_to(vA))])
	print("                %.2f m/s aimed back at the beam, %.2f m short of the ideal launch"
		% [dv.dot(tob), (pC - pA).length()])
	var vD := Vector2(D["vx"][h], D["vy"][h])
	var vB := Vector2(B["vx"][h], B["vy"][h])
	print("     same number with the pin+static mu precleared: %.2f m/s ; on a frictionless beam: %.2f m/s"
		% [vC.length() - vD.length(), vC.length() - vB.length()])
	print("     LANDED beam A%d?  shipped %s (tick %d)   ideal %s (tick %d)   frictionless %s"
		% [kb, "YES" if A["held"] else "NO ", A["caught"],
		   "YES" if C["held"] else "NO ", C["caught"],
		   "YES" if B["held"] else "NO "])
	if A["resnag"] >= 0:
		print("     *** the beam it left RE-TOOK the rope %d ticks after release ***"
			% A["resnag"])
	print("")

func _initialize() -> void:
	print("=== THE DRAG ON A REAL LEG OF THE LEVEL =======================")
	print("beams: 0(-2.0,-2.2) 1(3.6,-2.2) 2(15.6,-2.2) 3(21.4,-2.2) 4(31.4,0.8)")
	print("       5(41.4,3.8) 6(49.4,6.8) 7(27.2,-1.5) 8(35.0,1.5) 9(42.8,4.5)")
	print("       10(50.6,7.5).  Only legs whose body stays above main.gd's y>6")
	print("       safety net can be measured at all; the rest are dropped.")
	print("")
	for cs: Array in [[7, 8, 2.8, 1.8, 6.0], [7, 8, 2.4, 1.8, 6.0],
			[7, 8, 3.2, 1.8, 6.0], [7, 8, 2.8, 1.3, 6.0],
			[7, 8, 2.8, 2.2, 6.0], [7, 8, 2.8, 1.8, 10.0],
			[7, 8, 2.8, 1.8, 3.0], [3, 7, 2.8, 1.8, 6.0],
			[3, 7, 2.4, 1.8, 6.0], [3, 7, 3.2, 1.8, 6.0],
			[0, 1, 2.8, 1.8, 6.0], [1, 2, 2.8, 1.8, 6.0],
			[4, 8, 2.8, 1.8, 6.0], [2, 3, 2.8, 1.8, 6.0]]:
		_leg(cs[0], cs[1], cs[2], cs[3], cs[4])
	quit(0)
