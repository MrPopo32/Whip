extends SceneTree
## MOVE 3, STAGE 2 - per cell: the fine search, P(lock) under the trackpad
## noise model, the basin ladders (each at TWO widths), the r 0.11 check and
## the carried swing.
##   godot --headless --path . -s res://tests/climb_swing_refine.gd -- <amp> <out.txt> <cells> [nnoise]
## cells = "dx,dy,ki,aim;dx,dy,ki,aim;..." - each with the seed stroke from
## the coarse map (climb_swing_map.gd). Origin = beam A's centre, dy UP.
##
## THE NOISE (tests/hand_noise.gd, tier "trackpad": 2 px = 33 mm offset,
## 2 px tremor at 5 Hz, 5% stroke speed, +/-3 ticks press). Two independent
## draws per sample: "rel" supplies the cursor error (every tick from the
## release to the end of the hold), the stroke-onset speed scale and the
## RELEASE jitter (the hand opens that many ticks off the chosen instant);
## "grip" supplies the jitter on the hand shutting (two-pass rewind).
const SW := preload("res://tests/climb_swing_lib.gd")
const MAP := preload("res://tests/climb_swing_map.gd")
const HN := preload("res://tests/hand_noise.gd")

var out: FileAccess
var b
var w: Dictionary
var sn: Array

func emit(s: String) -> void:
	print(s)
	out.store_line(s)
	out.flush()

func att(dx: float, dy: float, c: Dictionary, hn: RefCounted = null,
		hg: RefCounted = null, gshift := 0, off := Vector2.ZERO, rb := -1.0,
		carry := 0, dki := 0) -> Dictionary:
	var ki: int = int(c["ki"]) + dki
	if hn != null:
		ki += int(hn.jit)
	if ki < 0 or ki >= sn.size():
		return {"lock": false, "caught": false, "oob": true}
	var p: Dictionary = SW.stroke(float(c["aim"]), int(c["lead"]))
	return b.attempt(w, ki, dx, dy, p, hn, hg, gshift, false, false, carry, off, rb)

# sweep one knob, pick the centre of the longest run of locks
func sweep(dx: float, dy: float, c: Dictionary, key: String, vals: Array) -> Dictionary:
	var ok := []
	var s := ""
	for v in vals:
		var c2 := c.duplicate()
		c2[key] = v
		var r: Dictionary = att(dx, dy, c2)
		ok.append(bool(r["lock"]))
		s += "L" if bool(r["lock"]) else ("c" if bool(r["caught"]) else ".")
	var best_lo := -1
	var best_hi := -2
	var i := 0
	while i < ok.size():
		if bool(ok[i]):
			var j := i
			while j + 1 < ok.size() and bool(ok[j + 1]):
				j += 1
			if j - i > best_hi - best_lo:
				best_lo = i
				best_hi = j
			i = j + 1
		else:
			i += 1
	var c3 := c.duplicate()
	if best_lo >= 0:
		c3[key] = vals[(best_lo + best_hi) / 2]
	return {"c": c3, "str": s, "run": best_hi - best_lo + 1 if best_lo >= 0 else 0}

func noise_p(dx: float, dy: float, c: Dictionary, n: int, rb: float, tag: String) -> Array:
	var nl := 0
	var nn := 0
	for s in n:
		var hn = HN.new("trackpad", tag + "/rel", s)
		var hg = HN.new("trackpad", tag + "/grip", s)
		var r: Dictionary = att(dx, dy, c, hn, hg, 0, Vector2.ZERO, rb)
		if r.has("oob"):
			continue
		nn += 1
		if bool(r["lock"]):
			nl += 1
	return [nl, nn]

func ladder(dx: float, dy: float, c: Dictionary, kind: String, vals: Array) -> String:
	var s := ""
	for v in vals:
		var r: Dictionary = {}
		if kind == "rel":
			r = att(dx, dy, c, null, null, 0, Vector2.ZERO, -1.0, 0, int(v))
		elif kind == "press":
			r = att(dx, dy, c, null, null, int(v))
		elif kind == "offx" or kind == "offy":
			# a fixed cursor offset during the stroke, mm, across (offx) or
			# along (offy) the line body -> B at the release
			var u: Vector2 = (Vector2(dx, -dy) - (sn[int(c["ki"])]["pos"] as Vector2)).normalized()
			var dirv: Vector2 = Vector2(-u.y, u.x) if kind == "offx" else u
			r = att(dx, dy, c, null, null, 0, dirv * float(v) / 1000.0)
		elif kind == "aim":
			var c2 := c.duplicate()
			c2["aim"] = float(c["aim"]) + float(v)
			r = att(dx, dy, c2)
		if r.has("oob"):
			s += "_"
		else:
			s += "L" if bool(r["lock"]) else ("c" if bool(r["caught"]) else ".")
	return s

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var amp := float(a[0])
	out = FileAccess.open(a[1], FileAccess.WRITE)
	var nnoise := 24
	if a.size() > 3:
		nnoise = int(a[3])
	var t0 := Time.get_ticks_msec()
	b = SW.new(0.10)
	b.late_cut = 200           # the coarse map gave up at 90; here nothing is cut
	w = b.pump_window(amp, MAP.targets_for(amp))
	sn = w["snaps"]
	emit("WINDOW amp %.0f ok %s target %.0f fwd %.1f pump_t %d snaps %d" % [amp, w["ok"],
		float(w.get("target", -1)), w["amp_fwd"], w["pump_t"], sn.size()])
	for cs in String(a[2]).split(";"):
		var f := cs.split(",")
		var dx := float(f[0])
		var dy := float(f[1])
		var c := {"ki": int(f[2]), "aim": float(f[3]), "lead": 38}
		var seed: Dictionary = att(dx, dy, c)
		emit("CELL %.1f %.1f seed ki %d aim %.2f -> lock %d" % [dx, dy, c["ki"], c["aim"], int(seed["lock"])])
		# fine search: release tick, then aim, then lead
		var ks2 := []
		for d in range(-6, 7):
			var k: int = int(c["ki"]) + d
			if k >= 0 and k < sn.size():
				ks2.append(k)
		var s1 := sweep(dx, dy, c, "ki", ks2)
		c = s1["c"]
		var s2 := sweep(dx, dy, c, "aim", [-1.5, -1.3, -1.1, -0.9, -0.7, -0.5, -0.3, -0.1, 0.1])
		c = s2["c"]
		var s3 := sweep(dx, dy, c, "lead", [22, 30, 38, 46, 54])
		c = s3["c"]
		emit("  SEARCH ki[%d..%d] %s | aim[-1.5..0.1/0.2] %s | lead[22..54/8] %s" % [
			ks2[0], ks2[ks2.size() - 1], s1["str"], s2["str"], s3["str"]])
		var r0: Dictionary = att(dx, dy, c, null, null, 0, Vector2.ZERO, -1.0, 420)
		var e: Dictionary = sn[int(c["ki"])]
		emit("  BEST ki %d th %.1f v %.2f aim %.2f lead %d -> lock %d tether %.2f pin %d s0 %d g0 %d f %d min_d %.2f apex %.2f" % [
			c["ki"], float(e["th"]), (e["v"] as Vector2).length(), c["aim"], c["lead"], int(r0["lock"]),
			float(r0.get("tether", -1)), int(r0.get("pin", -1)), int(r0.get("s0", -1)), int(r0.get("g0", -1)),
			int(r0.get("f", -1)), float(r0.get("min_d", -1)), float(r0.get("apex_up", 0))])
		if not bool(r0["lock"]):
			emit("  NOLOCK")
			continue
		var pk: Array = r0.get("c_peaks", [])
		var ps := []
		for x in pk:
			ps.append("%.0f" % float(x))
		emit("  CARRY held %s over %s tether %.2f peaks %s" % [r0.get("c_held"), r0.get("c_over"), float(r0.get("c_tether", -1)), " ".join(ps)])
		var tag := "sw%.0f_%.1f_%.1f" % [amp, dx, dy]
		var pn := noise_p(dx, dy, c, nnoise, -1.0, tag)
		emit("  NOISE r0.10 trackpad %d / %d" % [pn[0], pn[1]])
		var pn2 := noise_p(dx, dy, c, nnoise, 0.11, tag)
		var r11: Dictionary = att(dx, dy, c, null, null, 0, Vector2.ZERO, 0.11)
		emit("  R011 noisefree lock %d  trackpad %d / %d" % [int(r11["lock"]), pn2[0], pn2[1]])
		if float(pn[0]) / maxf(float(pn[1]), 1.0) >= 0.4:
			emit("  LAD rel   narrow[-4..4/1]       " + ladder(dx, dy, c, "rel", [-4, -3, -2, -1, 0, 1, 2, 3, 4]))
			emit("  LAD rel   wide[-12..12/3]       " + ladder(dx, dy, c, "rel", [-12, -9, -6, -3, 0, 3, 6, 9, 12]))
			emit("  LAD press narrow[-8..8/2]       " + ladder(dx, dy, c, "press", [-8, -6, -4, -2, 0, 2, 4, 6, 8]))
			emit("  LAD press wide[-20..20/5]       " + ladder(dx, dy, c, "press", [-20, -15, -10, -5, 0, 5, 10, 15, 20]))
			emit("  LAD aim   narrow[-.12..12/.03]  " + ladder(dx, dy, c, "aim", [-0.12, -0.09, -0.06, -0.03, 0.0, 0.03, 0.06, 0.09, 0.12]))
			emit("  LAD aim   wide[-.4..4/.1]       " + ladder(dx, dy, c, "aim", [-0.4, -0.3, -0.2, -0.1, 0.0, 0.1, 0.2, 0.3, 0.4]))
			emit("  LAD offx  narrow[-200..200/50]  " + ladder(dx, dy, c, "offx", [-200, -150, -100, -50, 0, 50, 100, 150, 200]))
			emit("  LAD offx  wide[-600..600/150]   " + ladder(dx, dy, c, "offx", [-600, -450, -300, -150, 0, 150, 300, 450, 600]))
			emit("  LAD offy  wide[-600..600/150]   " + ladder(dx, dy, c, "offy", [-600, -450, -300, -150, 0, 150, 300, 450, 600]))
		emit("  T %d s" % ((Time.get_ticks_msec() - t0) / 1000))
	emit("DONE %d s" % ((Time.get_ticks_msec() - t0) / 1000))
	out.close()
	b.free_sim()
	quit(0)
