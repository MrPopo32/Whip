extends SceneTree
## FEEL PROBE - two playtest notes, measured before anything is changed.
##
##   -- hop [grip]      THE HOP. Drop the body onto flat floor from H metres
##                      with the whip laid back, and play one of these hands
##                      (hand open unless `grip`):
##        park    cursor on the body: no stick
##        down    cursor straight down at full reach the whole fall
##        arch    cursor straight UP while falling, snapped straight DOWN
##                once the feet are 1.5 m off the floor ("arch, then push
##                down on the stick")
##        fwd     cursor 30 deg forward of straight down the whole fall
##        pogo    down while the body is going down, on the body going up
##      plus, from standing: `snap` (up 40 ticks, then down and held).
##      Printed: every apex after the first contact (feet above floor, m),
##      the lowest the feet went, where the body came to rest, how far it
##      travelled.
##   -- wiggle [taper=26]   THE SPAGHETTI. Standing, hand open, the cursor
##                      waggled side to side (A metres either side of the
##                      body, 0.5 m up) at f Hz for 3 s. Printed per cell: the
##                      tip's top speed, how many cracks fired, and how high
##                      above the body the tip got. 1 px of mouse = 16.7 mm.
const DL := preload("res://tests/climb_door_lib.gd")

var stick := false                 # the P option under test, and its two knobs
var stick_c := 4.0
var stick_fmax := 400.0
var hammer := false                # the hammer stick under test, and its knobs
var hg := 10.0
var hv := 4.0
var ht := 0.05
var hf := 560.0
var hmu := 1.2
var hp := 0.30

func world(taper := 26.0) -> Node2D:
	var m: Node2D = DL.make(3.5, 2.0, 2.0, false, [], "step", -6.0)
	m.taper = taper
	m.stick_on = stick
	m.stick_c = stick_c
	m.stick_fmax = stick_fmax
	m.hammer_on = hammer
	m.hammer_gain = hg
	m.hammer_vmax = hv
	m.hammer_tau = ht
	m.hammer_fmax = hf
	m.hammer_mu = hmu
	m.hammer_press = hp
	m._reset()
	DL.stand(m, -6.0, 0.0, PI)
	return m

func feet(m: Node2D) -> float:
	return -(m.body_pos.y + m.BODY_R)

func hop(pol: String, H: float, grip: bool, T := 360) -> String:
	var m := world()
	var x0: float = m.body_pos.x
	if H > 0.0:
		m.teleport(m.body_pos + Vector2(0.0, -H))
	var prev := feet(m)
	var going_up := false
	var apexes: Array = []
	var lowest := 99.0
	var touched := false
	var prev_b: Vector2 = m.body_pos
	for t in T:
		var b: Vector2 = m.body_pos
		var vy := -(b.y - prev_b.y)            # up is positive
		prev_b = b
		var up := b + Vector2(0.0, -m.REACH)
		var dn := b + Vector2(0.0, m.REACH)
		var cur := b
		match pol:
			"park": cur = b
			"down": cur = dn
			"arch": cur = dn if (feet(m) < 1.5 and (vy < 0.0 or touched)) else up
			"fwd": cur = b + Vector2(sin(PI / 6.0), cos(PI / 6.0)) * m.REACH
			"back": cur = b + Vector2(-sin(PI / 6.0), cos(PI / 6.0)) * m.REACH
			"snapb": cur = up if t < 40 else b + Vector2(-sin(PI / 6.0), cos(PI / 6.0)) * m.REACH
			"pogo": cur = dn if vy <= 0.0 else b
			"bounce": cur = dn if (vy <= 0.0 and feet(m) < 1.6) else up
			"cycle": cur = up if (t % 90) < 25 else dn
			"cycle2": cur = up if (t % 70) < 20 else dn
			"snap": cur = up if t < 40 else dn
		m.step_tick(cur, grip)
		var f := feet(m)
		lowest = minf(lowest, f)
		if f < prev - 0.0005:
			if going_up and touched:
				apexes.append(snappedf(prev, 0.01))
			going_up = false
		elif f > prev + 0.0005:
			going_up = true
		if m.grounded or f < 0.9:
			touched = true
		prev = f
	var s := "%-5s H %.1f %s | apexes after contact %s | lowest feet %.2f | rests at feet %.2f, grounded %s | travelled %+.2f m" % [
		pol, H, "grip" if grip else "open", str(apexes.slice(0, 6)), lowest, feet(m),
		str(m.grounded), m.body_pos.x - x0]
	m.free()
	return s

func settle(m: Node2D, off: Vector2, n := 120) -> void:
	# bring the hand to where the gesture starts, slowly, and let the whip hang
	# still there: the gesture is then the only thing that moves it
	var from: Vector2 = Vector2(-m.REACH, 0.0)
	for t in n:
		var k := minf(1.0, float(t) / float(n / 2))
		m.step_tick(m.body_pos + from.lerp(off, k), false)

func wiggle(A: float, f: float, taper: float) -> Array:
	var m := world(taper)
	settle(m, Vector2(0.0, -0.5))
	var vmax := 0.0
	var cracks := 0
	var top := -99.0
	for t in 180:
		var ph := TAU * f * float(t) / 60.0
		m.step_tick(m.body_pos + Vector2(A * sin(ph), -0.5), false)
		vmax = maxf(vmax, float(m.tip_speed))
		if float(m.crack_flash) >= 0.999:
			cracks += 1
		top = maxf(top, m.body_pos.y - m.pos[m.NP - 1].y)
	m.free()
	return [vmax, cracks, top]

## A single small flick UP from a hand held low at your side, the whip hanging
## still from it: the cursor rises A metres in `dur` ticks and stays there.
func flick(A: float, dur: int, taper: float) -> Array:
	var m := world(taper)
	var base := Vector2(0.35, 0.3)
	settle(m, base)
	var vmax := 0.0
	var cracks := 0
	var top := -99.0
	for t in 120:
		var k := minf(1.0, float(t) / float(dur))
		m.step_tick(m.body_pos + base + Vector2(0.0, -A * k), false)
		vmax = maxf(vmax, float(m.tip_speed))
		if float(m.crack_flash) >= 0.999:
			cracks += 1
		top = maxf(top, m.body_pos.y - m.pos[m.NP - 1].y)
	m.free()
	return [vmax, cracks, top]

## THE HAMMER BENCH, on the long flat floor (x -12..0; the body starts at -6
## and walks toward -x... no: toward +x, the lip at x 0 is the end of the run)
func ang_off(m: Node2D, deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * m.REACH

## the Getting Over It walk: swing the stick overhead from behind-low to
## ahead-low, plant it, then sweep it underneath from ahead to behind - the
## planted stick stays and you vault past it. `per` ticks a step.
func walk(per: int, secs := 8.0) -> String:
	var m := world()
	m.teleport(Vector2(-11.0, m.body_pos.y))
	for t in 30:
		m.step_tick(m.body_pos + ang_off(m, 140.0), false)
	var x0: float = m.body_pos.x
	var top := 0.0
	var falls0: int = m.falls
	var n := int(secs * 60.0)
	for t in n:
		var f := float(t % per) / float(per)
		var deg: float
		if f < 0.30:
			deg = lerpf(140.0, 400.0, f / 0.30)          # overhead, through straight up
		elif f < 0.40:
			deg = 40.0                                   # plant ahead
		else:
			deg = lerpf(40.0, 140.0, (f - 0.40) / 0.60)  # sweep under: vault past it
		m.step_tick(m.body_pos + ang_off(m, deg), false)
		top = maxf(top, feet(m))
		if m.body_pos.x > -1.5:
			n = t
			break
	var d: float = m.body_pos.x - x0
	var out := "walk %2d-tick step: %+.2f m in %.1f s = %.2f m/s | feet up to %.2f m" % [per, d, float(n) / 60.0, d / maxf(float(n) / 60.0, 0.01), top]
	m.free()
	return out

func launch(kind: String) -> String:
	var m := world()
	var top := 0.0
	var xmax := -99.0
	var x0: float = m.body_pos.x
	var ys: Array = []
	for t in 360:
		var cur: Vector2
		match kind:
			"snap": cur = m.body_pos + (ang_off(m, 270.0) if t < 40 else ang_off(m, 90.0))
			"vault": cur = m.body_pos + (ang_off(m, 140.0) if t < 60 else ang_off(m, 40.0))
			"cycle": cur = m.body_pos + (ang_off(m, 270.0) if (t % 70) < 20 else ang_off(m, 90.0))
			"stilt": cur = m.body_pos + ang_off(m, 90.0)
		m.step_tick(cur, false)
		top = maxf(top, feet(m))
		xmax = maxf(xmax, m.body_pos.x - x0)
		if kind == "stilt" and t >= 180:
			ys.append(m.body_pos.y)
	var jit := ""
	if kind == "stilt":
		var lo: float = ys.min()
		var hi: float = ys.max()
		jit = " | body y wobble over the last 3 s %.1f mm, resting feet %.2f m" % [(hi - lo) * 1000.0, feet(m)]
	var out := "%-5s feet up to %.2f m, forward %+.2f m%s" % [kind, top, xmax, jit]
	m.free()
	return out

## ONE TO ONE? Plant the stick ahead, then sweep the mouse slowly under you
## (1 rad/s) and back. While planted, how far is the body from the spot the
## mouse puts it (handle minus the mouse's offset)?
func track() -> String:
	var m := world()
	for t in 40:
		m.step_tick(m.body_pos + ang_off(m, 40.0), false)
	var errs: Array = []
	var deg := 40.0
	var dirn := 1.0
	for t in 360:
		deg += dirn * rad_to_deg(1.0) / 60.0
		if deg > 140.0: dirn = -1.0
		if deg < 40.0: dirn = 1.0
		var off := ang_off(m, deg)
		m.step_tick(m.body_pos + off, false)
		if m._hand_on_rock():
			var bv: Vector2 = (m.body_pos - m.body_prv) / m.SDT
			var want: Vector2 = m.pos[0] - m._hammer_cmd(bv) if hammer else m.pos[0] - off
			errs.append(m.body_pos.distance_to(want))
	errs.sort()
	var out := "track: planted %d of 360 ticks, body off its spot: median %.0f mm, p90 %.0f mm" % [errs.size(),
		1000.0 * float(errs[errs.size() / 2]) if errs.size() > 0 else -1.0,
		1000.0 * float(errs[(errs.size() * 9) / 10]) if errs.size() > 0 else -1.0]
	m.free()
	return out

## THE HANG: catch the first door, then hold still (hand shut, mouse parked)
## for 4 s. Per tick: the ARM (hand to body) and the ROPE's stretch past its
## free length (hand to the wrap's pin or lock point, minus a_freelen).
func hang(hk: float, hd: float, st := false) -> String:
	var HN := preload("res://tests/hand_noise.gd")
	var m: Node2D = DL.make(3.5, 2.0, 2.0, true, [], "step")
	if st:
		m.stretch_set(true)
	elif hd >= 0.0:
		m.hang_damp = hd
		m.hang_k = hk
	var c: Dictionary = DL.grid36()[24]
	m._reset()
	DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
	var r: Dictionary = DL.throw(m, 0, c, HN.new("null", "hang", 0), false)
	if not bool(r["lock"]):
		m.free()
		return "no lock"
	var arm: Array = []
	var ext: Array = []
	var stretch := -99.0
	for t in 240:
		m.step_tick(m.body_pos, true)
		arm.append(m.pos[0].distance_to(m.body_pos))
		var lp: Vector2 = m.ctl_load_point()
		var e := 0.0
		if not is_nan(lp.x):
			e = m.pos[0].distance_to(lp) - float(m.a_freelen[0])
			stretch = maxf(stretch, e)
		ext.append(e)
	# the arm's bob: its turning points, and their size
	var turns: Array = []
	for i in range(1, arm.size() - 1):
		if (arm[i] - arm[i - 1]) * (arm[i + 1] - arm[i]) < 0.0:
			turns.append(i)
	var bobs := 0
	for j in range(1, turns.size()):
		if absf(float(arm[turns[j]]) - float(arm[turns[j - 1]])) > 0.02:
			bobs += 1
	var period := 0.0
	if turns.size() > 4:
		period = 2.0 * float(int(turns[turns.size() - 1]) - int(turns[0])) / float(turns.size() - 1) / 60.0
	var series := ""
	var eser := ""
	for i in range(0, 240, 15):
		series += " %.2f" % float(arm[i])
		eser += " %+.0f" % (float(ext[i]) * 100.0)
	var out := "%s | arm every 0.25 s:%s | arm swings > 2 cm: %d | rope past its free length every 0.25 s (cm):%s | max %.1f cm" % [
		"STRETCHY ROPE (firm grip)" if st else "arm K %4.0f C %5.1f" % [hk, hd if hd >= 0.0 else 17.0],
		series, bobs, eser, stretch * 100.0]
	m.free()
	return out

func door_locks() -> int:
	var HN := preload("res://tests/hand_noise.gd")
	var n := 0
	for i in 36:
		var c: Dictionary = DL.grid36()[i]
		var m: Node2D = DL.make(3.5, 2.0, 2.0, true, [], "step")
		m.hammer_on = hammer
		m.hammer_gain = hg; m.hammer_vmax = hv; m.hammer_tau = ht; m.hammer_fmax = hf
		m.hammer_mu = hmu; m.hammer_press = hp
		m._reset()
		DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
		var r: Dictionary = DL.throw(m, 0, c, HN.new("null", "hm", 0), false)
		if bool(r["lock"]):
			n += 1
		m.free()
	return n

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	if a.size() > 0 and String(a[0]) == "hang":
		print(hang(340.0, -1.0))
		print(hang(1500.0, 219.0))
		print(hang(0.0, -1.0, true))
	elif a.size() > 0 and String(a[0]) == "doorst":
		var HN2 := preload("res://tests/hand_noise.gd")
		for st in [false, true]:
			var n := 0
			for i in 36:
				var c: Dictionary = DL.grid36()[i]
				var dm: Node2D = DL.make(3.5, 2.0, 2.0, true, [], "step")
				dm.stretch_set(st)
				dm._reset()
				DL.stand(dm, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
				if bool(DL.throw(dm, 0, c, HN2.new("null", "st", 0), false)["lock"]):
					n += 1
				dm.free()
			print("door catch, stretchy rope %s: %d/36" % ["on" if st else "off", n])
	elif a.size() > 0 and String(a[0]) == "hammer":
		hammer = not a.has("off")
		for q in a:
			var qs := String(q)
			if qs.begins_with("g="): hg = float(qs.substr(2))
			elif qs.begins_with("v="): hv = float(qs.substr(2))
			elif qs.begins_with("t="): ht = float(qs.substr(2))
			elif qs.begins_with("f="): hf = float(qs.substr(2))
			elif qs.begins_with("mu="): hmu = float(qs.substr(3))
			elif qs.begins_with("p="): hp = float(qs.substr(2))
		print("HAMMER %s  gain %.0f  vmax %.1f  tau %.2f  f %.0f  mu %.2f  press %.2f" % ["on" if hammer else "OFF", hg, hv, ht, hf, hmu, hp])
		for per in [30, 45, 60, 90]:
			print("   " + walk(per))
		for kind in ["snap", "vault", "cycle", "stilt"]:
			print("   " + launch(kind))
		print("   " + track())
		if a.has("door"):
			print("   door catch: %d/36 standing strokes lock" % door_locks())
		# the bots' old lash gait, 10 s, with this stick
		var TL := preload("res://tests/tapelib.gd")
		var gm := world()
		gm.teleport(Vector2(-11.0, gm.body_pos.y))
		var gx: float = gm.body_pos.x
		TL.run(gm, [{"kind": "gait", "n": 600}])
		print("   lash gait (the old crawl): %+.2f m in 10 s" % (gm.body_pos.x - gx))
		gm.free()
	elif a.size() > 0 and String(a[0]) == "stick":
		# the springy stick: standing snap, a 3 m fall onto a planted stick,
		# and a bot that re-plants on every descent and lifts on every rise for
		# 15 s - the pogo that must NOT climb a 2 m step
		print("STICK: best apex (feet, m) | standing snap | 2 m fall | 3 m fall | 15 s of re-planting (max apex)")
		for pr in [[false, 17.0, 320.0], [true, 8.0, 320.0], [true, 4.0, 320.0], [true, 0.0, 320.0],
				[true, 8.0, 400.0], [true, 4.0, 400.0], [true, 4.0, 480.0], [true, 0.0, 480.0]]:
			stick = bool(pr[0]); stick_c = float(pr[1]); stick_fmax = float(pr[2])
			var r: Array = []
			for spec in [["snap", 0.0, 360], ["down", 2.0, 360], ["down", 3.0, 360], ["bounce", 0.0, 900]]:
				var line := hop(String(spec[0]), float(spec[1]), false, int(spec[2]))
				var i0 := line.find("apexes after contact [") + 22
				var i1 := line.find("]", i0)
				var ap := Array(line.substr(i0, i1 - i0).split(",")).filter(func(x): return x.strip_edges() != "").map(func(x): return float(x))
				r.append(ap.max() if ap.size() > 0 else 0.0)
			print("   %-4s C %4.1f  F %3.0f   |  %.2f  |  %.2f  |  %.2f  |  %.2f" % ["on" if stick else "OFF", stick_c, stick_fmax, r[0], r[1], r[2], r[3]])
	elif a.size() > 0 and String(a[0]) == "stick2":
		for on in [false, true]:
			stick = on; stick_c = 4.0; stick_fmax = 320.0
			print("%s  %s" % ["on " if on else "OFF", hop("cycle", 0.0, false, 900)])
			print("%s  %s" % ["on " if on else "OFF", hop("cycle2", 0.0, false, 900)])
		# the door catch with the option on and off: the 36 standing strokes
		var HN := preload("res://tests/hand_noise.gd")
		for on in [false, true]:
			var locks: Array = []
			for i in 36:
				var c: Dictionary = DL.grid36()[i]
				var m: Node2D = DL.make(3.5, 2.0, 2.0, true, [], "step")
				m.stick_on = on
				m.stick_c = 4.0
				m._reset()
				DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
				var r: Dictionary = DL.throw(m, 0, c, HN.new("null", "st", 0), false)
				if bool(r["lock"]):
					locks.append(i)
				m.free()
			print("DOOR CATCH, springy stick %s: %d/36 strokes lock %s" % ["on" if on else "off", locks.size(), str(locks)])
	elif a.size() > 0 and String(a[0]) == "throws":
		# the 36 standard standing strokes at the first door, hand shut as
		# climb_door_lib throws them: the tip's top speed during each
		var sp: Array = []
		var HN := preload("res://tests/hand_noise.gd")
		for c: Dictionary in DL.grid36():
			var m: Node2D = DL.make(3.5, 2.0, 2.0, true, [], "step")
			m._reset()
			DL.stand(m, DL.DOOR.x - 1.8, 0.0, float(c["a0"]))
			var vmax := 0.0
			var w := int(c["w"])
			for t in w + 60:
				var te := float(t - w)
				var ang := float(c["a0"])
				var amp := 1.0
				if t >= w:
					if te < float(c["sd"]):
						ang = float(c["a1"])
					elif bool(c["pull"]) and te < float(c["sd"]) + 10.0:
						ang = float(c["a0"]); amp = 0.7
					else:
						ang = float(c["a1"])
				m.step_tick(m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp, false)
				if t >= w:
					vmax = maxf(vmax, float(m.tip_speed))
			sp.append(vmax)
			m.free()
		sp.sort()
		print("THROWS: tip top speed over the 36 standing strokes, sorted: %s" % str(sp.map(func(v): return snappedf(v, 0.1))))
		print("   min %.1f  p10 %.1f  median %.1f  max %.1f m/s" % [sp[0], sp[3], sp[18], sp[35]])
	elif a.size() > 0 and String(a[0]) == "hop2":
		print(hop("back", 2.0, false))
		print(hop("back", 3.0, false))
		print(hop("snapb", 0.0, false))
	elif a.size() > 0 and String(a[0]) == "hop":
		var grip := a.has("grip")
		for H in [1.0, 2.0, 3.0]:
			for pol in ["park", "down", "arch", "fwd", "pogo"]:
				print(hop(pol, H, grip))
		print(hop("snap", 0.0, grip))
		print(hop("pogo", 0.0, grip, 900))
		print(hop("bounce", 0.0, grip, 900))
	elif a.size() > 0 and String(a[0]) == "flick":
		var taper := 26.0
		for q in a:
			if String(q).begins_with("taper="):
				taper = float(String(q).substr(6))
		print("FLICK taper %.0f: one flick up from a low hand, the whip hanging still: tip top speed / cracks / tip's highest point above the body m" % taper)
		var ds := [3, 6, 12, 24]
		var hdr := "   A m (px) / ticks"
		for d in ds:
			hdr += "          %2d" % d
		print(hdr)
		for A in [0.05, 0.10, 0.20, 0.40, 0.80]:
			var line := "   %.2f (%3d)       " % [A, roundi(A / 0.0167)]
			for d in ds:
				var r := flick(A, d, taper)
				line += "  %4.1f/%d/%+.1f" % [float(r[0]), int(r[1]), float(r[2])]
			print(line)
	else:
		var taper := 26.0
		for q in a:
			if String(q).begins_with("taper="):
				taper = float(String(q).substr(6))
		print("WIGGLE taper %.0f: tip top speed m/s / cracks in 3 s / tip's highest point above the body m   (crack at %.0f m/s)" % [taper, 24.0])
		var fs := [0.5, 1.0, 2.0, 3.0, 5.0]
		var hdr := "   A m (px) \\ f Hz"
		for f in fs:
			hdr += "        %4.1f" % f
		print(hdr)
		for A in [0.05, 0.10, 0.20, 0.40, 0.80]:
			var line := "   %.2f (%3d)     " % [A, roundi(A / 0.0167)]
			for f in fs:
				var r := wiggle(A, f, taper)
				line += "  %4.1f/%d/%+.1f" % [float(r[0]), int(r[1]), float(r[2])]
			print(line)
	quit(0)
