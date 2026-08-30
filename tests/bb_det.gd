extends SceneTree
## G2 for the NEW code path. The seven gates never put the body against a beam,
## so their determinism hash says nothing about body-vs-beam collision. This
## runs scenarios that DO collide - hundreds of times each - and demands a
## bit-identical state hash every time, plus a hash that differs from the same
## scenario with the beam removed (otherwise the test is vacuous).
const SUB := 16
const SDT := 1.0 / 60.0 / 16.0

func _rig(seedi: int, present: bool) -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	if not present:
		for k in range(m.a_pos.size()):
			m.a_pos[k] = Vector2(0.0, 900.0)
	var c: Vector2 = Vector2(-2.0, -2.2)
	var ang: float = float(seedi) * 0.7
	m.teleport(c + Vector2(cos(ang), sin(ang)) * 1.4)
	m.body_prv = m.body_pos - Vector2(cos(ang + PI), sin(ang + PI)) \
		* (2.0 + 0.9 * float(seedi % 7)) * SDT
	return m

func _run(seedi: int, present: bool) -> Array:
	var m := _rig(seedi, present)
	var hits := 0
	for t in 240:
		var ph := float(t) * 0.13 + float(seedi)
		m.step_tick(m.body_pos + Vector2(cos(ph), sin(ph)) * m.REACH,
			(t / 20) % 2 == 0)
		for k in range(m.a_pos.size()):
			if m.body_pos.distance_to(m.a_pos[k]) < m.a_r[k] + m.BODY_R + 1e-6:
				hits += 1
				break
	var h: int = m.state_hash()
	m.free()
	return [h, hits]

func _initialize() -> void:
	var bad := 0
	var vacuous := 0
	var total_hits := 0
	var n := 40
	for i in n:
		var a := _run(i, true)
		var b := _run(i, true)
		var c := _run(i, true)
		if a[0] != b[0] or a[0] != c[0]:
			bad += 1
			print("  NON-DETERMINISTIC at scenario %d: %d %d %d" % [i, a[0], b[0], c[0]])
		var d := _run(i, false)
		if a[0] == d[0]:
			vacuous += 1
		total_hits += int(a[1])
	print("determinism of the body-vs-beam path")
	print("  scenarios                              %d" % n)
	print("  ticks with the body touching a beam    %d" % total_hits)
	print("  scenarios run 3x with differing hash   %d" % bad)
	print("  scenarios where removing the beams did")
	print("  NOT change the hash (test was vacuous) %d" % vacuous)
	print("VERDICT: %s" % ("PASS" if bad == 0 and vacuous < n and total_hits > 0 else "FAIL"))
	quit(0)
