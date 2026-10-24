extends SceneTree
## MOVE 1 - THE STANDING CATCH, AS A 2D MAP (and what a standing catch can pump).
##
## Per cell (dx ahead of the feet, dy UP from the floor, beam radius r), one
## beam over the lab floor (tests/climb_stand_lib.gd):
##
##  1. COARSE: the 108-stroke grid (climb_stand_lib.grid108), noise-free.
##     Without a pull the stroke length is a no-op (the aim is a1 from the
##     end of the windup on, whatever sd says), so the 36 no-pull entries are
##     18 shapes each counted three times; they are thrown once and counted
##     three times, and the fraction is reported over the 108 AND over the 72
##     distinct shapes.
##  2. FINE: the 3x-finer 27-stroke lattice around up to 6 coarse winners
##     (spread through the winner list); 9 for a no-pull winner (sd is a
##     no-op). That is the second width of the stroke search.
##  3. SELECT then CERTIFY: every searched winner is scored by its SUPPORT -
##     the fraction of its own fine lattice that locks (a stroke in a solid
##     block scores 1.0). The top 2 are replayed N_SEL times under the
##     trackpad tier; the better one is then replayed N_CERT times under a
##     FRESH seed tag. The P reported is the held-out one, so picking the
##     best of two does not inflate it.
##  4. BASIN, noise-free, around the certified stroke, at TWO WIDTHS in one
##     ladder so a basin that fills the narrow window is seen to: cursor
##     offset along x and y (+/-25..300 mm), stroke angle a1 (+/-0.02..0.24
##     rad), first press shifted (+/-1..16 ticks). Per ladder: the solid
##     block containing 0, whether it touches the ladder's end, and whether
##     any rung OUTSIDE the block locks (fragmented).
##  5. LUCK LADDER, when the held-out P is 0.25..0.75: the a1 ladder again
##     but N_LAD noisy throws per rung. A skill rises toward the winner.
##  6. PUMP: the certified stroke replayed noise-free and, if it locks, pumped
##     flat out with tests/bot_pump.gd's servo for PUMP_T ticks: true swing
##     amplitude about the beam, ticks with the body on the floor, the feet's
##     height, the peak tangential speed.
##
## One JSON per cell into <outdir>, skipped if present (resumable). Shard by
## cell index. The sim has no RNG; the noise is seeded per (tag, sample).
##
##   godot --headless --path . -s res://tests/climb_stand_map.gd -- <r> <outdir> <shard> <nshards> [dxlist] [dylist]
const CL := preload("res://tests/climb_stand_lib.gd")
const HN := preload("res://tests/hand_noise.gd")

const N_SEL := 20
const N_CERT := 40
const N_LAD := 10
const PUMP_T := 900
const MAX_FINE := 6
const OFF_MM := [-300, -225, -150, -75, -50, -25, 0, 25, 50, 75, 150, 225, 300]
const DA1 := [-0.24, -0.18, -0.12, -0.09, -0.06, -0.04, -0.02, 0.0, 0.02, 0.04,
	0.06, 0.09, 0.12, 0.18, 0.24]
const DPR := [-16, -12, -8, -6, -4, -2, -1, 0, 1, 2, 4, 6, 8, 12, 16]
const LAD := [-0.12, -0.06, -0.03, 0.0, 0.03, 0.06, 0.12]

static func block(rungs: Array, ok: Array) -> Dictionary:
	# the contiguous run of locking rungs containing the centre (value 0)
	var ic := rungs.find(0) if rungs.find(0) >= 0 else rungs.find(0.0)
	if ic < 0 or not bool(ok[ic]):
		return {"lo": null, "hi": null, "centre": false, "edge": false,
			"frag": ok.has(true), "n_out": ok.count(true)}
	var lo := ic
	while lo - 1 >= 0 and bool(ok[lo - 1]):
		lo -= 1
	var hi := ic
	while hi + 1 < ok.size() and bool(ok[hi + 1]):
		hi += 1
	var n_out := 0
	for i in ok.size():
		if (i < lo or i > hi) and bool(ok[i]):
			n_out += 1
	return {"lo": rungs[lo], "hi": rungs[hi], "centre": true,
		"edge": lo == 0 or hi == ok.size() - 1, "frag": n_out > 0,
		"n_out": n_out}

func noisy(b: RefCounted, c: Dictionary, tag: String, n: int) -> Dictionary:
	var lk := 0
	var ca := 0
	for s in n:
		var r: Dictionary = b.throw(c, HN.new("trackpad", tag, s))
		if bool(r["caught"]): ca += 1
		if bool(r["lock"]): lk += 1
	return {"n": n, "lock": lk, "caught": ca, "p": float(lk) / n}

static func sdesc(c: Dictionary) -> Dictionary:
	return {"a0_pi": float(c["a0"]) / PI, "a1_pi": float(c["a1"]) / PI,
		"sd": int(c["sd"]), "pull": bool(c["pull"]), "w": int(c["w"])}

func do_cell(dx: float, dy: float, r: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var b: RefCounted = CL.new(dx, dy, r)
	var res := {"dx": dx, "dy": dy, "r": r}
	# 1. coarse -----------------------------------------------------------
	var memo := {}
	var winners: Array = []
	var nlock108 := 0
	var ncatch108 := 0
	var nlock72 := 0
	var feet: Array = []
	for c: Dictionary in CL.grid108():
		var key := CL.key_of(c) if bool(c["pull"]) else "%.5f/%.5f/np" % [
			float(c["a0"]), float(c["a1"])]
		var first := not memo.has(key)
		if first:
			memo[key] = b.throw_fast(c)
		var rr: Dictionary = memo[key]
		if bool(rr["caught"]): ncatch108 += 1
		if bool(rr["lock"]):
			nlock108 += 1
			if first:
				nlock72 += 1
				var cc := c.duplicate()
				cc["key"] = key
				winners.append(cc)
				feet.append([float(rr["body_up"]), float(rr["tether"])])
	res["coarse"] = {"lock108": nlock108, "catch108": ncatch108,
		"lock72": nlock72, "distinct": memo.size()}
	# 2. fine -------------------------------------------------------------
	var fine_n := 0
	var fine_lock := 0
	var support: Array = []
	var fmemo := {}
	var picks: Array = []
	if winners.size() <= MAX_FINE:
		picks = winners
	else:
		for i in MAX_FINE:
			picks.append(winners[int(round(float(i) * (winners.size() - 1) / (MAX_FINE - 1)))])
	for w: Dictionary in picks:
		var lat := CL.fine27(w)
		var nl := 0
		var nn := 0
		for c: Dictionary in lat:
			var f: Array = c["fine"]
			if not bool(c["pull"]) and int(f[2]) != 0:
				continue                    # sd is a no-op without a pull
			var key := CL.key_of(c) if bool(c["pull"]) else "%.5f/%.5f/np" % [
				float(c["a0"]), float(c["a1"])]
			if not fmemo.has(key):
				fmemo[key] = b.throw_fast(c)
				fine_n += 1
				if bool(fmemo[key]["lock"]): fine_lock += 1
			nn += 1
			if bool(fmemo[key]["lock"]): nl += 1
		support.append({"c": w, "sup": float(nl) / nn, "n": nn, "nl": nl})
	res["fine"] = {"n": fine_n, "lock": fine_lock, "centres": picks.size(),
		"of_winners": winners.size()}
	if winners.is_empty():
		res["best"] = {}
		res["secs"] = (Time.get_ticks_msec() - t0) / 1000.0
		b.free_sim()
		return res
	# 3. select + certify -------------------------------------------------
	support.sort_custom(func(a, bb): return float(a["sup"]) > float(bb["sup"]))
	var cand: Array = support.slice(0, 2)
	var sel: Array = []
	for s: Dictionary in cand:
		var c: Dictionary = s["c"]
		var tag := "stand/%.2f/%.2f/%.2f/%s" % [dx, dy, r, String(c["key"])]
		var nz := noisy(b, c, "sel/" + tag, N_SEL)
		sel.append({"stroke": sdesc(c), "sup": s["sup"], "p_sel": nz["p"],
			"c": c, "tag": tag})
	sel.sort_custom(func(a, bb): return float(a["p_sel"]) > float(bb["p_sel"]))
	var best: Dictionary = sel[0]
	var bc: Dictionary = best["c"]
	var cert := noisy(b, bc, "cert/" + String(best["tag"]), N_CERT)
	# the instrument's null on this very stroke: three null-tier full throws
	# and the fast path must give one hash
	var hs := {}
	var fr: Dictionary = b.throw_fast(bc)
	hs[int(fr["hash"])] = true
	for s in 3:
		hs[int(b.throw(bc, HN.new("null", "null", s))["hash"])] = true
	var sels: Array = []
	for s: Dictionary in sel:
		sels.append({"stroke": s["stroke"], "sup": s["sup"], "p_sel": s["p_sel"]})
	res["select"] = sels
	res["best"] = {"stroke": sdesc(bc), "sup": best["sup"], "p_sel": best["p_sel"],
		"cert": cert, "null_hashes": hs.size(), "free_lock": bool(fr["lock"]),
		"feet_up": float(fr["body_up"]), "tether": float(fr["tether"]),
		"feet_x": float(fr["feet_x"]), "g0": int(fr["g0"]), "et": int(fr["et"])}
	# 4. basin ------------------------------------------------------------
	var bas := {}
	for ax in ["x", "y"]:
		var ok: Array = []
		for mm in OFF_MM:
			var o := Vector2(float(mm) / 1000.0, 0.0) if ax == "x" \
				else Vector2(0.0, float(mm) / 1000.0)
			ok.append(bool(b.throw_fast(bc, o)["lock"]))
		bas["off_" + ax] = {"ok": ok, "blk": block(OFF_MM, ok)}
	var oka: Array = []
	for d in DA1:
		var c2 := bc.duplicate()
		c2["a1"] = float(bc["a1"]) + float(d)
		oka.append(bool(b.throw_fast(c2)["lock"]))
	bas["a1"] = {"ok": oka, "blk": block(DA1, oka)}
	var okp: Array = []
	for d in DPR:
		okp.append(bool(b.throw_fast(bc, Vector2.ZERO, int(d))["lock"]))
	bas["press"] = {"ok": okp, "blk": block(DPR, okp)}
	var ok2 := 0
	for ox in [-75, 75]:
		for oy in [-75, 75]:
			if bool(b.throw_fast(bc, Vector2(ox / 1000.0, oy / 1000.0))["lock"]):
				ok2 += 1
	bas["diag75"] = ok2
	res["basin"] = bas
	# 5. luck ladder ------------------------------------------------------
	var pc := float(cert["p"])
	if pc >= 0.25 and pc <= 0.75:
		var lad: Array = []
		for d in LAD:
			var c3 := bc.duplicate()
			c3["a1"] = float(bc["a1"]) + float(d)
			lad.append(noisy(b, c3, "lad/%s/%.2f" % [String(best["tag"]), d], N_LAD)["p"])
		res["ladder"] = lad
	# 6. pump -------------------------------------------------------------
	var pr: Dictionary = b.throw_fast(bc)
	if bool(pr["lock"]):
		res["pump"] = b.pump_after(PUMP_T)
		res["pump"]["feet_up0"] = float(pr["body_up"])
		res["pump"]["tether0"] = float(pr["tether"])
	res["secs"] = (Time.get_ticks_msec() - t0) / 1000.0
	b.free_sim()
	return res

func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var r := float(a[0])
	var outdir := String(a[1])
	var shard := int(a[2])
	var ns := int(a[3])
	var dxs: Array = []
	var dys: Array = []
	if a.size() > 4 and String(a[4]) != "-":
		for v in String(a[4]).split(","): dxs.append(float(v))
	else:
		for i in 12: dxs.append(0.5 + 0.5 * i)
	if a.size() > 5 and String(a[5]) != "-":
		for v in String(a[5]).split(","): dys.append(float(v))
	else:
		for j in 15: dys.append(0.5 + 0.25 * j)
	var idx := -1
	for dy in dys:
		for dx in dxs:
			idx += 1
			if idx % ns != shard:
				continue
			var fn := "%s/r%03d_dx%03d_dy%03d.json" % [outdir, int(round(r * 100)),
				int(round(float(dx) * 100)), int(round(float(dy) * 100))]
			if FileAccess.file_exists(fn):
				continue
			var res := do_cell(float(dx), float(dy), r)
			var f := FileAccess.open(fn, FileAccess.WRITE)
			f.store_string(JSON.stringify(res))
			f.close()
			var bs: Dictionary = res["best"]
			print("r %.2f dx %.2f dy %.2f  coarse %d/108  fine %d/%d  P %s  %.0fs" % [
				r, dx, dy, int(res["coarse"]["lock108"]), int(res["fine"]["lock"]),
				int(res["fine"]["n"]),
				"-" if bs.is_empty() else "%d/%d" % [int(bs["cert"]["lock"]), int(bs["cert"]["n"])],
				float(res["secs"])])
	quit(0)
