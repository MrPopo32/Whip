extends SceneTree
## THE CAMERA GATE. Five things about the camera that must stay true, checked
## the way this project checks everything else: by running the shipped code, not
## by reading it.
##
##   C1  the camera block in main.gd names no whip state          (source)
##   C2  the mouse-to-reach mapping is invariant to the camera    (real transform)
##   C3  the zoom blend never exceeds the rate cap                (the shipped blender)
##   C4  the framing holds over every trace the game can produce  (corpus + leaps)
##   C5  no path from the mouse to the world runs through the camera (source)
##
## EVERY NUMBER BELOW COMES OUT OF main.gd. C3 calls main.gd's own blender, C4
## calls main.gd's own law over main.gd's own volume table, and C2 calls
## main.gd's own cursor functions against a real Camera2D in a real viewport.
## A gate that re-implements the thing it is gating tests the copy.
##
## C1 AND C5 ARE THE STRUCTURAL ONES. A comment saying "do not read the whip
## here" is not enforcement; a gate that fails when a whip identifier appears
## between the camera's own markers is.
const MAIN := preload("res://main.gd")
const TL := preload("res://tests/tapelib.gd")
const LEAP := preload("res://tests/bot_leap.gd")
const PPM := 60.0
const VW := 1600.0 / PPM
const VH := 900.0 / PPM
const DT := 1.0 / 60.0

const MARK_A := "# ---- CAMERA: a pure function of the body and the level ----"
const MARK_B := "# ---- end camera ----"
# every name that would make the camera a function of the rope. a_pos/a_r are
# BEAM POSITIONS - level geometry, authored, static - and are deliberately not
# on this list; a_theta and a_freelen are what the rope is doing right now, and
# are.
const BANNED := ["a_theta", "a_freelen", "a_locked", "a_lockidx", "a_pinidx",
	"a_half", "a_ength", "a_minth", "a_prun", "a_paytick", "tip_speed", "taut",
	"slipping", "crack_flash", "pos[", "prv[", "cum_len", "grip_edge",
	"av_tension", "av_lidx", "av_over", "_wrap_tension", "_holds"]

const MARK_C := "# ---- CURSOR: the mouse reaches the world through a constant"
const MARK_D := "# ---- end cursor ----"
# THE TRAP, banned by name. Every one of these is a way for the camera to get
# back into the metres-per-pixel of a position-mapped control. "cam." and "cam_"
# cannot occur in prose about a camera; ".zoom" cannot occur in prose about
# zoom; and get_global_mouse_position is the original defect itself.
const CBANNED := ["get_global_mouse_position", "get_canvas_transform",
	"get_global_transform_with_canvas", "cam.", "cam_", "Camera2D", ".zoom",
	"CAM_"]

var cam: Camera2D
var m: Node2D
var frames := 0
var si := 0
# (zoom, window width) - the two doors the same bug comes through
var sweep := [[1.00, 1600], [1.25, 1600], [0.90, 1600], [0.80, 1600],
	[0.70, 1600], [1.00, 1280], [0.70, 1280], [1.00, 2400]]
var applied := false
var mrows: Array = []
var fails := 0

func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		# main.gd, for real, so C2 measures the SHIPPED cursor functions rather
		# than a copy of their arithmetic. save_path is redirected first and
		# save_enabled dropped straight after: _ready defers to _boot_session,
		# which turns saving on for an ordinary session, and this gate must not
		# put a run the player never played over the one slot.
		root.size = Vector2i(1600, 900)
		m = MAIN.new()
		m.external_drive = true
		m.save_path = "user://cam_gate_scratch.save"
		m.setup_sim()
		root.add_child(m)
		m.save_enabled = false
		if m.mouse_owned:
			m.mouse_owned = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		cam = m.cam
		return false
	if si < sweep.size():
		var z: float = float(sweep[si][0])
		var w: int = int(sweep[si][1])
		if not applied:
			root.size = Vector2i(w, int(round(w * 9.0 / 16.0)))
			cam.zoom = Vector2(z, z)
			cam.position = Vector2(1234.0, -567.0)   # somewhere non-trivial
			cam.force_update_scroll()
			applied = true
			return false                # let the engine write the transforms
		mrows.append(_measure(z, w))
		si += 1
		applied = false
		return false
	root.size = Vector2i(1600, 900)
	_c1()
	_c2()
	_c3()
	_c4()
	_c5()
	print("")
	if fails == 0:
		print("PASS  camera gate")
		quit(0)
	else:
		print("FAIL  %d of 5" % fails)
		quit(1)
	return true

func _measure(z: float, w: int) -> Array:
	# ONE HUNDRED PHYSICAL PIXELS OF MOUSE. That is the unit the player's hand
	# actually moves in, so it is the unit the invariance has to hold in.
	var stretch: float = root.get_final_transform().get_scale().x
	var mpp: float = m.cursor_m_per_px()          # m per DESIGN px, from main.gd
	var anchor: Vector2 = m.cursor_anchor_px()    # design px, from main.gd
	var d_design := Vector2(100.0 / stretch, 0.0)
	var b := Vector2(7.0, -3.0)
	# the shipped mapping, called by name
	var c0: Vector2 = m.cursor_of(b, anchor, anchor, mpp)
	var c1: Vector2 = m.cursor_of(b, anchor + d_design, anchor, mpp)
	# what it would have been through the camera: exactly what
	# get_global_mouse_position() computes for a node at the origin
	var inv := root.get_canvas_transform().affine_inverse()
	var p0 := anchor
	var p1 := anchor + d_design
	var was: float = (inv * p1 - inv * p0).x / PPM
	# and the rim of the reach circle, in physical pixels of desk
	var rim_px: float = MAIN.REACH / mpp * stretch
	# and what the rim WOULD have been, on the desk, through the camera
	var rim_was: float = MAIN.REACH / was * 100.0
	return [z, w, (c1 - c0).x, was, rim_px, root.size.x / (PPM * z), rim_was]

func _c1() -> void:
	var blk := _block(MARK_A, MARK_B)
	if blk == "":
		fails += 1
		print("C1 FAIL     main.gd has no camera block. Wrap the law in")
		print("            %s ... %s" % [MARK_A, MARK_B])
		return
	var hit: Array = []
	for w: String in BANNED:
		if blk.find(w) >= 0:
			hit.append(w)
	if hit.is_empty():
		print("C1 ok       the camera block names no whip state (%d lines, %d names"
			% [blk.split("\n").size(), BANNED.size()])
		print("            checked). The law is 3 static funcs: a static func cannot")
		print("            reach instance state, so the rope is not in scope to read.")
	else:
		fails += 1
		print("C1 FAIL     the camera reads the whip: %s" % str(hit))
		print("            Zoom or framing driven by the rope pumps with the rope,")
		print("            and rescaling mid-stroke regrades the wave.")

func _c2() -> void:
	var lo := 1e9
	var hi := -1e9
	var flo := 1e9
	var fhi := -1e9
	print("C2          100 PHYSICAL px of mouse, measured through a real Camera2D")
	print("            at a real window size, via main.gd's own cursor_of():")
	print("")
	var rlo := 1e9
	var rhi := -1e9
	print("            zoom  window   view      SHIPPED    reach rim     was    rim")
	for r: Array in mrows:
		lo = minf(lo, float(r[3])); hi = maxf(hi, float(r[3]))
		flo = minf(flo, float(r[2])); fhi = maxf(fhi, float(r[2]))
		rlo = minf(rlo, float(r[6])); rhi = maxf(rhi, float(r[6]))
		print("            %.2f  %5d  %6.2f m  %8.5f m  %4.0f px desk  %5.3f m %3.0f px"
			% [r[0], r[1], r[5], r[2], 2.0 * float(r[4]), r[3], 2.0 * float(r[6])])
	print("")
	if fhi - flo > 0.0:
		fails += 1
		print("C2 FAIL     the shipped mapping moved: %.9f .. %.9f m" % [flo, fhi])
		return
	print("C2 ok       %.5f m per 100 px at every zoom and every window size -"
		% flo)
	print("            spread exactly 0.0 m, not merely small. Through the camera")
	print("            the same sweep is %.3f..%.3f m, a %.0f%% swing in the"
		% [lo, hi, (hi / lo - 1.0) * 100.0])
	print("            sensitivity of a position-mapped control, and the reach")
	print("            rim - the whole control surface - would run from %.0f px of"
		% (2.0 * rlo))
	print("            desk to %.0f. It is %.0f px at every one of them here."
		% [2.0 * rhi, 2.0 * float(mrows[0][4])])

func _c3() -> void:
	# THE WORST TRANSITION THE AUTHORED TABLE CAN ASK FOR, run through main.gd's
	# own blender. On this level every volume is 1.00, so the authored worst case
	# is a rate of exactly zero; the cap is therefore also exercised against a
	# deliberately oversized 35% step, which is what it is FOR.
	var zmin := 9.0
	var zmax := 0.0
	var worst_pair := 0.0
	for i in MAIN.CAM_VOLS.size():
		var z: float = float(MAIN.CAM_VOLS[i][3])
		zmin = minf(zmin, z); zmax = maxf(zmax, z)
		if i > 0:
			var p: float = float(MAIN.CAM_VOLS[i - 1][3])
			worst_pair = maxf(worst_pair, absf(log(z / p)))
	var authored: float = zmax / maxf(zmin, 0.001)
	var step: float = maxf(authored, 1.35)
	var st := {"lz": 0.0, "vz": 0.0}
	var worst := 0.0
	var w300 := 0.0
	var hist: Array = []
	for i in 600:
		var z := MAIN.cam_zoom_step(st, step, DT)
		hist.append(log(z))
		worst = maxf(worst, absf(float(st["vz"])))
		if hist.size() > 18:
			w300 = maxf(w300, absf(float(hist[hist.size() - 1])
				- float(hist[hist.size() - 19])))
	var settle := 0
	for i in hist.size():
		if absf(float(hist[i]) - log(step)) < 0.01:
			settle = i
			break
	var bind: float = exp(MAIN.CAM_ZRATE / (0.368 * MAIN.CAM_WZ)) - 1.0
	if worst > MAIN.CAM_ZRATE + 1e-9:
		fails += 1
		print("C3 FAIL     zoom rate %.4f/s exceeded the %.2f cap"
			% [worst, MAIN.CAM_ZRATE])
		return
	if worst_pair > log(1.0 + bind) + 1e-9:
		fails += 1
		print("C3 FAIL     two adjacent volumes differ by %.0f%%, over the %.0f%% at"
			% [(exp(worst_pair) - 1.0) * 100.0, bind * 100.0])
		print("            which the cap binds and the blend stops being damped.")
		return
	print("C3 ok       the authored table's worst step is %.1f%% (adjacent worst"
		% ((authored - 1.0) * 100.0))
	print("            %.1f%%), so the authored zoom rate on this level is 0.000/s."
		% ((exp(worst_pair) - 1.0) * 100.0))
	print("            Forced to a %.0f%% step the shipped blender peaks at %.3f/s"
		% [(step - 1.0) * 100.0, worst])
	print("            (cap %.2f) and the most scale a 300 ms stroke ever sees is"
		% MAIN.CAM_ZRATE)
	print("            %.2f%% (budget 2.5%%). It takes %.1f s, which is what a rate"
		% [w300 * 100.0, settle / 60.0])
	print("            cap costs. No adjacent pair may differ by more than %.0f%%."
		% (bind * 100.0))

func _c4() -> void:
	var traces := _all_traces()
	var worst_edge := 1e9
	var worst_name := ""
	var tip_off := 0
	var n := 0
	var zrate := 0.0
	for T: Array in traces:
		var tr: Array = T[1]
		if tr.is_empty():
			continue
		var st: Dictionary = MAIN.cam_new(tr[0][0])
		for i in tr.size():
			var b: Vector2 = tr[i][0]
			var c: Vector2 = MAIN.cam_law(st, b, tr[i][1], DT)
			MAIN.cam_zoom_step(st, float(MAIN.CAM_VOLS[int(st["vi"])][3]), DT)
			zrate = maxf(zrate, absf(float(st["vz"])))
			var hw: float = VW * 0.5 / MAIN.cam_scale(st)
			var hh: float = VH * 0.5 / MAIN.cam_scale(st)
			var e: float = minf(hw - absf(b.x - c.x), hh - absf(b.y - c.y))
			if e < worst_edge:
				worst_edge = e
				worst_name = String(T[0])
			var tp: Vector2 = tr[i][2]
			if absf(tp.x - c.x) > hw or absf(tp.y - c.y) > hh:
				tip_off += 1
			n += 1
	if worst_edge < MAIN.CAM_EDGE or tip_off > 0:
		fails += 1
		print("C4 FAIL     body came %.2f m from an edge (%s); tip off screen %d ticks"
			% [worst_edge, worst_name, tip_off])
		return
	print("C4 ok       %d ticks over %d traces through main.gd's own law: the body"
		% [n, traces.size()])
	print("            never came closer than %.2f m to an edge (worst: %s,"
		% [worst_edge, worst_name])
	print("            floor %.1f), the tip was never off screen, and the zoom rate"
		% MAIN.CAM_EDGE)
	print("            over every one of them was %.4f/s." % zrate)

func _c5() -> void:
	var f := FileAccess.open("res://main.gd", FileAccess.READ)
	var src := f.get_as_text()
	# THE FILE-WIDE HALF, and it is the one that actually shuts the trap: the
	# original defect was one call, and it is now absent from the whole file.
	var whole: Array = []
	for ln in src.split("
"):
		var h: int = ln.find("#")
		var code: String = ln if h < 0 else ln.substr(0, h)
		if code.find("get_global_mouse_position") >= 0:
			whole.append("get_global_mouse_position")
			break
	var blk := _block(MARK_C, MARK_D)
	if blk == "":
		fails += 1
		print("C5 FAIL     main.gd has no cursor block. Wrap the mapping in")
		print("            %s ... %s" % [MARK_C, MARK_D])
		return
	var hit: Array = []
	for w: String in CBANNED:
		if blk.find(w) >= 0:
			hit.append(w)
	if not hit.is_empty() or not whole.is_empty():
		fails += 1
		print("C5 FAIL     the camera is back in the control: block %s, file %s"
			% [str(hit), str(whole)])
		print("            Mouse sensitivity would then move with the camera, and")
		print("            it would feel like the whip getting worse, not the")
		print("            camera changing.")
		return
	print("C5 ok       get_global_mouse_position appears nowhere in main.gd, and")
	print("            the cursor block (%d lines) names none of the %d ways back"
		% [blk.split("\n").size(), CBANNED.size()])
	print("            to the camera. The mapping is body + (px - anchor) * const.")

func _block(a_mark: String, b_mark: String) -> String:
	# CODE ONLY. The comments in these blocks explain the ban, so they name the
	# banned things - "there is no get_global_mouse_position anywhere in this
	# file" is the documentation of the fix, not the fix coming undone. Scanning
	# prose would make the gate fail on its own explanation and, worse, teach
	# whoever hit it to delete the explanation. Neither block contains a string
	# literal with a '#' in it, so a line-wise cut at the first '#' is exact.
	var f := FileAccess.open("res://main.gd", FileAccess.READ)
	var src := f.get_as_text()
	var a := src.find(a_mark)
	var b := src.find(b_mark)
	if a < 0 or b < 0 or b <= a:
		return ""
	var out := ""
	for ln in src.substr(a, b - a).split("\n"):
		var h: int = ln.find("#")
		out += (ln if h < 0 else ln.substr(0, h)) + "\n"
	return out

func _all_traces() -> Array:
	var traces: Array = []
	var d := DirAccess.open("res://tapes")
	var names: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".tape"):
			names.append(f)
	names.sort()
	for f in names:
		traces.append([f.get_basename(), _tape_trace("res://tapes/%s" % f)])
	for L: Array in [[7, 8], [8, 9], [9, 10]]:
		var tr := _leap_trace(int(L[0]), int(L[1]))
		if not tr.is_empty():
			traces.append(["leap %d-%d" % [L[0], L[1]], tr])
	return traces

func _tape_trace(p: String) -> Array:
	var t: Dictionary = MAIN.tape_load(p)
	var s := TL.new_sim()
	var tr: Array = []
	if not bool(t.get("ok", false)) or not s.restore(t["start"]):
		s.free()
		return tr
	var cur: PackedVector2Array = t["cur"]
	var grp: PackedByteArray = t["grip"]
	for i in cur.size():
		s.pending_reset = (grp[i] & 2) != 0
		s.step_tick(cur[i], (grp[i] & 1) != 0)
		tr.append([s.body_pos, s._body_vel(), s.pos[s.NP - 1]])
	s.free()
	return tr

func _leap_trace(ka: int, kb: int) -> Array:
	for hang in [1.6, 2.0, 2.4, 2.8, 3.2]:
		var s := LEAP.rig_level(ka, float(hang), 1.8, 0.0)
		for t in 30:
			s.step_tick(s.body_pos, true)
		if s.a_freelen[ka] < 0.0:
			s.free(); continue
		var st := LEAP.leap_begin(s, ka, kb)
		var prev: Vector2 = s.body_pos
		var tr: Array = []
		var guard := 0
		while st["phase"] != "fail" and st["phase"] != "hang" and guard < 2000:
			var cg := LEAP.leap_step(s, st, prev)
			prev = s.body_pos
			s.step_tick(cg[0], cg[1])
			guard += 1
			tr.append([s.body_pos, s._body_vel(), s.pos[s.NP - 1]])
		var held: bool = String(st["phase"]) == "hang"
		if held:
			for t in 150:
				var cg2 := LEAP.leap_step(s, st, prev)
				prev = s.body_pos
				s.step_tick(cg2[0], cg2[1])
				tr.append([s.body_pos, s._body_vel(), s.pos[s.NP - 1]])
				if s.a_freelen[kb] < 0.0 or s.grounded:
					held = false; break
		s.free()
		if held:
			return tr
	return []
