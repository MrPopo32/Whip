extends SceneTree
## MOVE 3 - THE SWING-TO-BEAM MAP, one (radius, amplitude class) per process.
##   godot --headless --path . -s res://tests/climb_swing_map.gd -- <r> <amp> <out.txt> [stage]
## Origin = beam A's centre. dx metres along the swing, dy metres UP (dy > 0 =
## B above A). Every cell is thrown: releases picked from the snapshot window
## (every tick is a candidate; the search takes those whose BALLISTIC closest
## approach to B is within BALLISTIC_MAX, spread over the window, and if none
## is, the two closest anyway - so an out-of-reach cell is still thrown and
## must report 0), crossed with the stroke aims.
const SW := preload("res://tests/climb_swing_lib.gd")
const BALLISTIC_MAX := 5.0
const MAXREL := 8

var out: FileAccess

func emit(s: String) -> void:
	print(s)
	out.store_line(s)
	out.flush()

static func targets_for(amp: float) -> Array:
	if amp >= 179.0: return [0.0]
	if amp <= 95.0: return [110.0, 120.0, 100.0, 130.0]
	if amp <= 125.0: return [150.0, 140.0, 160.0, 130.0]
	return [170.0, 160.0, 175.0, 150.0]

static func ballistic_dmin(e: Dictionary, B: Vector2) -> float:
	var p: Vector2 = e["pos"]
	var v: Vector2 = e["v"]
	var dmin := 1e9
	for i in 150:
		var tt: float = float(i) / 60.0
		var q: Vector2 = p + v * tt + Vector2(0.0, 5.0 * tt * tt)
		dmin = minf(dmin, q.distance_to(B))
	return dmin

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var r := float(a[0])
	var amp := float(a[1])
	out = FileAccess.open(a[2], FileAccess.WRITE)
	var t0 := Time.get_ticks_msec()
	var b = SW.new(r)
	emit("RIG r %.2f start_ok %s tether %.3f" % [r, b.start_ok, b.start_tether])
	# instrument null: a class the harvest is told it may not have
	var wn: Dictionary = b.pump_window(amp, [targets_for(amp)[0]], 600, true)
	emit("NULL never-ready window: ok %s snaps %d (must be false 0)" % [wn["ok"], (wn["snaps"] as Array).size()])
	var w: Dictionary = b.pump_window(amp, targets_for(amp))
	var sn: Array = w["snaps"]
	emit("WINDOW amp %.0f ok %s target %.0f fwd %.1f prev %.1f pump_t %d over %s snaps %d k0 %d (%d s)" % [
		amp, w["ok"], float(w.get("target", -1)), w["amp_fwd"], w["amp_prev"], w["pump_t"],
		w["over"], sn.size(), w["k0"], (Time.get_ticks_msec() - t0) / 1000])
	emit("HARVEST " + " ".join(w["log"]))
	if not bool(w["ok"]):
		emit("NO WINDOW - class unreachable by the servo")
		out.close(); b.free_sim(); quit(0); return
	var ths := []
	for e in sn:
		ths.append("%d:%.0f/%.1f" % [sn.find(e), float(e["th"]), (e["v"] as Vector2).length()])
	emit("TH " + " ".join(ths))
	# optional: <dx_lo> <dx_hi> <dy_hi> <dy_lo> <step> [late_cut]
	var dx_lo := 3.0
	var dx_hi := 11.0
	var dy_hi := 5.0
	var dy_lo := -4.0
	var st := 1.0
	if a.size() >= 8:
		dx_lo = float(a[3]); dx_hi = float(a[4]); dy_hi = float(a[5])
		dy_lo = float(a[6]); st = float(a[7])
	if a.size() >= 9:
		b.late_cut = int(a[8])
	var dxs := []
	var dys := []
	var xx := dx_lo
	while xx <= dx_hi + 1e-6:
		dxs.append(xx); xx += st
	var yy := dy_hi
	while yy >= dy_lo - 1e-6:
		dys.append(yy); yy -= st
	var aims := [-1.0, -0.5]
	var natt := 0
	for dy in dys:
		for dx in dxs:
			var B := Vector2(dx, -dy)
			var cand := []
			var dl := []
			for ki in range(0, sn.size(), 3):
				var dm := ballistic_dmin(sn[ki], B)
				dl.append([dm, ki])
				if dm <= BALLISTIC_MAX:
					cand.append(ki)
			var tag := "in"
			if cand.is_empty():
				tag = "out"
				dl.sort_custom(func(x, y): return x[0] < y[0])
				cand = [dl[0][1], dl[1][1]]
			elif cand.size() > MAXREL:
				var c2 := []
				for i in MAXREL:
					c2.append(cand[int(round(float(i) * float(cand.size() - 1) / float(MAXREL - 1)))])
				cand = c2
			var n := 0
			var nl := 0
			var nc := 0
			var best := {}
			for ki in cand:
				var al: Array = aims if tag == "in" else [-0.5]
				for aim in al:
					var p: Dictionary = SW.stroke(aim, 38)
					var rr: Dictionary = b.attempt(w, ki, dx, dy, p)
					n += 1
					natt += 1
					if bool(rr["caught"]): nc += 1
					if bool(rr["lock"]):
						nl += 1
					emit("ATT %.1f %.1f ki %d th %.0f aim %.2f lead 38 caught %d lock %d tether %.2f pin %d s0 %d g0 %d f %d closes %d min_d %.2f apex %.2f" % [
						dx, dy, ki, float(sn[ki]["th"]), aim, int(rr["caught"]), int(rr["lock"]),
						rr["tether"], rr["pin"], rr["s0"], rr["g0"], rr["f"], rr["closes"], rr["min_d"], rr["apex_up"]])
			emit("CELL %.1f %.1f %s N %d caught %d lock %d  (%d att, %d s)" % [dx, dy, tag, n, nc, nl, natt, (Time.get_ticks_msec() - t0) / 1000])
	emit("DONE %d s" % ((Time.get_ticks_msec() - t0) / 1000))
	out.close()
	b.free_sim()
	quit(0)
