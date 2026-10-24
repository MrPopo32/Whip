extends SceneTree
## SKILL OR CHANCE, PART 3: THE PLAYER'S OWN THROWS, REPEATED UNDER HIS OWN HAND.
##
## The closest thing there is to "would he have caught that again". Each of the
## player's catches on takes/bug1.tape is restored from the state 60 ticks
## BEFORE it (harvested on the recording build by tests/skill_harvest.gd, since
## HEAD's replay of the tape diverges at ~tick 1830 and sees 5 catches where he
## made 30) and continued on THIS build with HIS recorded cursor and grip for
## those 60 ticks plus POST after, N times, under the hand noise of
## tests/hand_noise.gd.
##
## The recorded cursor is replayed RELATIVE TO THE BODY the recording build had
## on that tick (main.gd maps the mouse as body + px * m_per_px, so the hand he
## moved was a body-relative one), time-warped by the throw's speed scale, with
## the whole-hand offset and tremor added, and every closing of the hand inside
## the window shifted by the timing jitter.
##
## THE PROBE HAS RNG; THE SIM DOES NOT. Tier "null" (all sigmas zero) is run
## three times per catch and must give one state hash - the instrument's null,
## asserted per catch - and its outcome is the reference the noisy samples are
## read against ("ref eng@": on which tick relative to the recorded catch the
## noise-free continuation engaged, 0 = the recorded tick). Nothing here enters
## the tree or writes a save.
##
##   godot --headless --path . -s res://tests/skill_catch.gd -- takes/bug1.tape <bindir> <N> <tier> <out.json> [shard nshards]
const TL := preload("res://tests/tapelib.gd")
const HN := preload("res://tests/hand_noise.gd")
const POST := 90                       # ticks of his hand after the catch (a
                                       # lock is decided inside LOCK_WINDOW = 30)

var m: Node2D
var cur: PackedVector2Array
var grp: PackedByteArray
var n := 0

func cont(cat: Dictionary, tier: String, s: int) -> Dictionary:
	var c: int = int(cat["tick"])
	var k: int = int(cat["k"])
	var PRE: int = int(cat["pre"])
	var body: PackedVector2Array = cat["body"]
	if not m.restore(cat["snap"]):
		return {"refused": true}
	var hn: RefCounted = HN.new(tier, "catch/%d" % c, s)
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
	var end_t := -999
	var how := "held"
	for j in L:
		var rf: float = float(c0) + float(j) / float(hn.speed)
		var i0 := clampi(int(floor(rf)), 0, n - 1)
		var fr: float = rf - float(i0)
		var b0 := clampi(i0 - c0, 0, body.size() - 1)
		var cursor: Vector2
		if fr == 0.0 or i0 + 1 >= n or b0 + 1 >= body.size():
			# with zero noise and the body where the recording build had it,
			# this is cur + (b - b) + 0 == cur, bit for bit
			cursor = cur[i0] + (m.body_pos - body[b0]) + hn.tick()
		else:
			var h0: Vector2 = cur[i0] - body[b0]
			var h1: Vector2 = cur[i0 + 1] - body[b0 + 1]
			cursor = m.body_pos + h0.lerp(h1, fr) + hn.tick()
		m.pending_reset = false
		m.step_tick(cursor, gw[j] == 1)
		var e: bool = float(m.a_freelen[k]) >= 0.0
		if e and not was and eng_t == -999:
			eng_t = c0 + j - c
		if e and int(m.a_locked[k]) == 1 and not lock:
			lock = true
			lock_t = c0 + j - c
		if not e and was and eng_t != -999 and end_t == -999:
			end_t = c0 + j - c
			how = "hand opened" if gw[j] == 0 else "wrap ended"
		was = e
	return {"refused": false, "eng": eng_t != -999, "eng_t": eng_t,
		"lock": lock, "lock_t": lock_t, "held": float(m.a_freelen[k]) >= 0.0,
		"end_t": end_t, "how": how, "hash": m.state_hash(), "speed": hn.speed,
		"jit": hn.jit}

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
	var bindir: String = args[1]
	var N := int(args[2])
	var tier := String(args[3])
	var outp := String(args[4])
	var shard := int(args[5]) if args.size() > 5 else 0
	var nshards := int(args[6]) if args.size() > 6 else 1
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
	var files: Array = []
	for f in DirAccess.get_files_at(bindir):
		if f.begins_with("pre_") and f.ends_with(".bin"):
			files.append(f)
	files.sort()
	print("")
	print("PLAYER'S CATCHES  %s: %d ticks; %d catch snapshots from the recording build in %s"
		% [path, n, files.size(), bindir])
	print("  window: his hand from PRE ticks before the catch to %d after; tier %s = %s; N %d; shard %d/%d"
		% [POST, tier, HN.new(tier, "x", 0).describe(), N, shard, nshards])
	print("")
	print("   n   tick  k  taped(old build)     | ref: eng@ lock end/how      | null | P(eng)  P(lock)  P(held)  eng_t mean/sd  lock_t  opened/ended")
	var rows: Array = []
	var fi := -1
	for fn: String in files:
		fi += 1
		if fi % nshards != shard:
			continue
		var f := FileAccess.open("%s/%s" % [bindir, fn], FileAccess.READ)
		var cat: Dictionary = f.get_var()
		f.close()
		var ci := int(cat["i"])
		var taped := "%s %+d %s" % ["lock" if bool(cat["locked"]) else "part",
			int(cat["end"]), String(cat["how"])]
		# the reference and the null: three noise-free continuations, one hash
		var ref := cont(cat, "null", 0)
		if bool(ref["refused"]):
			print("  %2d  %5d  %d  %-22s | snapshot REFUSED by this build's restore()" % [
				ci, int(cat["tick"]), int(cat["k"]), taped])
			rows.append({"i": ci, "c": int(cat["tick"]), "k": int(cat["k"]),
				"refused": true})
			continue
		var nh := {int(ref["hash"]): true}
		for s in range(1, 3):
			nh[int(cont(cat, "null", s)["hash"])] = true
		var eng := 0
		var lock := 0
		var held := 0
		var opened := 0
		var ended := 0
		var ets: Array = []
		var lts: Array = []
		var hashes := {}
		for s in N:
			var r := cont(cat, tier, s)
			hashes[int(r["hash"])] = true
			if bool(r["eng"]):
				eng += 1
				ets.append(int(r["eng_t"]))
			if bool(r["lock"]):
				lock += 1
				lts.append(int(r["lock_t"]))
			if bool(r["held"]):
				held += 1
			if int(r["end_t"]) != -999:
				if String(r["how"]) == "hand opened":
					opened += 1
				else:
					ended += 1
		var em := mean_sd(ets)
		var lm := mean_sd(lts)
		var row := {"i": ci, "c": int(cat["tick"]), "k": int(cat["k"]),
			"refused": false, "taped_lock": bool(cat["locked"]),
			"taped_end": int(cat["end"]), "taped_how": String(cat["how"]),
			"ref_eng_t": int(ref["eng_t"]), "ref_lock": bool(ref["lock"]),
			"ref_end_t": int(ref["end_t"]), "ref_how": String(ref["how"]),
			"null_hashes": nh.size(), "N": N, "eng": eng, "lock": lock,
			"held": held, "opened": opened, "ended": ended,
			"eng_t_mean": em[0], "eng_t_sd": em[1], "lock_t_mean": lm[0],
			"distinct": hashes.size()}
		rows.append(row)
		print("  %2d  %5d  %d  %-22s | %+4d  %-5s %+4d/%-11s | %d    |  %5.2f   %5.2f    %5.2f    %+5.1f / %4.1f   %+5.1f   %2d/%2d"
			% [ci, int(cat["tick"]), int(cat["k"]), taped, int(ref["eng_t"]),
			str(bool(ref["lock"])), int(ref["end_t"]), String(ref["how"]),
			nh.size(), float(eng) / N, float(lock) / N, float(held) / N,
			float(em[0]), float(em[1]), float(lm[0]), opened, ended])
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"tape": path, "n": n, "POST": POST,
			"tier": tier, "N": N, "shard": shard, "nshards": nshards,
			"files": files.size(), "rows": rows}, "  "))
		f.close()
	m.free()
	quit(0)
