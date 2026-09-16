extends SceneTree
## THE BELLY, on recorded play. Per tick where the hand is shut on an engaged
## wrap and the body is airborne: the free span (handle -> first particle in
## the beam's contact band), its chord, its arc, its sag below the chord, the
## belly's lateral speed relative to the handle, and the angle the first rope
## segment leaves the fist at against the load line (handle -> pin).
##
##   godot --headless --path . -s res://tests/belly_census.gd -- takes/bug1.tape
const TL := preload("res://tests/tapelib.gd")

static func pct(a: Array, q: float) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	var i := int(floor(q * float(b.size() - 1) + 0.5))
	return float(b[clampi(i, 0, b.size() - 1)])

static func first_contact(m: Node2D, k: int) -> int:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return i
	return -1

static func load_pt(m: Node2D, k: int) -> Vector2:
	if m.a_pinidx[k] >= 0:
		return m.a_pinpt[k]
	var li: int = m.a_lockidx[k]
	if li < 0:
		return m.a_pos[k]
	return m.a_pos[k] + (m.pos[li] - m.a_pos[k]).normalized() * m.a_r[k]

# one tick's belly numbers, or {} if there is no free span to measure
static func measure(m: Node2D, k: int, prev_pos: PackedVector2Array) -> Dictionary:
	var fc := first_contact(m, k)
	if fc < 1:
		return {"fc": fc}
	var p0: Vector2 = m.pos[0]
	var pf: Vector2 = m.pos[fc]
	var chord := p0.distance_to(pf)
	var arc: float = m.cum_len[fc]
	var poly := 0.0
	for i in fc:
		poly += (m.pos[i + 1] - m.pos[i]).length()
	var u := (pf - p0) / maxf(chord, 1e-6)
	var sag := 0.0
	var j := 0
	for i in range(1, fc):
		var perp := absf((m.pos[i] - p0).cross(u))
		if perp > sag:
			sag = perp
			j = i
	var swing := 0.0
	if j > 0:
		var vj: Vector2 = (m.pos[j] - prev_pos[j]) * 60.0
		var v0 := (p0 - prev_pos[0]) * 60.0
		swing = absf((vj - v0).cross(u))
	var lp := load_pt(m, k)
	var seg: Vector2 = m.pos[1] - p0
	var load := lp - p0
	var kink := rad_to_deg(absf(seg.angle_to(load)))
	var taut: bool = p0.distance_to(lp) >= float(m.a_freelen[k]) - 0.001
	return {"fc": fc, "chord": chord, "arc": arc, "poly": poly, "slack": arc - chord,
		"sag": sag, "swing": swing, "kink": kink, "taut": taut,
		"tether": float(m.a_freelen[k]), "d": p0.distance_to(lp)}

# the anchor that is carrying: ALIGN's rule, the tightest engaged tether
static func carrier(m: Node2D) -> int:
	var best := -1
	var best_s := 0.0
	for k in m.a_pos.size():
		if m.a_freelen[k] < 0.0:
			continue
		var s: float = m.pos[0].distance_to(load_pt(m, k)) - float(m.a_freelen[k])
		if best < 0 or s > best_s:
			best = k
			best_s = s
	return best

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var path: String = args[0] if args.size() > 0 else "takes/bug1.tape"
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var t: Dictionary = load("res://main.gd").tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load %s: %s" % [path, t.get("err", "")])
		quit(1)
		return
	var m := TL.new_sim()
	m.restore(t["start"])
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var prev_pos: PackedVector2Array = m.pos.duplicate()
	var sag: Array = []
	var swing: Array = []
	var kink: Array = []
	var slack: Array = []
	var arc: Array = []
	var chord: Array = []
	var n_eng := 0
	var n_shut := 0
	var n_air := 0
	var n_nofc := 0
	var n_taut := 0
	var catches := 0
	var was := PackedByteArray()
	was.resize(m.a_pos.size())
	for i in cur.size():
		var grip := (grp[i] & 1) != 0
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], grip)
		for k in m.a_pos.size():
			var e := 1 if m.a_freelen[k] >= 0.0 else 0
			if e == 1 and was[k] == 0:
				catches += 1
			was[k] = e
		var k := carrier(m)
		if k >= 0:
			n_eng += 1
			if grip:
				n_shut += 1
				if not m.grounded:
					n_air += 1
					var r := measure(m, k, prev_pos)
					if int(r["fc"]) < 1:
						n_nofc += 1
					else:
						sag.append(r["sag"]); swing.append(r["swing"])
						kink.append(r["kink"]); slack.append(r["slack"])
						arc.append(r["arc"]); chord.append(r["chord"])
						if bool(r["taut"]):
							n_taut += 1
		prev_pos = m.pos.duplicate()
	m.free()
	print("")
	print("BELLY  %s  %d ticks  catches %d" % [path, cur.size(), catches])
	print("  engaged %d   engaged+shut %d   engaged+shut+airborne %d   (no free span %d)"
		% [n_eng, n_shut, n_air, n_nofc])
	print("  measured ticks n = %d   tether taut on %d of them (%.0f%%)"
		% [sag.size(), n_taut, 100.0 * float(n_taut) / maxf(float(sag.size()), 1.0)])
	print("                 p50      p90      max")
	for row in [["free-span arc (m)", arc], ["free-span chord (m)", chord],
			["slack arc-chord (m)", slack], ["sag below chord (m)", sag],
			["belly lateral speed vs handle (m/s)", swing],
			["kink: first segment vs load line (deg)", kink]]:
		var a: Array = row[1]
		print("  %-40s %7.3f  %7.3f  %7.3f" % [String(row[0]), pct(a, 0.5), pct(a, 0.9),
			pct(a, 1.0)])
	quit(0)
