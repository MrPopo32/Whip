extends SceneTree
## MOVE 2 - THE LAUNCH FOOTPRINT ("max jump"). See tests/climb_lib.gd for the
## frame (beam at the origin, throwing floor 2.2 m under it, Y DOWN), the thrown
## hang, the servo and the release.
##
##   -- mode=survey tether=S|L A=<deg> out=<file>
##        pump to A, then every release phase (7.5 deg grid, both directions
##        of travel, both dead points, and two phases PAST the amplitude that
##        must never fire), each flown with the hand open in open air; one JSON
##        line per release with the body's whole flight, plus one line with
##        the settled swing's own path (body and chain) for obstruction checks.
##   -- mode=jobs in=<file> out=<file>
##        stop runs and noise samples, one JSON job per line (see _job)
const CL := preload("res://tests/climb_lib.gd")
const NOISE := preload("res://tests/hand_noise.gd")

var args := {}

func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001)]

func _path(a: PackedVector2Array, every := 1) -> Array:
	var o: Array = []
	for i in range(0, a.size(), every):
		o.append(_v(a[i]))
	return o

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var mode := String(args.get("mode", "survey"))
	if mode == "survey":
		survey()
	elif mode == "jobs":
		jobs()
	elif mode == "nograb":
		nograb()
	quit(0)

func survey() -> void:
	var t0 := Time.get_ticks_msec()
	var which := String(args.get("tether", "S"))
	var A := float(args.get("A", "90"))
	var fo := FileAccess.open(String(args["out"]), FileAccess.WRITE)
	var hg: Dictionary = CL.make_hang(which)
	var m: Node2D = hg["m"]
	var head := {"kind": "hang", "tether_id": which, "ok": hg["ok"],
		"tether": hg["tether"], "locked": hg["locked"], "pin": hg["pin"],
		"body": _v(hg["body"])}
	print(JSON.stringify(head))
	fo.store_line(JSON.stringify(head))
	if not bool(hg["ok"]):
		return
	var pr: Dictionary = CL.pump_to(m, A, null, 3000, args.get("loose", "0") == "1")
	var info := {"kind": "pump", "tether_id": which, "A": A, "ok": pr["ok"],
		"why": pr.get("why", ""), "ticks": pr["ticks"], "target": pr["target"],
		"peaks": pr["peaks"], "circ": pr.get("circ", false),
		"loose": pr.get("loose", false), "tether": float(m.a_freelen[0])}
	print(JSON.stringify(info))
	fo.store_line(JSON.stringify(info))
	if not bool(pr["ok"]):
		return
	var S: Dictionary = m.snapshot()
	var prev0: Vector2 = pr["prev"]
	var target: float = pr["target"]
	var peaks: Array = pr["peaks"]
	var atrue: float = 180.0 if bool(pr.get("circ", false)) else \
		(float(peaks[peaks.size() - 1]) + float(peaks[peaks.size() - 2])) * 0.5
	# the settled swing's own path, one period and a half, body + chain
	var body := PackedVector2Array()
	var chain := PackedVector2Array()
	var prev: Vector2 = prev0
	var per := int(TAU * sqrt((float(m.a_freelen[0]) + 0.5) / 10.0) * 60.0 * 1.6)
	for t in per:
		var pb: Vector2 = m.body_pos
		CL.pump_tick(m, prev, target, null)
		prev = pb
		body.append(m.body_pos)
		if t % 3 == 0:
			for i in m.NP:
				chain.append(m.pos[i])
	var swl := {"kind": "swing", "tether_id": which, "A": A, "atrue": atrue,
		"body": _path(body), "chain": _path(chain)}
	fo.store_line(JSON.stringify(swl))
	# the release grid
	var phases: Array = []
	var circ := bool(pr.get("circ", false))
	if circ:
		var sw: Array = []
		var cd := 0
		# which way round: the last bottom crossing's direction
		m.restore(S)
		var p1: Vector2 = m.body_pos
		CL.pump_tick(m, prev0, target, null)
		cd = 1 if CL.wrapd(CL.theta_of(m.body_pos) - CL.theta_of(p1)) > 0.0 else -1
		var th := -180.0
		while th < 180.0:
			phases.append([th, cd, false])
			th += 7.5
		phases.append([-180.0, -cd, false])   # NULL: the other way round
	else:
		var lim := atrue - 3.0
		var th := -floorf(lim / 7.5) * 7.5
		while th <= lim:
			phases.append([th, 1, false])
			phases.append([th, -1, false])
			th += 7.5
		phases.append([0.0, 1, true])
		phases.append([0.0, -1, true])
		# NULLS: past the amplitude - the body never gets there
		phases.append([atrue + 12.0, 1, false])
		phases.append([-(atrue + 12.0), -1, false])
	var n_ok := 0
	for ph: Array in phases:
		m.restore(S)
		var rec: Dictionary = CL.release(m, prev0, target, float(ph[0]), int(ph[1]),
			bool(ph[2]), 0, null)
		var line := {"kind": "rel", "tether_id": which, "A": A, "atrue": atrue,
			"th_rel": ph[0], "dir": ph[1], "apex": ph[2], "ok": rec["ok"]}
		if bool(rec["ok"]):
			n_ok += 1
			var f: Dictionary = CL.fly(m, null)
			line["t"] = rec["t"]
			line["pos"] = _v(rec["pos"])
			line["vel"] = _v(rec["vel"])
			line["theta"] = snappedf(float(rec["theta"]), 0.01)
			line["off"] = rec["off"]
			line["traj"] = _path(f["traj"])
		else:
			line["why"] = rec["why"]
		fo.store_line(JSON.stringify(line))
	print("survey %s A %.0f: atrue %.1f, %d phases, %d released, %.0f s" % [
		which, A, atrue, phases.size(), n_ok, (Time.get_ticks_msec() - t0) / 1000.0])

# ------------------------------------------------------------------- jobs --
# A job line: {"id", "tether", "A", "sample" (-1 = noise-free), "tier",
# "runs": [{"th_rel","dir","apex","jit","pillar":[x0,h,w,dir] or null}, ...]}
# One hang + one pump per job line (the pump is shared by its runs), which is
# where a noise sample's pump noise lives.
func jobs() -> void:
	var t0 := Time.get_ticks_msec()
	var fi := FileAccess.open(String(args["in"]), FileAccess.READ)
	var fo := FileAccess.open(String(args["out"]), FileAccess.WRITE)
	var hangs := {}
	var nj := 0
	while not fi.eof_reached():
		var ln := fi.get_line().strip_edges()
		if ln == "":
			continue
		var j: Dictionary = JSON.parse_string(ln)
		var which := String(j["tether"])
		if not hangs.has(which):
			var hg: Dictionary = CL.make_hang(which)
			hangs[which] = hg["m"].snapshot()
			hangs[which + "_m"] = hg["m"]
		var m: Node2D = hangs[which + "_m"]
		m.restore(hangs[which])
		# restore() does not carry the terrain ARCS (SNAP_SKIP: level
		# furniture), so the last run's pillar fillets would still be standing
		# in the open air as invisible rock. Measured: 4 of 40 pumps "never
		# settled" on the first pass because of exactly that. Clear them.
		var door := bool(j.get("door", false))
		if door:
			CL.door_only(m)
		else:
			CL.open_air(m)
		var sample := int(j.get("sample", -1))
		var hn: Variant = null
		if sample >= 0:
			hn = NOISE.new(String(j.get("tier", "trackpad")),
				"climb/%s/%s" % [which, str(j["A"])], sample)
		var pr: Dictionary = CL.pump_to(m, float(j["A"]), hn, 3000,
			bool(j.get("loose", false)))
		if not bool(pr["ok"]):
			fo.store_line(JSON.stringify({"id": j["id"], "pump_ok": false,
				"why": pr.get("why", "")}))
			continue
		var S: Dictionary = m.snapshot()
		var HS: Dictionary = hn.save_state() if hn != null else {}
		var res: Array = []
		for r: Dictionary in j["runs"]:
			m.restore(S)
			if hn != null:
				hn.restore_state(HS)
			var pl: Variant = r.get("pillar", null)
			if door:
				CL.door_only(m)
			else:
				CL.open_air(m)
			if pl != null:
				CL.pillar(m, float(pl[0]), float(pl[1]), float(pl[2]), int(pl[3]),
					door)
			var rec: Dictionary = CL.release(m, pr["prev"], float(pr["target"]),
				float(r["th_rel"]), int(r["dir"]), bool(r["apex"]),
				int(r.get("jit", 0)), hn)
			var o := {"ok": rec["ok"]}
			if not bool(rec["ok"]):
				o["why"] = rec["why"]
				o["v"] = "OBSTRUCT" if String(rec["why"]).begins_with("hit") \
					else "NOREL"
			else:
				o["pos"] = _v(rec["pos"]); o["vel"] = _v(rec["vel"])
				o["theta"] = snappedf(float(rec["theta"]), 0.01)
				var f: Dictionary = CL.fly(m, hn, 480, CL.F0 + 2.0, pl != null)
				if pl != null:
					o["v"] = CL.verdict(f, float(pl[0]), float(pl[1]),
						float(pl[2]), int(pl[3]))
					o["first"] = f["first"]
					if not f["g120"].is_empty():
						o["end"] = _v(f["g120"]["p"])
					var tr: PackedVector2Array = f["traj"]
					if int(f["first"]) >= 0:
						o["land"] = _v(tr[int(f["first"]) + 1])
						var v: Vector2 = (tr[int(f["first"]) + 1] - tr[int(f["first"])]) * 60.0
						o["vland"] = _v(v)
				else:
					o["traj"] = _path(f["traj"])
			res.append(o)
		var peaks: Array = pr["peaks"]
		fo.store_line(JSON.stringify({"id": j["id"], "pump_ok": true,
			"ptick": pr["ticks"], "peaks": peaks.slice(maxi(peaks.size() - 4, 0)),
			"res": res}))
		nj += 1
	print("jobs: %d lines, %.0f s" % [nj, (Time.get_ticks_msec() - t0) / 1000.0])

# NULL: THE GRIP NEVER CLOSES. The S catch's own stroke from the S stand, with
# the hand held open throughout. There must be no wrap, the pump must refuse
# (pump_cursor returns the body: nothing to hang on) and nothing is launched.
func nograb() -> void:
	var cfg: Dictionary = CL.CATCH["S"]
	var m: Node2D = CL.TL.new_sim()
	CL.door_world(m, float(cfg["lead"]))
	for t in 60:
		m.step_tick(m.body_pos, false)
	var c: Dictionary = cfg["c"]
	var th_max := 0.0
	for i in int(c["w"]) + 130:
		var ang: float = float(c["a0"]) if i < int(c["w"]) else float(c["a1"])
		m.step_tick(m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH, false)
		th_max = maxf(th_max, absf(float(m.a_theta[0])))
	var engaged := float(m.a_freelen[0]) >= 0.0
	CL.open_air(m)
	var pr: Dictionary = CL.pump_to(m, 90.0)
	print("NULL nograb: max wrap reading %.2f rad, engaged %s, pump ok %s (%s), body y %.2f" % [
		th_max, str(engaged), str(pr["ok"]), str(pr.get("why", "")), m.body_pos.y])
