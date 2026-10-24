extends SceneTree
## THE LEAP INTENTION, FOUND AND TRACED: door 3 (21.4,-2.2) -> fast 7
## (27.2,-1.5) on the shipped traverse, from a swing, with bot_leap's OWN
## policy (leap_begin / leap_step, unmodified, route_bot's amp_max 250 and
## max_half 22 so a short catch's big swing is not thrown away).
##
## No RNG anywhere: every cell here is one deterministic leap. This is the
## search for the intention that tests/rp_repeat.gd's leapreplay then repeats
## under a noisy hand; a trace of one leap is printed so the flight can be
## read tick by tick (mode "trace").
##
## The grid pumps ONCE per start (hang, th0) with a release angle the policy
## can never reach, snapshots the sim (main.gd's bit-exact snapshot/restore)
## the first time the swing sweeps up past each candidate release angle once
## the policy's own "ready" holds, then flies every (rel, aim) from its
## snapshot - route_bot's pump_snaps idea, so the pump is paid for once.
##
##   godot --headless --path . -s res://tests/rp_leaptrace.gd -- grid <out.json> [ka kb]
##   godot --headless --path . -s res://tests/rp_leaptrace.gd -- trace <hang> <th0> <rel> <aim> [ka kb]
const MAIN := preload("res://main.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const PUMP := preload("res://tests/bot_pump.gd")
const RELS := [8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0,
	52.0, 62.0]
const HOLD := 180

var KA := 3
var KB := 7

func new_sim() -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.setup_sim()
	m.save_enabled = false
	return m

func policy(rel: float, aim: float, lead: int) -> Dictionary:
	var p: Dictionary = LEAP.default_policy()
	p["amp_max"] = 250.0
	p["max_half"] = 22
	p["rel"] = rel
	p["aim"] = aim
	p["lead"] = lead
	return p

func start(hang: float, th0: float) -> Node2D:
	var m := new_sim()
	LEAP._wind_on(m, KA, hang, 1.8, deg_to_rad(th0))
	for t in 30:
		m.step_tick(m.body_pos, true)
	if float(m.a_freelen[KA]) < 0.0:
		m.free()
		return null
	return m

# fly from a state: st is a leap state already past the pump (or a fresh one
# whose pump will run), with the policy's rel/aim set. Returns the ledger.
func fly(m: Node2D, st: Dictionary, prev: Vector2, trace: bool) -> Dictionary:
	var guard := 0
	var snag := -1
	var pump_gnd := 0
	var B: Vector2 = m.a_pos[KB]
	while st["phase"] != "fail" and st["phase"] != "hang" and guard < 2500:
		var ph0 := String(st["phase"])
		var cg: Array = LEAP.leap_step(m, st, prev)
		var v: Vector2 = (m.body_pos - prev) * 60.0
		prev = m.body_pos
		m.step_tick(cg[0], cg[1])
		guard += 1
		if ph0 == "pump" and m.grounded:
			pump_gnd += 1
		if trace:
			var ph1 := String(st["phase"])
			if ph0 == "pump" and guard % 30 == 0:
				print("    t %4d pump  body (%.2f,%.2f) v %.2f gnd %s th7 %.2f" % [
					guard, m.body_pos.x, m.body_pos.y, v.length(), str(m.grounded),
					float(m.a_theta[KB])])
			elif ph1 != "pump":
				print("    t %4d %-5s f %3d body (%.2f,%.2f) v (%.2f,%.2f) d %.2f thB %.2f freeB %.2f grip %s gnd %s s0 %d" % [
					guard, ph1, int(st["f"]), m.body_pos.x, m.body_pos.y, v.x, v.y,
					m.body_pos.distance_to(B), float(m.a_theta[KB]),
					float(m.a_freelen[KB]), str(bool(cg[1])), str(m.grounded),
					int(st["s0"])])
		for j in m.a_pos.size():
			if j != KA and j != KB and float(m.a_freelen[j]) >= 0.0:
				snag = j
		if snag >= 0:
			break
	var r := {"phase": String(st["phase"]), "rel_t": int(st["rel_t"]),
		"throw_t": int(st["throw_t"]), "grip_t": int(st["grip_t"]),
		"fly": int(st["f"]), "amp": float(st["rel_amp"]),
		"min_d": float(st["min_d"]), "max_th": float(st["max_th"]),
		"peak_v": float(st["peak_v"]), "ground_fly": int(st["ground_t"]),
		"pump_gnd": pump_gnd, "snag": snag, "caught": false, "locked": -1,
		"held": false, "green": false, "tether": -1.0, "gnd_hold": 0,
		"th_catch": 0.0, "hash": 0}
	if st["phase"] == "hang":
		r["caught"] = true
		r["tether"] = float(m.a_freelen[KB])
		r["th_catch"] = absf(float(m.a_theta[KB]))
		var gnd := 0
		for t in HOLD:
			m.step_tick(m.body_pos, true)
			if m.grounded:
				gnd += 1
			if int(r["locked"]) < 0 and int(m.a_locked[KB]) >= 0:
				r["locked"] = int(m.a_locked[KB])
			if float(m.a_freelen[KB]) < 0.0:
				break
		r["gnd_hold"] = gnd
		r["held"] = float(m.a_freelen[KB]) >= 0.0
		r["green"] = bool(m._holds(KB))
	r["hash"] = m.state_hash()
	if snag >= 0:
		r["why"] = "snag A%d" % snag
	elif not bool(r["caught"]):
		if int(st["rel_t"]) < 0:
			r["why"] = "never launched"
		elif int(st["ground_t"]) > 0:
			r["why"] = "grounded in flight"
		else:
			r["why"] = "miss"
	elif bool(r["green"]):
		r["why"] = "GREEN"
	elif int(r["locked"]) == 1:
		r["why"] = "locked then lost"
	elif int(r["locked"]) == 0:
		r["why"] = "partial"
	else:
		r["why"] = "caught, unclassified"
	return r

func run_one(hang: float, th0: float, rel: float, aim: float, lead: int,
		trace: bool) -> Dictionary:
	var m := start(hang, th0)
	if m == null:
		return {"why": "start wrap did not take", "caught": false, "green": false}
	var st := LEAP.leap_begin(m, KA, KB, policy(rel, aim, lead))
	var r := fly(m, st, m.body_pos, trace)
	m.free()
	return r

# pump once, snapshot at each release angle the policy would accept
func pump_snaps(m: Node2D, lead: int) -> Array:
	var p := policy(999.0, -0.5, lead)     # rel 999: the policy never launches
	var st := LEAP.leap_begin(m, KA, KB, p)
	var prev: Vector2 = m.body_pos
	var dir: float = signf(float(m.a_pos[KB].x) - float(m.a_pos[KA].x))
	var got := {}
	var out: Array = []
	for t in 2400:
		if float(m.a_freelen[KA]) < 0.0:
			break
		# the policy's own readiness, read off the state it keeps
		var ready: bool = (float(st["last_pk"]) >= float(p["amp"])
			and float(st["last_pk"]) <= float(p["amp_max"])) \
			or int(st["half"]) >= int(p["max_half"])
		var s := PUMP.swing_state(m, KA, prev)
		var th: float = rad_to_deg(float(s["theta"])) * dir
		var om: float = float(s["omega"]) * dir
		if ready and om > 0.0:
			for rel in RELS:
				if th >= float(rel) and not got.has(rel):
					got[rel] = true
					out.append({"snap": m.snapshot(), "prev": prev,
						"st": st.duplicate(true), "rel": float(rel),
						"amp": float(st["last_pk"]), "t": t, "th": th,
						"v": ((m.body_pos - prev) * 60.0).length()})
		if got.size() == RELS.size():
			break
		var cg: Array = LEAP.leap_step(m, st, prev)
		prev = m.body_pos
		m.step_tick(cg[0], cg[1])
	return out

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var mode := String(args[0])
	var t0 := Time.get_ticks_msec()
	if mode == "trace":
		if args.size() > 6:
			KA = int(args[5])
			KB = int(args[6])
		var r := run_one(float(args[1]), float(args[2]), float(args[3]),
			float(args[4]), 38, true)
		print(JSON.stringify(r))
		quit(0)
		return
	if args.size() > 3:
		KA = int(args[2])
		KB = int(args[3])
	var m0 := new_sim()
	var A: Vector2 = m0.a_pos[KA]
	var Bp: Vector2 = m0.a_pos[KB]
	m0.free()
	print("")
	print("LEAP GRID A%d (%.1f,%.1f) -> A%d (%.1f,%.1f): %.2f m along, %.2f m %s. bot_leap policy, amp_max 250 max_half 22, lead 38." % [
		KA, A.x, A.y, KB, Bp.x, Bp.y, Bp.x - A.x, absf(Bp.y - A.y),
		"down" if Bp.y > A.y else "up"])
	print("  pump once per start, snapshot at each release angle, fly each aim from the snapshot.")
	print("  hang th0 | rel  aim | t_rel amp  v_rel th@rel | s0  grip fly  min_d max_th gndF | caught lock held green teth  th@c  why")
	var rows: Array = []
	var green := 0
	# a door hangs 2.2 m over the tier behind it (a long tail drags there); a
	# fast beam has 4.5 m of air all round, and bot_leap's STARTS span 1.6-3.2
	var hangs := [0.7, 0.9, 1.1, 1.3, 1.6, 2.0] if KA < 7 else [1.6, 2.0, 2.4, 2.8, 3.2]
	for hang in hangs:
		for th0 in [6.0, 11.0]:
			var m := start(hang, th0)
			if m == null:
				print("  %.1f  %2.0f  the start wrap did not take" % [hang, th0])
				continue
			var snaps := pump_snaps(m, 38)
			if snaps.is_empty():
				print("  %.1f  %2.0f  never ready: no release snapshot" % [hang, th0])
				m.free()
				continue
			for e: Dictionary in snaps:
				for aim in [-0.3, -0.5, -0.8]:
					m.restore(e["snap"])
					var st: Dictionary = (e["st"] as Dictionary).duplicate(true)
					st["p"]["rel"] = float(e["rel"])
					st["p"]["aim"] = aim
					st["rel_deg"] = -1.0
					var r := fly(m, st, e["prev"], false)
					r["hang"] = hang
					r["th0"] = th0
					r["rel"] = float(e["rel"])
					r["aim"] = aim
					r["lead"] = 38
					r["snap_t"] = int(e["t"])
					r["snap_th"] = float(e["th"])
					r["snap_v"] = float(e["v"])
					rows.append(r)
					if bool(r["green"]):
						green += 1
					print("  %.1f  %2.0f  | %3.0f %4.1f | %4d  %3.0f  %5.2f  %5.1f | %3d  %3d  %3d  %5.2f  %4.2f  %3d | %5s  %2d  %5s %5s %5.2f %5.2f  %s" % [
						hang, th0, float(e["rel"]), aim, int(r["rel_t"]),
						float(r["amp"]), float(e["v"]), float(e["th"]),
						int(r["throw_t"]), int(r["grip_t"]), int(r["fly"]),
						float(r["min_d"]), float(r["max_th"]), int(r["ground_fly"]),
						str(bool(r["caught"])), int(r["locked"]),
						str(bool(r["held"])), str(bool(r["green"])),
						float(r["tether"]), float(r["th_catch"]), String(r["why"])])
			m.free()
	print("  %d green of %d   (%.0f s)" % [green, rows.size(),
		(Time.get_ticks_msec() - t0) / 1000.0])
	if args.size() > 1:
		var f := FileAccess.open(String(args[1]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"ka": KA, "kb": KB, "rows": rows}))
			f.close()
	quit(0)
