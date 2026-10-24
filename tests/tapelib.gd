extends RefCounted
## SHARED INPUT POLICIES for the tape corpus (tests/tape_rec.gd) and the
## save/resume gate (tests/save_test.gd).
##
## Every policy here is a pure function of (sim state, tick within its phase),
## which is the property both callers depend on: a restored state must produce
## the same input and therefore the same tick. Nothing in this file reaches into
## the sim except through step_tick - a program is exactly as replayable as a
## player is, and no program can hand-lay a state that no run produces.
##
## The verbs are the measured ones and are not re-derived here:
##  - the lash gait, at the period and angles tests/ground_probe.gd found best
##    and tests/route_bot.gd crawls with
##  - the throw, in the windup / stroke / pull shape of route_bot's plan_throw
##    grid, with route_bot's own trigger-grip policy
##  - the pump and the leap, tests/bot_pump.gd and tests/bot_leap.gd verbatim

const PUMP := preload("res://tests/bot_pump.gd")
const LEAP := preload("res://tests/bot_leap.gd")

const GAIT_PERIOD := 24
const GAIT_BACK := 2.83
const GAIT_FWD := -0.94
const GAIT_TAUT := 0.50

static func new_sim() -> Node2D:
	# not added to the tree: pure sim, no camera / HUD / audio, and _ready never
	# fires, so a probe can never touch a save file
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	return m

## The sim whose world has this fingerprint, or null: the traverse, the lab,
## the crag, then each res://levels/<name>.tscn (not the _scratch ones).
static func sim_for_fingerprint(fp: int) -> Node2D:
	var names: Array[String] = ["", "lab", "crag"]
	var d := DirAccess.open("res://levels")
	if d != null:
		var files := Array(d.get_files())
		files.sort()
		for f: String in files:
			if f.ends_with(".tscn") and not f.begins_with("_"):
				names.append(f.get_basename())
	for n: String in names:
		var m: Node2D = load("res://main.gd").new()
		m.external_drive = true
		m.level_id = n
		m.setup_sim()
		m.save_enabled = false
		if m.level_fingerprint() == fp:
			return m
		m.free()
	return null

# ---------------------------------------------------------- the phase kinds --
# still  hand parked on the body, open        gait  the lash gait, forward
# hold   hand parked on the body, closed      back  the lash gait, backward
# slack  hand held at a fixed angle, open     pump  bot_pump's servo, closed
# stroke a throw: windup, stroke, follow      leap  bot_leap's whole crossing
static func inp(m: Node2D, ph: Dictionary, i: int, st: Dictionary) -> Array:
	var b: Vector2 = m.body_pos
	var kind := String(ph["kind"])
	if kind == "still":
		return [b, false]
	if kind == "hold":
		return [b, true]
	if kind == "gait":
		var fg := float(i % GAIT_PERIOD) / float(GAIT_PERIOD)
		if fg < 0.45:
			return [b + Vector2(cos(GAIT_BACK), sin(GAIT_BACK)) * m.REACH, false]
		return [b + Vector2(cos(GAIT_FWD), sin(GAIT_FWD)) * m.REACH,
			fg > GAIT_TAUT]
	if kind == "back":
		var fb := float(i % GAIT_PERIOD) / float(GAIT_PERIOD)
		if fb < 0.45:
			return [b + Vector2(cos(PI - GAIT_FWD), sin(PI - GAIT_FWD)) * m.REACH,
				false]
		return [b + Vector2(cos(PI - GAIT_BACK), sin(PI - GAIT_BACK)) * m.REACH,
			fb > GAIT_TAUT]
	if kind == "slack":
		var ang := float(ph.get("ang", PI * 1.10))
		return [b + Vector2(cos(ang), sin(ang)) * m.REACH * float(ph.get("amp", 1.0)),
			false]
	if kind == "pump":
		return [PUMP.pump_cursor(m, int(ph["k"]), st.get("pb", b),
			float(ph.get("deg", 95.0))), true]
	if kind == "leap":
		if not st.has("ls"):
			st["ls"] = LEAP.leap_begin(m, int(ph["ka"]), int(ph["kb"]))
		return LEAP.leap_step(m, st["ls"], st.get("pb", b))
	if kind == "stroke":
		return _stroke(m, ph, i, st)
	return [b, false]

static func _stroke(m: Node2D, ph: Dictionary, i: int, st: Dictionary) -> Array:
	var c: Dictionary = ph["c"]
	var k := int(ph["k"])
	var w := int(c["w"])
	var sd := int(c["sd"])
	var ang: float
	var amp := 1.0
	if i < w:
		ang = float(c["a0"])
	elif i < w + sd:
		ang = float(c["a1"])
	elif bool(c["pull"]) and i < w + 10 + sd:
		ang = float(c["a0"])
		amp = 0.7
	else:
		ang = float(c["a1"])
	# GRIP IS A TRIGGER: shut on the wrap reading, re-open if the 15-tick window
	# lapses with nothing caught. route_bot's throw_once policy, unchanged.
	var grip := bool(st.get("grip", false))
	var closes := int(st.get("closes", 0))
	if grip and m.tick_count - m.grip_edge > m.GRIP_WINDOW \
			and float(m.a_freelen[k]) < 0.0:
		grip = false
	if not grip and absf(float(m.a_theta[k])) >= float(ph.get("arm", 2.6)) \
			and closes < 4 and float(m.a_freelen[k]) < 0.0:
		grip = true
		closes += 1
	st["grip"] = grip
	st["closes"] = closes
	return [m.body_pos + Vector2(cos(ang), sin(ang)) * m.REACH * amp, grip]

# ------------------------------------------------------------ the executor --
static func run(m: Node2D, prog: Array) -> int:
	var total := 0
	for ph: Dictionary in prog:
		var st := {}
		var n := int(ph.get("n", 0))
		for i in n:
			var cg := inp(m, ph, i, st)
			st["pb"] = m.body_pos          # "previous body" for the next tick
			m.step_tick(cg[0], cg[1])
			total += 1
			if _done(m, ph, st, i):
				break
	return total

static func _done(m: Node2D, ph: Dictionary, st: Dictionary, i: int) -> bool:
	var u := String(ph.get("until", ""))
	if u == "" or i < int(ph.get("after", 0)):
		return false
	if u == "catch":
		return float(m.a_freelen[int(ph["k"])]) >= 0.0
	if u == "free":
		return float(m.a_freelen[int(ph["k"])]) < 0.0
	if u == "ground":
		return bool(m.grounded)
	if u == "x":
		return m.body_pos.x >= float(ph["x"])
	if u == "xback":
		return m.body_pos.x <= float(ph["x"])
	if u == "leapdone":
		var ls: Dictionary = st.get("ls", {})
		return String(ls.get("phase", "")) == "fail" \
			or float(m.a_freelen[int(ph["kb"])]) >= 0.0
	return false

# --------------------------------------------------------- the throw search --
# route_bot's plan_throw grid, scored for what a given TAPE has to contain: a
# lock for a tape about hanging, a wrap that pays out for a tape about betrayal.
# Searched live from the state the recorder is actually in - freezing a winning
# stroke into a constant is how a probe ends up certifying a state no real run
# produces, which is one of the three lies this whole exercise exists to answer.
static func floor_y(m: Node2D, x: float) -> float:
	var best := 99.0
	for s in m.t_a.size():
		var A: Vector2 = m.t_a[s]
		var B: Vector2 = m.t_b[s]
		if absf(B.x - A.x) < 0.01 or x < minf(A.x, B.x) or x > maxf(A.x, B.x):
			continue
		best = minf(best, A.y + (B.y - A.y) * ((x - A.x) / (B.x - A.x)))
	return best

# route_bot's rule for HOW LONG A CATCH TO WANT, and it is not "the longest":
# the body rides tether + 0.24 m under the pin, so on a beam h metres over its
# floor anything past about h - 1.6 m leaves the feet on the floor and there is
# no pendulum at all. Measured on A1: a 2.66 m catch gave a 0 degree swing and
# could not be left; a 1.04 m catch on the same beam gave 50 degrees.
static func want_tether(m: Node2D, k: int) -> float:
	return clampf(floor_y(m, float(m.a_pos[k].x)) - float(m.a_pos[k].y) - 1.30,
		0.8, 2.9)

static func try_throw(m: Node2D, k: int, c: Dictionary, settle := 90) -> Dictionary:
	run(m, [{"kind": "stroke", "k": k, "c": c, "n": int(c["w"]) + 130,
		"until": "catch"}])
	if float(m.a_freelen[k]) < 0.0:
		return {"caught": false, "locked": -1, "tether": -1.0, "pay": 0,
			"held": false}
	var pay := 0
	var pi0 := int(m.a_pinidx[k])
	var lk := -1
	for t in settle:
		m.step_tick(m.body_pos, true)
		var pn := int(m.a_pinidx[k])
		if pn > pi0:
			pay += pn - pi0
		if pn >= 0:
			pi0 = pn
		if lk == -1:
			lk = int(m.a_locked[k])
		if float(m.a_freelen[k]) < 0.0:
			break
	return {"caught": true, "locked": lk, "tether": float(m.a_freelen[k]),
		"pay": pay, "held": float(m.a_freelen[k]) >= 0.0}

static func find_throw(m: Node2D, k: int, want: String, w := 120) -> Dictionary:
	var was: bool = m.rec_on
	m.rec_on = false                    # candidates are not part of the tape
	var snap: Dictionary = m.snapshot()
	var best := {}
	var bs := -1e9
	var done := false
	for a0 in [PI * 0.85, PI * 1.10]:
		for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
			for sd in [5, 9, 14]:
				for pull in [false, true]:
					if done:
						continue
					m.restore(snap)
					var c := {"a0": a0, "a1": a1, "sd": sd, "pull": pull, "w": w}
					var r := try_throw(m, k, c)
					var s := 0.0
					if want == "lock":
						# nearest the wanted tether, not the longest: a long
						# catch on a low beam hangs with the feet on the floor
						# and there is nothing to dismount from
						s = -absf(float(r["tether"]) - want_tether(m, k))
						if int(r["locked"]) == 1 and bool(r["held"]):
							s += 200.0
						elif bool(r["caught"]):
							s += 10.0
					else:
						if int(r["pay"]) > 0:
							s = 100.0 + float(r["pay"])
						elif bool(r["caught"]):
							s = 10.0
					if s > bs:
						bs = s
						best = c
						best["r"] = r
					# route_bot's own stopping rule: a lock inside 0.30 m of the
					# wanted tether is good enough, and the rest of the grid is
					# only clock
					if want == "lock" and s > 199.70:
						done = true
					elif want != "lock" and int(r["pay"]) >= 3:
						done = true
	m.restore(snap)
	m.rec_on = was
	return best

static func walk_to(m: Node2D, x: float, cap := 6000) -> void:
	if m.body_pos.x < x - 0.15:
		run(m, [{"kind": "gait", "n": cap, "until": "x", "x": x}])
	elif m.body_pos.x > x + 0.15:
		run(m, [{"kind": "back", "n": mini(cap, 1200), "until": "xback", "x": x}])

# THE LEAD LADDER, from route_bot's ground_capture: how far back you stand sets
# the catch length, so a beam is attempted from 2.9 m out and closed on 0.4 m at
# a time. PLANNING IS ENTIRELY OFF-TAPE, and every rung starts from the same
# restored state, so the one that wins can be reproduced exactly by walking that
# far and throwing - which is what do_capture then does, on tape. A tape that
# contained the rejected rungs would replay them and diverge.
static func plan_capture(m: Node2D, k: int, want: String,
		tries := 6) -> Dictionary:
	var was: bool = m.rec_on
	m.rec_on = false
	var snap: Dictionary = m.snapshot()
	var bx: float = float(m.a_pos[k].x)
	var lead: float = minf(bx - m.body_pos.x, 2.9)
	var best := {}
	var bs := -1e9
	for att in tries:
		if lead < 1.2:
			break                          # too close to stroke at it at all
		m.restore(snap)
		walk_to(m, bx - lead)
		var c := find_throw(m, k, want)
		var r: Dictionary = c.get("r", {})
		var s := 0.0
		if want == "lock":
			s = -absf(float(r.get("tether", 9.0)) - want_tether(m, k))
			if int(r.get("locked", -1)) == 1 and bool(r.get("held", false)):
				s += 200.0
		else:
			s = float(r.get("pay", 0))
		if s > bs:
			bs = s
			best = {"lead": lead, "c": c, "r": r, "score": s}
		if (want == "lock" and bs > 199.85) or (want != "lock" and bs >= 3.0):
			break                          # good enough; stop burning clock
		lead -= 0.4
	m.restore(snap)
	m.rec_on = was
	return best

static func do_capture(m: Node2D, k: int, plan: Dictionary) -> bool:
	if plan.is_empty():
		return false
	var c: Dictionary = plan["c"]
	walk_to(m, float(m.a_pos[k].x) - float(plan["lead"]))
	run(m, [{"kind": "stroke", "k": k, "c": c, "n": int(c["w"]) + 130,
		"until": "catch"}])
	return float(m.a_freelen[k]) >= 0.0

# -------------------------------------------------------------- the replay --
# THE WHOLE POINT. Restore the state the tape started from, feed its recorded
# inputs back through step_tick, and ask whether the same ticks come out. This
# needs no oracle: it does not know what the game ought to do, only what it did.
#
# The checkpoint hashes are compared AS THEY ARE PRODUCED, so a divergence is
# reported at the half-second it began rather than at the end of the tape.
const MAIN := preload("res://main.gd")

static func verify(path: String) -> Dictionary:
	var t: Dictionary = MAIN.tape_load(path)
	var out := {"ok": false, "why": "", "at": -1, "n": int(t.get("n", 0)),
		"note": str(t.get("note", "")), "cen": t.get("cen", {}), "cen2": {},
		"h": int(t.get("h", 0)), "h2": 0}
	if not bool(t.get("ok", false)):
		out["why"] = str(t.get("err", "unreadable"))
		return out
	var m := new_sim()
	if int(t["lvl"]) != m.level_fingerprint():
		# A tape names its level only by fingerprint, so look for the level
		# it was recorded on: the lab, the crag, then every scene in levels/.
		# (levels/demo.tape is the demo's recorded run, replayed on the demo.)
		m.free()
		m = sim_for_fingerprint(int(t["lvl"]))
	if m == null:
		# NOT a divergence: the tape's cursor no longer refers to anything, so
		# it cannot be asked whether the sim still behaves. Its own message.
		out["why"] = "recorded on a different level"
		return out
	if not m.restore(t["start"]):
		out["why"] = "start state refused - the sim's state layout changed " \
			+ "(a var added, renamed or deleted). Re-record."
		m.free()
		return out
	m.rec_begin(str(t["note"]))
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var chk: PackedInt64Array = t["chk"]
	var opts: PackedByteArray = t.get("opt", PackedByteArray())
	var j := 0
	for i in cur.size():
		m.pending_reset = (grp[i] & 2) != 0
		m.align_w = m.ALIGN_W_FLIP if (grp[i] & 4) != 0 else m.ALIGN_W
		m.crack_speed = m.CRACK_SPEED_HI if (grp[i] & 32) != 0 else m.CRACK_SPEED
		m.stick_on = (grp[i] & 64) != 0
		m.hammer_on = (grp[i] & 128) != 0
		m.firm_set(i < opts.size() and (opts[i] & 1) != 0)
		m.stretch_set(i < opts.size() and (opts[i] & 2) != 0)
		m.pending_jump = i < opts.size() and (opts[i] & 4) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)
		if (i + 1) % int(m.TAPE_CHECK) == 0:
			if j < chk.size() and int(m.rec_chk[j]) != int(chk[j]):
				out["at"] = i + 1
				out["why"] = "state diverged by tick %d" % (i + 1)
				m.rec_end()
				m.free()
				return out
			j += 1
	out["h2"] = m.state_hash()
	out["cen2"] = m.rec_cen.duplicate()
	m.rec_end()
	m.free()
	if int(out["h2"]) != int(out["h"]):
		out["why"] = "final hash differs (no checkpoint caught it - the tape " \
			+ "is shorter than one checkpoint interval)"
		out["at"] = int(out["n"])
		return out
	var cd := cen_diff(out["cen"], out["cen2"])
	if cd != "":
		out["why"] = "same hashes but a different run: " + cd
		return out
	out["ok"] = true
	return out

static func cen_diff(a: Dictionary, b: Dictionary) -> String:
	var bad: Array[String] = []
	for k in a:
		if not b.has(k):
			bad.append("%s missing" % k)
		elif typeof(a[k]) != typeof(b[k]) or a[k] != b[k]:
			bad.append("%s %s != %s" % [k, str(a[k]), str(b[k])])
	for k in b:
		if not a.has(k):
			bad.append("%s unexpected" % k)
	return ", ".join(bad)

static func short_cen(c: Dictionary) -> String:
	# "net" is the out-of-world safety net firing, which is a bug-catcher and
	# not the game's idea of a fall; the fall you can see is "air" ticks and
	# "drop" metres. Labelling the net "fall" would read as a claim this corpus
	# does not make.
	return "catch %d lock %d pay %d slide %d dismount %d net %d air %d drop %.1f crawl %.1f" % [
		int(c.get("catch", 0)), int(c.get("lock", 0)), int(c.get("pay", 0)),
		int(c.get("slide", 0)), int(c.get("dismount", 0)),
		int(c.get("fall", 0)), int(c.get("airrun", 0)),
		float(c.get("maxdrop", 0.0)), float(c.get("crawl", 0.0))]

# ------------------------------------------------------------- reporting --
static func census_line(c: Dictionary) -> String:
	return ("catch %d  lock %d  pay %d  slide %d  dismount %d  unwind %d  "
		+ "net %d  crack %d  wrapped %d  air %d/%d  drop %.2f  crawl %.2f  "
		+ "tip %.0f  x %.2f->%.2f") % [
		int(c.get("catch", 0)), int(c.get("lock", 0)), int(c.get("pay", 0)),
		int(c.get("slide", 0)), int(c.get("dismount", 0)),
		int(c.get("unwind", 0)), int(c.get("fall", 0)), int(c.get("crack", 0)),
		int(c.get("wrapped", 0)), int(c.get("airrun", 0)), int(c.get("air", 0)),
		float(c.get("maxdrop", 0.0)), float(c.get("crawl", 0.0)),
		float(c.get("maxtip", 0.0)), float(c.get("x0", 0.0)),
		float(c.get("x1", 0.0))]

# The hashrun session, verbatim from tests/hashrun.gd, as a policy. Its final
# state hash is this project's golden number (2762505307938286422) and pinning a
# tape to it ties the whole tape system to a constant that predates it.
static func hashrun_inp(m: Node2D, t: int) -> Array:
	var b: Vector2 = m.body_pos
	var tgt: Vector2
	var grip := false
	if t < 90:
		tgt = b + Vector2(0.5, -0.5)
	elif t < 280:
		var ph := float(t - 90) * 0.11
		tgt = b + Vector2(cos(ph), sin(ph)) * 1.1
	elif t < 340:
		tgt = b + Vector2(-1.05, -0.35)
	elif t < 352:
		tgt = b + Vector2(1.05, -0.45)
	elif t < 600:
		tgt = b + Vector2(0.8, -0.8)
		grip = t > 420
	else:
		var p2 := float(t) * 0.05
		tgt = b + Vector2(cos(p2), -0.6)
		grip = true
	return [tgt, grip]
