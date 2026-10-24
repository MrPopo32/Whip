extends SceneTree
## VERIFIER (lens: instrument) for tests/hand_noise.gd. Does the noise model
## emit what it claims? Measures, for each tier: the sd of the per-throw
## offset over 400 samples; the jitter and speed distributions; the tremor's
## stationary sd, its lag autocorrelation (AR(1) claims rho(l) = alpha^l with
## alpha = 0.592) and a Hann-windowed periodogram against the AR(1) theory;
## seed reproducibility (same (tag, sample) twice -> same bytes; neighbouring
## samples and other tags -> different bytes).
##
##   godot --headless --path . -s res://tests/vfy_ctrl_noise.gd
const HN := preload("res://tests/hand_noise.gd")

func sd_of(v: Array) -> float:
	var n := v.size()
	var mu := 0.0
	for x in v:
		mu += float(x)
	mu /= n
	var ss := 0.0
	for x in v:
		ss += (float(x) - mu) * (float(x) - mu)
	return sqrt(ss / maxi(1, n - 1))

func _initialize() -> void:
	var alpha: float = exp(-2.0 * PI * 5.0 / 60.0)
	print("AR(1) pole alpha = %.4f" % alpha)
	for tier in ["mouse03", "mouse1", "trackpad", "off_only", "trem_only", "jit_only", "speed_only", "null"]:
		var offx: Array = []
		var offy: Array = []
		var spd: Array = []
		var jits := {}
		for s in 400:
			var hn: RefCounted = HN.new(tier, "vfy", s)
			offx.append(hn.offset.x * 1000.0)
			offy.append(hn.offset.y * 1000.0)
			spd.append(hn.speed)
			jits[hn.jit] = int(jits.get(hn.jit, 0)) + 1
		var jl := ""
		var jk := jits.keys()
		jk.sort()
		for j in jk:
			jl += "%+d:%d " % [j, jits[j]]
		# tremor: one long realisation, sample 0, 12000 ticks
		var hn0: RefCounted = HN.new(tier, "vfy", 0)
		var off0: Vector2 = hn0.offset
		var NT := 12000
		var tx := PackedFloat64Array()
		var ty := PackedFloat64Array()
		tx.resize(NT)
		ty.resize(NT)
		for t in NT:
			var e: Vector2 = hn0.tick() - off0
			tx[t] = e.x * 1000.0
			ty[t] = e.y * 1000.0
		var mu := 0.0
		for t in NT:
			mu += tx[t]
		mu /= NT
		var var0 := 0.0
		for t in NT:
			var0 += (tx[t] - mu) * (tx[t] - mu)
		var0 /= NT
		var acl := ""
		for lag in [1, 2, 3, 6, 12, 30]:
			var c := 0.0
			for t in NT - int(lag):
				c += (tx[t] - mu) * (tx[t + int(lag)] - mu)
			c /= (NT - int(lag))
			acl += "L%d %.3f/%.3f  " % [lag, c / maxf(var0, 1e-30), pow(alpha, float(lag))]
		# within-throw tremor sd (250-tick windows), mean across 48 windows
		var ws := 0.0
		for wnd in 48:
			var seg: Array = []
			for t in 250:
				seg.append(tx[wnd * 250 + t])
			ws += sd_of(seg)
		ws /= 48.0
		# Hann periodogram, 10 segments of 1200 ticks, at chosen frequencies;
		# normalised so DC bin of the AR(1) theory = 1
		var freqs := [0.5, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 15.0, 20.0, 25.0, 29.5]
		var pl := ""
		if var0 > 0.0:
			var SEG := 1200
			var NS := NT / SEG
			var p0 := 0.0
			var pw: Array = []
			for f in freqs:
				var acc := 0.0
				for sgi in NS:
					var re := 0.0
					var im := 0.0
					for t in SEG:
						var wv := 0.5 - 0.5 * cos(2.0 * PI * t / SEG)
						var ph := -2.0 * PI * float(f) * t / 60.0
						var xv := (tx[sgi * SEG + t] - mu) * wv
						re += xv * cos(ph)
						im += xv * sin(ph)
					acc += re * re + im * im
				pw.append(acc / NS)
			# theory: 1/(1 - 2a cos w + a^2), normalised at f=0.5 Hz
			var th0 := 0.0
			for i in freqs.size():
				var w := 2.0 * PI * float(freqs[i]) / 60.0
				var th := 1.0 / (1.0 - 2.0 * alpha * cos(w) + alpha * alpha)
				if i == 0:
					p0 = float(pw[0])
					th0 = th
				pl += "%.1fHz %.2f/%.2f  " % [float(freqs[i]), float(pw[i]) / p0, th / th0]
		print("")
		print("TIER %-10s %s" % [tier, HN.new(tier, "x", 0).describe()])
		print("  offset sd over 400 throws: x %.2f mm  y %.2f mm   (claimed %.1f mm)" % [
			sd_of(offx), sd_of(offy), float(HN.TIERS[tier]["off"]) * 1000.0 / 60.0])
		print("  speed: mean %.4f sd %.4f  min %.3f max %.3f  (claimed sd %.2f)" % [
			(spd.reduce(func(a, b): return a + b, 0.0)) / 400.0, sd_of(spd), spd.min(), spd.max(), float(HN.TIERS[tier]["speed"])])
		print("  jit counts: %s" % jl)
		print("  tremor 12000 ticks: mean %.2f mm  stationary sd %.2f mm  within-250-tick sd %.2f mm  (claimed %.1f mm)" % [
			mu, sqrt(var0), ws, float(HN.TIERS[tier]["trem"]) * 1000.0 / 60.0])
		print("  autocorr measured/AR1: %s" % acl)
		print("  periodogram measured/theory (rel. 0.5 Hz): %s" % pl)
	# seed reproducibility
	print("")
	var a: RefCounted = HN.new("trackpad", "vfy", 7)
	var b: RefCounted = HN.new("trackpad", "vfy", 7)
	var c: RefCounted = HN.new("trackpad", "vfy", 8)
	var d: RefCounted = HN.new("trackpad", "vfx", 7)
	var e: RefCounted = HN.new("off_only", "vfy", 7)
	var same_ab: bool = a.offset == b.offset and a.speed == b.speed and a.jit == b.jit
	var same_ac: bool = a.offset == c.offset
	var same_ad: bool = a.offset == d.offset
	var same_ae: bool = a.offset == e.offset
	var seq_eq := true
	for t in 500:
		if a.tick() != b.tick():
			seq_eq = false
	print("SEEDS: (trackpad,vfy,7) twice -> draws equal %s, 500-tick sequences equal %s; sample 7 vs 8 offset equal %s; tag vfy vs vfx equal %s; tier trackpad vs off_only equal %s" % [
		same_ab, seq_eq, same_ac, same_ad, same_ae])
	print("  seed_of(vfy/trackpad,7) = %d  seed_of(vfy/trackpad,8) = %d" % [HN.seed_of("vfy/trackpad", 7), HN.seed_of("vfy/trackpad", 8)])
	# save/restore of the noise state rewinds the sequence bit-exactly
	var f: RefCounted = HN.new("trackpad", "vfy", 3)
	for t in 100:
		f.tick()
	var st: Dictionary = f.save_state()
	var s1: Array = []
	for t in 50:
		s1.append(f.tick())
	f.restore_state(st)
	var s2ok := true
	for t in 50:
		if f.tick() != s1[t]:
			s2ok = false
	print("  save/restore rewinds the tremor sequence bit-exactly: %s" % s2ok)
	quit(0)
