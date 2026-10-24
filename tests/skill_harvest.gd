extends SceneTree
## HARVEST THE PLAYER'S CATCHES, 60 TICKS EARLY, ON THE BUILD THAT RECORDED THEM.
##
## takes/bug1.tape was recorded on 2026-08-31 17:10, nine minutes after commit
## 11f8bd3, and on HEAD it diverges after ~tick 1830 (README, "Input tapes"):
## a straight replay on HEAD sees 5 catches where the player made 30. So this
## script is meant to run INSIDE AN EXPORTED TREE of the recording build
## (git archive 11f8bd3), where the tape replays exactly - and it proves that
## as it goes, by comparing state_hash() to the tape's own checkpoint hashes
## every TAPE_CHECK ticks and refusing to write anything past a divergence.
##
## For every tick on which an anchor ENGAGES it writes <outdir>/pre_NN.bin:
##   tick   the catch tick c            k      the anchor
##   pre    PRE (60)                    snap   snapshot() as it stood BEFORE
##                                             tick c - PRE was stepped
##   body   body_pos before each tick c-PRE .. c+POST, i.e. the body the
##          recorded cursor of that tick was read against (main.gd maps the
##          mouse as body + px * m_per_px, so the hand the player moved was a
##          body-relative one; a continuation on another build must replay
##          it relative to ITS body)
##   locked / end / how   what happened next on THIS build: did the wrap lock,
##          on which tick relative to c did the engagement end, and was it
##          the hand opening or the wrap ending
## tests/skill_catch.gd (HEAD) restores these and continues them under the
## hand-noise model. Nothing here enters the tree or writes a save.
##
##   godot --headless --path <exported tree> -s res://tests/skill_harvest.gd -- takes/bug1.tape <outdir>
const PRE := 60
const POST := 90

func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var path: String = args[0]
	var outdir: String = args[1]
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	var MAIN := load("res://main.gd")
	var t: Dictionary = MAIN.tape_load(path)
	if not bool(t.get("ok", false)):
		print("cannot load %s: %s" % [path, t.get("err", "")])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(outdir)
	var m: Node2D = MAIN.new()
	m.external_drive = true
	m.setup_sim()
	if not m.restore(t["start"]):
		print("start state refused on this build")
		quit(1)
		return
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	var chk: PackedInt64Array = t["chk"]
	var n := cur.size()
	var body := PackedVector2Array()
	body.resize(n)
	var ring: Array = []
	ring.resize(PRE + 1)
	var na: int = m.a_pos.size()
	var was := PackedByteArray()
	was.resize(na)
	var catches: Array = []
	var open_of := {}                  # k -> index of the catch still engaged
	var j := 0
	var diverged := -1
	var checked := 0
	for i in n:
		ring[i % (PRE + 1)] = m.snapshot()
		body[i] = m.body_pos
		m.pending_reset = (grp[i] & 2) != 0
		m.step_tick(cur[i], (grp[i] & 1) != 0)
		if (i + 1) % int(m.TAPE_CHECK) == 0 and j < chk.size():
			checked += 1
			if int(m.state_hash()) != int(chk[j]):
				diverged = i + 1
				print("DIVERGED at tick %d (checkpoint %d): this is not the recording build. Nothing written." % [i + 1, j])
				break
			j += 1
		for k in na:
			var e := 1 if float(m.a_freelen[k]) >= 0.0 else 0
			if e == 1 and was[k] == 0:
				catches.append({"tick": i, "k": k, "pre": PRE,
					"snap": ring[(i - PRE) % (PRE + 1)] if i >= PRE else {},
					"locked": false, "end": -1, "how": "held",
					"grip_at": grp[i] & 1})
				open_of[k] = catches.size() - 1
			if e == 1 and open_of.has(k) and int(m.a_locked[k]) == 1:
				catches[open_of[k]]["locked"] = true
			if e == 0 and was[k] == 1 and open_of.has(k):
				var c: Dictionary = catches[open_of[k]]
				c["end"] = i - int(c["tick"])
				c["how"] = "hand opened" if (grp[i] & 1) == 0 else "wrap ended"
				open_of.erase(k)
			was[k] = e
	if diverged >= 0:
		m.free()
		quit(1)
		return
	print("REPLAY EXACT: %d ticks, %d checkpoints matched, final hash %d (tape says %d)" % [
		n, checked, m.state_hash(), int(t.get("h", 0))])
	print("  n  tick   k  locked  end(+ticks)  how")
	var written := 0
	var nlock := 0
	for ci in catches.size():
		var c: Dictionary = catches[ci]
		var tk := int(c["tick"])
		print("  %2d  %5d  %d  %-6s  %5d  %s" % [ci, tk, int(c["k"]),
			str(bool(c["locked"])), int(c["end"]), String(c["how"])])
		if bool(c["locked"]):
			nlock += 1
		if tk < PRE:
			continue
		var b := PackedVector2Array()
		for i in range(tk - PRE, mini(n, tk + POST + 1)):
			b.append(body[i])
		var f := FileAccess.open("%s/pre_%02d.bin" % [outdir, ci], FileAccess.WRITE)
		f.store_var({"i": ci, "tick": tk, "k": int(c["k"]), "pre": PRE,
			"snap": c["snap"], "body": b, "locked": bool(c["locked"]),
			"end": int(c["end"]), "how": String(c["how"])})
		f.close()
		written += 1
	print("%d catches, %d locked on this build; %d snapshots written to %s" % [
		catches.size(), nlock, written, outdir])
	m.free()
	quit(0)
