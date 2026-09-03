extends SceneTree
## ROUTE VARIETY - does a level's TERRAIN turn the whip's one motion into many
## problems? The darts/golf question asked of ROUTING rather than of the anchor.
##
## The whip has one hold verb. Anchor TYPES were measured as the same verb at a
## discount, and the crack as one motion covering 87.5% of its envelope. What
## has not been measured is the ENVIRONMENT: terrain between the body and the
## anchor that the rope must route around. This rig enumerates every legal
## standing spot on a level, throws lab_throw's motion grid at every anchor in
## rope reach from every spot, and asks how many DISTINCT MOTIONS the level's
## reachable anchors need.
##
## THE DEFINITION THAT DECIDES THE ANSWER. Standing position is NOT part of the
## motion - "the same throw, standing elsewhere" is darts. A motion is the
## CURSOR PATH fed to step_tick: (windup angle a0, stroke angle a1, pull,
## stroke duration sd if pulling), taken in the frame facing the anchor, and
## two paths closer than a few cm are the same motion (1.15 m of reach is 138
## physical px, ~17 mm per px).
##
## Nothing is hand-laid past what tests/lab_throw.gd hand-lays: the body is
## teleported onto a spot with the chain trailing behind it, settled 90 ticks
## with the hand held back at the windup angle, and everything after is
## (cursor, grip) through step_tick with a cue-driven grip. The lock oracle is
## the sim's own: a_freelen >= 0 and a_locked == 1 after 55 ticks with the
## hand shut (crit_jitter's convention; _holds()).
##
##   godot --headless --path . -s res://tests/route_variety.gd -- [key=value ...]
##
##   level=traverse|lab|<id>   which level (default traverse; "" is traverse)
##   grid=narrow|wide          narrow = lab_throw's 36 cells (24 distinct paths)
##                             wide   = 336 cells (224 distinct paths)
##   spacing=0.25              m between standing spots along a floor
##   floors=ground|all         ground = floors connected to the spawn's floor
##                             (island tops excluded); all = every up-facing segment
##   merge=0.05                m: two cursor paths closer than this are one motion
##   anchors=all|0,3,5         restrict the survey to these anchors
##   maxspots=0                cap on standing spots (0 = all), for timing runs
##   controls=1                run the negative controls (raised anchor, grip never)
##   repro=0                   lab only: rerun lab_throw's exact 108-cell sweeps
##   tap=1                     re-throw each anchor's best stroke with the
##                             substep contact tap and report the terrain touched
##   hashcheck=1               prove the tap does not move the state hash, and
##                             that the windup shortcut is the full path
##   out=<file.json>           write this survey's lock records (shard by anchors=)
##   load=<a.json,b.json>      skip the survey, report from these shards
##
## Writes nothing but the shard file out= names (never under user://). Reads
## nothing but main.gd and the shards load= names. Fails, exit 1, if a probe
## sim ever has save_enabled set, if any user:// save slot changed, if the
## survey made no throws, or if a shard was taken on another level or grid.
##
## COST, measured 2026-09-02 on a Ryzen 3 7335U with the sim at ~3-6 ms per
## tick in GDScript: a throw is ~150-190 ticks (the windup is played once per
## (spot, facing, a0) and snapshotted), so ~0.5-1 s each. The lab narrow
## survey is ~4300 throws, the traverse ~11000, the crag ~11000; the wide
## grid is 9.3x that. Shard by anchor across cores (anchors= out=) and merge
## with load=. This is an overnight instrument, not a commit gate.

const TAP := preload("res://tests/route_tap.gd")
const MAIN := preload("res://main.gd")

const ROPE := 6.40            # m: 5.25 m of chain + 1.15 m of arm
const FLOOR_DEG := 20.0       # the gait cannot climb steeper than this
const SETTLE := 90            # lab_throw's stand_at
const W := 120                # lab_throw's windup
const RUN := 130              # lab_throw's stroke + follow
const HOLD := 55              # crit_jitter's hold, hand shut
const CUE_WRAP := 2.6         # route_bot's wrap cue
const SAVES := ["user://run.save", "user://run_lab.save", "user://run_crag.save"]

var A := {}
var level := ""
var spacing := 0.25
var merge := 0.05
var n_throws := 0
var n_ticks := 0
var t_start := 0

# the level, read once
var names: Array = []
var apos: Array = []
var arad: Array = []
var ajam: Array = []
var nseg := 0
var narc := 0                 # fillet arcs (crag), terrain the rope can touch too
var lvl_fp := 0
var spots: Array = []         # {pos, seg, along, clipped}
var island_segs := 0          # floor-facing segments not connected to the ground
var island_spots := 0

# the grid
var cells: Array = []         # {a0, a1, sd, pull, cls}
var classes: Array = []       # leader cell index per motion class
var a0s: Array = []

# the survey: every lock as [k, spot, cell, facing, primary, tether]
var locks: Array = []
var attempts: Array = []      # per anchor
var pairs := 0

func p(s: String) -> void:
	print(s)

# A GATE THAT CANNOT PASS BY FALLING THROUGH. GDScript's assert only breaks
# the function it is in; the script runs on and the last line would still say
# PASS. Anything that invalidates the run goes through here instead.
var dead := false
func die(msg: String) -> void:
	dead = true
	print("FAIL route_variety: " + msg)
	quit(1)

func arg(k: String, d: String) -> String:
	return String(A.get(k, d))

func ms() -> int:
	return Time.get_ticks_msec() - t_start

# ---------------------------------------------------------------- the sim --
func new_sim() -> Node2D:
	var m: Node2D = TAP.new()
	m.external_drive = true
	m.level_id = level
	m.setup_sim()
	if m.save_enabled:
		die("a probe sim must never write a save")
	return m

func tick(m: Node2D, tgt: Vector2, grip: bool) -> void:
	m.step_tick(tgt, grip)
	n_ticks += 1

func save_stamp() -> Array:
	var out := []
	for s in SAVES:
		out.append([FileAccess.file_exists(s), FileAccess.get_modified_time(s)])
	return out

# ------------------------------------------------------------- the level --
func read_level() -> void:
	var m := new_sim()
	lvl_fp = m.level_fingerprint()
	nseg = m.t_a.size()
	narc = m.t_arc_c.size() if "t_arc_c" in m else 0
	for k in m.a_pos.size():
		names.append(String(m.a_name[k]))
		apos.append(m.a_pos[k])
		arad.append(float(m.a_r[k]))
		ajam.append(int(m.a_jam[k]))
	attempts.resize(apos.size())
	attempts.fill(0)
	# LEGAL STANDING SPOTS: every terrain segment whose outward normal points
	# up to within FLOOR_DEG, sampled along its length, inset BODY_R from each
	# end (a body centred nearer the end than its radius is not touching the
	# segment and falls off it - _collide_body's round cap needs |d| < BODY_R),
	# the body centred BODY_R along the normal.
	var cosmax := cos(deg_to_rad(FLOOR_DEG))
	var br: float = m.BODY_R
	# THE GROUND IS WHAT THE SPAWN'S FLOOR CONNECTS TO. An island's top face
	# (a brow, a lump, a shelf) has an upward normal too, and the gait can
	# never reach it, so spots there are counted and left out unless
	# floors=all. Segments are joined where they share an endpoint.
	var comp := PackedInt32Array()
	comp.resize(nseg)
	for i in nseg:
		comp[i] = i
	# A FILLETED CORNER SHARES NO ENDPOINT: _fillet shortens both segments to
	# the tangent points of a circle kept in t_arc_c / t_arc_r, so two
	# segments are also joined when an endpoint of each lies on the same arc.
	var arcs_c: PackedVector2Array = m.t_arc_c if "t_arc_c" in m else PackedVector2Array()
	var arcs_r: PackedFloat32Array = m.t_arc_r if "t_arc_r" in m else PackedFloat32Array()
	for i in nseg:
		for j in range(i + 1, nseg):
			var touch := false
			for e1 in [m.t_a[i], m.t_b[i]]:
				for e2 in [m.t_a[j], m.t_b[j]]:
					if e1.distance_to(e2) < 1e-4:
						touch = true
					for a in arcs_c.size():
						if absf(e1.distance_to(arcs_c[a]) - arcs_r[a]) < 1e-3 								and absf(e2.distance_to(arcs_c[a]) - arcs_r[a]) < 1e-3:
							touch = true
			if touch:
				var ci := comp_root(comp, i)
				var cj := comp_root(comp, j)
				if ci != cj:
					comp[ci] = cj
	var ground_seg := -1
	var gd := 1e9
	for i in nseg:
		var cp := Geometry2D.get_closest_point_to_segment(m.spawn, m.t_a[i], m.t_b[i])
		if m.spawn.distance_to(cp) < gd and -m.t_n[i].y >= cosmax:
			gd = m.spawn.distance_to(cp)
			ground_seg = i
	var ground := comp_root(comp, ground_seg)
	var all_floors := arg("floors", "ground") == "all"
	for s in nseg:
		var n: Vector2 = m.t_n[s]
		if -n.y < cosmax:
			continue
		if not all_floors and comp_root(comp, s) != ground:
			var L2: float = (m.t_b[s] - m.t_a[s]).length()
			island_spots += maxi(int(floor((L2 - 2.0 * br) / spacing)) + 1, 0)
			island_segs += 1
			continue
		var Aa: Vector2 = m.t_a[s]
		var Bb: Vector2 = m.t_b[s]
		var L := (Bb - Aa).length()
		var dir := (Bb - Aa) / L
		var d := br
		while d <= L - br + 1e-6:
			spots.append({"pos": Aa + dir * d + n * br, "seg": s, "along": d,
				"clipped": false})
			d += spacing
	m.free()
	var cap := int(arg("maxspots", "0"))
	if cap > 0 and spots.size() > cap:
		spots.resize(cap)

func print_level() -> void:
	p("")
	p("LEVEL %s  fingerprint %d  main.gd md5 %s" % [
		"traverse" if level == "" else level, lvl_fp,
		FileAccess.get_md5("res://main.gd")])
	p("  %d terrain segments (%d fillet arcs), %d anchors, %d standing spots at %.2f m on the floors%s"
		% [nseg, narc, apos.size(), spots.size(), spacing,
		"" if island_segs == 0 else "  (%d island-top segments with %d more spots the gait cannot reach: excluded, floors=all includes them)" % [island_segs, island_spots]])
	var per := {}
	for sp in spots:
		per[sp["seg"]] = int(per.get(sp["seg"], 0)) + 1
	var m := new_sim()
	for s in per:
		p("    floor seg %2d  (%.1f,%.1f)->(%.1f,%.1f)  %d spots" % [s,
			m.t_a[s].x, m.t_a[s].y, m.t_b[s].x, m.t_b[s].y, int(per[s])])
	m.free()
	p("  anchors:")
	for k in apos.size():
		p("    %2d %-10s (%6.2f,%6.2f) r %.2f jam %d" % [k, aname(k),
			apos[k].x, apos[k].y, arad[k], ajam[k]])

func comp_root(comp: PackedInt32Array, i: int) -> int:
	while comp[i] != i:
		i = comp[i]
	return i

func aname(k: int) -> String:
	return names[k] if names[k] != "" else "A%d" % k

# -------------------------------------------------------------- the grid --
func build_grid(kind: String) -> void:
	var a0v: Array
	var a1v: Array
	if kind == "wide":
		a0v = [PI * 0.70, PI * 0.78, PI * 0.85, PI * 0.93, PI * 1.02, PI * 1.10,
			PI * 1.18]
		a1v = [-PI * 0.55, -PI * 0.48, -PI * 0.42, -PI * 0.36, -PI * 0.30,
			-PI * 0.24, -PI * 0.18, -PI * 0.10]
	else:
		a0v = [PI * 0.85, PI * 1.10]
		a1v = [-PI * 0.42, -PI * 0.30, -PI * 0.18]
	a0s = a0v
	var dup := 0
	for a0 in a0v:
		for a1 in a1v:
			for sd in [5, 9, 14]:
				for pull in [false, true]:
					# sd does nothing when pull is off (measured: 7 values, one
					# hash), so those cells are one cursor path and are thrown
					# once. The cell count reported is the grid's; the paths
					# thrown are the distinct ones.
					if not pull and sd != 9:
						dup += 1
						continue
					cells.append({"a0": a0, "a1": a1, "sd": sd, "pull": pull,
						"cls": -1})
	cluster()
	p("")
	p("MOTION GRID %s: %d cells, %d distinct cursor paths, %d motions after merging paths closer than %.0f mm"
		% [kind, cells.size() + dup, cells.size(), classes.size(), merge * 1000.0])
	for thr in [0.02, 0.05, 0.10, 0.20]:
		p("    merge at %3.0f mm -> %3d motions" % [thr * 1000.0,
			cluster_count(thr)])

func path_of(c: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var sd := int(c["sd"])
	var pull := bool(c["pull"])
	for t in W + RUN:
		var ang: float
		var amp := 1.0
		if t < W:
			ang = float(c["a0"])
		elif t < W + sd:
			ang = float(c["a1"])
		elif pull and t < W + 10 + sd:
			ang = float(c["a0"]); amp = 0.7
		else:
			ang = float(c["a1"])
		out.append(Vector2(cos(ang), sin(ang)) * 1.15 * amp)
	return out

# DISTANCE BETWEEN TWO MOTIONS: the windup poses must agree, and over the 130
# stroke ticks the two cursor targets must agree on average. Mean, not max: a
# stroke that is 1 tick longer is not a different throw, one that is 9 ticks
# longer (150 ms, well outside human press scatter) is.
func path_dist(pa: PackedVector2Array, pb: PackedVector2Array) -> float:
	var wind := pa[0].distance_to(pb[0])
	var acc := 0.0
	for t in range(W, W + RUN):
		acc += pa[t].distance_to(pb[t])
	return maxf(wind, acc / float(RUN))

func cluster() -> void:
	classes.clear()
	var paths := []
	for c in cells:
		paths.append(path_of(c))
	for i in cells.size():
		var found := -1
		for ci in classes.size():
			if path_dist(paths[i], paths[int(classes[ci])]) < merge:
				found = ci
				break
		if found < 0:
			classes.append(i)
			found = classes.size() - 1
		cells[i]["cls"] = found

func cluster_count(thr: float) -> int:
	var leaders := []
	var paths := []
	for c in cells:
		paths.append(path_of(c))
	for i in cells.size():
		var found := false
		for l in leaders:
			if path_dist(paths[i], paths[int(l)]) < thr:
				found = true
				break
		if not found:
			leaders.append(i)
	return leaders.size()

func cell_str(c: Dictionary) -> String:
	if bool(c["pull"]):
		return "a0 %.2fpi a1 %+.2fpi pull sd %2d" % [float(c["a0"]) / PI,
			float(c["a1"]) / PI, int(c["sd"])]
	return "a0 %.2fpi a1 %+.2fpi no pull " % [float(c["a0"]) / PI,
		float(c["a1"]) / PI]

# ------------------------------------------------------------- one throw --
func ang_f(ang: float, f: int) -> float:
	return ang if f > 0 else PI - ang

# Is any particle inside terrain OTHER than the shallow bed the reset layout
# always puts it in? _reset lays the chain 0.55 m under the body centre, so
# teleport(x, -BODY_R) - lab_throw's own idiom - starts the chain 0.27 m into
# the floor it stands on and the rescue branch lifts it out on substep 1.
# That is every spot and is not the thing worth counting; a chain that went
# into a ledge or a wall behind the spot is.
func inside_terrain(m: Node2D, stand_seg: int) -> bool:
	for i in m.NP:
		var q: Vector2 = m.pos[i]
		for s in m.t_a.size():
			var Aa: Vector2 = m.t_a[s]
			var ab: Vector2 = m.t_b[s] - Aa
			var tt := (q - Aa).dot(ab) / ab.length_squared()
			if tt <= 0.0 or tt >= 1.0:
				continue
			var depth := -(q - (Aa + ab * tt)).dot(m.t_n[s])
			if depth > (0.30 if s == stand_seg else 0.0):
				return true
	return false

# STAND, AND WIND UP - lab_throw's stand_at: teleport the body onto the spot
# with the chain trailing rigidly behind it, then settle SETTLE ticks with the
# hand held back at the windup angle. For an anchor to the LEFT the chain is
# mirrored about the body first, so a leftward throw starts from the mirror
# image of the posture a rightward one starts from. Returns whether the
# trailing chain was placed inside terrain (a ledge or wall behind the spot),
# which the sim's rescue branch lifts out on the first substep.
func stand(m: Node2D, sp: Dictionary, f: int, a0: float) -> bool:
	m.teleport(sp["pos"])
	if f < 0:
		var bx: float = m.body_pos.x
		var ps: PackedVector2Array = m.pos.duplicate()
		for i in ps.size():
			ps[i] = Vector2(2.0 * bx - ps[i].x, ps[i].y)
		m.pos = ps
		m.prv = ps.duplicate()
	var clipped := inside_terrain(m, int(sp["seg"]))
	var a := ang_f(a0, f)
	for t in SETTLE:
		tick(m, m.body_pos + Vector2(cos(a), sin(a)) * m.REACH, false)
	return clipped

func touching(m: Node2D, k: int) -> bool:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

func policy_of(k: int) -> String:
	# what the lab probes chose per station: the wrap cue on a beam, the touch
	# cue on a jam (crit_basin / crit_jitter rows)
	return "touch" if ajam[k] == 1 else "wrap"

func cue_of(m: Node2D, k: int, policy: String) -> bool:
	if policy == "wrap":
		return absf(float(m.a_theta[k])) >= CUE_WRAP
	if policy == "touch":
		return touching(m, k)
	return false

# lab_throw's throw_once, with the facing frame and a "never" policy for the
# negative control. Returns every anchor the sim holds LOCKED after the hold.
#
# t_from: ticks of the throw already played. The 120-tick windup is the same
# input for every cell that shares a windup angle (hand at a0, grip open), so
# the survey plays it once per (spot, facing, a0), snapshots, and starts every
# cell at the stroke - bit-identical to playing it through, PROVIDED the grip
# cue never fired during the windup (the survey checks per target and falls
# back to the full path when it did). hash_check() proves the identity.
func throw_once(m: Node2D, k: int, c: Dictionary, policy: String,
		f: int, t_from := 0) -> Dictionary:
	var grip := false
	var closes := 0
	var sd := int(c["sd"])
	var pull := bool(c["pull"])
	var caught := false
	var et := -1
	var g0 := -1
	for t in range(t_from, W + RUN):
		var ang: float
		var amp := 1.0
		if t < W:
			ang = float(c["a0"])
		elif t < W + sd:
			ang = float(c["a1"])
		elif pull and t < W + 10 + sd:
			ang = float(c["a0"]); amp = 0.7
		else:
			ang = float(c["a1"])
		var a := ang_f(ang, f)
		var tgt: Vector2 = m.body_pos + Vector2(cos(a), sin(a)) * m.REACH * amp
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var cue := cue_of(m, k, policy)
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		tick(m, tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	n_throws += 1
	var held := []
	var engaged := false
	for j in apos.size():
		if float(m.a_freelen[j]) >= 0.0:
			engaged = true
	if engaged:
		for t in HOLD:
			tick(m, m.body_pos, true)
			var any := false
			for j in apos.size():
				if float(m.a_freelen[j]) >= 0.0:
					any = true
			if not any:
				break
		for j in apos.size():
			if bool(m._holds(j)):
				held.append(j)
	return {"caught": caught, "et": et, "g0": g0, "held": held,
		"tether": float(m.a_freelen[k])}

# The windup, played once: SETTLE ticks then W ticks with the hand at a0 and
# the grip open, watching whether any target's cue would have fired. Returns
# the post-settle snapshot, the post-windup snapshot, and the set of targets
# whose cue fired (those must be thrown from the post-settle snapshot).
func windup(m: Node2D, sp: Dictionary, f: int, a0: float, tg: Array,
		policy_override: String) -> Dictionary:
	var clipped := stand(m, sp, f, a0)
	var s0: Dictionary = m.snapshot()
	var fired := {}
	var a := ang_f(a0, f)
	for t in W:
		tick(m, m.body_pos + Vector2(cos(a), sin(a)) * m.REACH, false)
		for k in tg:
			var pol := policy_override if policy_override != "" else policy_of(k)
			if cue_of(m, k, pol):
				fired[k] = true
	var s1: Dictionary = m.snapshot()
	return {"s0": s0, "s1": s1, "fired": fired, "clipped": clipped}

# ------------------------------------------------------------ the survey --
func targets_of(sp: Dictionary, f: int, ks: Array, override := {}) -> Array:
	var out := []
	for k in ks:
		var ap: Vector2 = override.get(k, apos[k])
		var dx: float = ap.x - sp["pos"].x
		if (f > 0 and dx < 0.0) or (f < 0 and dx >= 0.0):
			continue
		if sp["pos"].distance_to(ap) > ROPE:
			continue
		out.append(k)
	return out

func survey(ks: Array, policy_override := "", record := true) -> Dictionary:
	# returns the lock records; also fills `locks` when record is on
	var found := []
	var t0 := ms()
	var thr0 := n_throws
	var clipped := 0
	var settled := 0
	var lefts := 0
	var fallbacks := 0
	pairs = 0
	for si in spots.size():
		var sp: Dictionary = spots[si]
		for f in [1, -1]:
			var tg := targets_of(sp, f, ks)
			if tg.is_empty():
				continue
			pairs += tg.size()
			for a0 in a0s:
				var m := new_sim()
				var wu := windup(m, sp, f, a0, tg, policy_override)
				if bool(wu["clipped"]):
					sp["clipped"] = true
				settled += 1
				for k in tg:
					var pol := policy_override if policy_override != "" \
						else policy_of(k)
					var full: bool = wu["fired"].has(k)
					if full:
						fallbacks += 1
					for ci in cells.size():
						var c: Dictionary = cells[ci]
						if float(c["a0"]) != float(a0):
							continue
						if not m.restore(wu["s0"] if full else wu["s1"]):
							die("restore refused its own snapshot")
							return {}
						var r := throw_once(m, k, c, pol, f, 0 if full else W)
						attempts[k] += 1
						for j in r["held"]:
							var rec := [int(j), si, ci, f, int(j) == k,
								float(m.a_freelen[j])]
							found.append(rec)
							if record:
								locks.append(rec)
							if f < 0:
								lefts += 1
				m.free()
		if (si + 1) % 50 == 0:
			p("    ... spot %d/%d  %d throws  %.1f s" % [si + 1, spots.size(),
				n_throws - thr0, float(ms() - t0) / 1000.0])
	for sp in spots:
		if bool(sp["clipped"]):
			clipped += 1
	return {"found": found, "throws": n_throws - thr0, "ms": ms() - t0,
		"settled": settled, "clipped": clipped, "lefts": lefts, "pairs": pairs,
		"fallbacks": fallbacks}

# ------------------------------------------------------------- the report --
func lead_of(k: int, si: int) -> float:
	return absf(apos[k].x - spots[si]["pos"].x)

func report(ks: Array, sv: Dictionary) -> Dictionary:
	# per-anchor tables, the coverage curve, the designer's view
	var by_k := {}          # k -> {spots:{}, cls:{}, cells:{}, n:int, best_spot, ...}
	for k in ks:
		by_k[k] = {"spots": {}, "cls": {}, "n": 0, "prim": 0, "spotcells": {},
			"clscount": {}}
	for rec in sv["found"]:
		var k: int = rec[0]
		if not by_k.has(k):
			continue
		var d: Dictionary = by_k[k]
		d["n"] += 1
		if bool(rec[4]):
			d["prim"] += 1
		d["spots"][rec[1]] = true
		var cls := int(cells[rec[2]]["cls"])
		d["cls"][cls] = true
		d["clscount"][cls] = int(d["clscount"].get(cls, 0)) + 1
		var key := int(rec[1])
		d["spotcells"][key] = int(d["spotcells"].get(key, 0)) + 1
	p("")
	p("PER ANCHOR - %d throws over %d (anchor, spot) pairs in %.1f s; %d windups, %d target(s) needed the full path (cue fired in the windup), %d of %d spots had the trailing chain placed inside terrain, %d locks were left-facing"
		% [int(sv["throws"]), int(sv["pairs"]), float(sv["ms"]) / 1000.0,
		int(sv["settled"]), int(sv.get("fallbacks", 0)), int(sv["clipped"]),
		spots.size(), int(sv["lefts"])])
	p("  anchor          att  locks  spots  motions  lead(m)      best spot           best motion (its locks)  shares with")
	var reach := []
	var best_cls := {}
	for k in ks:
		var d: Dictionary = by_k[k]
		if d["n"] == 0:
			p("  %2d %-10s %5d      0      0        0  -            unreachable from any spot with any motion"
				% [k, aname(k), attempts[k]])
			continue
		reach.append(k)
		# best spot: the one with the most locking cells
		var bs := -1
		var bsn := -1
		for si in d["spotcells"]:
			if int(d["spotcells"][si]) > bsn:
				bsn = int(d["spotcells"][si]); bs = int(si)
		# best motion: the class with the most locks on this anchor
		var bc := -1
		var bcn := -1
		for cls in d["clscount"]:
			if int(d["clscount"][cls]) > bcn:
				bcn = int(d["clscount"][cls]); bc = int(cls)
		best_cls[k] = bc
		var lmin := 1e9
		var lmax := 0.0
		for si in d["spots"]:
			lmin = minf(lmin, lead_of(k, int(si)))
			lmax = maxf(lmax, lead_of(k, int(si)))
		d["best_spot"] = bs
		d["best_cls"] = bc
		p("  %2d %-10s %5d %6d %6d %8d  %4.2f-%4.2f  (%6.2f,%6.2f) %2d/%-3d  #%-3d %-28s %3d  %s"
			% [k, aname(k), attempts[k], d["n"], d["spots"].size(),
			d["cls"].size(), lmin, lmax, spots[bs]["pos"].x, spots[bs]["pos"].y,
			bsn, cells_per_spot_for(k, bs), bc, cell_str(cells[int(classes[bc])]),
			bcn, "(see below)"])
	# which anchors does each motion lock at all, from any spot
	var cover := {}
	for cls in classes.size():
		cover[cls] = {}
	for rec in sv["found"]:
		var k: int = rec[0]
		if by_k.has(k):
			cover[int(cells[rec[2]]["cls"])][k] = true
	p("")
	p("  best motion sharing - an anchor whose best motion also locks six others is not adding a problem:")
	for k in reach:
		var bc: int = best_cls[k]
		var others := []
		for j in cover[bc]:
			if int(j) != k:
				others.append(aname(int(j)))
		p("    %2d %-10s best #%-3d %-28s also locks %d other anchor(s): %s"
			% [k, aname(k), bc, cell_str(cells[int(classes[bc])]), others.size(),
			", ".join(others) if others.size() > 0 else "-"])
	# THE HEADLINE: greedy set cover of the reachable anchors by motions, lead free
	p("")
	p("COVERAGE CURVE, lead free (greedy set cover): %d reachable anchors of %d"
		% [reach.size(), ks.size()])
	var uncovered := {}
	for k in reach:
		uncovered[k] = true
	var chosen := []
	var curve := []
	var step := 0
	while uncovered.size() > 0:
		var best := -1
		var bn := 0
		for cls in classes.size():
			var n := 0
			for k in cover[cls]:
				if uncovered.has(k):
					n += 1
			if n > bn:
				bn = n; best = cls
		if best < 0:
			break
		chosen.append(best)
		for k in cover[best]:
			uncovered.erase(k)
		step += 1
		var pct := 100.0 * float(reach.size() - uncovered.size()) / float(maxi(reach.size(), 1))
		curve.append(pct)
		p("    %2d motion(s): %5.1f%% of reachable anchors   (+%d: #%-3d %s)"
			% [step, pct, bn, best, cell_str(cells[int(classes[best])])])
	var n90 := 0
	for i in curve.size():
		if float(curve[i]) >= 90.0:
			n90 = i + 1
			break
	if reach.size() == 0:
		p("    nothing reachable: no curve")
	else:
		p("    -> %d motion(s) lock 90%% of the reachable anchors; %d lock all of them"
			% [n90, chosen.size()])
		p("    verdict: %s" % ("DARTS (flat by 2-3: the environment adds nothing)"
			if n90 <= 3 else ("still climbing at %d: the terrain is forcing a repertoire" % n90
			if n90 >= 8 else "in between")))
	return {"by_k": by_k, "reach": reach, "best_cls": best_cls, "n90": n90,
		"curve": curve}

func cells_per_spot_for(k: int, si: int) -> int:
	# how many cells were thrown at k from spot si (both facings)
	var n := 0
	var sp: Dictionary = spots[si]
	for f in [1, -1]:
		if targets_of(sp, f, [k]).size() > 0:
			n += cells.size()
	return n

# --------------------------------------------------------------- the tap --
func line_hits(a: Vector2, b: Vector2, m: Node2D, skip: int) -> Array:
	var out := []
	for s in m.t_a.size():
		if s == skip:
			continue
		var x: Vector2 = MAIN._seg_cross(a, b, m.t_a[s], m.t_b[s])
		if x.x != INF:
			out.append(s)
	return out

func tap_winners(rep: Dictionary, sv: Dictionary) -> void:
	p("")
	p("TERRAIN ON THE WAY IN - each reachable anchor's best spot, its first locking stroke re-thrown with the substep contact tap")
	p("  (substep = 16 samples per tick, the sim's own contact resolution; per-tick = the same point test once per tick, the control that tunnels)")
	for k in rep["reach"]:
		var d: Dictionary = rep["by_k"][k]
		var bs := int(d["best_spot"])
		# first locking record at that spot for this anchor, primary preferred
		var rec := []
		for r in sv["found"]:
			if int(r[0]) == k and int(r[1]) == bs and bool(r[4]):
				rec = r
				break
		if rec.is_empty():
			for r in sv["found"]:
				if int(r[0]) == k and int(r[1]) == bs:
					rec = r
					break
		if rec.is_empty():
			continue
		var c: Dictionary = cells[int(rec[2])]
		var f := int(rec[3])
		var m := new_sim()
		stand(m, spots[bs], f, float(c["a0"]))
		TAP.tap_reset(nseg, apos.size(), narc)
		# the per-tick control, sampled by the rig after every step_tick
		var tk_seg := PackedInt32Array(); tk_seg.resize(nseg); tk_seg.fill(0)
		var tk_first := PackedInt32Array(); tk_first.resize(nseg); tk_first.fill(-1)
		var tk_lo := PackedInt32Array(); tk_lo.resize(nseg); tk_lo.fill(999)
		var tk_hi := PackedInt32Array(); tk_hi.resize(nseg); tk_hi.fill(-1)
		var tk_anc := PackedInt32Array(); tk_anc.resize(apos.size()); tk_anc.fill(0)
		var tk_afirst := PackedInt32Array(); tk_afirst.resize(apos.size()); tk_afirst.fill(-1)
		TAP.tap_on = true
		var r := throw_tapped(m, k, c, policy_of(k), f, tk_seg, tk_first, tk_lo,
			tk_hi, tk_anc, tk_afirst)
		TAP.tap_on = false
		var body: Vector2 = spots[bs]["pos"]
		var line := line_hits(body, apos[k], m, int(spots[bs]["seg"]))
		p("")
		p("  %2d %-10s from (%6.2f,%6.2f) facing %s  %s  -> %s (tether %.2f, caught tick %d, hand shut tick %d)"
			% [k, aname(k), body.x, body.y, "right" if f > 0 else "left",
			cell_str(c), "LOCKED" if r["held"].has(k) else "did not repeat",
			float(r["tether"]), int(r["et"]), int(r["g0"])])
		p("     straight line body->anchor crosses %d terrain segment(s): %s"
			% [line.size(), str(line) if line.size() > 0 else "none"])
		var sub := []
		var per := []
		for s in nseg:
			if TAP.tap_seg[s] > 0:
				sub.append(s)
			if tk_seg[s] > 0:
				per.append(s)
		p("     rope touched %d segment(s) at substep resolution, %d at per-tick resolution%s"
			% [sub.size(), per.size(),
			"" if sub.size() == per.size() else "  <- the per-tick test missed %d" % (sub.size() - per.size())])
		for s in sub:
			p("       seg %2d (%.1f,%.1f)->(%.1f,%.1f)  first substep %5d (tick %4d)  %6d substep contacts (per-tick %4d)  particles %d..%d%s"
				% [s, m.t_a[s].x, m.t_a[s].y, m.t_b[s].x, m.t_b[s].y,
				TAP.tap_first[s], TAP.tap_first[s] / m.SUB, TAP.tap_seg[s],
				tk_seg[s], TAP.tap_lo[s], TAP.tap_hi[s],
				"  [the floor stood on]" if s == int(spots[bs]["seg"]) else ""])
		var arcs := []
		for j in narc:
			if TAP.tap_arc[j] > 0:
				arcs.append("arc %d at (%.2f,%.2f) r %.2f first substep %d (%d contacts)"
					% [j, m.t_arc_c[j].x, m.t_arc_c[j].y, m.t_arc_r[j],
					TAP.tap_arcfirst[j], TAP.tap_arc[j]])
		if narc > 0:
			p("     fillet arcs touched: %s" % (", ".join(arcs) if arcs.size() > 0 else "none"))
		var anc := []
		for j in apos.size():
			if TAP.tap_anc[j] > 0:
				anc.append("%s first substep %d (%d contacts)" % [aname(j),
					TAP.tap_afirst[j], TAP.tap_anc[j]])
		p("     anchors touched: %s" % (", ".join(anc) if anc.size() > 0 else "none"))
		m.free()

func throw_tapped(m: Node2D, k: int, c: Dictionary, policy: String, f: int,
		tk_seg: PackedInt32Array, tk_first: PackedInt32Array,
		tk_lo: PackedInt32Array, tk_hi: PackedInt32Array,
		tk_anc: PackedInt32Array, tk_afirst: PackedInt32Array) -> Dictionary:
	# throw_once with the per-tick control sampled after every step_tick. The
	# per-tick sampler is the tap's own point test, so the only difference is
	# how often it looks.
	var grip := false
	var closes := 0
	var sd := int(c["sd"])
	var pull := bool(c["pull"])
	var caught := false
	var et := -1
	var g0 := -1
	var tt := 0
	for t in W + RUN:
		var ang: float
		var amp := 1.0
		if t < W:
			ang = float(c["a0"])
		elif t < W + sd:
			ang = float(c["a1"])
		elif pull and t < W + 10 + sd:
			ang = float(c["a0"]); amp = 0.7
		else:
			ang = float(c["a1"])
		var a := ang_f(ang, f)
		var tgt: Vector2 = m.body_pos + Vector2(cos(a), sin(a)) * m.REACH * amp
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var cue := false
		if policy == "wrap":
			cue = absf(float(m.a_theta[k])) >= CUE_WRAP
		elif policy == "touch":
			cue = touching(m, k)
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		tick(m, tgt, grip)
		tt += 1
		m._tap_sample(tk_seg, tk_first, tk_lo, tk_hi, tk_anc, tk_afirst, -tt)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	n_throws += 1
	var held := []
	if caught:
		for t in HOLD:
			tick(m, m.body_pos, true)
			tt += 1
			m._tap_sample(tk_seg, tk_first, tk_lo, tk_hi, tk_anc, tk_afirst, -tt)
			if float(m.a_freelen[k]) < 0.0:
				break
		for j in apos.size():
			if bool(m._holds(j)):
				held.append(j)
	return {"caught": caught, "et": et, "g0": g0, "held": held,
		"tether": float(m.a_freelen[k])}

# THE TAP DOES NOT MOVE THE STATE. Static storage is not in
# get_property_list(), so the snapshot layout is main.gd's own, and a tapped
# run hashes identically to an untapped one on three stroke shapes.
func hash_check() -> bool:
	var ok := true
	var base: Node2D = MAIN.new()
	base.external_drive = true
	base.level_id = level
	base.setup_sim()
	var sub := new_sim()
	var kb: PackedStringArray = base.snap_keys()
	var ks: PackedStringArray = sub.snap_keys()
	p("")
	p("TAP HASH CHECK - snapshot keys: main.gd %d, route_tap.gd %d%s" % [
		kb.size(), ks.size(), "  (identical layout)" if kb == ks else "  MISMATCH"])
	if kb != ks:
		ok = false
	for nm in ["tap_on", "tap_seg", "tap_n"]:
		if ks.has(nm):
			p("  static %s leaked into the snapshot" % nm)
			ok = false
	# a main.gd snapshot restores into the subclass
	var snap: Dictionary = base.snapshot()
	if not sub.restore(snap):
		p("  the subclass REFUSED a main.gd snapshot")
		ok = false
	base.free()
	sub.free()
	if spots.is_empty() or apos.is_empty():
		return ok
	# three stroke shapes from the first spot in reach of the first anchor
	var k := 0
	var si := -1
	for i in spots.size():
		if targets_of(spots[i], 1, [k]).size() > 0 and lead_of(k, i) >= 1.5:
			si = i
			break
	if si < 0:
		p("  no spot in reach of anchor 0: hash check skipped")
		return ok
	var shapes := [{"a0": PI * 0.85, "a1": -PI * 0.30, "sd": 9, "pull": false},
		{"a0": PI * 0.85, "a1": -PI * 0.30, "sd": 9, "pull": true},
		{"a0": PI * 1.10, "a1": -PI * 0.42, "sd": 14, "pull": true}]
	for c in shapes:
		var hs := []
		var hold := []
		for tapped in [false, true]:
			var m := new_sim()
			stand(m, spots[si], 1, float(c["a0"]))
			TAP.tap_reset(nseg, apos.size(), narc)
			TAP.tap_on = tapped
			var r := throw_once(m, k, c, policy_of(k), 1)
			TAP.tap_on = false
			hs.append(m.state_hash())
			hold.append(r["held"].has(k))
			m.free()
		var same: bool = int(hs[0]) == int(hs[1])
		p("  %-34s untapped %d  tapped %d  %s  (locked %s/%s, %d substeps tapped)"
			% [cell_str(c), hs[0], hs[1], "SAME" if same else "DIFFERENT",
			str(hold[0]), str(hold[1]), TAP.tap_n])
		if not same:
			ok = false
		# and the survey's windup shortcut: play the windup once, snapshot,
		# throw from the stroke - must hash as the full path did
		var m2 := new_sim()
		var wu := windup(m2, spots[si], 1, float(c["a0"]), [k], "")
		m2.restore(wu["s1"])
		var r2 := throw_once(m2, k, c, policy_of(k), 1, W)
		var h2: int = m2.state_hash()
		var same2: bool = h2 == int(hs[0])
		p("  %-34s full path %d  windup shortcut %d  %s  (locked %s/%s)"
			% ["", hs[0], h2, "SAME" if same2 else "DIFFERENT", str(hold[0]),
			str(r2["held"].has(k))])
		if not same2:
			ok = false
		m2.free()
	return ok

# ----------------------------------------------------- negative controls --
func controls(ks: Array) -> bool:
	var ok := true
	p("")
	p("NEGATIVE CONTROLS")
	# 1. an anchor raised 12 m into the air, thrown at from every spot that was
	#    in reach of where it used to be, with the whole motion grid
	var k0 := int(ks[0])
	var raised: Vector2 = apos[k0] + Vector2(0.0, -12.0)
	var thr0 := n_throws
	var nl := 0
	var ncaught := 0
	var t0 := ms()
	for si in spots.size():
		var sp: Dictionary = spots[si]
		for f in [1, -1]:
			if targets_of(sp, f, [k0]).is_empty():
				continue
			for a0 in a0s:
				var m := new_sim()
				var ap: PackedVector2Array = m.a_pos.duplicate()
				ap[k0] = raised
				m.a_pos = ap
				stand(m, sp, f, a0)
				var snap: Dictionary = m.snapshot()
				for ci in cells.size():
					var c: Dictionary = cells[ci]
					if float(c["a0"]) != float(a0):
						continue
					m.restore(snap)
					var r := throw_once(m, k0, c, policy_of(k0), f)
					if bool(r["caught"]):
						ncaught += 1
					if r["held"].has(k0):
						nl += 1
				m.free()
	p("  anchor %d %s moved 12 m into the air (to %.2f,%.2f): %d throws from the spots that reached it before, %d caught, %d locked  %s  (%.1f s)"
		% [k0, aname(k0), raised.x, raised.y, n_throws - thr0, ncaught, nl,
		"OK" if nl == 0 and ncaught == 0 else "FAIL", float(ms() - t0) / 1000.0])
	if nl != 0 or ncaught != 0:
		ok = false
	# 2. the grip never closes: the same survey, policy "never" - on the first
	#    anchor by default, on every anchor with controls=all
	thr0 = n_throws
	t0 = ms()
	var cks := ks if arg("controls", "1") == "all" else [k0]
	var sv := survey(cks, "never", false)
	if dead:
		return false
	var caught_any := 0
	# throw_once reports caught only for the target; held covers every anchor
	p("  grip never closed (anchor%s): %d throws over %d pairs, %d locks on any anchor  %s  (%.1f s)"
		% ["s " + str(cks) if cks.size() > 1 else " " + aname(k0),
		int(sv["throws"]), int(sv["pairs"]), sv["found"].size(),
		"OK" if sv["found"].size() == 0 else "FAIL", float(ms() - t0) / 1000.0])
	if sv["found"].size() != 0:
		ok = false
	return ok

# ---------------------------------------------------------- lab repro --
# lab_throw.gd's own sweep - 3 leads x 36 cells per (station, cue), the body
# stood by teleport(Vector2(x, -BODY_R)) - run through THIS rig's throw, so the
# week's numbers (3/108 etc.) are reproduced or the difference is explained.
func repro() -> void:
	p("")
	p("LAB REPRO - lab_throw's 108-cell sweep per (station, cue) through this rig's throw_once")
	p("  (lab_throw's 'caught' is a catch still engaged after the hold = 'held' here; 'caught' here is the raw catch)")
	p("  station        cue    att caught  held locked  green   catch tick p10/p50/p90")
	for k in apos.size():
		for policy in ["wrap", "touch"]:
			var att := 0
			var caught := 0
			var held := 0
			var locked := 0
			var green := 0
			var ets := []
			for lead in [1.6, 2.0, 2.4]:
				for a0 in [PI * 0.85, PI * 1.10]:
					for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
						for sd in [5, 9, 14]:
							for pull in [false, true]:
								var m := new_sim()
								m.teleport(Vector2(apos[k].x - lead, -m.BODY_R))
								for t in SETTLE:
									tick(m, m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)
								var r := throw_once(m, k, {"a0": a0, "a1": a1,
									"sd": sd, "pull": pull}, policy, 1)
								att += 1
								if bool(r["caught"]):
									caught += 1
									ets.append(int(r["et"]))
									if float(m.a_freelen[k]) >= 0.0:
										held += 1
										if int(m.a_locked[k]) == 1:
											locked += 1
										if bool(m._holds(k)):
											green += 1
								m.free()
			ets.sort()
			var q := "-"
			if ets.size() > 0:
				q = "%d/%d/%d" % [ets[ets.size() / 10], ets[ets.size() / 2],
					ets[mini(ets.size() * 9 / 10, ets.size() - 1)]]
			p("  %-2d %-11s %-6s %3d %5d %5d %6d %6d   %s" % [k, aname(k), policy,
				att, caught, held, locked, green, q])

# ----------------------------------------------------------------- shards --
# A survey can be split by anchor across processes (anchors=0,1 out=a.json ...)
# and the reports produced from the union (load=a.json,b.json). Spots and
# cells are derived deterministically from the level and the grid, so the
# record indices line up; the header is checked so they cannot line up by
# accident on a different level or grid.
func shard_header() -> Dictionary:
	return {"level": level, "fp": lvl_fp, "grid": arg("grid", "narrow"),
		"spacing": spacing, "merge": merge, "nspots": spots.size(),
		"floors": arg("floors", "ground"),
		"ncells": cells.size(), "md5": FileAccess.get_md5("res://main.gd")}

func save_shard(path: String, ks: Array, sv: Dictionary) -> void:
	var d := shard_header()
	d["anchors"] = ks
	d["found"] = sv["found"]
	d["throws"] = sv["throws"]
	d["ms"] = sv["ms"]
	d["settled"] = sv["settled"]
	d["fallbacks"] = sv["fallbacks"]
	d["lefts"] = sv["lefts"]
	d["pairs"] = sv["pairs"]
	d["attempts"] = attempts
	var clipped := []
	for sp in spots:
		clipped.append(bool(sp["clipped"]))
	d["clipped"] = clipped
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		die("cannot write " + path)
		return
	f.store_string(JSON.stringify(d))
	f.close()
	p("  shard written: %s (%d records)" % [path, sv["found"].size()])

func load_shards(paths: String, ks: Array) -> Dictionary:
	var sv := {"found": [], "throws": 0, "ms": 0, "settled": 0, "fallbacks": 0,
		"lefts": 0, "pairs": 0, "clipped": 0}
	var hdr := shard_header()
	var seen := {}
	for path in paths.split(","):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			die("cannot read " + path)
			return {}
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		f.close()
		for key in hdr:
			var want: Variant = hdr[key]
			var got: Variant = d.get(key)
			if got == null and key == "floors":
				got = "ground"          # shards from before the key existed
			var same := false
			if typeof(want) == TYPE_STRING:
				same = str(want) == str(got)
			else:
				# JSON carries the int64 fingerprint as a double; compare both
				# sides through the same rounding
				same = absf(float(want) - float(got)) <= absf(float(want)) * 1e-12
			if not same and key == "md5":
				# provenance, not identity: the level fingerprint above is the
				# identity of the world, and main.gd is edited concurrently
				p("  note: shard %s was taken on main.gd md5 %s, this run has %s (level fingerprint matches)"
					% [path.get_file(), str(got), str(want)])
			elif not same:
				die("shard %s was taken with %s=%s, this run has %s" % [path, key,
					str(got), str(want)])
				return {}
		for k in d["anchors"]:
			if seen.has(int(k)):
				die("anchor %d appears in two shards" % int(k))
				return {}
			seen[int(k)] = true
		for rec in d["found"]:
			sv["found"].append([int(rec[0]), int(rec[1]), int(rec[2]),
				int(rec[3]), bool(rec[4]), float(rec[5])])
		for key in ["throws", "ms", "settled", "fallbacks", "lefts", "pairs"]:
			sv[key] = int(sv[key]) + int(d[key])
		for k in attempts.size():
			attempts[k] += int(d["attempts"][k])
		for i in spots.size():
			if bool(d["clipped"][i]):
				spots[i]["clipped"] = true
		p("  shard loaded: %s  anchors %s  %d records" % [path, str(d["anchors"]),
			d["found"].size()])
	for k in ks:
		if not seen.has(int(k)):
			die("anchor %d is in no shard" % int(k))
			return {}
	for sp in spots:
		if bool(sp["clipped"]):
			sv["clipped"] += 1
	return sv

# -------------------------------------------------------------------- run --
func _initialize() -> void:
	t_start = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	level = arg("level", "traverse")
	if level == "traverse":
		level = ""
	spacing = float(arg("spacing", "0.25"))
	merge = float(arg("merge", "0.05"))
	var grid := arg("grid", "narrow")
	var before := save_stamp()

	read_level()
	print_level()
	build_grid(grid)
	var ks := []
	if arg("anchors", "all") == "all":
		for k in apos.size():
			ks.append(k)
	else:
		for s in arg("anchors", "").split(","):
			ks.append(int(s))

	var all_ok := true
	if arg("hashcheck", "1") == "1":
		if not hash_check():
			all_ok = false

	if arg("repro", "0") == "1":
		repro()

	p("")
	var sv := {}
	if arg("load", "") != "":
		sv = load_shards(arg("load", ""), ks)
	else:
		p("SURVEY - every (anchor, spot) pair within %.2f m, %d cursor paths per pair" % [ROPE, cells.size()])
		sv = survey(ks)
		if not dead and arg("out", "") != "":
			save_shard(arg("out", ""), ks, sv)
	if dead:
		return
	# A GATE THAT PASSES ON NOTHING IS THE FAILURE THIS PROJECT KEEPS MEETING.
	# No throws means no survey: not a level with nothing reachable, a rig
	# that never asked.
	if int(sv["throws"]) == 0 or int(sv["pairs"]) == 0:
		die("the survey made %d throws over %d pairs - nothing was measured"
			% [int(sv["throws"]), int(sv["pairs"])])
		return
	var rep := report(ks, sv)

	if arg("tap", "1") == "1":
		tap_winners(rep, sv)

	if arg("controls", "1") != "0":
		if not controls(ks):
			all_ok = false

	var after := save_stamp()
	p("")
	p("SAVE GUARD: %s" % ("no user:// save slot changed" if before == after
		else "A SAVE SLOT CHANGED - FAIL"))
	if before != after:
		all_ok = false
	p("COST: %d throws, %d ticks, %.1f s total (%.2f ms per tick, %.0f ms per throw incl. settles)"
		% [n_throws, n_ticks, float(ms()) / 1000.0,
		float(ms()) / float(maxi(n_ticks, 1)),
		float(ms()) / float(maxi(n_throws, 1))])
	if dead:
		return
	p("%s route_variety %s %s" % ["PASS" if all_ok else "FAIL",
		"traverse" if level == "" else level, grid])
	quit(0 if all_ok else 1)
