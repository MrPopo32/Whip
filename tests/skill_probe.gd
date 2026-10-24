extends SceneTree
## SKILL OR CHANCE, PART 1: ONE INTENTION, REPEATED UNDER A HUMAN HAND.
##
## The sim has no RNG. The one thing that varies between two attempts at the
## SAME throw is the hand, and tests/hand_noise.gd is the model of that hand:
## a per-throw offset, a 5 Hz tremor, a 5% speed scale and a press-timing
## jitter, seeded per (stroke, sample) so every number here reproduces.
##
## Per station: find winning strokes with lab_throw's 108-cell search, then
## repeat each winner N times at each noise tier and read the OUTCOME
## distribution. Beside it, the same hand noise applied to the TIP'S landing
## position (particle 25 at peak speed) - the positive control. The tip is
## known to be chaotic (~0.9 m for a few mm of cursor); a rig that reported a
## tight tip would be broken. Then the LANDSCAPE: the same noise around
## strokes deliberately aimed off the winner, to see whether the odds fall
## away smoothly (a target you can walk toward) or spike (a needle).
##
## THE PROBE HAS RNG; THE SIM DOES NOT. Tier "null" (all sigmas zero) is run
## first and must give one state hash across every sample - the instrument's
## null - and that hash must equal the search's own hash for the same stroke.
##
##   godot --headless --path . -s res://tests/skill_probe.gd -- <station> <wrap|touch> <N> <out.json>
const MAIN := preload("res://main.gd")
const HN := preload("res://tests/hand_noise.gd")

const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]
const TIERS_MAIN := ["mouse03", "mouse1", "trackpad"]
const TIERS_SPLIT := ["off_only", "trem_only", "speed_only", "jit_only"]
const LANDSCAPE_D := [-0.12, -0.08, -0.04, -0.02, 0.0, 0.02, 0.04, 0.08, 0.12]

var m: Node2D
var stances := {}                     # (lead, a0) -> settled snapshot
var pristine := {}                    # every stance is built from the sim as
                                      # new_lab() made it (lab_throw's stand_at),
                                      # never from where the last throw left
                                      # the rope - see tests/skill_cell.gd
var report := {}

func new_lab() -> Node2D:
	var s: Node2D = MAIN.new()
	s.external_drive = true
	s.level_id = "lab"
	s.setup_sim()
	s.save_enabled = false
	return s

func stance(k: int, lead: float, a0: float) -> void:
	# lab_throw's stand_at: stand, hand held BACK at the windup angle, 90 ticks
	# of settle. Cached per (lead, a0) as a snapshot - the settle is noise-free
	# by construction, since the stroke (and its noise) has not begun.
	var key := "%.4f/%.4f" % [lead, a0]
	if not stances.has(key):
		m.restore(pristine)
		m.teleport(Vector2(float(m.a_pos[k].x) - lead, -m.BODY_R))
		for t in 90:
			m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
		stances[key] = m.snapshot()
	m.restore(stances[key])

func touching(k: int) -> bool:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

func cue(k: int, policy: String) -> bool:
	return absf(float(m.a_theta[k])) >= 2.6 if policy == "wrap" else touching(k)

# the stroke's aim at tick t, with the stroke's DURATION scaled by s
func aim(t: int, c: Dictionary, s: float) -> Array:
	var w := int(c["w"])
	if t < w:
		return [float(c["a0"]), 1.0]
	var te := float(t - w) / s
	if te < float(c["sd"]):
		return [float(c["a1"]), 1.0]
	if bool(c["pull"]) and te < float(c["sd"]) + 10.0:
		return [float(c["a0"]), 0.7]
	return [float(c["a1"]), 1.0]

# ONE NOISY THROW, from the restored stance. Two passes when the press is
# jittered: pass 1 closes the hand reactively on the cue (what the player is
# watching for) and records the tick it fired; pass 2 rewinds sim AND noise to
# the end of the windup and closes the hand at cue + jit instead - early
# (anticipating the rhythm) or late (reaction). After that first press the
# grip re-arms exactly as lab_throw's: re-open when GRIP_WINDOW lapses with
# nothing caught, re-close on the cue, at most 4 closes.
func throw(k: int, c: Dictionary, policy: String, hn: RefCounted) -> Dictionary:
	var w := int(c["w"])
	var r := _pass(k, c, policy, hn, w, -1)
	# no second pass when the whip caught inside the windup (a stance too
	# close to the beam): there is no windup-end snapshot to rewind to
	if hn.jit != 0 and int(r["g0"]) >= 0 and not (r["snap_w"] as Dictionary).is_empty():
		m.restore(r["snap_w"])
		hn.restore_state(r["hn_w"])
		var r2 := _pass(k, c, policy, hn, w, maxi(w, int(r["g0"]) + hn.jit))
		r2["g0"] = r["g0"]
		r2.erase("snap_w")
		r2.erase("hn_w")
		return r2
	r.erase("snap_w")
	r.erase("hn_w")
	return r

func _pass(k: int, c: Dictionary, policy: String, hn: RefCounted, w: int,
		press: int) -> Dictionary:
	var grip := false
	var closes := 0
	var g0 := -1
	var caught := false
	var et := -1
	var peak := -1.0
	var tip := Vector2.ZERO
	var tip_t := -1
	var out := {"snap_w": {}, "hn_w": {}}
	var t0 := 0
	if press >= 0:
		t0 = w                          # pass 2 resumes from the windup's end
	for t in range(t0, w + 130):
		if t == w and press < 0:
			out["snap_w"] = m.snapshot()
			out["hn_w"] = hn.save_state()
		var av := aim(t, c, hn.speed)
		var tgt: Vector2 = m.body_pos + Vector2(cos(float(av[0])),
			sin(float(av[0]))) * m.REACH * float(av[1]) + hn.tick()
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var fire := false
		if press >= 0 and closes == 0:
			fire = t >= press           # the jittered first press
		else:
			fire = cue(k, policy)
		if not grip and fire and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
		if t >= w and m.tip_speed > peak:
			peak = m.tip_speed
			tip = m.pos[m.NP - 1]
			tip_t = t
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	var green := false
	if caught:
		for t in 55:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		green = bool(m._holds(k))
	out["caught"] = caught
	out["green"] = green
	out["et"] = et
	out["g0"] = g0
	out["press"] = press if press >= 0 else g0
	out["tip"] = tip
	out["tip_t"] = tip_t
	out["peak"] = peak
	out["hash"] = m.state_hash()
	return out

func one(k: int, c: Dictionary, policy: String, tier: String, tag: String,
		s: int) -> Dictionary:
	stance(k, float(c["lead"]), float(c["a0"]))
	var hn: RefCounted = HN.new(tier, tag, s)
	var r := throw(k, c, policy, hn)
	r["speed"] = hn.speed
	r["jit"] = hn.jit
	r["off"] = hn.offset
	return r

static func sd_of(v: Array) -> float:
	if v.size() < 2:
		return 0.0
	var mu := 0.0
	for x in v:
		mu += float(x)
	mu /= v.size()
	var ss := 0.0
	for x in v:
		ss += (float(x) - mu) * (float(x) - mu)
	return sqrt(ss / (v.size() - 1))

func cell(k: int, c: Dictionary, policy: String, tier: String, tag: String,
		n: int, ref_tip: Vector2) -> Dictionary:
	var caught := 0
	var green := 0
	var xs: Array = []
	var ys: Array = []
	var dist: Array = []
	var ets: Array = []
	var hashes := {}
	for s in n:
		var r := one(k, c, policy, tier, tag, s)
		if bool(r["caught"]):
			caught += 1
		if bool(r["green"]):
			green += 1
		var tp: Vector2 = r["tip"]
		xs.append(tp.x)
		ys.append(tp.y)
		dist.append(tp.distance_to(ref_tip))
		if int(r["et"]) >= 0:
			ets.append(int(r["et"]))
		hashes[int(r["hash"])] = true
	var tip_rms := sqrt(sd_of(xs) * sd_of(xs) + sd_of(ys) * sd_of(ys))
	var dmean := 0.0
	for d in dist:
		dmean += float(d)
	dmean /= maxi(1, dist.size())
	return {"n": n, "caught": caught, "green": green, "tip_rms": tip_rms,
		"tip_dmean": dmean, "et_sd": sd_of(ets), "hashes": hashes.size()}

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var k := int(args[0])
	var policy := String(args[1])
	var N := int(args[2])
	var outp := String(args[3])
	m = new_lab()
	pristine = m.snapshot()
	var name := String(m.a_name[k])
	report = {"station": k, "name": name, "policy": policy, "N": N,
		"m_per_px": HN.M_PER_PX, "tiers": HN.TIERS}
	print("")
	print("SKILL PROBE  station %d %s  cue %s  N %d  (1 px = %.1f mm of hand)"
		% [k, name, policy, N, HN.M_PER_PX * 1000.0])

	# ---- 1. the search: lab_throw's 108 cells, noise-free ------------------
	var winners: Array = []
	var t0 := Time.get_ticks_msec()
	for lead in [1.6, 2.0, 2.4]:
		for ang: Array in GRID:
			for sd in [5, 9, 14]:
				for pull in [false, true]:
					var c := {"lead": lead, "a0": ang[0], "a1": ang[1],
						"sd": sd, "pull": pull, "w": 120}
					var r := one(k, c, policy, "null", "search", 0)
					if bool(r["green"]):
						c["hash"] = int(r["hash"])
						c["tip"] = r["tip"]
						c["g0"] = int(r["g0"])
						winners.append(c)
	print("  search: %d / 108 strokes lock (%.0f s)" % [winners.size(),
		(Time.get_ticks_msec() - t0) / 1000.0])
	report["search_green"] = winners.size()
	if winners.is_empty():
		print("  no winner: nothing to repeat")
		_dump(outp)
		quit(0)
		return
	var pick: Array = []
	if winners.size() <= 3:
		pick = winners
	else:
		pick = [winners[0], winners[winners.size() / 2],
			winners[winners.size() - 1]]

	# ---- 2. the null: all sigmas zero, N replays, one hash ------------------
	var w0: Dictionary = pick[0]
	var nh := {}
	for s in 5:
		var r := one(k, w0, policy, "null", "null", s)
		nh[int(r["hash"])] = true
	var null_ok: bool = nh.size() == 1 and nh.has(int(w0["hash"]))
	print("  NULL: 5 replays of winner 0 under tier null -> %d distinct hash(es); equals the search hash: %s"
		% [nh.size(), str(null_ok)])
	report["null_distinct_hashes"] = nh.size()
	report["null_ok"] = null_ok

	# ---- 3. one intention under noise -------------------------------------
	var cells: Array = []
	print("")
	print("  winner              tier        n  caught  green  P(green)  tip rms(m)  tip |d|(m)  et sd  hashes")
	for wi in pick.size():
		var c: Dictionary = pick[wi]
		var tag := "%s/%d/%.3f/%.3f/%d/%s" % [name, int(c["lead"] * 10), c["a0"],
			c["a1"], c["sd"], str(c["pull"])]
		var wl := "L%.1f a0 %.2f a1 %.2f sd %d %s" % [float(c["lead"]),
			float(c["a0"]), float(c["a1"]), int(c["sd"]),
			"pull" if bool(c["pull"]) else "    "]
		for tier: String in ["null"] + TIERS_MAIN + TIERS_SPLIT:
			var n := N if tier != "null" else 3
			var ce := cell(k, c, policy, tier, tag, n, c["tip"])
			ce["winner"] = wi
			ce["tier"] = tier
			ce["stroke"] = {"lead": c["lead"], "a0": c["a0"], "a1": c["a1"],
				"sd": c["sd"], "pull": c["pull"]}
			cells.append(ce)
			print("  %-30s %-10s %3d %6d %6d %8.2f %10.3f %10.3f %6.1f %6d" % [
				wl, tier, n, int(ce["caught"]), int(ce["green"]),
				float(ce["green"]) / n, float(ce["tip_rms"]),
				float(ce["tip_dmean"]), float(ce["et_sd"]), int(ce["hashes"])])
	report["cells"] = cells

	# ---- 4. the landscape: aimed off the winner, under the trackpad hand ----
	print("")
	print("  LANDSCAPE around winner 0 (stroke angle a1 shifted by d rad; 0.02 rad = 23 mm of cursor), trackpad tier")
	print("   d(rad)  noise-free  n  green  P(green)")
	var land: Array = []
	var nl := maxi(10, N * 2 / 3)
	for d in LANDSCAPE_D:
		var c := w0.duplicate()
		c["a1"] = float(w0["a1"]) + float(d)
		var r0 := one(k, c, policy, "null", "land", 0)
		var tag := "%s/land/%.3f" % [name, float(d)]
		var ce := cell(k, c, policy, "trackpad", tag, nl, r0["tip"])
		land.append({"d": d, "free": bool(r0["green"]), "n": nl,
			"green": int(ce["green"])})
		print("   %+5.2f   %-10s %3d %6d %8.2f" % [float(d),
			"green" if bool(r0["green"]) else ".", nl, int(ce["green"]),
			float(ce["green"]) / nl])
	report["landscape"] = land
	_dump(outp)
	quit(0)

func _dump(outp: String) -> void:
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	m.free()
