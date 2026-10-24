extends SceneTree
## ADVERSARIAL REPRODUCTION of tests/skill_catch.gd (the player's own catches
## repeated under hand noise), written from the spec with the noise model of
## tests/vfy_control.gd (class Hand: own seeds, own filter, own draw order).
##
## Each catch state (scratchpad/pre/pre_NN.bin, harvested on the recording
## build 60 ticks before the catch, with that build's body track for the
## window) is restored on THIS build and continued for PRE + 1 + POST ticks
## with the player's recorded cursor and grip:
##   cursor  = body_now + (cur_rec[i] - body_rec[i]) + noise    (body-relative)
##   time    = the recorded index i is round(c0 + j / speed): nearest tick, no
##             interpolation (a deliberate implementation difference from
##             skill_catch, which lerps)
##   grip    = the recorded bit at the warped index, every rising edge moved by
##             jit ticks (early: shuts sooner; late: stays open longer)
## Outcome: LOCK = a_locked[k] == 1 seen while the tether is active inside the
## window; ENG = the tether engaged at all; HELD = still engaged at the end.
## Null: 3 all-zero-sigma continuations per catch must give one hash.
##
##   godot --headless --path . -s res://tests/vfy_control_catch.gd -- <bindir> <N> <tier> [shard nshards]
const TL := preload("res://tests/tapelib.gd")
const VC := preload("res://tests/vfy_control.gd")
const POST := 90

var m: Node2D
var cur: PackedVector2Array
var grp: PackedByteArray
var n := 0

func cont(cat: Dictionary, tier: Array, seed_str: String) -> Dictionary:
	var c := int(cat["tick"])
	var k := int(cat["k"])
	var PRE := int(cat["pre"])
	var body: PackedVector2Array = cat["body"]
	if not m.restore(cat["snap"]):
		return {"refused": true}
	var h := VC.Hand.new(tier, seed_str)
	var c0 := c - PRE
	var L := PRE + 1 + POST
	var idx := PackedInt32Array()
	idx.resize(L)
	var g := PackedByteArray()
	g.resize(L)
	for j in L:
		var i := clampi(int(round(float(c0) + float(j) / h.speed)), 0, n - 1)
		idx[j] = i
		g[j] = grp[i] & 1
	if h.jit != 0:
		var g2 := g.duplicate()
		for j in range(1, L):
			if g[j] == 1 and g[j - 1] == 0:
				if h.jit > 0:
					for x in range(j, mini(j + h.jit, L)):
						g2[x] = 0
				else:
					for x in range(maxi(0, j + h.jit), j):
						g2[x] = 1
		g = g2
	var eng := false
	var lock := false
	var eng_t := -999
	for j in L:
		var i := idx[j]
		var b := clampi(i - c0, 0, body.size() - 1)
		var cursor: Vector2 = m.body_pos + (cur[i] - body[b]) + h.step()
		m.pending_reset = false
		m.step_tick(cursor, g[j] == 1)
		var e := float(m.a_freelen[k]) >= 0.0
		if e and not eng:
			eng = true
			eng_t = j - PRE
		if e and int(m.a_locked[k]) == 1:
			lock = true
	return {"refused": false, "eng": eng, "eng_t": eng_t, "lock": lock,
		"held": float(m.a_freelen[k]) >= 0.0, "hash": m.state_hash()}

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var bindir := String(args[0])
	var N := int(args[1])
	var tier_name := String(args[2])
	var shard := int(args[3]) if args.size() > 3 else 0
	var nsh := int(args[4]) if args.size() > 4 else 1
	var tier: Array = VC.TIERS[tier_name]
	var t: Dictionary = load("res://main.gd").tape_load("res://takes/bug1.tape")
	cur = t["cur"]
	grp = t["grip"]
	n = cur.size()
	m = TL.new_sim()
	var files: Array = []
	for f in DirAccess.get_files_at(bindir):
		if f.begins_with("pre_") and f.ends_with(".bin"):
			files.append(f)
	files.sort()
	print("VFY CATCHES tape %d ticks, %d snapshots, tier %s N %d shard %d/%d" % [n, files.size(), tier_name, N, shard, nsh])
	print("  n  tick  k  taped        | null  ref(eng lock held) | P(eng) P(lock) P(held)  pattern")
	var t0 := Time.get_ticks_msec()
	for fi in files.size():
		if fi % nsh != shard:
			continue
		var f := FileAccess.open(bindir + "/" + files[fi], FileAccess.READ)
		var cat: Dictionary = f.get_var()
		f.close()
		var hs := {}
		var ref := {}
		for s in 3:
			ref = cont(cat, VC.TIERS["null"], "null")
			if bool(ref.get("refused", false)):
				break
			hs[int(ref["hash"])] = true
		if bool(ref.get("refused", false)):
			print("  %2d  %5d  refused on this build" % [int(cat["i"]), int(cat["tick"])])
			continue
		var ne := 0
		var nl := 0
		var nh := 0
		var line := ""
		for s in N:
			var r := cont(cat, tier, "vfycatch|%d|%s|%d" % [int(cat["tick"]), tier_name, s])
			if bool(r["eng"]):
				ne += 1
			if bool(r["lock"]):
				nl += 1
			if bool(r["held"]):
				nh += 1
			line += "L" if bool(r["lock"]) else ("e" if bool(r["eng"]) else ".")
		print("  %2d  %5d  %d  %-5s %+4d  | %d     %s %s %s        | %.2f   %.2f    %.2f   %s" % [
			int(cat["i"]), int(cat["tick"]), int(cat["k"]),
			"lock" if bool(cat["locked"]) else "part", int(cat["end"]), hs.size(),
			"1" if bool(ref["eng"]) else "0", "1" if bool(ref["lock"]) else "0",
			"1" if bool(ref["held"]) else "0",
			float(ne) / N, float(nl) / N, float(nh) / N, line])
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	m.free()
	quit(0)
