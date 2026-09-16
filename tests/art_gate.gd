extends SceneTree
## THE ART GATE. Art is a picture: it shows up only in a real windowed session,
## it feeds nothing back, no probe ever sees it, and it does not get to hide
## the game's instruments. Seven checkable claims, checked the way the audio
## gate checks its own (tests/aud_gate.gd): by running the shipped code.
##
##   godot --headless --path . -s res://tests/art_gate.gd        A1 A2 A3 + boot cost
##   godot --path . -s res://tests/art_gate.gd -- [out=DIR]      all of A1..A7 (a window,
##                                                               on screen a few seconds)
##   godot --headless --path . -s res://tests/art_gate.gd -- search
##                                   re-search the A5 catch stroke (prints new constants)
##
## A1 INERT HEADLESS   a probe builds steps_art with new() and never enters the
##                     tree: art_on false, no live instance, 0 nodes, 0 children -
##                     while the scene itself authors N nodes under Art.
## A2 INERT PERIOD     hashrun's session on steps_art with the art layer FORCED
##                     on (the instance built and attached to the sim) hashes the
##                     same as with it off, and the same as plain steps; and the
##                     traverse's golden hash is untouched by the same call.
## A3 SAME WORLD       steps_art fingerprints 3144857459313072037, steps' own
##                     number, with every array identical (level_fidelity F1's
##                     comparison) - the art reached none of them.
## A4 BYTE-IDENTICAL   greybox = true leaves the rendered frame of steps, and of
##                     crag.tscn, byte-identical to HEAD 1a6d1ed's: the md5 of
##                     tests/art_frame.gd's picture, taken before this change.
## A8 REFUSED BY NAME  a Sprite2D parented to Ground - on a vertex, the silent
##                     case - refuses the level and says art goes under Art
## A9 CLAMPED          a z_index 5 sprite under Art is clamped to 0 and a
##                     CanvasLayer at layer 2 to -1; the authored parallax is not
## A10 NOT BLIND       greybox = false on a scene with no Art node keeps the
##                     greybox on; steps_art's own greybox = false is honoured
## A5 ART SHOWS UP     a frame of steps_art has the rock texture under the floor,
##                     the beam sprite on the beam, the skyline in the sky, the
##                     clear colour where nothing is, the body over it all - and
##                     on a searched catch the GREEN RING is drawn over the
##                     sprite's plate (pixels sampled, and named).
## A6 PARALLAX         the camera moved 600 px: the far layer moved 180 (0.3x),
##                     the mid layer 360 (0.6x), the world 600. Read off the
##                     ParallaxLayer nodes and off the pixels (the far peak).
## A7 COST             a windowed frame of steps_art with the art layer shown
##                     against hidden: CPU + GPU render time per frame, and the
##                     one-off cost of building the layer at boot.
const MAIN := preload("res://main.gd")
const LIB := preload("res://tests/level_lib.gd")
const PPM := 60.0
const DT := 1.0 / 60.0
const GOLDEN := 2762505307938286422
const STEPS_FP := 3144857459313072037
# tests/art_frame.gd -- level=steps ticks=60 and level=crag.tscn ticks=60, on
# main.gd at 1a6d1ed (before the art layer existed), this machine, 3 of 3 runs
# each. The same command must print the same md5 after every change to _draw
# that claims to leave the default picture alone. A different GPU or font
# rasteriser is a different picture; if A4 fails on another machine with the
# frames looking identical, re-take these two numbers there and say so.
const HEAD_MD5 := {"steps": "fc7de3e8a733c941bcc33ca41d335f37",
	"crag.tscn": "9707c2f48d53452be10fffb3726cb0dc"}
# THE A5 CATCH: the first stroke of the 108-stroke grid (tests/lab_shots.gd's
# throw_shots, body teleported to stand `lead` m before the beam, hand held
# back, no crawl) that LOCKED on steps_art's A0 BEAM. Found by `-- search`;
# rerun it if the sim changes and this stroke stops locking.
const CATCH := {"k": 0, "lead": 1.6, "a0": PI * 1.10, "a1": -PI * 0.42,
	"sd": 9, "pull": false, "w": 120, "cue": "wrap"}   # stroke 19 of 108, 13.3 s
const CLEAR := Color(0.09, 0.1, 0.13)          # project.godot's clear colour
const GREEN := Color(0.3, 0.9, 0.45)            # _draw's "it holds"

var fails := 0
var frames := 0
var m: Node2D
var steps: Array[Callable] = []
var si := 0
var outdir := "user://art_gate"
var catch_hang := {}
var far_pos: Array = []
var peak_x: Array = []
var cost := {}

func _ok(name: String, cond: bool, detail := "") -> void:
	if not cond:
		fails += 1
	print("  %s  %s%s" % ["ok  " if cond else "FAIL", name,
		("   " + detail) if detail != "" else ""])

# ============================================================== headless ==
func _a1() -> void:
	var s := LIB.new_sim("steps_art")
	var authored := _authored()
	_ok("A1 headless: art_on %s, live instance %s, %d art nodes, %d children; the scene authors %d nodes under Art and %d under anchors"
		% [str(s.art_on), "none" if s.art_root == null else "PRESENT", s.art_node_count(),
		s.get_child_count(), authored[0], authored[1]],
		not bool(s.art_on) and s.art_root == null and s.art_node_count() == 0
		and s.get_child_count() == 0 and authored[0] > 0 and authored[1] > 0)
	s.free()

func _authored() -> Array:
	# what the scene carries, counted on a throwaway instance: nodes under
	# Art, and nodes under the anchors' markers
	var ps: PackedScene = load(MAIN.level_scene_path("steps_art"))
	var r: Node = ps.instantiate()
	var art := r.get_node_or_null("Art")
	var n_art: int = 0 if art == null else MAIN._art_count(art) - 1
	var n_anc := 0
	var an := r.get_node_or_null("Anchors")
	if an != null:
		for c in an.get_children():
			n_anc += MAIN._art_count(c) - 1
	r.free()
	return [n_art, n_anc]

static func session(s: Node2D) -> int:
	# hashrun.gd's 900 ticks, verbatim
	for t in 900:
		var b: Vector2 = s.body_pos
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
			tgt = b + Vector2(0.8, -0.8); grip = t > 420
		else:
			var p2 := float(t) * 0.05
			tgt = b + Vector2(cos(p2), -0.6); grip = true
		s.step_tick(tgt, grip)
	return s.state_hash()

func _a2() -> void:
	var h := {}
	var n_on := 0
	for it: Array in [["steps_art", true], ["steps_art", false], ["steps", false], ["", true]]:
		var s := LIB.new_sim(String(it[0]))
		if bool(it[1]):
			var t0 := Time.get_ticks_usec()
			s._art_build()              # forced: the headless test is in _ready, not here
			cost["boot_us_" + ("traverse" if String(it[0]) == "" else String(it[0]))] = Time.get_ticks_usec() - t0
			if String(it[0]) == "steps_art":
				n_on = s.art_node_count()
		h["%s/%s" % [it[0] if it[0] != "" else "traverse", "on" if it[1] else "off"]] = session(s)
		s.free()
	var same: bool = int(h["steps_art/on"]) == int(h["steps_art/off"]) \
		and int(h["steps_art/off"]) == int(h["steps/off"])
	_ok("A2 900 ticks on steps_art with the art layer forced ON (%d live nodes, greybox read) hash %d; OFF %d; plain steps %d"
		% [n_on, int(h["steps_art/on"]), int(h["steps_art/off"]), int(h["steps/off"])],
		same and n_on > 0)
	_ok("A2 the traverse with _art_build called still hashes %d (golden %d): a built-in level builds no layer"
		% [int(h["traverse/on"]), GOLDEN], int(h["traverse/on"]) == GOLDEN)

func _a3() -> void:
	var a := LIB.new_sim("steps")
	var b := LIB.new_sim("steps_art")
	var bad: Array[String] = []
	if String(b.level_err) != "":
		bad.append("steps_art refused: " + String(b.level_err))
	if int(a.level_fingerprint()) != STEPS_FP:
		bad.append("steps fingerprints %d, not %d - steps.tscn moved" % [a.level_fingerprint(), STEPS_FP])
	if int(b.level_fingerprint()) != int(a.level_fingerprint()):
		bad.append("fingerprint %d vs %d" % [b.level_fingerprint(), a.level_fingerprint()])
	for nm: String in ["t_a", "t_b", "t_n", "t_lo", "t_hi", "t_arc_c", "t_arc_ang", "a_pos"]:
		bad.append_array(_cmp_v2(nm, a.get(nm), b.get(nm)))
	for nm: String in ["t_deep", "t_arc_r", "a_r"]:
		bad.append_array(_cmp_f(nm, a.get(nm), b.get(nm)))
	if a.a_jam != b.a_jam:
		bad.append("a_jam differ")
	if a.a_name != b.a_name:
		bad.append("a_name differ")
	if a.spawn != b.spawn:
		bad.append("spawn differ")
	for nm: String in ["goal_x", "goal_y", "world_bottom"]:
		if float(a.get(nm)) != float(b.get(nm)):
			bad.append("%s %.9f vs %.9f" % [nm, float(a.get(nm)), float(b.get(nm))])
	if str(a.cam_vols) != str(b.cam_vols):
		bad.append("camera table differs")
	if a.bd_poly.size() != b.bd_poly.size():
		bad.append("backdrop %d vs %d polygons" % [a.bd_poly.size(), b.bd_poly.size()])
	else:
		for j in a.bd_poly.size():
			bad.append_array(_cmp_v2("bd_poly[%d]" % j, a.bd_poly[j], b.bd_poly[j]))
			if a.bd_col[j] != b.bd_col[j]:
				bad.append("bd_col[%d] differ" % j)
	_ok("A3 steps_art fingerprints %d = steps (%d): %d segments, %d arcs, %d anchors, %d volumes, %d backdrop polygons, %d per-element checks, all identical%s"
		% [b.level_fingerprint(), a.level_fingerprint(), b.t_a.size(), b.t_arc_c.size(),
		b.a_pos.size(), b.cam_vols.size(), b.bd_poly.size(), 11 + b.bd_poly.size(),
		"" if bad.is_empty() else ("  DIFFER: " + ", ".join(PackedStringArray(bad)))],
		bad.is_empty())
	a.free(); b.free()

# =========================================== the three rules, enforced ==
# A8-A10 build their fixtures from the real steps_art scene, mutated in memory
# and saved to user://, which level_scene_path accepts. Nothing lands in the
# repo, and a crashed run leaves only scratch. Each has its CONTROL - the
# unmutated scene through the same path - so a gate that refused everything,
# or clamped everything, would fail its own control.
const FIX := "user://art_gate_fixture_%d.tscn"

func _fixture(idx: int, mutate: Callable) -> String:
	var ps: PackedScene = ResourceLoader.load("res://levels/steps_art.tscn", "PackedScene")
	var root: Node = ps.instantiate()
	mutate.call(root)
	var out := PackedScene.new()
	out.pack(root)
	var path := FIX % idx
	ResourceSaver.save(out, path)
	root.free()
	return path

func _fixture_drop(idx: int) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIX % idx))

func _a8() -> void:
	# A SPRITE UNDER GROUND IS REFUSED BY NAME. Before this rule it was read as
	# a fillet: off a vertex, refused with a message about corners; on one,
	# silently taken as radius 0 and the fingerprint moved.
	var path := _fixture(8, func(root: Node) -> void:
		var sp := Sprite2D.new()
		sp.name = "stray_sprite"
		sp.position = Vector2(360, 0)         # exactly on a Ground vertex: the silent case
		root.get_node("Ground").add_child(sp)
		sp.owner = root)
	var s := LIB.new_sim(path)
	var refused: String = String(s.level_err)
	s.free()
	var c := LIB.new_sim("steps_art")
	var control: String = String(c.level_err)
	c.free()
	_fixture_drop(8)
	_ok("A8 a Sprite2D under Ground refuses the level and says where art goes: %s" % refused.left(96),
		refused.contains("not a fillet marker") and refused.contains("stray_sprite") and control == "",
		"" if control == "" else "CONTROL: steps_art itself was refused: " + control)

func _a9() -> void:
	# A POSITIVE z_index UNDER ART, OR A CanvasLayer AT 0 OR ABOVE, IS CLAMPED.
	var path := _fixture(9, func(root: Node) -> void:
		var art: Node = root.get_node("Art")
		var sp := Sprite2D.new()
		sp.name = "over_the_rope"
		sp.z_index = 5
		art.add_child(sp); sp.owner = root
		var cl := CanvasLayer.new()
		cl.name = "over_the_hud"
		cl.layer = 2
		art.add_child(cl); cl.owner = root)
	var s := LIB.new_sim(path)
	s._art_build()
	var sp: CanvasItem = s.art_root.get_node_or_null("Art/over_the_rope")
	var cl: CanvasLayer = s.art_root.get_node_or_null("Art/over_the_hud")
	var par: CanvasLayer = s.art_root.get_node_or_null("Art/Parallax")
	# Read everything BEFORE the sim is freed: a freed reference compares equal
	# to null in Godot 4, so a liveness check after free() is a check of nothing.
	var found := sp != null and cl != null and par != null
	var z: int = sp.z_index if sp != null else 99
	var l: int = cl.layer if cl != null else 99
	var pl: int = par.layer if par != null else 99
	s.free()
	_fixture_drop(9)
	_ok("A9 under Art a z_index 5 sprite is clamped to %d and a layer-2 CanvasLayer to %d; the authored Parallax stays at %d" % [z, l, pl],
		found and z == 0 and l == -1 and pl < 0,
		"" if found else "a fixture node was not found under the live Art")

func _a10() -> void:
	# greybox = false WITH NO ART NODE KEEPS THE GREY WORLD ON.
	var path := _fixture(10, func(root: Node) -> void:
		root.set("greybox", false)
		var art: Node = root.get_node("Art")
		root.remove_child(art)
		art.free())
	var s := LIB.new_sim(path)
	s._art_build()
	var blind_kept: bool = bool(s.greybox)
	s.free()
	var c := LIB.new_sim("steps_art")
	c._art_build()
	var dressed_off: bool = not bool(c.greybox)
	c.free()
	_fixture_drop(10)
	_ok("A10 greybox=false with no Art node: greybox read back %s (kept on); steps_art with its Art: greybox %s (honoured)"
		% [str(blind_kept), str(not dressed_off)],
		blind_kept and dressed_off)

static func _cmp_v2(nm: String, A: PackedVector2Array, B: PackedVector2Array) -> Array[String]:
	if A.size() != B.size():
		return ["%s: %d vs %d elements" % [nm, A.size(), B.size()]]
	for i in A.size():
		if A[i].x != B[i].x or A[i].y != B[i].y:
			return ["%s[%d] differs" % [nm, i]]
	return []

static func _cmp_f(nm: String, A: PackedFloat32Array, B: PackedFloat32Array) -> Array[String]:
	if A.size() != B.size():
		return ["%s: %d vs %d elements" % [nm, A.size(), B.size()]]
	for i in A.size():
		if A[i] != B[i] and not (is_inf(A[i]) and is_inf(B[i])):
			return ["%s[%d] differs" % [nm, i]]
	return []

# ------------------------------------------------------------- the catch --
static func stand_at(s: Node2D, x: float, a0: float) -> void:
	s.teleport(Vector2(x, -s.BODY_R))
	for t in 90:
		s.step_tick(s.body_pos + Vector2(cos(a0), sin(a0)) * s.REACH, false)

static func touching(s: Node2D, k: int) -> bool:
	for i in s.NP:
		if (s.pos[i] - s.a_pos[k]).length() < s.a_r[k] + s.p_rad[i] + s.wrap_shell + 0.02:
			return true
	return false

static func throw_shots(lvl: String, c: Dictionary) -> Dictionary:
	# tests/lab_shots.gd's throw_shots, on any level: stand `lead` m before the
	# beam, wind up, stroke, close the hand on the cue; the catch state and the
	# state 100 ticks into the hang
	var k: int = int(c["k"])
	var s := LIB.new_sim(lvl)
	stand_at(s, float(s.a_pos[k].x) - float(c["lead"]), float(c["a0"]))
	var grip := false
	var closes := 0
	var w: int = int(c["w"])
	var sd: int = int(c["sd"])
	for t in w + 130:
		var ang: float
		var amp := 1.0
		if t < w:
			ang = float(c["a0"])
		elif t < w + sd:
			ang = float(c["a1"])
		elif bool(c["pull"]) and t < w + 10 + sd:
			ang = float(c["a0"]); amp = 0.7
		else:
			ang = float(c["a1"])
		var tgt: Vector2 = s.body_pos + Vector2(cos(ang), sin(ang)) * s.REACH * amp
		if grip and s.tick_count - s.grip_edge > s.GRIP_WINDOW and float(s.a_freelen[k]) < 0.0:
			grip = false
		var fire: bool = absf(float(s.a_theta[k])) >= 2.6 if String(c["cue"]) == "wrap" else touching(s, k)
		if not grip and fire and closes < 4 and float(s.a_freelen[k]) < 0.0:
			grip = true
			closes += 1
		s.step_tick(tgt, grip)
		if float(s.a_freelen[k]) >= 0.0:
			break
	if float(s.a_freelen[k]) < 0.0:
		s.free()
		return {}
	for t in 20:
		s.step_tick(s.body_pos, true)
	var catch_snap: Dictionary = s.snapshot()
	for t in 100:
		s.step_tick(s.body_pos, true)
	var out := {"catch": catch_snap, "hang": s.snapshot(), "hang_green": bool(s._holds(k)),
		"locked": int(s.a_locked[k]), "tether": float(s.a_freelen[k]), "theta": absf(float(s.a_theta[k]))}
	s.free()
	return out

const GRID := [
	[PI * 0.85, -PI * 0.42], [PI * 0.85, -PI * 0.30], [PI * 0.85, -PI * 0.18],
	[PI * 1.10, -PI * 0.42], [PI * 1.10, -PI * 0.30], [PI * 1.10, -PI * 0.18]]

func _search() -> void:
	var n := 0
	var t0 := Time.get_ticks_msec()
	for lead in [1.6, 2.0, 2.4]:
		for ang: Array in GRID:
			for sd in [9, 14, 5]:
				for pull in [false, true]:
					n += 1
					var c := {"k": 0, "lead": lead, "a0": ang[0], "a1": ang[1], "sd": sd,
						"pull": pull, "w": 120, "cue": "wrap"}
					var r := throw_shots("steps_art", c)
					if r.is_empty():
						continue
					print("  stroke %d: lead %.1f a0 %.2f a1 %.2f sd %d pull %s -> locked %d green %s tether %.2f"
						% [n, lead, ang[0], ang[1], sd, str(pull), int(r["locked"]), str(r["hang_green"]), float(r["tether"])])
					if bool(r["hang_green"]):
						print("FOUND after %d strokes, %.1f s. Put in CATCH: lead %.1f, a0 %s, a1 %s, sd %d, pull %s"
							% [n, (Time.get_ticks_msec() - t0) / 1000.0, lead,
							"PI * %.2f" % (ang[0] / PI), "-PI * %.2f" % (-ang[1] / PI), sd, str(pull)])
						return
	print("no stroke of %d locked A0 on steps_art" % n)

# ============================================================== windowed ==
func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		var search := false
		for a: String in OS.get_cmdline_user_args():
			if a == "search":
				search = true
			if a.begins_with("out="):
				outdir = a.substr(4)
		if search:
			_search()
			quit(0)
			return true
		print("")
		print("=== ART GATE: headless half ===")
		_a1()
		_a2()
		_a3()
		_a8()
		_a9()
		_a10()
		if DisplayServer.get_name() == "headless":
			print("  A4-A7 need a window (a real viewport texture): run without --headless")
			_finish()
			return true
		root.size = Vector2i(1600, 900)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
		print("")
		print("=== ART GATE: windowed half, frames into %s ===" % outdir)
		_plan()
		return false
	if frames < 3:
		return false
	if si >= steps.size():
		_finish()
		return true
	var f: Callable = steps[si]
	si += 1
	f.call()
	return false

func _finish() -> void:
	print("")
	if fails == 0:
		print("PASS  art is a picture: absent headless, inert, the same world, over nothing that matters")
	else:
		print("FAIL  %d art gate(s)" % fails)
	quit(1 if fails > 0 else 0)

# One step per frame. A picture is taken at the START of the frame after the
# state that produced it was set up - the canvas is redrawn by the engine's
# own idle step, so a shot set up and taken in one frame photographs the
# frame before. The queue makes that rule structural.
func _plan() -> void:
	# A4: steps and crag.tscn, exactly tests/art_frame.gd's picture
	for lvl: String in ["steps", "crag.tscn"]:
		_push_open(lvl)
		steps.append(func() -> void: _settle(60))
		steps.append(func() -> void:
			var p := _shot("a4_%s" % MAIN.level_name(lvl))
			var md5 := FileAccess.get_md5(p)
			_ok("A4 %s greybox=true: frame md5 %s, HEAD's %s (art_on %s, %d live nodes, none of them visible)"
				% [lvl, md5, HEAD_MD5[lvl], str(m.art_on), m.art_node_count()],
				md5 == String(HEAD_MD5[lvl]) and bool(m.art_on)))
		_push_close()
	# A5 at spawn, then A6 with the camera placed by hand, then A7
	_push_open("steps_art")
	steps.append(func() -> void: _settle(60))
	steps.append(func() -> void:
		var img := _image()
		_shot("a5_steps_art_spawn")
		_a5_spawn(img)
		# A6: first camera position, placed by hand - the camera law is not
		# what is being measured
		m.cam.position = Vector2(-405.0, -132.0)
		m.cam.force_update_scroll()
		m.queue_redraw())
	steps.append(func() -> void:
		var img := _image()
		peak_x.append(_far_peak(img))
		far_pos.append(_layer_pos())
		_shot("a6_cam_a")
		m.cam.position = Vector2(195.0, -132.0)
		m.cam.force_update_scroll()
		m.queue_redraw())
	steps.append(func() -> void:
		var img := _image()
		peak_x.append(_far_peak(img))
		far_pos.append(_layer_pos())
		_shot("a6_cam_b")
		_a6()
		m.cam.position = Vector2(-405.0, -132.0)
		m.cam.force_update_scroll()
		_a7_begin())
	for i in 2:
		for j in 90:
			steps.append(func() -> void: _a7_frame())
		steps.append(func() -> void: _a7_switch())
	steps.append(func() -> void: _a7_report())
	_push_close()
	# A5, the catch: the searched stroke, restored into steps_art and
	# photographed; then the same state on steps, for the README's pair
	steps.append(func() -> void:
		var r := throw_shots("steps_art", CATCH)
		_ok("A5 the searched stroke (lead %.1f, a0 %.2f, a1 %.2f, sd %d, pull %s) caught A0 BEAM on steps_art: locked %d, green %s, tether %.2f m, theta %.2f rad after 100 ticks"
			% [float(CATCH["lead"]), float(CATCH["a0"]), float(CATCH["a1"]), int(CATCH["sd"]),
			str(CATCH["pull"]), int(r.get("locked", -9)), str(r.get("hang_green", false)),
			float(r.get("tether", 0.0)), float(r.get("theta", 0.0))],
			not r.is_empty() and bool(r["hang_green"]))
		if not r.is_empty():
			catch_hang = r["hang"])
	for lvl: String in ["steps_art", "steps"]:
		_push_open(lvl)
		steps.append(func() -> void:
			if catch_hang.is_empty():
				return
			m.restore(catch_hang)
			m.cam_reinit()
			m.cam_apply(DT)
			m.queue_redraw())
		steps.append(func() -> void:
			if catch_hang.is_empty():
				return
			var img := _image()
			_shot("a5_%s_catch" % MAIN.level_name(lvl))
			if lvl == "steps_art":
				_a5_catch(img))
		_push_close()

func _push_open(lvl: String) -> void:
	steps.append(func() -> void: _open(lvl))
	steps.append(func() -> void: pass)         # two idle frames, as art_frame.gd
	steps.append(func() -> void: pass)

func _push_close() -> void:
	steps.append(func() -> void: _close())

func _open(lvl: String) -> void:
	# tests/art_frame.gd's opening, to the letter: setup_sim() first, a scratch
	# save path, add_child, save_enabled off, the pointer given back, the
	# scratch removed
	m = MAIN.new()
	m.external_drive = true
	m.level_id = lvl
	m.setup_sim()
	m.save_path = "user://art_gate_scratch.save"
	root.add_child(m)
	m.save_enabled = false
	m.play_on = false
	if m.mouse_owned:
		m.mouse_owned = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
	if m.save_enabled or m.mouse_owned or m.save_path.begins_with("user://run"):
		fails += 1
		print("  FAIL this session still owns a save slot or the pointer")

func _close() -> void:
	if m != null:
		m._av_stop()
		root.remove_child(m)
		m.free()
		m = null

func _settle(ticks: int) -> void:
	m._reset()
	m.cam_reinit()
	for t in ticks:
		m.step_tick(m.body_pos, false)
		m.cam_apply(DT)
	m.queue_redraw()

func _image() -> Image:
	return root.get_texture().get_image()

func _shot(name: String) -> String:
	var p := "%s/%s.png" % [outdir, name]
	_image().save_png(p)
	return ProjectSettings.globalize_path(p)

# ------------------------------------------------------------- sampling --
func _screen(world_m: Vector2) -> Vector2i:
	# world metres -> viewport pixels through the live camera
	var px := world_m * PPM
	var c: Vector2 = m.cam.position
	var z: float = m.cam.zoom.x
	return Vector2i(Vector2(800.0, 450.0) + (px - c) * z)

static func near(a: Color, b: Color, tol := 0.02) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol

static func cs(c: Color) -> String:
	return "(%.2f, %.2f, %.2f)" % [c.r, c.g, c.b]

static func plateish(c: Color) -> bool:
	# the beam sprite's iron plate: (0.26..0.32, 0.25..0.30, 0.28..0.34), b >= g
	return c.r > 0.22 and c.r < 0.36 and c.g > 0.21 and c.g < 0.34 and c.b > 0.24 and c.b < 0.38 and c.b >= c.g

static func rockish(c: Color) -> bool:
	# the placeholder rock: warm, r > g > b, mid-bright. Not the clear colour,
	# not a flat backdrop grey-blue (those have b >= r)
	return c.r > c.g and c.g > c.b and c.r > 0.2 and c.r < 0.9

func _a5_spawn(img: Image) -> void:
	var samples: Array = [
		["rock face under the home floor, world (-3.0, 1.0) m", _screen(Vector2(-3.0, 1.0)), "rock"],
		["rock face under the left wall, world (-13.0, -3.0) m", _screen(Vector2(-13.0, -3.0)), "rock"],
		["the ground_edge band, 8 px into the floor at x -1.0 m", _screen(Vector2(-1.0, 0.0)) + Vector2i(0, 8), "rock"],
		["the beam sprite's bar at A0's centre, world (-2.0, -2.2) m", _screen(Vector2(-2.0, -2.2)), "bar"],
		["the beam sprite's plate, 36 px right and 26 up of A0 (the sprite is 96 x 64)", _screen(Vector2(-2.0, -2.2)) + Vector2i(36, -26), "plate"],
		["the body, 10 px left and 6 down of its centre (off the face and the arm)", _screen(m.body_pos) + Vector2i(-10, 6), "body"],
		["the sky at screen (1560, 60), where nothing is authored", Vector2i(1560, 60), "clear"],
	]
	for s: Array in samples:
		var p: Vector2i = s[1]
		var c := img.get_pixel(p.x, p.y)
		var want := String(s[2])
		var good := false
		if want == "rock":
			good = rockish(c)
		elif want == "bar":
			good = c.r > 0.5 and c.r < 0.75 and c.g > 0.34 and c.g < 0.5 and c.b > 0.15 and c.b < 0.3
		elif want == "plate":
			good = plateish(c)
		elif want == "body":
			# the capsule (0.85, 0.82, 0.75), or the arm's half-alpha line over
			# it: bright and warm either way, and nothing under it is
			good = c.r > 0.8 and c.g > 0.75 and c.b > 0.65
		elif want == "clear":
			good = near(c, CLEAR, 0.02)
		_ok("A5 %s: %s is %s" % [String(s[0]), str(p), cs(c) + ("" if good else "  - NOT " + want)], good)
	# the parallax skyline: the far peak's top is cliff-coloured and the pixel
	# 20 px above it is the clear colour - so the layer is there, and the sky
	# above it is empty
	var pk := _far_peak(img)
	if pk.x < 0:
		_ok("A5 the far skyline's peak is on screen", false)
		return
	var top := img.get_pixel(pk.x, pk.y + 2)
	var above := img.get_pixel(pk.x, pk.y - 20)
	_ok("A5 the far skyline's peak at screen %s is %s and 20 px above it the sky is %s (clear %s)"
		% [str(pk), cs(top), cs(above), cs(CLEAR)],
		near(top, Color(0.17, 0.18, 0.23), 0.03) and near(above, CLEAR, 0.02))

func _far_peak(img: Image) -> Vector2i:
	# the topmost pixel in the frame that is the far layer's own top colour
	# (0.17, 0.18, 0.23) - the far skyline is the only thing painted in it,
	# and its peak is its highest point. Scanned below the HUD text.
	for y in range(100, 600):
		var xs: Array[int] = []
		for x in range(0, 1600, 1):
			if near(img.get_pixel(x, y), Color(0.17, 0.18, 0.23), 0.012):
				xs.append(x)
		if xs.size() >= 3:
			return Vector2i(int(round((xs[0] + xs[xs.size() - 1]) * 0.5)), y)
	return Vector2i(-1, -1)

func _layer_pos() -> Array:
	# the ParallaxLayer nodes' own positions, as the engine set them
	var pb: Node = m.art_root.get_node_or_null("Art/Parallax")
	if pb == null:
		return [Vector2.ZERO, Vector2.ZERO]
	return [(pb.get_node("Far") as ParallaxLayer).position, (pb.get_node("Mid") as ParallaxLayer).position]

func _a6() -> void:
	var dcam := 600.0
	var dfar: float = (far_pos[1][0] as Vector2).x - (far_pos[0][0] as Vector2).x
	var dmid: float = (far_pos[1][1] as Vector2).x - (far_pos[0][1] as Vector2).x
	var dpk: int = peak_x[1].x - peak_x[0].x
	_ok("A6 camera +%.0f px: the world moved -%.0f px on screen, the Far layer (motion_scale 0.3) %.1f px, the Mid layer (0.6) %.1f px - read off the ParallaxLayer nodes"
		% [dcam, dcam, dfar, dmid],
		absf(dfar + 0.3 * dcam) < 0.5 and absf(dmid + 0.6 * dcam) < 0.5)
	_ok("A6 and off the pixels: the far skyline's peak went from x %d to %d, %d px for the camera's %.0f (%.3fx; 0.3 authored)"
		% [peak_x[0].x, peak_x[1].x, dpk, dcam, -float(dpk) / dcam],
		peak_x[0].x >= 0 and peak_x[1].x >= 0 and absf(float(dpk) + 0.3 * dcam) <= 2.0)

func _a5_catch(img: Image) -> void:
	var k: int = int(CATCH["k"])
	var c: Vector2 = m.a_pos[k]
	var r: float = m.a_r[k] * PPM
	var centre := _screen(c)
	# the ring is drawn at r + 8 px from -PI/2 (straight up) through theta;
	# theta > 0.3 by A5's own precondition, so the pixel straight above the
	# centre at r + 8 is the ring. 3 px wide, so +-1 px of it is ring.
	var ring_p := centre + Vector2i(0, -int(round(r + 8.0)))
	var ring := img.get_pixel(ring_p.x, ring_p.y)
	# and 8 px further out, past the ring's outer edge (r + 9.5) and its slip
	# ring at r + 13 (not drawn while it holds), is plate again: the sprite's
	# plate runs from 12 to 32 px above the centre, the ring sits at 21. A
	# ring pixel between two plate pixels is a ring drawn OVER the sprite.
	var plate_p := centre + Vector2i(0, -int(round(r + 8.0)) - 8)
	var plate := img.get_pixel(plate_p.x, plate_p.y)
	# 5 px inside the ring is plate too - unless the WRAPPED ROPE is there,
	# drawn taut (0.95, 0.45, 0.25) over the plate, which is the same claim
	# made by the other instrument: measured, it is the rope.
	var inner_p := centre + Vector2i(0, -int(round(r + 8.0)) + 5)
	var inner := img.get_pixel(inner_p.x, inner_p.y)
	var inner_is := "plate" if plateish(inner) else ("the taut rope" if near(inner, Color(0.95, 0.45, 0.25), 0.06) else "NEITHER")
	_ok("A5 catch: the ring pixel at %s is %s (green %s; holds %s, locked %d, theta %.2f); 8 px outside it the plate %s; 5 px inside it %s, %s: ring and rope are drawn over the sprite"
		% [str(ring_p), cs(ring), cs(GREEN), str(m._holds(k)), int(m.a_locked[k]),
		absf(float(m.a_theta[k])), cs(plate), cs(inner), inner_is],
		m._holds(k) and near(ring, GREEN, 0.06) and plateish(plate) and inner_is != "NEITHER")
	_ok("A5 catch: the anchor's centre %s is the sprite's bar %s, not the grey disc (0.55, 0.48, 0.38): the disc is off with greybox = false and the ring is not"
		% [str(centre), cs(img.get_pixel(centre.x, centre.y))],
		not near(img.get_pixel(centre.x, centre.y), Color(0.55, 0.48, 0.38), 0.03))

# ------------------------------------------------------------------- A7 --
var a7_phase := 0
var a7_cpu: Array[float] = []
var a7_gpu: Array[float] = []
var a7_wall: Array[float] = []
var a7_t0 := 0

func _a7_begin() -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	a7_phase = 0
	_art_visible(true)
	a7_t0 = Time.get_ticks_usec()

func _art_visible(v: bool) -> void:
	var art: CanvasItem = m.art_root.get_node_or_null("Art")
	if art != null:
		art.visible = v
	# a CanvasLayer's visibility is its own, not its parent's
	for l in m.art_root.find_children("*", "CanvasLayer", true, false):
		(l as CanvasLayer).visible = v

func _a7_frame() -> void:
	var now := Time.get_ticks_usec()
	var wall := float(now - a7_t0) / 1000.0
	a7_t0 = now
	var rid := root.get_viewport_rid()
	a7_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	a7_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	a7_wall.append(wall)
	# a live game frame: one tick, the camera, a redraw
	m.step_tick(m.body_pos + Vector2(0.5, -0.9), false)
	m.cam_apply(DT)
	m.queue_redraw()

static func median(a: Array[float]) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]

func _a7_switch() -> void:
	# drop the first 10 frames of each run (the switch itself, the warm-up)
	var keep := func(a: Array[float]) -> Array[float]: return a.slice(10)
	cost["%d" % a7_phase] = [median(keep.call(a7_cpu)), median(keep.call(a7_gpu)), median(keep.call(a7_wall))]
	a7_cpu.clear(); a7_gpu.clear(); a7_wall.clear()
	a7_phase += 1
	_art_visible(a7_phase == 0)

func _a7_report() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var on: Array = cost["0"]
	var off: Array = cost["1"]
	_ok("A7 windowed frame on steps_art, median of 80: art SHOWN cpu %.2f ms + gpu %.2f ms (wall %.2f ms/frame, vsync off); art HIDDEN cpu %.2f + gpu %.2f (wall %.2f); the layer costs %+.2f ms cpu, %+.2f ms gpu"
		% [on[0], on[1], on[2], off[0], off[1], off[2], on[0] - off[0], on[1] - off[1]],
		(on[0] - off[0]) + (on[1] - off[1]) < 4.0)
	_ok("A7 boot: _art_build on steps_art %.2f ms once (instantiate, prune, attach %d nodes); on the traverse %.3f ms (returns at once)"
		% [float(cost["boot_us_steps_art"]) / 1000.0, m.art_node_count(), float(cost["boot_us_traverse"]) / 1000.0],
		float(cost["boot_us_steps_art"]) < 100000.0)
