extends SceneTree
## CAN THE LAB'S ANCHORS ACTUALLY BE CAUGHT, AND DO THEY THEN HOLD?
##
## Everything here is thrown, never hand-laid. Every rig starts with the body
## standing on the lab's own floor with the whip wherever gravity left it, and
## the only inputs are (cursor, grip) through step_tick - the same surface a
## tape records. Hand-laying a chain into a wrap is how three probes in this
## project's history certified things that never happen in play.
##
##   godot --headless --path . -s res://tests/lab_throw.gd -- [aim|hold|all]
const MAIN := preload("res://main.gd")

var out: Array[String] = []

func p(s: String) -> void:
	out.append(s)
	print(s)

# ------------------------------------------------------------- the bench ----
func new_lab() -> Node2D:
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.level_id = "lab"
	m.setup_sim()
	m.save_enabled = false
	return m

func stand_at(m: Node2D, x: float, a0: float) -> void:
	# STAND, AND WIND UP. The hand is held BACK at the stroke's own windup
	# angle while the whip settles, which lays the chain out behind the body -
	# and that is not cosmetic. Measured on the shipped school beam A0, which
	# school.tape proves is catchable from a standstill, 24 strokes per cell:
	#
	#     posture                       lead 1.6   lead 2.0   lead 2.4
	#     settle with the hand at the
	#       body (a heap underneath)     0 / 0      0 / 0      2 / 0
	#     settle with the hand BACK      7 / 2      7 / 0      6 / 0
	#     crawl the last 1.2 m in        2 / 2      0 / 0      3 / 0
	#                                    (caught / locked)
	#
	# A chain piled under the body cannot throw a turn, and a rig that starts
	# there measures the pile, not the beam. The first version of this file did
	# exactly that and reported 3/108 on a beam the game catches routinely.
	m.teleport(Vector2(x, -m.BODY_R))
	for t in 90:
		m.step_tick(m.body_pos + Vector2(cos(a0), sin(a0)) * m.REACH, false)

func touching(m: Node2D, k: int) -> bool:
	# the same contact band _pinch uses for a jam - what the player sees when
	# the rope arrives on the anchor
	for i in m.NP:
		if (m.pos[i] - m.a_pos[k]).length() \
				< m.a_r[k] + m.p_rad[i] + m.wrap_shell + 0.02:
			return true
	return false

# ------------------------------------------------------------- one throw ----
# route_bot's stroke shape and its RE-ARMING grip trigger. The first version of
# this file used a 30-tick windup and measured a 3% catch rate on a beam the
# shipped game catches routinely; route_bot's own comment says a 120-tick
# windup catches two to three times as often, and it does.
func throw_once(m: Node2D, k: int, c: Dictionary, policy: String) -> Dictionary:
	var grip := false
	var closes := 0
	var sd: int = int(c["sd"])
	var pull: bool = bool(c["pull"])
	var w: int = int(c["w"])
	var caught := false
	var et := -1
	for t in w + 130:
		var ang: float
		var amp := 1.0
		if t < w:
			ang = float(c["a0"])
		elif t < w + sd:
			ang = float(c["a1"])
		elif pull and t < w + 10 + sd:
			ang = float(c["a0"]); amp = 0.7
		else:
			ang = float(c["a1"])
		var tgt: Vector2 = m.body_pos \
			+ Vector2(cos(ang), sin(ang)) * m.REACH * amp
		if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
				and float(m.a_freelen[k]) < 0.0:
			grip = false
		# THE CUE THE PLAYER IS ACTING ON. "wrap" is route_bot's: shut the hand
		# when the arc reads as a catch. "touch" is the one a jam offers: shut
		# it when the rope arrives on the anchor. Both are present-state
		# readings off the screen; neither can see the future or _pinch.
		var cue := absf(float(m.a_theta[k])) >= 2.6 if policy == "wrap" \
			else touching(m, k)
		if not grip and cue and closes < 4 and float(m.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		m.step_tick(tgt, grip)
		if float(m.a_freelen[k]) >= 0.0:
			caught = true
			et = t
			break
	if not caught:
		return {"ok": false, "locked": -1, "green": false, "tether": -1.0,
			"et": -1}
	for t in 55:
		m.step_tick(m.body_pos, true)
		if float(m.a_freelen[k]) < 0.0:
			break
	return {"ok": float(m.a_freelen[k]) >= 0.0, "locked": int(m.a_locked[k]),
		"green": bool(m._holds(k)), "tether": float(m.a_freelen[k]), "et": et}

const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18],
]

func sweep(k: int, policy: String, jam_override: int) -> Dictionary:
	# 108 attempts: 3 leads x 6 stroke angles x 3 stroke durations x pull.
	var att := 0
	var caught := 0
	var locked := 0
	var green := 0
	var best := {}
	# leads from tests/lab_diag2.gd: 1.6-2.4 is where the shipped school beam
	# catches at all under this rig (0/48 at 1.2, 3/48 at 2.8-3.2)
	for lead in [1.6, 2.0, 2.4]:
		for ang: Array in GRID:
			for sd in [5, 9, 14]:
				for pull in [false, true]:
					var m := new_lab()
					if jam_override >= 0:
						var j: PackedInt32Array = m.a_jam
						j[k] = jam_override
						m.a_jam = j
					stand_at(m, float(m.a_pos[k].x) - lead, float(ang[0]))
					var r := throw_once(m, k, {"a0": ang[0], "a1": ang[1],
						"sd": sd, "pull": pull, "w": 120}, policy)
					att += 1
					if bool(r["ok"]):
						caught += 1
						if int(r["locked"]) == 1:
							locked += 1
						if bool(r["green"]):
							green += 1
							if best.is_empty():
								best = {"lead": lead, "a0": ang[0],
									"a1": ang[1], "sd": sd, "pull": pull,
									"w": 120, "tether": float(r["tether"])}
					m.free()
	return {"att": att, "caught": caught, "locked": locked, "green": green,
		"best": best}

# --------------------------------------------------- does it bear a body? ---
func strip_floor(m: Node2D) -> void:
	# THE FLOOR IS REMOVED BY REBUILDING THE ARRAYS AND ASSIGNING THEM BACK.
	# m.t_a.remove_at(i) through a property mutates a COPY - the probe that
	# learned this the hard way spent a whole sweep measuring the FLOOR's 91 N
	# and calling it a jam. The walls go too: with the floor gone they are the
	# only thing left to catch on.
	m.t_a = PackedVector2Array()
	m.t_b = PackedVector2Array()
	m.t_n = PackedVector2Array()
	m.t_lo = PackedVector2Array()
	m.t_hi = PackedVector2Array()
	m.world_bottom = 1.0e9

func hold_test(k: int, c: Dictionary, policy: String) -> Dictionary:
	# Throw it for real, catch it, THEN take the floor away and see what the
	# anchor is actually carrying - on a 2.2 m beam the body drags its feet, so
	# a hang measured with the floor in is a hang measured on the floor.
	var m := new_lab()
	stand_at(m, float(m.a_pos[k].x) - float(c["lead"]), float(c["a0"]))
	var r := throw_once(m, k, c, policy)
	if not bool(r["ok"]):
		m.free()
		return {"ok": false}
	strip_floor(m)
	var snap: Dictionary = m.snapshot()
	# A. hand SHUT for 3 s
	var y0: float = m.body_pos.y
	var tmin := 1.0e9
	var tmax := 0.0
	var held := 0
	var greenticks := 0
	for t in 180:
		m.step_tick(m.body_pos, true)
		if float(m.a_freelen[k]) >= 0.0:
			held += 1
			var tn: float = m._wrap_tension()
			tmin = minf(tmin, tn)
			tmax = maxf(tmax, tn)
		if bool(m._holds(k)):
			greenticks += 1
	var d_shut: float = m.body_pos.y - y0
	# B. same state, hand OPEN
	m.restore(snap)
	var y1: float = m.body_pos.y
	var rel := -1
	for t in 180:
		m.step_tick(m.body_pos, false)
		if rel < 0 and float(m.a_freelen[k]) < 0.0:
			rel = t
	var d_open: float = m.body_pos.y - y1
	m.free()
	return {"ok": true, "shut": d_shut, "open": d_open, "held": held,
		"green": greenticks, "rel": rel,
		"tmin": tmin if tmin < 1e8 else 0.0, "tmax": tmax}

# -------------------------------------------------------------------- run ---
# ONE PASS. Each (station, cue) cell is swept ONCE and the first stroke that
# went green out of that same sweep is the one carried into the hold test, so
# the hold is measured on a throw this table can point at rather than on a
# second, luckier one.
func _initialize() -> void:
	var m0 := new_lab()
	var names: Array[String] = []
	var jams: Array[int] = []
	for k in m0.a_pos.size():
		names.append(String(m0.a_name[k]))
		jams.append(int(m0.a_jam[k]))
	m0.free()

	p("")
	p("AIM AND HOLD - 108 searched strokes per cell (3 leads x 6 stroke angles")
	p("x 3 stroke lengths x pull), thrown from the lab's own floor with nothing")
	p("hand-laid. Then the floor is REMOVED under the winning stroke and the")
	p("body hangs for 3 s: shut = hand closed, open = the identical state with")
	p("the hand open. That second column is sim_test's G7 asked per anchor.")
	p("")
	p("  station        cue    att caught locked  green | shut_dy  open_dy held green rel  T(N)")
	for k in names.size():
		for policy in ["wrap", "touch"]:
			var r := sweep(k, policy, -1)
			var line := "  %-2d %-11s %-6s %3d %5d %6d %6d |" % [k, names[k],
				policy, int(r["att"]), int(r["caught"]), int(r["locked"]),
				int(r["green"])]
			var b: Dictionary = r["best"]
			if b.is_empty():
				p(line + "  no green stroke to hold-test")
				continue
			var h := hold_test(k, b, policy)
			if not bool(h["ok"]):
				p(line + "  the winning stroke did not repeat")
				continue
			p(line + " %7.3f %8.3f %5d %5d %4d  %.0f-%.0f" % [float(h["shut"]),
				float(h["open"]), int(h["held"]), int(h["green"]),
				int(h["rel"]), float(h["tmin"]), float(h["tmax"])])

	p("")
	p("CONTROL - the two jam stations with the jam flag FORCED OFF: the same")
	p("r=0.14 anchor at the same place, as an ordinary beam. Nothing else about")
	p("the rig changes, so whatever the two tables differ by is the flag.")
	p("  station        cue    att caught locked  green")
	for k in names.size():
		if jams[k] != 1:
			continue
		for policy in ["wrap", "touch"]:
			var r := sweep(k, policy, 0)
			p("  %-2d %-11s %-6s %3d %5d %6d %6d  (jam OFF)" % [k, names[k],
				policy, int(r["att"]), int(r["caught"]), int(r["locked"]),
				int(r["green"])])
	quit(0)
