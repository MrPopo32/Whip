extends SceneTree
## THE DISMOUNT DRAG, measured by counterfactual.
##
## Releasing clears a_freelen / a_pinidx / a_locked on the release tick. What it
## does NOT clear is the CHAIN: at the instant you open your hand the rope is
## still physically coiled one or two turns round the beam, and the rope is
## inextensible in BOTH modes (SLACK_STIFF = 1.0). So the coil has to unspool
## over the beam surface before the body is really free, paying rope round a
## cylinder against anchor_mu contact friction.
##
## Fork A - the real build. Hand opens, coil unspools.
## Fork B - the counterfactual. Same tick, same state, but the beam is teleported
##          out of the world so the coil is free to fly along with the body.
##          Everything else (gravity, rope inertia, arm spring, hand input) is
##          bit-identical. A minus B IS the beam's post-release influence.
## Fork C - pure ballistics from the release velocity. The "ideal launch".

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

const RELS := [8.0, 16.0, 24.0, 32.0, 40.0, 52.0, 62.0]
const HORIZON := 90

func _park(m: Node2D) -> void:
	m.a_pos[0] = Vector2(0.0, 900.0)
	m.a_r[0] = 0.001

# min gap between any chain particle and the beam surface
func _gap(m: Node2D) -> float:
	var c: Vector2 = m.a_pos[0]
	var g := 1e9
	for i in m.pos.size():
		g = minf(g, m.pos[i].distance_to(c) - m.a_r[0] - m.p_rad[i])
	return g

func _contacts(m: Node2D) -> int:
	var c: Vector2 = m.a_pos[0]
	var n := 0
	for i in m.pos.size():
		if m.pos[i].distance_to(c) - m.a_r[0] - m.p_rad[i] < 0.005:
			n += 1
	return n

func _snaps(hang: float, r: float, turns: float, drop: float) -> Array:
	var m := PUMP.rig(hang, r, turns, deg_to_rad(6.0), drop)
	for t in 30:
		m.step_tick(m.body_pos, true)
	if m.a_freelen[0] < 0.0:
		m.free()
		return []
	var prev: Vector2 = m.body_pos
	var pk := 0.0
	var last_pk := 0.0
	var half := 0
	var sgn := 0.0
	var got := {}
	var out: Array = []
	for t in 2400:
		if m.a_freelen[0] < 0.0:
			break
		var s := PUMP.swing_state(m, 0, prev)
		var th: float = rad_to_deg(float(s["theta"]))
		var om: float = float(s["omega"])
		pk = maxf(pk, absf(th))
		var sg: float = signf(th)
		if sg != 0.0 and sg != sgn:
			if sgn != 0.0:
				last_pk = pk
				half += 1
			sgn = sg
			pk = 0.0
		if (last_pk >= 55.0 or half >= 22) and om > 0.0:
			for rel in RELS:
				if th >= float(rel) and not got.has(rel):
					got[rel] = true
					out.append({"snap": LEAP.save_state(m), "prev": prev,
						"rel": float(rel), "amp": last_pk,
						"pin": int(m.a_pinidx[0]), "teth": float(m.a_freelen[0]),
						"th": absf(float(m.a_theta[0])),
						"cont": _contacts(m)})
		if got.size() == RELS.size():
			break
		if t > 1200 and out.is_empty():
			break
		var cur: Vector2 = PUMP.pump_cursor(m, 0, prev, 95.0)
		prev = m.body_pos
		step_of(m, cur, true)
	m.free()
	return out

func step_of(m: Node2D, cur: Vector2, grip: bool) -> void:
	m.step_tick(cur, grip)

func _fly(hang: float, r: float, turns: float, drop: float,
		e: Dictionary, kill: bool) -> Dictionary:
	var m := PUMP.rig(hang, r, turns, deg_to_rad(6.0), drop)
	LEAP.load_state(m, e["snap"])
	if kill:
		_park(m)
		m.a_freelen[0] = -1.0
		m.a_pinidx[0] = -1
		m.a_locked[0] = -1
	var beam := Vector2(0.0, -40.0)
	var v0: Vector2 = (m.body_pos - Vector2(e["prev"])) * 60.0
	var traj: Array = []
	var contact_ticks := 0
	var clear_at := -1
	var clear_run := 0
	for t in HORIZON:
		var pb: Vector2 = m.body_pos
		m.step_tick(m.body_pos, false)
		var v: Vector2 = (m.body_pos - pb) * 60.0
		if not kill:
			var nc := _contacts(m)
			if nc > 0:
				contact_ticks += 1
				clear_run = 0
			else:
				clear_run += 1
				if clear_run >= 5 and clear_at < 0:
					clear_at = t - 4
		traj.append({"p": m.body_pos, "v": v,
			"d": m.body_pos.distance_to(beam), "g": m.grounded})
	m.free()
	return {"v0": v0, "traj": traj, "ct": contact_ticks, "clear": clear_at}

func _initialize() -> void:
	print("THE DISMOUNT DRAG: what the beam still does to you AFTER you let go.")
	print("")
	print("Rig: one beam in open air, floor 4.5 m under it (fast-beam geometry).")
	print("Pump to a real swing, open the hand at `rel` degrees on the upswing,")
	print("hand parked from then on. Fork A = the real build. Fork B = identical")
	print("state with the beam removed at the release tick. C = pure ballistics.")
	print("")
	for cfg in [[1.6, 0.10, 1.8], [2.4, 0.10, 1.8], [3.2, 0.10, 1.8],
			[2.0, 0.11, 1.8], [2.0, 0.22, 1.8]]:
		var hang: float = cfg[0]
		var r: float = cfg[1]
		var turns: float = cfg[2]
		print("== hang %.1f m, beam r %.2f, %.1f turns laid on ==" % [hang, r, turns])
		var snaps := _snaps(hang, r, turns, 4.5)
		if snaps.is_empty():
			print("   (never pumped to a release)")
			print("")
			continue
		print("   rel  amp   tether  pin  theta  contact  clear   |v0|   dist from beam at +40t   speed at +40t    x-progress at +60t")
		print("   deg  deg     m           rad   ticks   tick    m/s      A       B     lost      A      B          A       B     lost")
		for e in snaps:
			var A := _fly(hang, r, turns, 4.5, e, false)
			var B := _fly(hang, r, turns, 4.5, e, true)
			var ta: Array = A["traj"]
			var tb: Array = B["traj"]
			var i40 := mini(39, ta.size() - 1)
			var i60 := mini(59, ta.size() - 1)
			var da: float = float(ta[i40]["d"])
			var db: float = float(tb[i40]["d"])
			var sa: float = Vector2(ta[i40]["v"]).length()
			var sb: float = Vector2(tb[i40]["v"]).length()
			var xa: float = Vector2(ta[i60]["p"]).x
			var xb: float = Vector2(tb[i60]["p"]).x
			print("   %3.0f  %3.0f   %5.2f  %3d  %5.2f   %4d    %4s   %5.2f  %6.2f  %6.2f  %+6.2f  %5.2f  %5.2f  %+5.2f  %6.2f  %6.2f  %+6.2f"
				% [float(e["rel"]), float(e["amp"]), float(e["teth"]),
				   int(e["pin"]), float(e["th"]), int(A["ct"]),
				   str(A["clear"]) if int(A["clear"]) >= 0 else "none",
				   Vector2(A["v0"]).length(),
				   da, db, da - db, sa, sb, sa - sb, xa, xb, xa - xb])
		print("")
	quit(0)
