extends SceneTree
## WHAT THE PLAYER WAS LOOKING AT. Replays a recorded tape and, around every
## tick the player marked with F, dumps the full lock state of every anchor -
## and, on the ticks where no catch fired, WHICH CLAUSE of the catch condition
## refused it.
##
##   godot --headless --path . -s res://tests/mark_look.gd -- tapes/mine.tape
##   ...                                                  -- FILE w=45 mark=2
##   ...                                                  -- FILE k=3 all
##   ...                                                  -- FILE at=389,742
##   ...                                                  -- --selftest
##   ...                                                  -- --selftest lie=all
##
##   FILE      the tape to inspect (bare paths mean the project, not the shell)
##   w=N       half-window in ticks around each mark (default 90)
##   mark=N    only the Nth mark, 1-based (default: all of them)
##   k=N       only anchor N (default: every anchor that is IN PLAY in the
##             window - engaged at some point, or with |theta| over 0.3)
##   all       every anchor, in play or not
##   at=A,B    inspect these tape ticks as if they had been marked. This is
##             how the tool is exercised on the six committed tapes, which
##             were recorded before the marker existed and carry no marks.
##   rings     print only the ring strip, no per-anchor tables
##
## ---------------------------------------------------------------------------
## HOW THIS INSTRUMENT KNOWS IT IS NOT LYING
##
## Every number below is read AFTER step_tick has returned, which is a claim
## about timing and therefore a place to be wrong. The claim is this: for an
## anchor that was not engaged at the top of the tick, the six values the catch
## condition tests -
##
##     taut,  tick_count - grip_edge,  a_armed[k],  a_lockidx[k],
##     |a_theta[k]|,  _pinch(k)
##
## - all still hold, at the end of the tick, the value _update_locks tested.
## a_theta and a_lockidx are written by _measure_wraps immediately before and
## are not touched again; _pinch is a pure function of pos[], which
## _update_locks never writes; taut and grip_edge are set at the top of
## step_tick; and a_armed is written, in that same iteration, BEFORE the test,
## by the re-arm branch - and by nothing else on a disengaged anchor. The catch
## branch itself does not write a_armed or a_lockidx either, so the
## reconstruction is valid on the catch tick as well.
##
## That is an argument, and arguments are what this project keeps catching its
## probes lying with. So --selftest turns it into a falsifiable prediction and
## checks it against the sim:
##
##     for every (tick, anchor) where the anchor was disengaged at the end of
##     the previous tick, the reconstructed condition must be TRUE exactly
##     when a catch actually fired on that tick, and FALSE exactly when one
##     did not.
##
## The reconstruction has no way to see whether a catch fired; the sim has no
## way to see the reconstruction. If the reading is off by a tick, or names the
## wrong variable, or reads a threshold the sim does not use, the two disagree
## and --selftest says where. It runs over the six committed tapes AND over a
## generated throw corpus that puts strokes at all eleven beams - both fat
## school beams and the 0.10 m fast line - so the arithmetic is exercised on
## every radius in the level, not just the three the corpus happens to visit.
##
## And because a gate that cannot fail is worth nothing, `lie=NAME` injects a
## deliberate defect into the reconstruction and requires --selftest to catch
## it. `lie=all` runs every one of them. See LIES below for what each is.
const MAIN := preload("res://main.gd")
const TL := preload("res://tests/tapelib.gd")

# The named defects. Each is a plausible way to misread the catch condition,
# and --selftest must notice every one of them.
const LIES := {
	"thpart": "use th_rel (1.8) where the sim uses th_part (3.4)",
	"armed": "forget the a_armed clause entirely",
	"nopinch": "forget that _pinch() also qualifies a wrap",
	"pinidx": "forget the a_lockidx >= pin_min_idx clause",
	"window": "use < GRIP_WINDOW where the sim uses <=",
	"lag": "read taut and grip_edge one tick late",
}

var fails := 0
# THE KIND OF EACH MARK, parallel to the tape's mark list. A mark that does
# not say WHICH complaint it was is a tick with a question mark over it: the
# two symptoms are questions about different code, and the whole point of
# two keys is that the tape answers that on its own.
var kinds: PackedInt32Array = PackedInt32Array()
const KIND_NAME := ["unlabelled", "GREEN DROPPED ME", "SHOULD HAVE HOOKED"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var w := 90
	var only_mark := 0
	var only_k := -1
	var show_all := false
	var rings_only := false
	var selftest := false
	var lie := ""
	var at: Array[int] = []
	for a: String in args:
		if a == "--selftest":
			selftest = true
		elif a == "all":
			show_all = true
		elif a == "rings":
			rings_only = true
		elif a.begins_with("w="):
			w = int(a.substr(2))
		elif a.begins_with("mark="):
			only_mark = int(a.substr(5))
		elif a.begins_with("k="):
			only_k = int(a.substr(2))
		elif a.begins_with("lie="):
			lie = a.substr(4)
		elif a.begins_with("at="):
			for s in a.substr(3).split(",", false):
				at.append(int(s))
		elif not a.begins_with("-"):
			path = a
	if selftest:
		quit(_selftest(lie))
		return
	if path == "":
		print("usage: -s res://tests/mark_look.gd -- TAPE [w=90] [mark=N] "
			+ "[k=N] [all] [at=T,T] [rings]")
		print("       -s res://tests/mark_look.gd -- --selftest [lie=all]")
		quit(2)
		return
	quit(_look(_res(path), w, only_mark, only_k, show_all, rings_only, at))

static func _res(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://") \
			or p.is_absolute_path():
		return p
	return "res://" + p

# ============================================================== the dump mode
func _look(path: String, w: int, only_mark: int, only_k: int, show_all: bool,
		rings_only: bool, at: Array[int]) -> int:
	var t: Dictionary = MAIN.tape_load(path)
	if not bool(t.get("ok", false)):
		print("FAIL  %s: %s" % [path, str(t.get("err", "unreadable"))])
		return 1
	var m := TL.new_sim()
	if int(t["lvl"]) != m.level_fingerprint():
		print("FAIL  %s was recorded on a different level - its cursor no "
			% path + "longer points at anything. Re-record.")
		m.free()
		return 1
	if not m.restore(t["start"]):
		print("FAIL  %s: the start state was refused (the sim's state layout "
			% path + "changed). Re-record.")
		m.free()
		return 1
	var n := int(t["n"])
	var marks: PackedInt32Array = t.get("mark", PackedInt32Array())
	kinds = t.get("mkind", PackedInt32Array())
	var pts: Array[int] = []
	for v in marks:
		pts.append(int(v))
	var from_marks := pts.size()
	for v in at:
		if not pts.has(v):
			pts.append(v)
	pts.sort()
	print("")
	print("TAPE  %s" % path)
	print("      %d ticks (%.1f s)   note: %s" % [n, n / 60.0, str(t["note"])])
	print("      census: %s" % TL.census_line(t["cen"]))
	print("      %d mark(s) in the file%s" % [from_marks,
		(", plus %d asked for with at=" % (pts.size() - from_marks))
		if pts.size() > from_marks else ""])
	if pts.is_empty():
		print("")
		print("      Nothing to look at. This tape carries no marks - if it is")
		print("      one of the six committed ones that is expected, they")
		print("      predate the F key. Pick a tick by hand instead:")
		print("          ... -s res://tests/mark_look.gd -- %s at=%d"
			% [path, n / 2])
		m.free()
		return 0
	# which ticks we must sample, and for which mark
	var want: Dictionary = {}                # tick -> true
	var sel: Array[int] = []
	for i in pts.size():
		if only_mark > 0 and i + 1 != only_mark:
			continue
		sel.append(pts[i])
		for q in range(maxi(pts[i] - w, 0), mini(pts[i] + w + 1, n)):
			want[q] = true
	if sel.is_empty():
		print("FAIL  mark=%d, but this tape has %d" % [only_mark, pts.size()])
		m.free()
		return 1

	# ---- replay, sampling only the ticks we need
	var rows: Dictionary = {}                # tick -> row Dictionary
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var na: int = m.a_pos.size()
	var prev := _blank_prev(na, m)
	for i in n:
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)
		var r := _row(m, i, prev)
		prev = r["prev"]
		if want.has(i):
			rows[i] = r
	m.free()

	for i in pts.size():
		if not sel.has(pts[i]):
			continue
		_print_mark(i + 1, pts.size(), pts[i], i < from_marks, w, n, rows,
			na, only_k, show_all, rings_only)
	return 0

func _blank_prev(na: int, m: Node2D) -> Dictionary:
	var eng := PackedByteArray()
	var hold := PackedByteArray()
	var lk := PackedInt32Array()
	var pin := PackedInt32Array()
	eng.resize(na); hold.resize(na); lk.resize(na); pin.resize(na)
	for k in na:
		eng[k] = 1 if m.a_freelen[k] >= 0.0 else 0
		hold[k] = 1 if m._holds(k) else 0
		lk[k] = m.a_locked[k]
		pin[k] = m.a_pinidx[k]
	return {"eng": eng, "hold": hold, "lk": lk, "pin": pin, "taut": false,
		"ge": -999, "falls": int(m.falls)}

func _row(m: Node2D, i: int, prev: Dictionary) -> Dictionary:
	# ONE TICK, FULLY READ OUT. Everything here is read after step_tick has
	# returned; see the header for why that is the same tick's truth and for
	# the self-test that checks it rather than asserting it.
	var na: int = m.a_pos.size()
	var vel: Vector2 = m._body_vel()
	var an: Array = []
	var ring := ""
	var ev: Array[String] = []
	var pe: PackedByteArray = prev["eng"]
	var ph: PackedByteArray = prev["hold"]
	var pl: PackedInt32Array = prev["lk"]
	var pp: PackedInt32Array = prev["pin"]
	var ne := PackedByteArray(); ne.resize(na)
	var nh := PackedByteArray(); nh.resize(na)
	var nl := PackedInt32Array(); nl.resize(na)
	var np := PackedInt32Array(); np.resize(na)
	for k in na:
		var eng: bool = m.a_freelen[k] >= 0.0
		var holds: bool = m._holds(k)
		var pinch: bool = m._pinch(k)
		var th: float = absf(m.a_theta[k])
		var tail := -1.0
		var need: float = m.PINCH_TURN * TAU * (float(m.a_r[k]) + 0.02)
		if m.a_pinidx[k] >= 0:
			tail = float(m.cum_len[m.NP - 1]) - float(m.cum_len[m.a_pinidx[k]])
		an.append({
			"th": float(m.a_theta[k]), "eng": eng, "lk": int(m.a_locked[k]),
			"arm": int(m.a_armed[k]), "pinch": pinch, "holds": holds,
			"pidx": int(m.a_pinidx[k]), "p0": int(m.a_pin0[k]),
			"lidx": int(m.a_lockidx[k]), "free": float(m.a_freelen[k]),
			"tail": tail, "need": need, "clr": int(m.a_clear[k]),
			"pnd": int(m.a_pend[k]), "prun": int(m.a_prun[k]),
			"pay": int(m.a_paytick[k]), "minth": float(m.a_minth[k]),
			"ength": float(m.a_ength[k]),
			# the clause verdict, only where the catch test was reachable
			"blk": _blocked(m, k, th, pinch) if pe[k] == 0 else "engaged",
		})
		# THE RING STRIP: exactly what main.gd's _draw paints at this beam.
		# '.' nothing, '~' merely touching (grey), 'A' caught but not pinched
		# (amber), 'G' _holds() (green). The player's whole report is about
		# this column, so it is read from the game's own predicate.
		if eng:
			ring += "G" if holds else "A"
		elif th > 0.3:
			ring += "~"
		else:
			ring += "."
		if eng and pe[k] == 0:
			ev.append("A%d CATCH  theta %.2f  pin %d  tether %.2f"
				% [k, th, int(m.a_pinidx[k]), float(m.a_freelen[k])])
		if not eng and pe[k] == 1:
			var how := "SLID OFF (ran out of tail)"
			if not bool(m.taut):
				how = "LET GO (hand opened)"
			elif int(m.a_armed[k]) == 1:
				how = "UNWOUND (theta fell under th_rel and no pinch)"
			ev.append("A%d %s" % [k, how])
		if eng and int(m.a_locked[k]) != pl[k] and int(m.a_locked[k]) >= 0:
			ev.append("A%d VERDICT %s  (minth %.2f)" % [k,
				"LOCKED" if int(m.a_locked[k]) == 1 else "PARTIAL",
				float(m.a_ength[k])])
		if holds and ph[k] == 0:
			ev.append("A%d RING TURNS GREEN" % k)
		if not holds and ph[k] == 1:
			ev.append("A%d RING LEAVES GREEN%s" % [k,
				"" if eng else " (and the wrap ended this tick)"])
		if eng and pe[k] == 1 and int(m.a_pinidx[k]) > pp[k]:
			ev.append("A%d PAID %d segment(s) through the pin, tail now %.2f m"
				% [k, int(m.a_pinidx[k]) - pp[k], tail])
		ne[k] = 1 if eng else 0
		nh[k] = 1 if holds else 0
		nl[k] = int(m.a_locked[k])
		np[k] = int(m.a_pinidx[k])
	if bool(m.taut) and not bool(prev["taut"]):
		ev.append("HAND CLOSED (grip_edge)")
	if not bool(m.taut) and bool(prev["taut"]):
		ev.append("HAND OPENED")
	if int(m.falls) > int(prev["falls"]):
		ev.append("SAFETY NET: below the world, teleported to spawn")
	return {
		"tick": i, "taut": bool(m.taut), "gnd": bool(m.grounded),
		"sgrip": int(m.tick_count) - int(m.grip_edge),
		"bx": float(m.body_pos.x), "by": float(m.body_pos.y),
		"vx": vel.x, "vy": vel.y, "tip": float(m.tip_speed),
		"slip": bool(m.slipping), "ring": ring, "a": an, "ev": ev,
		"prev": {"eng": ne, "hold": nh, "lk": nl, "pin": np,
			"taut": bool(m.taut), "ge": int(m.grip_edge),
			"falls": int(m.falls)},
	}

# THE CATCH CONDITION, main.gd:1567, clause by clause. Returns "" if every
# clause held - which means a catch fired on this tick - otherwise one letter
# per clause that refused, in the sim's own order.
#
# THE DUMP AND THE SELF-TEST CALL THIS SAME FUNCTION, and that is the point of
# writing it as a static over explicit values rather than as something that
# reaches into the sim. A self-test that validated its own private copy of the
# arithmetic would be certifying code the dump does not run, which is this
# project's signature failure with one more coat of paint on it.
static func _clauses(taut: bool, sgrip: int, armed: int, lidx: int, th: float,
		pinch: bool, gw: int, pmin: int, thp: float) -> String:
	var s := ""
	if not taut:
		s += "t"
	if sgrip > gw:
		s += "w"
	if armed != 1:
		s += "a"
	if lidx < pmin:
		s += "i"
	if th < thp and not pinch:
		s += "g"
	return s

static func _blocked(m: Node2D, k: int, th: float, pinch: bool) -> String:
	return _clauses(bool(m.taut), int(m.tick_count) - int(m.grip_edge),
		int(m.a_armed[k]), int(m.a_lockidx[k]), th, pinch,
		int(m.GRIP_WINDOW), int(m.pin_min_idx), float(m.th_part))

const BLK_KEY := {
	"t": "hand OPEN", "w": "the 15-tick grip window had LAPSED",
	"a": "the beam was NOT ARMED (it must fully unwind first)",
	"i": "a_lockidx below pin_min_idx (%d) - no vertex could hold it",
	"g": "GEOMETRY: theta under th_part and no self-pinch",
}

func _print_mark(idx: int, total: int, at: int, real: bool, w: int, n: int,
		rows: Dictionary, na: int, only_k: int, show_all: bool,
		rings_only: bool) -> void:
	var lo := maxi(at - w, 0)
	var hi := mini(at + w, n - 1)
	print("")
	print("=" .repeat(112))
	var kind := 0
	if real and idx >= 1 and idx <= kinds.size():
		kind = int(kinds[idx - 1])
	var label: String = "  [%s]" % KIND_NAME[kind] if real else ""
	print("%s %d of %d%s   tape tick %d   %.2f s into the tape   window %d..%d"
		% ["MARK" if real else "TICK (at=)", idx, total, label, at, at / 60.0,
		lo, hi])
	print("=".repeat(112))
	if not rows.has(at):
		print("  (that tick is not in the tape)")
		return

	# ---- the ring strip: what the beams were showing, tick by tick
	print("")
	print("  THE RINGS, one column per anchor, as _draw would have painted "
		+ "them")
	print("    . nothing   ~ touching (grey)   A caught, not pinched (amber)"
		+ "   G _holds() (GREEN)")
	print("    beams:      %s" % _ruler(na))
	var prev_ring := ""
	for i in range(lo, hi + 1):
		var r: Dictionary = rows[i]
		var rg := String(r["ring"])
		if rg != prev_ring or i == at:
			print("    %+5d %5d  %s%s" % [i - at, i, rg,
				"   <-- MARKED" if i == at else ""])
			prev_ring = rg
	print("    (only the ticks where the strip CHANGED are listed, plus the "
		+ "marked one)")

	# ---- the body
	print("")
	print("  THE BODY AND THE HAND")
	print("      d  tick  taut gnd sgrip     x      y      vx     vy    |v| "
		+ "   tip  slip")
	for i in range(lo, hi + 1):
		if (i - at) % 5 != 0 and i != at:
			continue
		var r: Dictionary = rows[i]
		print("  %+5d %5d   %s   %s %5d %7.2f %6.2f %7.2f %6.2f %6.2f %6.1f"
			% [i - at, i, "T" if bool(r["taut"]) else ".",
			"G" if bool(r["gnd"]) else ".", int(r["sgrip"]), float(r["bx"]),
			float(r["by"]), float(r["vx"]), float(r["vy"]),
			Vector2(float(r["vx"]), float(r["vy"])).length(), float(r["tip"])]
			+ ("   S" if bool(r["slip"]) else "") + ("   <--" if i == at
			else ""))

	# ---- what happened
	print("")
	print("  EVENTS IN THE WINDOW")
	var any := false
	for i in range(lo, hi + 1):
		for e: String in rows[i]["ev"]:
			print("  %+5d %5d  %s" % [i - at, i, e])
			any = true
	if not any:
		print("    (nothing changed state anywhere in this window)")

	# ---- which anchors to table
	var ks: Array[int] = []
	for k in na:
		if only_k >= 0 and k != only_k:
			continue
		if show_all:
			ks.append(k)
			continue
		var inplay := false
		for i in range(lo, hi + 1):
			var a: Dictionary = rows[i]["a"][k]
			if bool(a["eng"]) or absf(float(a["th"])) > 0.3 \
					or int(a["lidx"]) >= 0:
				inplay = true
				break
		if inplay:
			ks.append(k)
	if rings_only:
		return
	if ks.is_empty():
		print("")
		print("  No anchor was in play in this window (no wrap, no contact).")
		print("  Add `all` to table every beam anyway.")
		return
	for k in ks:
		_print_anchor(k, at, lo, hi, rows)

func _print_anchor(k: int, at: int, lo: int, hi: int, rows: Dictionary) -> void:
	print("")
	print("  " + "-".repeat(108))
	print("  ANCHOR %d" % k)
	print("   d    tick |theta| eng lk arm pn hd  pidx  p0 lidx   free   tail"
		+ "   need clr pnd prn  pay  minth ength  blocked")
	for i in range(lo, hi + 1):
		var r: Dictionary = rows[i]
		var a: Dictionary = r["a"][k]
		var blk := String(a["blk"])
		print(" %+5d %5d %7.3f  %s  %2d  %2d  %s  %s %5d %3d %4d %6.2f %6.2f "
			% [i - at, i, absf(float(a["th"])),
			"E" if bool(a["eng"]) else ".", int(a["lk"]), int(a["arm"]),
			"P" if bool(a["pinch"]) else ".",
			"G" if bool(a["holds"]) else ".", int(a["pidx"]), int(a["p0"]),
			int(a["lidx"]), float(a["free"]), float(a["tail"])]
			+ "%6.2f %3d %3d %3d %4d %6.2f %6.2f  %-6s" % [float(a["need"]),
			int(a["clr"]), int(a["pnd"]), int(a["prun"]), int(a["pay"]),
			float(a["minth"]), float(a["ength"]),
			blk if blk != "" else "CATCH!"]
			+ ("  <-- MARKED" if i == at else ""))
	# ---- and the summary the player's second complaint needs
	var cnt: Dictionary = {}
	var live := 0
	for i in range(lo, hi + 1):
		var a: Dictionary = rows[i]["a"][k]
		if String(a["blk"]) == "engaged":
			continue
		if int(a["lidx"]) < 0:
			continue          # the rope was nowhere near this beam
		live += 1
		for c in String(a["blk"]):
			cnt[c] = int(cnt.get(c, 0)) + 1
	print("")
	print("  WHY ANCHOR %d DID NOT CATCH, over %d tick(s) in this window on "
		% [k, live] + "which")
	print("  the rope was within reach of it (a_lockidx >= 0) and it was not "
		+ "already engaged:")
	if live == 0:
		print("      (the rope never came near this beam in the window)")
	elif cnt.is_empty():
		print("      (nothing blocked it - every such tick caught)")
	else:
		var order := ["t", "w", "a", "i", "g"]
		for c: String in order:
			if not cnt.has(c):
				continue
			var lbl := String(BLK_KEY[c])
			if c == "i":
				lbl = lbl % 3
			print("      %4d  %s" % [int(cnt[c]), lbl])

static func _ruler(na: int) -> String:
	var s := ""
	for k in na:
		s += str(k % 10)
	return s


# =============================================================== the self-test
# THE THROW CORPUS. The six tapes tick all eleven anchors, so the clause
# arithmetic is exercised everywhere by them - but the rope only ever goes NEAR
# three of those beams, and only three catches happen in the whole 7679 ticks.
# So strokes are thrown at every beam in the level as well: the fat 0.22 m
# school pair, the 0.20 m run-up, the four 0.11 m doors and the four 0.10 m
# fast beams, where a full turn is under five tip segments.
#
# The strokes are tapelib's own, with tapelib's own trigger-grip rule, thrown
# from a body that CRAWLED into its chain shape rather than one hand-laid into
# it: 96 ticks of the lash gait first, so the whip trails the way it trails in
# play, and only then is the body moved under the beam. The seven
# (lead, a0, a1) triples below are the ones measured to land - a grid scan over
# 12 strokes x 11 beams, kept as the subset that actually engages, so the
# self-test spends its clock on ticks that reach the catch condition rather
# than on strokes that fall short of it.
const WARM_GAIT := 96
const THROWS := [
	[2.2, PI * 1.10, -PI * 0.42], [2.2, PI * 1.10, -PI * 0.30],
	[2.2, PI * 1.10, -PI * 0.18], [2.9, PI * 0.85, -PI * 0.42],
	[2.9, PI * 0.85, -PI * 0.30], [2.9, PI * 1.10, -PI * 0.30],
	[2.9, PI * 1.10, -PI * 0.18],
]

func _selftest(lie: String) -> int:
	var lies: Array[String] = [""]
	if lie == "all":
		var ks: Array = LIES.keys()
		ks.sort()
		for key: String in ks:
			lies.append(key)
	elif lie != "":
		lies.append(lie)
	print("")
	print("=== mark_look SELF-TEST " + "=".repeat(64))
	print("The reconstruction cannot see whether a catch fired; the sim cannot")
	print("see the reconstruction. On every (tick, anchor) where the anchor was")
	print("disengaged at the end of the PREVIOUS tick, the two must agree - the")
	print("condition is true on exactly the ticks a catch actually happened.")
	var t0 := Time.get_ticks_msec()
	var c := _collect()
	print("")
	print("  CORPUS")
	for s: String in c["srcs"]:
		print("    %s" % s)
	print("    %d anchor-ticks where the catch condition was reachable"
		% int(c["n"]))
	print("    %d of them are ticks a catch really fired on" % int(c["catch"]))
	print("    %d skipped: the safety net or an R press wiped every anchor"
		% int(c["skip"]))
	print("      inside the tick, after _update_locks had already run, so")
	print("      there is no catch left to compare the reading against")
	print("    collected in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if int(c["catch"]) < 5:
		fails += 1
		print("    FAIL  too few real catches to test the TRUE direction at all")
	_histogram(c)
	print("")
	var base := PackedByteArray()
	var caught := 0
	var reached := 0
	for li: String in lies:
		var r := _score(c, li, base)
		var mis := int(r["mis"])
		var fp := int(r["fp"])
		var fn := int(r["fn"])
		if li == "":
			base = r["preds"]
			print("  HONEST READING")
			print("    %s  %d disagreement(s)   (%d said catch where none did, "
				% ["PASS" if mis == 0 else "FAIL", mis, fp]
				+ "%d said no catch where one did)" % fn)
			if mis > 0:
				fails += 1
				print("      first: %s" % str(r["first"]))
			continue
		print("  LIE %s: %s" % [li, str(LIES.get(li, "?"))])
		if int(r["changed"]) == 0:
			# NOT A FAILURE, AND SAYING SO IS THE POINT. This lie predicts
			# exactly what the honest reading predicts on every one of these
			# anchor-ticks, so there is nothing here for the self-test to
			# notice. What it means is that the corpus never puts this clause
			# in the deciding position - which is a fact about the corpus, and
			# a useful one, not a hole in the instrument. The histogram above
			# says how often each clause refuses at all.
			print("    NOT REACHED  this corpus never lets that clause decide")
			continue
		reached += 1
		print("    %s  %d disagreement(s) over %d changed prediction(s)   "
			% ["PASS - caught" if mis > 0 else
			"FAIL - the self-test slept through it", mis, int(r["changed"])]
			+ "(%d false catch, %d missed)" % [fp, fn])
		if mis == 0:
			fails += 1
		else:
			caught += 1
			print("      first: %s" % str(r["first"]))
	if lies.size() > 1:
		print("")
		print("  %s  %d of %d lie(s) reached this corpus, %d of those caught"
			% ["PASS" if (reached == 0 or caught == reached) and caught > 0
			else "FAIL", reached, lies.size() - 1, caught])
		if caught == 0:
			fails += 1
	print("")
	print("%s  mark_look self-test: %d failure(s)" % ["PASS" if fails == 0
		else "FAIL", fails])
	return 1 if fails > 0 else 0

# ---- one pass over every source, caching the six values the condition reads
func _collect() -> Dictionary:
	var d := {
		"taut": PackedByteArray(), "sgrip": PackedInt32Array(),
		"armed": PackedInt32Array(), "lidx": PackedInt32Array(),
		"th": PackedFloat32Array(), "pinch": PackedByteArray(),
		"ltaut": PackedByteArray(), "lsgrip": PackedInt32Array(),
		"eng": PackedByteArray(), "src": PackedStringArray(),
		"tick": PackedInt32Array(), "k": PackedInt32Array(),
		"n": 0, "catch": 0, "skip": 0, "srcs": [],
	}
	var m := TL.new_sim()
	d["gw"] = int(m.GRIP_WINDOW)
	d["pmin"] = int(m.pin_min_idx)
	d["thp"] = float(m.th_part)
	d["thr"] = float(m.th_rel)
	var na: int = m.a_pos.size()
	m.free()
	var names: Array[String] = []
	var dd := DirAccess.open("res://tapes")
	if dd != null:
		var fs: Array[String] = []
		for fn in dd.get_files():
			if fn.ends_with(".tape"):
				fs.append(fn)
		fs.sort()
		for fn in fs:
			var was := int(d["n"])
			_collect_tape("res://tapes/%s" % fn, fn, d)
			names.append("%-14s %6d anchor-ticks" % [fn, int(d["n"]) - was])
	var wt := int(d["n"])
	var wc := int(d["catch"])
	_collect_throws(d)
	names.append("%-14s %6d anchor-ticks, %d catches, %d strokes over %d beams"
		% ["throws", int(d["n"]) - wt, int(d["catch"]) - wc,
		THROWS.size() * na, na])
	d["srcs"] = names
	return d

func _collect_tape(path: String, name: String, d: Dictionary) -> void:
	var t: Dictionary = MAIN.tape_load(path)
	var m := TL.new_sim()
	if not bool(t.get("ok", false)) or int(t["lvl"]) != m.level_fingerprint() \
			or not m.restore(t["start"]):
		m.free()
		return
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var st := _fresh(m)
	for i in cur.size():
		m.pending_reset = (grp[i] & 2) != 0
		_one(m, name, i, (grp[i] & 2) != 0, st, d, cur[i], (grp[i] & 1) != 0)
	m.free()

func _collect_throws(d: Dictionary) -> void:
	var m := TL.new_sim()
	TL.run(m, [{"kind": "gait", "n": WARM_GAIT}])
	var warm: Dictionary = m.snapshot()
	for k in m.a_pos.size():
		for ci in THROWS.size():
			var tr: Array = THROWS[ci]
			m.restore(warm)
			var bx: float = float(m.a_pos[k].x) - float(tr[0])
			m.teleport(Vector2(bx, TL.floor_y(m, bx) - 0.34))
			for i in 20:
				m.step_tick(m.body_pos, false)
			var c := {"a0": tr[1], "a1": tr[2], "sd": 9, "pull": false,
				"w": 110}
			var ph := {"kind": "stroke", "k": k, "c": c}
			var ss := {}
			var st := _fresh(m)
			var nm := "throw A%d c%d" % [k, ci]
			for i in 230:
				var cg: Array = TL.inp(m, ph, i, ss)
				ss["pb"] = m.body_pos
				_one(m, nm, i, false, st, d, cg[0], bool(cg[1]))
			# THE RE-GRIP, and it is here because it is the only thing in the
			# game that makes a_armed the DECIDING clause. Open the hand for
			# two ticks - main.gd drops the wrap that instant and clears
			# a_armed - then close it again with the rope still lying on the
			# beam. Every other clause then passes: the hand is shut, the
			# window is fresh, the rope is still wound round the beam. The one
			# thing refusing is that you already had this beam and let it go.
			# Without these 42 ticks the corpus cannot tell a reading that
			# honours a_armed from one that ignores it, and a self-test that
			# cannot tell them apart is not testing that clause at all.
			if float(m.a_freelen[k]) >= 0.0:
				for i in 2:
					_one(m, nm + " regrip", 230 + i, false, st, d,
						m.body_pos, false)
				for i in 40:
					_one(m, nm + " regrip", 232 + i, false, st, d,
						m.body_pos, true)
	m.free()

func _fresh(m: Node2D) -> Dictionary:
	var na: int = m.a_pos.size()
	var pe := PackedByteArray()
	pe.resize(na)
	for k in na:
		pe[k] = 1 if m.a_freelen[k] >= 0.0 else 0
	return {"pe": pe, "taut": bool(m.taut), "ge": int(m.grip_edge),
		"falls": int(m.falls)}

func _one(m: Node2D, name: String, i: int, was_r: bool, st: Dictionary,
		d: Dictionary, cursor: Vector2, grip: bool) -> void:
	var pt: bool = bool(st["taut"])
	var pge: int = int(st["ge"])
	m.step_tick(cursor, grip)
	var wiped: bool = int(m.falls) > int(st["falls"]) or was_r
	st["falls"] = int(m.falls)
	var pe: PackedByteArray = st["pe"]
	for k in m.a_pos.size():
		var eng: bool = m.a_freelen[k] >= 0.0
		if pe[k] == 0:
			if wiped:
				d["skip"] = int(d["skip"]) + 1
			else:
				# EVERY VALUE HERE IS READ AFTER step_tick RETURNED, exactly as
				# the dump mode reads them. That reading is what is on trial.
				d["taut"].append(1 if bool(m.taut) else 0)
				d["sgrip"].append(int(m.tick_count) - int(m.grip_edge))
				d["armed"].append(int(m.a_armed[k]))
				d["lidx"].append(int(m.a_lockidx[k]))
				d["th"].append(absf(float(m.a_theta[k])))
				d["pinch"].append(1 if m._pinch(k) else 0)
				d["ltaut"].append(1 if pt else 0)
				d["lsgrip"].append(int(m.tick_count) - pge)
				d["eng"].append(1 if eng else 0)
				d["src"].append(name)
				d["tick"].append(i)
				d["k"].append(k)
				d["n"] = int(d["n"]) + 1
				if eng:
					d["catch"] = int(d["catch"]) + 1
		pe[k] = 1 if eng else 0
	st["taut"] = bool(m.taut)
	st["ge"] = int(m.grip_edge)

# ---- the scoring, over that cache, for one reading: honest, or lying
func _score(c: Dictionary, lie: String, base: PackedByteArray) -> Dictionary:
	var taut: PackedByteArray = c["taut"]
	var sgrip: PackedInt32Array = c["sgrip"]
	var armed: PackedInt32Array = c["armed"]
	var lidx: PackedInt32Array = c["lidx"]
	var th: PackedFloat32Array = c["th"]
	var pinch: PackedByteArray = c["pinch"]
	var ltaut: PackedByteArray = c["ltaut"]
	var lsgrip: PackedInt32Array = c["lsgrip"]
	var eng: PackedByteArray = c["eng"]
	var gw: int = int(c["gw"])
	var pmin: int = int(c["pmin"])
	var thp: float = float(c["thp"])
	var fp := 0
	var fn := 0
	var changed := 0
	var first := ""
	var preds := PackedByteArray()
	preds.resize(int(c["n"]))
	for j in int(c["n"]):
		var vt: bool = taut[j] == 1
		var vs: int = sgrip[j]
		var va: int = armed[j]
		var vl: int = lidx[j]
		var vp: bool = pinch[j] == 1
		var vgw := gw
		var vth := thp
		match lie:
			"lag":
				vt = ltaut[j] == 1
				vs = lsgrip[j]
			"armed":
				va = 1
			"nopinch":
				vp = false
			"pinidx":
				vl = pmin
			"window":
				vgw = gw - 1
			"thpart":
				vth = float(c["thr"])
		var pred := _clauses(vt, vs, va, vl, th[j], vp, vgw, pmin, vth) == ""
		preds[j] = 1 if pred else 0
		if base.size() == preds.size() and (1 if pred else 0) != base[j]:
			changed += 1
		if pred != (eng[j] == 1):
			if pred:
				fp += 1
			else:
				fn += 1
			if first == "":
				first = "%s tick %d anchor %d: the reading says %s, the sim %s" \
					% [String(c["src"][j]), int(c["tick"][j]), int(c["k"][j]),
					"CATCH" if pred else "no catch",
					"caught" if eng[j] == 1 else "did not"]
	return {"mis": fp + fn, "fp": fp, "fn": fn, "first": first,
		"changed": changed, "preds": preds}

# ---- WHICH CLAUSE REFUSES, over the whole corpus. Not part of the pass/fail:
# this is the number the investigation actually wants, and it is what explains
# a lie that goes NOT REACHED. Counted only on anchor-ticks where the rope was
# within reach of the beam (a_lockidx >= 0), because a beam the whip is nowhere
# near refuses for reasons no player would call a missed hook.
func _histogram(c: Dictionary) -> void:
	var order := ["t", "w", "a", "i", "g"]
	var lbl := {"t": "hand OPEN", "w": "grip window LAPSED",
		"a": "beam NOT ARMED", "i": "lockidx below pin_min_idx",
		"g": "GEOMETRY (theta < th_part and no pinch)"}
	var any: Dictionary = {}
	var sole: Dictionary = {}
	var near := 0
	var caught := 0
	var taut: PackedByteArray = c["taut"]
	var sgrip: PackedInt32Array = c["sgrip"]
	var armed: PackedInt32Array = c["armed"]
	var lidx: PackedInt32Array = c["lidx"]
	var th: PackedFloat32Array = c["th"]
	var pinch: PackedByteArray = c["pinch"]
	var eng: PackedByteArray = c["eng"]
	for j in int(c["n"]):
		if lidx[j] < 0:
			continue
		near += 1
		var s := _clauses(taut[j] == 1, sgrip[j], armed[j], lidx[j], th[j],
			pinch[j] == 1, int(c["gw"]), int(c["pmin"]), float(c["thp"]))
		if s == "":
			caught += 1
			continue
		for ch in s:
			any[ch] = int(any.get(ch, 0)) + 1
		if s.length() == 1:
			sole[s] = int(sole.get(s, 0)) + 1
	print("")
	print("  WHICH CLAUSE REFUSES, over the %d anchor-ticks where the rope was"
		% near)
	print("  within reach of the beam and the anchor was not already engaged")
	print("  (%d of them caught):" % caught)
	print("      clause                                  refuses   and alone")
	for ch: String in order:
		print("      %s  %-36s %7d   %9d" % [ch, String(lbl[ch]),
			int(any.get(ch, 0)), int(sole.get(ch, 0))])
	print("  'and alone' is the column a lie needs to be non-zero in before")
	print("  this corpus can tell that clause is being read at all.")
