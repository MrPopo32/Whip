extends SceneTree
## SKILL OR CHANCE, PART 3: THE PLAYER'S OWN THROWS, REPEATED UNDER HIS OWN HAND.
##
## takes/bug1.tape is the player's real session. This build's replay of it is
## run once, noise-free, keeping the state from 60 ticks before every catch;
## then each catch is continued from that state with HIS recorded cursor and
## grip for those 60 ticks plus POST ticks after, N times, under the hand
## noise of tests/hand_noise.gd. The recorded cursor is replayed RELATIVE TO
## THE BODY (main.gd maps the mouse as body + px * m_per_px, so the hand the
## player moved was a body-relative one), time-warped by the speed scale, with
## the whole-hand offset and tremor added and each closing of the hand shifted
## by the timing jitter. P(engage) and P(lock) per catch is the closest thing
## there is to "would he have caught that again".
##
## THE PROBE HAS RNG; THE SIM DOES NOT. Tier "null" must reproduce the catch on
## exactly its recorded tick and give one state hash across samples - asserted
## per catch, and the reference the noisy samples are read against. Nothing
## here enters the tree or writes a save.
##
##   godot --headless --path . -s res://tests/skill_tape.gd -- takes/bug1.tape <shard> <nshards> <N> <tier> <out.json>
const TL := preload("res://tests/tapelib.gd")
const HN := preload("res://tests/hand_noise.gd")
const PRE := 60                        # ticks of his hand before the catch
const POST := 90                       # ticks of his hand after it (a lock is
                                       # decided inside LOCK_WINDOW = 30)

var m: Node2D
var cur: PackedVector2Array
var grp: PackedByteArray
var body_pre: PackedVector2Array       # body_pos the recorded cursor was read against
var n := 0

func cont(cat: Dictionary, tier: String, s: int) -> Dictionary:
	var c: int = int(cat["c"])
	var k: int = int(cat["k"])
	m.restore(cat["snap"])
	var hn: RefCounted = HN.new(tier, "tape/%d" % c, s)
	var c0 := c - PRE
	var L := PRE + 1 + POST
	# the grip, time-warped, then every closing shifted by the jitter
	var gw := PackedByteArray()
	gw.resize(L)
	for j in L:
		var ri := clampi(int(round(float(c0) + float(j) / hn.speed)), 0, n - 1)
		gw[j] = grp[ri] & 1
	if hn.jit != 0:
		var g2 := gw.duplicate()
		for j in range(1, L):
			if gw[j] == 1 and gw[j - 1] == 0:
				if hn.jit > 0:
					for x in range(j, mini(j + hn.jit, L)):
						g2[x] = 0          # late: the hand stays open longer
				else:
					for x in range(maxi(0, j + hn.jit), j):
						g2[x] = 1          # early: it shuts sooner
		gw = g2
	var was: bool = float(m.a_freelen[k]) >= 0.0
	var eng_t := -999
	var lock := false
	var lock_t := -999
	for j in L:
		var rf: float = float(c0) + float(j) / float(hn.speed)
		var i0 := clampi(int(floor(rf)), 0, n - 1)
		var fr: float = rf - float(i0)
		var cursor: Vector2
		if fr == 0.0 or i0 + 1 >= n:
			# EXACT when the noise is zero: cur + (b - b) + 0 == cur bit for bit
			cursor = cur[i0] + (m.body_pos - body_pre[i0]) + hn.tick()
		else:
			var h0: Vector2 = cur[i0] - body_pre[i0]
			var h1: Vector2 = cur[i0 + 1] - body_pre[i0 + 1]
			cursor = m.body_pos + h0.lerp(h1, fr) + hn.tick()
		m.pending_reset = false
		m.step_tick(cursor, gw[j] == 1)
		var e: bool = float(m.a_freelen[k]) >= 0.0
		if e and not was and eng_t == -999:
			eng_t = c0 + j - c
		if e and int(m.a_locked[k]) == 1 and not lock:
			lock = true
			lock_t = c0 + j - c
		was = e
	return {"eng": eng_t != -999, "eng_t": eng_t, "lock": lock, "lock_t": lock_t,
		"held": float(m.a_freelen[k]) >= 0.0, "hash": m.state_hash(),
		"speed": hn.speed, "jit": hn.jit}

static func mean_sd(v: Array) -> Array:
	if v.is_empty():
		return [0.0, 0.0]
	var mu := 0.0
	for x in v:
		mu += float(x)
	mu /= v.size()
	var ss := 0.0
	for x in v:
		ss += (float(x) - mu) * (float(x) - mu)
	return [mu, sqrt(ss / maxi(1, v.size() - 1))]

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var path: String = args[0]
	var shard := int(args[1])
	var nshards := int(args[2])
	var N := int(args[3])
	var tier := String(args[4])
	var outp := String(args[5])
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var t: Dictionary = load("res://main.gd").tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load %s: %s" % [path, t.get("err", "")])
		quit(1)
		return
	cur = t["cur"]
	grp = t["grip"]
	n = cur.size()
	m = TL.new_sim()
	if not m.restore(t["start"]):
		print("start state refused")
		quit(1)
		return
	body_pre = PackedVector2Array()
	body_pre.resize(n)
	var ring: Array = []
	ring.resize(PRE + 1)
	var na: int = m.a_pos.size()
	var was := PackedByteArray()
	was.resize(na)
	var catches: Array = []
	var last_of := {}                  # k -> index into catches
	var t0 := Time.get_ticks_msec()
	for i in n:
		ring[i % (PRE + 1)] = m.snapshot()
		body_pre[i] = m.body_pos
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)
		for k in na:
			var e := 1 if float(m.a_freelen[k]) >= 0.0 else 0
			if e == 1 and was[k] == 0:
				catches.append({"c": i, "k": k, "lock": false,
					"snap": ring[(i - PRE) % (PRE + 1)] if i >= PRE else {},
					"reset_in_window": false})
				last_of[k] = catches.size() - 1
			if e == 1 and int(m.a_locked[k]) == 1 and last_of.has(k):
				catches[last_of[k]]["lock"] = true
			was[k] = e
	# a reset inside a window would make the continuation meaningless
	for cat: Dictionary in catches:
		var c: int = int(cat["c"])
		for i in range(maxi(0, c - PRE), mini(n, c + POST + 1)):
			if (grp[i] & 2) != 0:
				cat["reset_in_window"] = true
	var nlock := 0
	for cat: Dictionary in catches:
		if bool(cat["lock"]):
			nlock += 1
	print("")
	print("PLAYER REPLAY  %s: %d ticks, %d catches, %d of them locked on this build (%.0f s)"
		% [path, n, catches.size(), nlock, (Time.get_ticks_msec() - t0) / 1000.0])
	print("  window: his hand from %d ticks before the catch to %d after; tier %s = %s; N %d; shard %d/%d"
		% [PRE, POST, tier, HN.new(tier, "x", 0).describe(), N, shard, nshards])
	print("")
	print("   n   tick  k  taped  | ref eng@  ref lock | null hashes |  P(eng)  P(lock)  eng_t mean/sd  lock_t mean")
	var rows: Array = []
	for ci in catches.size():
		if ci % nshards != shard:
			continue
		var cat: Dictionary = catches[ci]
		if int(cat["c"]) < PRE or bool(cat["reset_in_window"]):
			print("  %2d  %5d  %d  skipped (too early or a reset in the window)"
				% [ci, int(cat["c"]), int(cat["k"])])
			continue
		# the reference and the null: three noise-free continuations, one hash
		var ref := cont(cat, "null", 0)
		var nh := {int(ref["hash"]): true}
		for s in range(1, 3):
			nh[int(cont(cat, "null", s)["hash"])] = true
		var eng := 0
		var lock := 0
		var held := 0
		var ets: Array = []
		var lts: Array = []
		for s in N:
			var r := cont(cat, tier, s)
			if bool(r["eng"]):
				eng += 1
				ets.append(int(r["eng_t"]))
			if bool(r["lock"]):
				lock += 1
				lts.append(int(r["lock_t"]))
			if bool(r["held"]):
				held += 1
		var em := mean_sd(ets)
		var lm := mean_sd(lts)
		var row := {"i": ci, "c": int(cat["c"]), "k": int(cat["k"]),
			"taped_lock": bool(cat["lock"]), "ref_eng_t": int(ref["eng_t"]),
			"ref_lock": bool(ref["lock"]), "null_hashes": nh.size(), "N": N,
			"eng": eng, "lock": lock, "held": held, "eng_t_mean": em[0],
			"eng_t_sd": em[1], "lock_t_mean": lm[0]}
		rows.append(row)
		print("  %2d  %5d  %d  %-5s  |   %+4d     %-5s  |     %d       |  %5.2f   %5.2f    %+5.1f / %4.1f    %+5.1f"
			% [ci, int(cat["c"]), int(cat["k"]),
			"lock" if bool(cat["lock"]) else "part", int(ref["eng_t"]),
			str(bool(ref["lock"])), nh.size(), float(eng) / N, float(lock) / N,
			float(em[0]), float(em[1]), float(lm[0])])
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"tape": path, "n": n, "PRE": PRE,
			"POST": POST, "tier": tier, "N": N, "shard": shard,
			"nshards": nshards, "catches": catches.size(), "taped_locks": nlock,
			"rows": rows}, "  "))
		f.close()
	m.free()
	quit(0)
