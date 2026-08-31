extends SceneTree
## LUCK TEST. "If the same throw sometimes takes and sometimes does not, that
## is luck and it is fatal." The sim is deterministic, so the same INPUT always
## gives the same result - the question is whether the same INTENTION does. The
## only part of a throw a human cannot hold still is WHEN the hand closes.
##
## So: find a stroke that goes green, note the tick its hand closed on, then
## re-throw the identical stroke pressing 1..6 ticks early and 1..6 ticks late.
## A press moved by one tick is 17 ms. Measured human keypress timing scatters
## by tens of ms, so an anchor that survives +/-1 tick and no more is an anchor
## nobody can hit on purpose.
##
##   godot --headless --path . -s res://tests/crit_jitter.gd
const MAIN := preload("res://main.gd")

func new_lab() -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = "lab"
	m.setup_sim()
	m.save_enabled = false
	return m

func stand_at(m: Node2D, x: float, a0: float) -> void:
	m.teleport(Vector2(x, -m.BODY_R))
	for t in 90:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)

func touching(m: Node2D, k: int) -> bool:
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]

func aim(t: int, sd: int, pull: bool, a0: float, a1: float) -> Array:
	if t < 120:
		return [a0, 1.0]
	if t < 120 + sd:
		return [a1, 1.0]
	if pull and t < 130 + sd:
		return [a0, 0.7]
	return [a1, 1.0]

# cue-driven: returns green + the tick the hand first closed
func cued(k: int, lead: float, a0: float, a1: float, sd: int, pull: bool,
		policy: String) -> Dictionary:
	var m := new_lab()
	stand_at(m, float(m.a_pos[k].x) - lead, a0)
	var grip := false
	var closes := 0
	var g0 := -1
	var caught := false
	for t in 250:
		var av := aim(t, sd, pull, a0, a1)
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(float(av[0])), sin(float(av[0]))) * m.REACH * float(av[1])
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var cue := absf(float(m.a_theta[k])) >= 2.6 if policy == "wrap" \
			else touching(m, k)
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
			if g0 < 0:
				g0 = t
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			break
	var g := false
	if caught:
		for t in 55:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		g = bool(m._holds(k))
	m.free()
	return {"green": g, "g0": g0}

# the same stroke, hand closed at a FIXED tick and held - what a player does
func at_tick(k: int, lead: float, a0: float, a1: float, sd: int, pull: bool,
		press: int) -> bool:
	var m := new_lab()
	stand_at(m, float(m.a_pos[k].x) - lead, a0)
	var caught := false
	for t in 250:
		var av := aim(t, sd, pull, a0, a1)
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(float(av[0])), sin(float(av[0]))) * m.REACH * float(av[1])
		m.step_tick(tgt, t >= press)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			break
	var g := false
	if caught:
		for t in 55:
			m.step_tick(m.body_pos, true)
			if float(m.a_freelen[k]) < 0.0:
				break
		g = bool(m._holds(k))
	m.free()
	return g

func _initialize() -> void:
	print("")
	print("PRESS JITTER. One winning stroke per station, then the identical")
	print("stroke with the hand closed N ticks early or late (1 tick = 17 ms).")
	print("'#' = still hangs green, '.' = does not.")
	print("")
	var m0 := new_lab()
	var names: Array[String] = []
	for k in m0.a_pos.size():
		names.append(String(m0.a_name[k]))
	m0.free()
	print(" Up to 6 distinct winning strokes per station. Each row is one stroke.")
	print("")
	print(" station                        -6 -5 -4 -3 -2 -1  0 +1 +2 +3 +4 +5 +6  hits widest holes")
	for row: Array in [[0, "wrap"], [1, "wrap"], [2, "touch"], [3, "touch"]]:
		var k: int = row[0]
		var policy: String = row[1]
		var ws: Array = []
		for lead in [1.6, 2.0, 2.4]:
			for ang: Array in GRID:
				for sd in [9, 14, 5]:
					for pull in [false, true]:
						if ws.size() < 6:
							var r := cued(k, lead, ang[0], ang[1], sd, pull,
								policy)
							if bool(r["green"]) and int(r["g0"]) >= 0:
								ws.append({"lead": lead, "a0": ang[0],
									"a1": ang[1], "sd": sd, "pull": pull,
									"g0": int(r["g0"])})
		if ws.is_empty():
			print(" %-2d %-11s  no green stroke in the 108-cell search"
				% [k, names[k]])
			continue
		var thits := 0
		var tholes := 0
		for w: Dictionary in ws:
			var g0: int = int(w["g0"])
			var marks := ""
			var hits: Array[bool] = []
			for off in range(-6, 7):
				var h := at_tick(k, float(w["lead"]), float(w["a0"]),
					float(w["a1"]), int(w["sd"]), bool(w["pull"]), g0 + off)
				hits.append(h)
				marks += " # " if h else " . "
			var best := 0
			var run := 0
			var n := 0
			var holes := 0
			var seen := false
			var gap := false
			for h in hits:
				if h:
					n += 1
					run += 1
					best = maxi(best, run)
					if seen and gap:
						holes += 1
						gap = false
					seen = true
				else:
					run = 0
					if seen:
						gap = true
			thits += n
			tholes += holes
			print(" %-2d %-11s cue@%3d %s %4d %6d %5d"
				% [k, names[k], g0, marks, n, best, holes])
		print("    %-14s %d strokes: %d/%d offsets held, %d interior holes"
			% ["", ws.size(), thits, ws.size() * 13, tholes])
	quit(0)
