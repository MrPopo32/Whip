extends SceneTree
## AIM, TIMING, OR LUCK?
##
## The sim has no RNG: the same inputs give the same outcome, always. So
## "luck" can only mean one thing here - a basin of success finer than a
## player can aim. This finds a stroke that really does go green, then walks
## ONE input at a time away from it in steps far smaller than a hand or a pair
## of feet can resolve, and reports where the verdict flips.
##
##   lead   swept +/- 150 mm in 2.5 mm steps. A player picks their lead by
##          WALKING; nobody stands to the nearest 2.5 mm.
##   a1     the stroke angle, swept +/- 0.06 rad in 0.002 rad steps. At the
##          1.15 m reach that is +/- 69 mm of cursor travel in 2.3 mm steps.
##
## The reading is the BLOCK STRUCTURE, not the hit count: one wide block means
## the throw has a target you can learn to hit. Many one-cell blocks mean the
## outcome is decided below the resolution of the player's hand, which is what
## luck looks like in a deterministic game.
##
##   godot --headless --path . -s res://tests/crit_basin.gd
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

func one(k: int, lead: float, a0: float, a1: float, sd: int, pull: bool,
		policy: String) -> bool:
	var m := new_lab()
	stand_at(m, float(m.a_pos[k].x) - lead, a0)
	var grip := false
	var closes := 0
	var caught := false
	for t in 250:
		var ang: float
		var amp := 1.0
		if t < 120:
			ang = a0
		elif t < 120 + sd:
			ang = a1
		elif pull and t < 130 + sd:
			ang = a0; amp = 0.7
		else:
			ang = a1
		var tgt: Vector2 = m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		var cue := absf(float(m.a_theta[k])) >= 2.6 if policy == "wrap" \
			else touching(m, k)
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
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
	return g

func report(tag: String, hits: Array[bool], step_mm: float) -> void:
	var blocks: Array[int] = []
	var run := 0
	for h in hits:
		if h:
			run += 1
		elif run > 0:
			blocks.append(run)
			run = 0
	if run > 0:
		blocks.append(run)
	var g := 0
	for h in hits:
		if h:
			g += 1
	var widest := 0
	var ones := 0
	for b in blocks:
		widest = maxi(widest, b)
		if b == 1:
			ones += 1
	var map := ""
	for h in hits:
		map += "#" if h else "."
	print(" %-30s %3d/%-3d  blocks %2d (1-cell %2d)  widest %5.1f mm"
		% [tag, g, hits.size(), blocks.size(), ones, float(widest) * step_mm])
	print("     %s" % map)

func _initialize() -> void:
	print("")
	print("BASIN AROUND A REAL WINNER. Every row starts from a stroke found by")
	print("the same 108-cell search tests/lab_throw.gd uses, then walks one")
	print("input away from it. '#' = the body still hangs green after 55 ticks.")
	print("Lead cells are 2.5 mm apart; angle cells are 0.002 rad = 2.3 mm of")
	print("cursor travel at the 1.15 m reach.")
	var m0 := new_lab()
	var names: Array[String] = []
	var jams: Array[int] = []
	for k in m0.a_pos.size():
		names.append(String(m0.a_name[k]))
		jams.append(int(m0.a_jam[k]))
	m0.free()
	for row: Array in [[0, "wrap"], [1, "wrap"], [2, "touch"], [3, "touch"]]:
		var k: int = row[0]
		var policy: String = row[1]
		var w := {}
		for lead in [1.6, 2.0, 2.4]:
			for ang: Array in GRID:
				for sd in [9, 14, 5]:
					for pull in [false, true]:
						if w.is_empty() and one(k, lead, ang[0], ang[1], sd,
								pull, policy):
							w = {"lead": lead, "a0": ang[0], "a1": ang[1],
								"sd": sd, "pull": pull}
		print("")
		if w.is_empty():
			print(" %-2d %-11s %s: the 108-cell search found no green stroke"
				% [k, names[k], policy])
			continue
		print(" %-2d %-11s jam %d  cue %s  winner: lead %.2f a0 %.2f a1 %.2f sd %d pull %s"
			% [k, names[k], jams[k], policy, float(w["lead"]), float(w["a0"]),
			float(w["a1"]), int(w["sd"]), str(bool(w["pull"]))])
		var hl: Array[bool] = []
		for i in range(-60, 61):
			hl.append(one(k, float(w["lead"]) + float(i) * 0.0025, w["a0"],
				w["a1"], w["sd"], w["pull"], policy))
		report("lead -150..+150 mm", hl, 2.5)
		var ha: Array[bool] = []
		for i in range(-30, 31):
			ha.append(one(k, float(w["lead"]), w["a0"],
				float(w["a1"]) + float(i) * 0.002, w["sd"], w["pull"], policy))
		report("stroke angle -0.06..+0.06 rad", ha, 2.3)
	quit(0)
