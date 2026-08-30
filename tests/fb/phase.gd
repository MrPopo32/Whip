extends SceneTree
## THE RELEASE PHASE SWEEP, on the real level's own gaps.
## For each pair, pump on A, open the hand at every release angle on the same
## upswing, and let bot_leap's shipped stroke do the rest. Reports whether the
## far beam is taken, when, and how much of the airborne budget was left.

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

const RELS := [8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 46.0, 52.0, 62.0]

func new_level() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	return m

func contacts(m: Node2D, k: int) -> int:
	var c: Vector2 = m.a_pos[k]
	var n := 0
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[k] - m.p_rad[i] < 0.005:
			n += 1
	return n

func snaps(ka: int, kb: int, hang: float) -> Array:
	var m := new_level()
	LEAP._wind_on(m, ka, hang, 1.8, deg_to_rad(6.0))
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[ka] < 0.0:
		m.free(); return []
	var dir: float = signf(float(m.a_pos[kb].x) - float(m.a_pos[ka].x))
	var prev: Vector2 = m.body_pos
	var pk := 0.0; var last_pk := 0.0; var half := 0; var sgn := 0.0
	var got := {}
	var out: Array = []
	for t in 2400:
		if m.a_freelen[ka] < 0.0: break
		var s := PUMP.swing_state(m, ka, prev)
		var th: float = rad_to_deg(float(s["theta"])) * dir
		var om: float = float(s["omega"]) * dir
		pk = maxf(pk, absf(th))
		var sg: float = signf(th)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0:
				last_pk = pk; half += 1
			sgn = sg; pk = 0.0
		if (last_pk >= 55.0 or half >= 22) and om > 0.0:
			for rel in RELS:
				if th >= float(rel) and not got.has(rel):
					got[rel] = true
					out.append({"snap": LEAP.save_state(m), "prev": prev,
						"rel": float(rel), "amp": last_pk,
						"teth": float(m.a_freelen[ka]),
						"pin": int(m.a_pinidx[ka]),
						"wrap": absf(float(m.a_theta[ka]))})
		if got.size() == RELS.size(): break
		if t > 1200 and out.is_empty(): break
		var cur: Vector2 = PUMP.pump_cursor(m, ka, prev, 95.0)
		prev = m.body_pos
		m.step_tick(cur, true)
	m.free()
	return out

func fly(ka: int, kb: int, hang: float, e: Dictionary, kill: bool) -> Dictionary:
	var m := new_level()
	LEAP._wind_on(m, ka, hang, 1.8, deg_to_rad(6.0))
	LEAP.load_state(m, e["snap"])
	if kill:
		m.a_pos[ka] = Vector2(0.0, 900.0); m.a_r[ka] = 0.001
		m.a_freelen[ka] = -1.0; m.a_pinidx[ka] = -1; m.a_locked[ka] = -1
	var p: Dictionary = LEAP.default_policy()
	p["amp_max"] = 250.0; p["max_half"] = 22
	var st := LEAP.leap_begin(m, ka, kb, p)
	st["phase"] = "fly"; st["rel_t"] = 0; st["f"] = 0
	var B: Vector2 = m.a_pos[kb]
	var v: Vector2 = (m.body_pos - Vector2(e["prev"])) * 60.0
	var tmin := 0; var dmin := 1e9
	for i in 240:
		var tt: float = float(i) / 60.0
		var q: Vector2 = m.body_pos + v * tt + Vector2(0.0, 5.0 * tt * tt)
		if q.distance_to(B) < dmin: dmin = q.distance_to(B); tmin = i
	st["s0"] = clampi(tmin - 38, 4, 18)
	st["wind"] = (B - m.body_pos).normalized().rotated(PI)
	var prev: Vector2 = m.body_pos
	var drag_end := -1
	var caught := -1
	var ground := -1
	var alt := -1
	for f in 220:
		var cg: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		m.step_tick(cg[0], cg[1])
		if not kill and contacts(m, ka) > 0:
			drag_end = f
		if m.grounded and ground < 0: ground = f
		if caught < 0 and m.a_freelen[kb] >= 0.0: caught = f
		for j in m.a_pos.size():
			if j != ka and j != kb and m.a_freelen[j] >= 0.0 and alt < 0:
				alt = j
		if caught >= 0 and f > caught + 90: break
		if ground >= 0 and f > ground + 30: break
	var held: bool = m.a_freelen[kb] >= 0.0
	var lk: int = int(m.a_locked[kb])
	var teth: float = float(m.a_freelen[kb])
	m.free()
	return {"drag": drag_end, "caught": caught, "ground": ground,
		"held": held, "lk": lk, "teth": teth, "alt": alt}

func pair(ka: int, kb: int, label: String) -> void:
	var m := new_level()
	var gap: float = m.a_pos[ka].distance_to(m.a_pos[kb])
	var dx: float = float(m.a_pos[kb].x) - float(m.a_pos[ka].x)
	m.free()
	print("== %s : A%d -> A%d, %.1f m along, %.2f m apart ==" % [label, ka, kb, dx, gap])
	for hang in [2.0, 2.4, 2.8]:
		var ss := snaps(ka, kb, hang)
		if ss.is_empty():
			print("   hang %.1f m: never pumped to a release" % hang); continue
		var line := "   hang %.1f (tether %.2f, wrap %.2f):  " % [
			hang, float(ss[0]["teth"]), float(ss[0]["wrap"])]
		var ok: Array = []
		var okfree: Array = []
		for e in ss:
			var r := fly(ka, kb, hang, e, false)
			var rf := fly(ka, kb, hang, e, true)
			if bool(r["held"]):
				ok.append("%.0f%s" % [float(e["rel"]), "L" if int(r["lk"]) == 1 else "p"])
			if bool(rf["held"]):
				okfree.append("%.0f%s" % [float(e["rel"]), "L" if int(rf["lk"]) == 1 else "p"])
		print(line)
		print("       real dismount holds A%d at rel:  %s" % [kb,
			", ".join(PackedStringArray(ok)) if not ok.is_empty() else "NOTHING - every release angle misses"])
		print("       free dismount holds A%d at rel:  %s" % [kb,
			", ".join(PackedStringArray(okfree)) if not okfree.is_empty() else "nothing"])
		# drag length for the record
		var dg: Array = []
		for e in ss:
			var r := fly(ka, kb, hang, e, false)
			dg.append(int(r["drag"]))
		var lo := 9999; var hi := -1
		for d in dg:
			lo = mini(lo, int(d)); hi = maxi(hi, int(d))
		print("       chain still on A%d until tick %d-%d after the hand opened" % [ka, lo, hi])
	print("")

func _initialize() -> void:
	print("RELEASE PHASE vs THE GAP. 'L' = a lock, 'p' = a partial (it betrays).")
	print("rel is degrees past the bottom of the swing on the way up.")
	print("")
	pair(3, 7, "the door onto the fast line")
	pair(7, 8, "fast line leg 1")
	pair(8, 9, "fast line leg 2")
	pair(0, 1, "the school, 5.6 m")
	quit(0)
