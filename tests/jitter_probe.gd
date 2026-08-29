extends SceneTree
## Measures "twitching with no input" on a given whip script.
## Usage: godot --headless --path . -s res://tests/jitter_probe.gd
## Optional: set SCRIPT_PATH via `--` args is awkward in -s mode, so we just
## run every script listed in SCRIPTS.

const SCRIPTS := ["res://main.gd"]

func _initialize() -> void:
	for s in SCRIPTS:
		print("=== %s ===" % s)
		_scenarios(s)
	quit(0)

func _new_sim(path: String) -> Node2D:
	var m: Node2D = load(path).new()
	m.external_drive = true
	m.setup_sim()
	return m

# ---------------------------------------------------------------- metrics --
class Rec:
	var hist: Array = []          # Array[PackedVector2Array] positions per tick
	var bhist: Array = []         # body pos per tick
	func add(sim) -> void:
		hist.append(PackedVector2Array(sim.pos))
		bhist.append(sim.body_pos)

	# mean |p_t - 2p_{t-1} + p_{t-2}| over window, mm
	func acc_mm(from: int) -> float:
		var s := 0.0
		var n := 0
		for t in range(maxi(from, 2), hist.size()):
			var a: PackedVector2Array = hist[t]
			var b: PackedVector2Array = hist[t - 1]
			var c: PackedVector2Array = hist[t - 2]
			for i in a.size():
				s += (a[i] - b[i] * 2.0 + c[i]).length()
				n += 1
		return 0.0 if n == 0 else 1000.0 * s / float(n)

	# Nyquist (30 Hz) component of tick velocity, per particle, mm
	func nyq(from: int) -> Array:
		var np: int = (hist[0] as PackedVector2Array).size()
		var acc := PackedVector2Array(); acc.resize(np)
		var n := 0
		for t in range(maxi(from, 1), hist.size()):
			var a: PackedVector2Array = hist[t]
			var b: PackedVector2Array = hist[t - 1]
			var sgn := 1.0 if t % 2 == 0 else -1.0
			for i in np:
				acc[i] = acc[i] + (a[i] - b[i]) * sgn
			n += 1
		var mx := 0.0
		var mean := 0.0
		var arg := -1
		for i in np:
			var v: float = 1000.0 * acc[i].length() / float(n)
			mean += v
			if v > mx:
				mx = v; arg = i
		return [mean / float(np), mx, arg]

	# mean tick speed (m/s) - how much is moving at all
	func speed(from: int) -> float:
		var s := 0.0; var n := 0
		for t in range(maxi(from, 1), hist.size()):
			var a: PackedVector2Array = hist[t]
			var b: PackedVector2Array = hist[t - 1]
			for i in a.size():
				s += (a[i] - b[i]).length() * 60.0
				n += 1
		return 0.0 if n == 0 else s / float(n)

	func body_nyq(from: int) -> float:
		var acc := Vector2.ZERO
		var n := 0
		for t in range(maxi(from, 1), bhist.size()):
			var sgn := 1.0 if t % 2 == 0 else -1.0
			acc += (bhist[t] - bhist[t - 1]) * sgn
			n += 1
		return 0.0 if n == 0 else 1000.0 * acc.length() / float(n)

func _report(tag: String, r: Rec, from: int) -> void:
	var ny: Array = r.nyq(from)
	print("  %-14s acc %7.3f mm | nyq mean %6.3f max %7.3f (p%d) | body nyq %6.3f | speed %5.2f m/s"
		% [tag, r.acc_mm(from), ny[0], ny[1], ny[2], r.body_nyq(from), r.speed(from)])

# -------------------------------------------------------------- scenarios --
func _prewrap(sim, k: int, turns: float) -> void:
	sim.a_r[k] = 0.20
	sim.a_pos[k] = Vector2(0.0, -40.0)
	var c: Vector2 = sim.a_pos[k]
	var r: float = sim.a_r[k] + 0.04
	var hang := 2.0
	var rise := hang - r
	var wrap_len := turns * TAU * r
	for i in sim.pos.size():
		var s: float = sim.cum_len[i]
		var p: Vector2
		if s < rise:
			p = c + Vector2(0.0, hang - s)
		elif s < rise + wrap_len:
			var ang: float = PI / 2.0 + (s - rise) / r
			p = c + Vector2(cos(ang), sin(ang)) * r
		else:
			var ang2: float = PI / 2.0 + turns * TAU
			var exit_pt: Vector2 = c + Vector2(cos(ang2), sin(ang2)) * r
			var side := 0.3 if cos(ang2) >= 0.0 else -0.3
			p = exit_pt + Vector2(side, s - rise - wrap_len)
		sim.pos[i] = p
		sim.prv[i] = p
	sim.body_pos = c + Vector2(0.0, hang + 0.6)
	sim.body_prv = sim.body_pos

func _scenarios(path: String) -> void:
	# A: airborne, body pinned, chain dangles in free air, cursor static.
	var a := _new_sim(path)
	a.teleport(Vector2(0, -30))
	var ra := Rec.new()
	for t in 500:
		a.body_prv = a.body_pos
		a.step_tick(a.body_pos + Vector2(0.3, -0.6), false)
		ra.add(a)
	_report("air-dangle", ra, 250)
	a.free()

	# B: whip draped on flat ground, cursor static, no grip.
	var b := _new_sim(path)
	var rb := Rec.new()
	for t in 600:
		b.step_tick(b.body_pos + Vector2(0.5, -0.5), false)
		rb.add(b)
	_report("ground-drape", rb, 350)
	b.free()

	# C: locked full wrap, hanging, hand static and gripped.
	var c := _new_sim(path)
	_prewrap(c, 0, 1.4)
	var rc := Rec.new()
	for t in 400:
		c.step_tick(c.body_pos, true)
		rc.add(c)
	_report("hang-locked", rc, 150)
	print("      locked=%d freelen=%.3f pin=%d theta=%.2f"
		% [c.a_locked[0], c.a_freelen[0], c.a_pinidx[0], absf(c.a_theta[0])])
	c.free()

	# D: partial wrap paying out under load.
	var d := _new_sim(path)
	_prewrap(d, 0, 0.9)
	var rd := Rec.new()
	for t in 400:
		d.step_tick(d.body_pos, true)
		rd.add(d)
	_report("hang-partial", rd, 20)
	d.free()

	# E: gripped hang on a LEVEL beam after a scripted throw is not scripted
	#    here; instead: body resting on ground, taut grip, cursor static.
	var e := _new_sim(path)
	var re := Rec.new()
	for t in 600:
		e.step_tick(e.body_pos + Vector2(0.6, -0.7), t > 200)
		re.add(e)
	_report("ground-taut", re, 350)
	e.free()
