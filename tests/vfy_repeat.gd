extends SceneTree
## VERIFY "repeat": ONE INTENTION, REPEATED UNDER A HUMAN HAND - REBUILT FROM
## SCRATCH. Independent of tests/hand_noise.gd, rp_repeat.gd, skill_probe.gd:
## own stance, own throw loop, own noise model built to the brief's spec, own
## null. Nothing here touches main.gd, tapes, takes or levels. new_sim never
## enters the tree; no user://run*.save is written (save_enabled = false).
##
## THE SIM HAS NO RNG. THIS PROBE DOES. RandomNumberGenerator seeded from
## (stroke key, tier, sample index), draw order fixed, so any (tier, sample)
## reproduces bit-for-bit.
##
## NOISE (brief's spec):
##   OFFSET  per throw, Gaussian, sigma = tier px, x and y independent
##   TREMOR  per tick, AR(1) low-pass, pole exp(-2 pi 5 Hz / 60), stationary
##           sd = tier px, added to the cursor every tick
##   SPEED   per throw, N(1, 0.05) scale on the stroke's duration (clamped .8-1.2)
##   TIMING  per throw, uniform integer in [-J, +J] ticks on the grip press
## The pixel: main.gd PPM_INPUT = 60 px per metre of mouse -> 1 px = 16.67 mm.
## Tiers as the brief names them, in px: 0.3 ("good mouse"), 1, 2 ("trackpad").
##
##   godot --headless --path . -s res://tests/vfy_repeat.gd -- <station> <a0> <a1> <sd> <pull 0|1> <lead> <N> <out.json> [tiers,comma]
const MAIN := preload("res://main.gd")
const M_PER_PX := 1.0 / 60.0
const DT := 1.0 / 60.0
const W := 120                        # windup ticks (lab_throw's)
const HOLD := 180                     # ticks the hand stays shut after a catch

const TIERS := {
	"null":     [0.0, 0.0, 0.00, 0],
	"m03":      [0.3, 0.3, 0.05, 1],
	"m1":       [1.0, 1.0, 0.05, 2],
	"pad":      [2.0, 2.0, 0.05, 3],
	"off2":     [2.0, 0.0, 0.00, 0],
	"trem2":    [0.0, 2.0, 0.00, 0],
	"spd":      [0.0, 0.0, 0.05, 0],
	"jit3":     [0.0, 0.0, 0.00, 3],
	# tremor during the THROW only; the cursor is dead still during the hold
	"trem2t":   [0.0, 2.0, 0.00, 0, 1],
	"padt":     [2.0, 2.0, 0.05, 3, 1],
}

var m: Node2D
var k := 0
var c := {}
var stance_snap := {}
var terrain := {}

func new_lab() -> Node2D:
	var s: Node2D = MAIN.new()
	s.external_drive = true
	s.level_id = "lab"
	s.setup_sim()
	s.save_enabled = false
	return s

# ------------------------------------------------------------- the hand ----
class Hand:
	var rng := RandomNumberGenerator.new()
	var offset := Vector2.ZERO
	var speed := 1.0
	var jit := 0
	var trem := Vector2.ZERO
	var alpha := 0.0
	var innov := 0.0
	var still_hold := false
	func _init(key: String, tier: Array, sample: int) -> void:
		still_hold = tier.size() > 4 and int(tier[4]) == 1
		rng.seed = int(("%s|%s|%d" % [key, str(tier), sample]).hash()) \
			* 1000003 + sample * 7919
		var off_m: float = float(tier[0]) * M_PER_PX
		var trem_m: float = float(tier[1]) * M_PER_PX
		offset = Vector2(rng.randfn(0.0, off_m), rng.randfn(0.0, off_m)) \
			if off_m > 0.0 else Vector2.ZERO
		speed = clampf(rng.randfn(1.0, float(tier[2])), 0.8, 1.2) \
			if float(tier[2]) > 0.0 else 1.0
		jit = rng.randi_range(-int(tier[3]), int(tier[3])) \
			if int(tier[3]) > 0 else 0
		alpha = exp(-2.0 * PI * 5.0 * DT)
		innov = trem_m * sqrt(1.0 - alpha * alpha)
		trem = Vector2(rng.randfn(0.0, trem_m), rng.randfn(0.0, trem_m)) \
			if trem_m > 0.0 else Vector2.ZERO
	func tick() -> Vector2:
		if innov > 0.0:
			trem = trem * alpha + Vector2(rng.randfn(0.0, innov),
				rng.randfn(0.0, innov))
		return offset + trem
	func save() -> Dictionary:
		return {"st": rng.state, "tr": trem}
	func load(d: Dictionary) -> void:
		rng.state = int(d["st"])
		trem = d["tr"]

# ------------------------------------------------------------- the throw ---
func stance() -> void:
	# lab_throw's stand_at: stand lead metres short of the anchor, hand held
	# BACK at a0 for 90 ticks. Cached; noise-free by construction.
	if stance_snap.is_empty():
		m.teleport(Vector2(float(m.a_pos[k].x) - float(c["lead"]), -m.BODY_R))
		var a0 := float(c["a0"])
		for t in 90:
			m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
		stance_snap = m.snapshot()
	else:
		m.restore(stance_snap)

func aim(t: int, s: float) -> Array:
	if t < W:
		return [float(c["a0"]), 1.0]
	var te := float(t - W) / s
	if te < float(c["sd"]):
		return [float(c["a1"]), 1.0]
	if bool(c["pull"]) and te < float(c["sd"]) + 10.0:
		return [float(c["a0"]), 0.7]
	return [float(c["a1"]), 1.0]

func cue() -> bool:
	return absf(float(m.a_theta[k])) >= 2.6

# one pass. press < 0: reactive (close on cue, record the tick). press >= 0:
# resume from the windup snapshot and close at that tick instead.
func _pass(h: Hand, press: int, snapw: Dictionary) -> Dictionary:
	var grip := false
	var closes := 0
	var g0 := -1
	var caught := -1
	var out := {}
	var t0 := 0
	if press >= 0:
		t0 = W
	for t in range(t0, W + 130):
		if t == W and press < 0:
			out["snapw"] = m.snapshot()
			out["hw"] = h.save()
		var av := aim(t, h.speed)
		var tgt: Vector2 = m.body_pos + Vector2(cos(float(av[0])),
			sin(float(av[0]))) * m.REACH * float(av[1]) + h.tick()
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var want := false
		if press < 0:
			want = cue()
		else:
			want = t >= press if closes == 0 else cue()
		if not grip and want and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = t
			break
	out["g0"] = g0
	out["caught"] = caught
	if caught < 0:
		out["lock0"] = -9
		out["held"] = 0
		out["greenticks"] = 0
		out["hash"] = m.state_hash()
		return out
	out["lock0"] = int(m.a_locked[k])
	out["th0"] = float(m.a_theta[k])
	out["tether"] = float(m.a_freelen[k])
	# HOLD: hand shut, cursor at the body plus tremor, floor in.
	var held := 0
	var greenticks := 0
	var lock_dec := -1                 # first classification the sim gave
	var lock_t := -1
	for t in HOLD:
		m.step_tick(m.body_pos + (Vector2.ZERO if h.still_hold else h.tick()), true)
		if float(m.a_freelen[k]) >= 0.0:
			held += 1
			if lock_dec < 0 and int(m.a_locked[k]) >= 0:
				lock_dec = int(m.a_locked[k])
				lock_t = t
		if bool(m._holds(k)):
			greenticks += 1
	out["held"] = held
	out["greenticks"] = greenticks
	out["lock_dec"] = lock_dec
	out["lock_t"] = lock_t
	out["green_end"] = bool(m._holds(k))
	out["lock_end"] = int(m.a_locked[k]) if float(m.a_freelen[k]) >= 0.0 else -9
	out["hash"] = m.state_hash()
	return out

func throw(h: Hand) -> Dictionary:
	stance()
	var r := _pass(h, -1, {})
	if h.jit != 0 and int(r["g0"]) >= 0:
		m.restore(r["snapw"])
		h.load(r["hw"])
		var r2 := _pass(h, maxi(W, int(r["g0"]) + h.jit), {})
		r2["g0"] = r["g0"]
		r2["press"] = maxi(W, int(r["g0"]) + h.jit)
		return r2
	r.erase("snapw")
	r.erase("hw")
	r["press"] = r["g0"]
	return r

func classify(r: Dictionary) -> String:
	if int(r["caught"]) < 0:
		return "nocatch" if int(r["g0"]) >= 0 else "nocue"
	if int(r["lock_dec"]) == 0:
		return "partial"               # classified as a partial wrap, never green
	if int(r["lock_dec"]) < 0:
		return "undecided"             # let go before the sim classified it
	if int(r["held"]) < HOLD:
		return "lost"                  # locked, then the wrap let go
	if not bool(r["green_end"]):
		return "demoted"               # locked, still held, no longer green
	return "green"

# -------------------------------------------------------------------- run ---
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 8:
		print("usage: station a0 a1 sd pull lead N out.json [tiers]")
		quit(1); return
	k = int(a[0])
	c = {"a0": float(a[1]), "a1": float(a[2]), "sd": int(a[3]),
		"pull": int(a[4]) == 1, "lead": float(a[5])}
	var n := int(a[6])
	var outp: String = a[7]
	var tiers: Array = ["null", "m03", "m1", "pad"]
	if a.size() > 8:
		tiers = Array(String(a[8]).split(","))
	var key := "k%d/%.4f/%.4f/%d/%d/%.2f" % [k, c["a0"], c["a1"], c["sd"],
		int(c["pull"]), c["lead"]]
	m = new_lab()
	print("station %d %s  stroke %s" % [k, m.a_name[k], key])

	# INSTRUMENT NULL A: fresh sim built the lab_throw way (never restored),
	# versus the snapshot stance. Both must give one post-throw hash.
	var h0 := Hand.new(key, TIERS["null"], 0)
	var r0 := throw(h0)
	var fresh := new_lab()
	var mm := m
	m = fresh
	var saved_snap := stance_snap
	stance_snap = {}
	var r1 := throw(Hand.new(key, TIERS["null"], 0))
	fresh.free()
	m = mm
	stance_snap = saved_snap
	print("NULL A: fresh-sim hash %d  snapshot-stance hash %d  same=%s  outcome %s (g0 %d caught %d lock_dec %d th0 %.2f)" % [
		int(r1["hash"]), int(r0["hash"]), str(int(r1["hash"]) == int(r0["hash"])),
		classify(r0), int(r0["g0"]), int(r0["caught"]), int(r0.get("lock_dec", -9)),
		float(r0.get("th0", 0.0))])

	var report := {"station": k, "name": String(m.a_name[k]), "stroke": c,
		"N": n, "tiers": {}, "pixel_mm": M_PER_PX * 1000.0, "hold": HOLD}
	for tn in tiers:
		var tier: Array = TIERS[tn]
		var counts := {}
		var hashes := {}
		var rows := []
		var nn := n if tn != "null" else mini(n, 8)
		for s in nn:
			var h := Hand.new(key, tier, s)
			var r := throw(h)
			var cl := classify(r)
			counts[cl] = int(counts.get(cl, 0)) + 1
			print("    %s s%d %s off(%+.1f,%+.1f)mm spd %.3f jit %+d g0 %d press %d caught %d lock_dec %d held %d gt %d th0 %.2f" % [
				tn, s, cl, h.offset.x * 1000.0, h.offset.y * 1000.0, h.speed, h.jit,
				int(r["g0"]), int(r["press"]), int(r["caught"]), int(r.get("lock_dec", -9)),
				int(r["held"]), int(r["greenticks"]), float(r.get("th0", 0.0))])
			hashes[int(r["hash"])] = true
			rows.append({"s": s, "cl": cl, "off": [h.offset.x * 1000.0,
				h.offset.y * 1000.0], "spd": h.speed, "jit": h.jit,
				"g0": r["g0"], "press": r["press"], "caught": r["caught"],
				"lock0": r["lock0"], "lock_dec": r.get("lock_dec", -9), "lock_t": r.get("lock_t", -1), "held": r["held"], "gt": r["greenticks"],
				"th0": r.get("th0", 0.0), "teth": r.get("tether", -1.0)})
		var g := int(counts.get("green", 0))
		print("  tier %-6s off %.1fpx trem %.1fpx spd %.0f%% jit +/-%d  N=%d  green %d (%.0f%%)  %s  distinct hashes %d" % [
			tn, float(tier[0]), float(tier[1]), float(tier[2]) * 100.0,
			int(tier[3]), nn, g, 100.0 * g / nn, str(counts), hashes.size()])
		report["tiers"][tn] = {"tier": tier, "N": nn, "counts": counts,
			"distinct_hashes": hashes.size(), "rows": rows}
	var f := FileAccess.open(outp, FileAccess.WRITE)
	f.store_string(JSON.stringify(report))
	f.close()
	m.free()
	quit(0)
