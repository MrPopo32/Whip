extends SceneTree
## SKILL OR CHANCE, PART 2: DIFFICULTY, KEPT APART FROM SKILL.
##
## Two fractions per station. First, how many stroke SHAPES lock the anchor at
## all: lab_throw's 108-cell grid plus a finer one around it (the stroke angle
## a1 at 5x the resolution, every stroke length 5..14, same 3 leads, 2 windup
## angles and pull/no-pull - 1320 cells, of which the 108 are a subset). That
## is how hard the throw is to FIND. Second, of the strokes that lock, how many
## still lock at P >= 0.8 under the trackpad tier of tests/hand_noise.gd
## (2 px offset, 2 px tremor, 5% speed, +/-3 ticks of press). That is how many
## of the working throws are ROBUST to the hand that has to make them. A game
## where many strokes work but few are robust punishes the hardware, not the
## player.
##
## The throw machinery is tests/skill_probe.gd's, line for line, so the two
## files' numbers are the same instrument. Noise-free cells use tier "null",
## which the probe asserts is bit-identical to no noise model at all.
##
##   godot --headless --path . -s res://tests/skill_grid.gd -- <station> <wrap|touch> <N_robust> <max_robust> <out.json>
const MAIN := preload("res://main.gd")
const HN := preload("res://tests/hand_noise.gd")

var m: Node2D
var stances := {}
var pristine := {}                    # every stance is built from the sim as
                                      # new_lab() made it (lab_throw's stand_at),
                                      # never from where the last throw left
                                      # the rope - see tests/skill_cell.gd

func new_lab() -> Node2D:
	var s: Node2D = MAIN.new()
	s.external_drive = true
	s.level_id = "lab"
	s.setup_sim()
	s.save_enabled = false
	return s

func stance(k: int, lead: float, a0: float) -> void:
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
	var out := {"snap_w": {}, "hn_w": {}}
	var t0 := 0
	if press >= 0:
		t0 = w
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
			fire = t >= press
		else:
			fire = cue(k, policy)
		if not grip and fire and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
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
	out["hash"] = m.state_hash()
	return out

func one(k: int, c: Dictionary, policy: String, tier: String, tag: String,
		s: int) -> Dictionary:
	stance(k, float(c["lead"]), float(c["a0"]))
	var hn: RefCounted = HN.new(tier, tag, s)
	return throw(k, c, policy, hn)

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var k := int(args[0])
	var policy := String(args[1])
	var NR := int(args[2])
	var MAXR := int(args[3])
	var outp := String(args[4])
	m = new_lab()
	pristine = m.snapshot()
	var name := String(m.a_name[k])
	var a1s: Array = []
	for i in 11:
		a1s.append(-PI * 0.42 + float(i) * PI * 0.024)
	var sds: Array = []
	for sd in range(5, 15):
		sds.append(sd)
	print("")
	print("DIFFICULTY  station %d %s  cue %s: 3 leads x 2 windups x 11 stroke angles x 10 stroke lengths x pull = 1320 cells"
		% [k, name, policy])
	var t0 := Time.get_ticks_msec()
	var cells: Array = []
	var fine_green := 0
	var fine_caught := 0
	var coarse_green := 0
	var coarse_n := 0
	for lead in [1.6, 2.0, 2.4]:
		for a0 in [PI * 0.85, PI * 1.10]:
			for pull in [false, true]:
				var map: Array = []
				for sd in sds:
					var line := ""
					for ai in a1s.size():
						var c := {"lead": lead, "a0": a0, "a1": a1s[ai],
							"sd": sd, "pull": pull, "w": 120}
						var r := one(k, c, policy, "null", "grid", 0)
						var g := bool(r["green"])
						var coarse: bool = (ai % 5 == 0) and (sd in [5, 9, 14])
						if coarse:
							coarse_n += 1
							if g:
								coarse_green += 1
						if g:
							fine_green += 1
						if bool(r["caught"]):
							fine_caught += 1
						line += "#" if g else ("o" if bool(r["caught"]) else ".")
						cells.append({"lead": lead, "a0": a0, "a1": a1s[ai],
							"sd": sd, "pull": pull, "caught": bool(r["caught"]),
							"green": g})
					map.append(line)
				print("  lead %.1f a0 %.2f %s   (rows sd 5..14, cols a1 -0.42pi..-0.18pi; # lock, o catch only, . miss)"
					% [float(lead), a0, "pull" if pull else "    "])
				for line: String in map:
					print("      " + line)
	print("  coarse 108: %d lock (%.1f%%)   fine 1320: %d catch, %d lock (%.1f%%)   %.0f s"
		% [coarse_green, 100.0 * coarse_green / maxi(1, coarse_n), fine_caught,
		fine_green, 100.0 * fine_green / 1320.0,
		(Time.get_ticks_msec() - t0) / 1000.0])

	# ---- robustness of the working strokes under the trackpad hand ----------
	var winners: Array = []
	for c: Dictionary in cells:
		if bool(c["green"]):
			winners.append(c)
	var pick: Array = []
	if winners.size() <= MAXR:
		pick = winners
	else:
		for i in MAXR:
			pick.append(winners[(i * winners.size()) / MAXR])
	print("")
	print("  ROBUSTNESS: %d of the %d locking strokes, N %d each at tier trackpad (%s)"
		% [pick.size(), winners.size(), NR, HN.new("trackpad", "x", 0).describe()])
	var ps: Array = []
	var hist := [0, 0, 0, 0, 0]        # <0.2, <0.5, <0.8, <1.0, ==1.0
	var t1 := Time.get_ticks_msec()
	for c: Dictionary in pick:
		var cc := c.duplicate()
		cc["w"] = 120
		var tag := "%s/grid/%.1f/%.3f/%.3f/%d/%s" % [name, float(c["lead"]),
			float(c["a0"]), float(c["a1"]), int(c["sd"]), str(bool(c["pull"]))]
		var g := 0
		for s in NR:
			if bool(one(k, cc, policy, "trackpad", tag, s)["green"]):
				g += 1
		var p := float(g) / NR
		ps.append(p)
		c["p_trackpad"] = p
		if p < 0.2:
			hist[0] += 1
		elif p < 0.5:
			hist[1] += 1
		elif p < 0.8:
			hist[2] += 1
		elif p < 1.0:
			hist[3] += 1
		else:
			hist[4] += 1
	var robust: int = int(hist[3]) + int(hist[4])
	var pm := 0.0
	for p in ps:
		pm += float(p)
	pm /= maxi(1, ps.size())
	print("  P(lock) under the trackpad hand: <0.2 %d   0.2-0.5 %d   0.5-0.8 %d   0.8-<1 %d   1.0 %d   mean %.2f   robust(>=0.8) %d/%d = %.0f%%   (%.0f s)"
		% [hist[0], hist[1], hist[2], hist[3], hist[4], pm, robust,
		ps.size(), 100.0 * robust / maxi(1, ps.size()),
		(Time.get_ticks_msec() - t1) / 1000.0])
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"station": k, "name": name,
			"policy": policy, "coarse_n": coarse_n, "coarse_green": coarse_green,
			"fine_n": 1320, "fine_caught": fine_caught, "fine_green": fine_green,
			"NR": NR, "picked": pick.size(), "hist": hist, "p_mean": pm,
			"robust": robust, "cells": cells}, "  "))
		f.close()
	m.free()
	quit(0)
