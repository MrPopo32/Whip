extends Node2D
## THE WHIP - greybox demo.
## Custom fixed-tick verlet sim (no engine physics). One verb: shape the whip.
## Mouse = handle target (clamped to a reach circle around the body).
## HOLD Space (or LMB) = TAUT grip. Release = SLACK. R = restart.
##
## Design contracts (do not "improve" these away):
##  - No RNG anywhere in the sim. Bit-identical replays on the same build.
##  - No assists: no tip magnetism, no auto-taut, no input smoothing beyond the
##    constant arm spring, no trajectory prediction, no slow-mo.
##  - Rope never pushes (all rope constraints are one-sided tethers).
##  - Arm spring force is an INTERNAL pair (reaction applied to the body), so
##    mouse waggling can never add net momentum (no helicopter flight).
##  - Wrap angle is MEASURED from live geometry every tick, never event-counted.
##  - Dissipation only via contact friction and the taut-catch yank. No air drag.

# ---------------------------------------------------------------- constants --
const PPM := 60.0                 # pixels per meter (render scale only)
const SUB := 16                   # physics substeps per 60 Hz tick
const DT := 1.0 / 60.0
const SDT := DT / SUB

const NSEG := 25                  # chain segments (26 particles, 0 = handle)
const NP := NSEG + 1

const GRAV := Vector2(0.0, 10.0)  # y-down

const REACH := 1.15               # m, cursor clamp radius around body
const ARM_MAX := 1.30             # m, one-sided body<->handle tether
const SPRING_K := 340.0           # handle spring toward cursor target
const SPRING_C := 17.0            # handle spring damping (vs body-relative vel)
const F_MAX := 320.0              # arm force cap ("panic saturates")

const BODY_M := 8.0               # body : whip mass ~ 8:1 (panel ruling)
const BODY_R := 0.28

const SLACK_STIFF := 1.0          # rope is inextensible in BOTH modes - waves
                                  # travel because the rope is stiff in stretch
                                  # and free in bending; slack vs taut differs
                                  # only in load-bearing (LRA) + solve budget
const TAUT_EXTRA_SWEEPS := 2      # extra constraint sweeps while taut

# Thresholds on the MEASURED winding angle. Calibrated against real thrown
# geometry (tangent in, arc, tangent tail) - NOT against the radial test rig,
# which suppresses the tangent legs and made a lock look like a full turn when
# it actually cost about a third of one.
var wrap_shell := 0.004               # m: contact shell for counting winding.
                                      # A shell WIDER than the contact circle lets
                                      # a straight hanging leg keep counting past
                                      # the tangent point, which is what lifted a
                                      # mere fold from pi to over 4 rad.
var th_part := 3.4                    # rad: a catch engages. MUST sit above
                                      # the fold ceiling - a chain merely
                                      # creased over a beam turns through pi
                                      # without winding anything, and measured
                                      # up to 2.62 rad with the tight shell.
                                      # It used to be 3.0, i.e. BELOW a fold,
                                      # so gravity alone could wrap you.
var th_full := 5.5                    # rad: LOCKED. Calibrated so a lock
                                      # needs more than a full turn: measured
                                      # settle is 2.5-3.9 at 1.0 turn (which
                                      # OVERLAPS the fold range, so a single
                                      # turn cannot be told from a crease) and
                                      # 6.1-11.3 at 1.3 turns. The HUD promise
                                      # of "a FULL turn" is now literally true.
                                  # plateaus between 0.6 and 1.0 turns and then
                                  # steps hard at ~1.05-1.15 turns - exactly
                                  # where the chain crosses its own standing
                                  # part. Putting the lock on that step means
                                  # "locked" IS the self-pinch, the only thing
                                  # that can physically hold a body on a beam.
var th_rel := 1.8                     # rad: release

const CRACK_SPEED := 24.0         # m/s tip speed -> crack event (sound only,
                                  # NO energy is shed - that would be a governor)

# ------------------------------------------------------------------- state --
var pos := PackedVector2Array()
var prv := PackedVector2Array()
var inv_m := PackedFloat32Array()
var p_rad := PackedFloat32Array()
var rest := PackedFloat32Array()
var cum_len := PackedFloat32Array()   # arc length handle -> particle i

var body_pos := Vector2.ZERO
var body_prv := Vector2.ZERO

var taut := false
var cursor_m := Vector2.ZERO          # last cursor (world meters)
var target_m := Vector2.ZERO          # clamped handle target

# anchors
var a_pos := PackedVector2Array()
var a_r := PackedFloat32Array()
var a_theta := PackedFloat32Array()   # measured winding, signed
var a_lockidx := PackedInt32Array()   # chain vertex nearest the wrap
var a_freelen := PackedFloat32Array() # active tether length (-1 = inactive)
var a_half := PackedInt32Array()      # last half-wrap count (for tick sfx)
# capstan lock = a pin on the rope's MATERIAL point at the anchor. This is the
# demo stand-in for real self-pinch (a bare tapered tail cannot hold a body by
# capstan friction alone - the pressure-test's key finding). Honest scope of
# the stand-in, as implemented:
#  - the pin engages on ANY catch (measured theta >= th_part), so a partial
#    wrap really does catch you - that is the briefed "it catches, then
#    betrays" and it is what makes a near-miss readable rather than nothing;
#  - a partial wrap pays MATERIAL through the pin, one segment per
#    PAYOUT_TICKS, while loaded: the betrayal is a visible, audible ratchet
#    that ends with the whip sliding off its own tail;
#  - a wrap classified locked (>= th_full) freezes payout - it is committed;
#  - any wrap releases when measured theta falls below th_rel, so an unwrap
#    wave that lifts segments off contact still frees it, loaded or not.
var a_pinidx := PackedInt32Array()
var a_pinpt := PackedVector2Array()
var a_paytick := PackedInt32Array()   # payout timer for partial-wrap slip
# wrap classification: measured contact-theta creeps upward as a loaded wrap
# beds in against the anchor, so partial-vs-locked is decided ONCE from
# settled geometry shortly after the catch and then FROZEN. It upgrades only
# on a genuine added turn (a large theta jump), never on bedding-in creep.
var a_locked := PackedInt32Array()    # -1 pending, 0 partial, 1 locked
var a_armed := PackedInt32Array()     # 0 = must fully unwind before re-catching
var a_pin0 := PackedInt32Array()      # pin index at engagement (has it slipped?)
var a_pend := PackedInt32Array()      # ticks since engagement (for classify)
var a_ength := PackedFloat32Array()   # theta at classification time
var a_minth := PackedFloat32Array()   # weakest theta seen during the settle
# The self-pinch is THE WRAP YOU MADE. These record which stretch of chain was
# actually in the wrap at the moment it engaged, as offsets from the pin, so
# the static grip travels with the pin during payout. Chain that arrives at the
# beam later is not part of that pinch and slides normally - without this, every
# new contact glues on too and the coil accretes until the entire whip, handle
# included, is spooled onto the beam (measured: 24 of 26 particles).
var a_lastth := PackedFloat32Array()  # |theta| last tick, to see winding grow
var a_shed := PackedInt32Array()      # timer for shedding an over-wound coil
var a_prun := PackedInt32Array()      # consecutive ticks this wrap has pinched
var a_wlo := PackedInt32Array()
var a_whi := PackedInt32Array()
const PAYOUT_TICKS := 15              # one segment pays through per interval.
                                      # Raised from 8 when the pin re-seat
                                      # landed: re-seating removes the wasted
                                      # teleport, which shortened the visible
                                      # betrayal from 56 to 39 ticks. This
                                      # restores it - the betrayal has to be
                                      # long enough to read as losing.
# A capstan holds only if there is tension on BOTH sides of the wrap. Your hand
# supplies the standing-side tension - that is what gripping IS. Let go and the
# rope simply runs through your hand, the wrap unwinds, and you fall. This is
# what gives SLACK and TAUT genuinely separate purposes: slack shapes waves and
# cannot bear you, taut bears you and cannot shape. Without it the rope is
# inextensible in both modes, a wrap holds whether or not you grip, and the
# grip button is decorative.
const TAIL_MIN := 1                   # tail segments that must remain past the
                                      # pin. A real thrown catch lands its pin
                                      # at material index 19-24, so TAIL_MIN=5
                                      # (which fails any pin >= 20) made every
                                      # long tip-catch slide off on its FIRST
                                      # payout - long range was a coin flip
                                      # between nothing and instant betrayal,
                                      # while close catches got a full second
                                      # of legible ratcheting. Now the tip
                                      # betrays at the same readable rate.
const CLASSIFY_TICKS := 6             # settle time before partial/locked call
const UPGRADE_JUMP := 1.2             # rad above classified theta = real turn
# a locked wrap degrades back to "partial" only when the measured wrap falls
# below the CATCH threshold. It cannot be th_full-epsilon: a wrap tightening
# under load straightens its wrapped segments out of the contact band, so
# measured theta legitimately decays ~1.5 rad while the wrap is physically
# unchanged. Demoting inside that band would betray honest full wraps.

# terrain segments. t_n is each segment's OUTWARD (air-side) normal. Terrain is
# a polyline, not a set of half-spaces, so without a stored outward direction
# collision has to guess "which side is the particle on" - and the instant a
# particle lands on the solid side that guess pushes it DEEPER and parks it
# under the floor, permanently. Winding is kept consistent so t_n is well
# defined: for every segment, normalize(ab.y, -ab.x) points into the air.
var t_a := PackedVector2Array()
var t_b := PackedVector2Array()
var t_n := PackedVector2Array()

var tip_speed := 0.0
var crack_cooldown := 0.0
var crack_flash := 0.0
var slipping := false
var grounded := false          # body resting on terrain this tick
var tick_count := 0
var grip_edge := -999                 # tick the hand last closed
var run_ticks := 0
var finished := false
var falls := 0
var spawn := Vector2(-4.6, -1.0)
var goal_x := 58.0

var taper := 26.0                     # handle:tip mass ratio (see _reset).
                                      # Taper sets FEEL, not difficulty: it
                                      # trades heft for snap (tests/taper_sweep
                                      # measures 3.0x amplification at 22:1,
                                      # 4.4x at 35:1) but barely moves the lock
                                      # rate (tests/lock_rate.gd). 26:1 keeps
                                      # the whip feeling weighted - a noodle is
                                      # not satisfying to throw - with a little
                                      # more life than the original 22:1.
var ground_mu := 0.30                 # chain/body friction against terrain
# COIL MODES (debug toggle: press 0 / 1 / 3 in game)
#  0 - off: winding a beam is free, so stirring the hand spools the whole whip
#      onto it at no cost. This is what "it just keeps wrapping" feels like.
#  1 - winding CONSUMES tether: every extra turn eats the rope it wound on, so
#      coiling hauls you toward the beam. Self-limiting, and honest - that is
#      what winding rope onto a post does. On its own it is also a WINCH: stir
#      to wind, get pulled up, for free. The design bans a reel as a hidden
#      second verb, which is what mode 3 fixes.
#  3 - mode 1 PLUS an over-wound coil pays back out under load: excess turns
#      are unstable when you hang on them, so a coil you wound to climb sheds
#      itself and drops you. Winding up costs rope; hanging on it gives it back.
var coil_mode := 1
const COIL_MIN_TETHER := 1.00         # m: winding can never reel you all the
                                      # way to the beam - it is a drift, not a
                                      # docking mechanism.
const COIL_RATE := 0.10               # m/s cap on how fast winding may eat
                                      # tether. This has to read as being
                                      # slowly drawn in; anything brisk both
                                      # yanks the body into a thrash and makes
                                      # landing a good whip pointless, because
                                      # stirring would beat throwing.
const COIL_EXCESS := 1.5              # rad past th_full before a coil sheds
const PINCH_RAD := 0.10               # m: how close to the beam a self-crossing
                                      # has to be to count as a pinch
const PINCH_TURN := 0.75              # turns of chain that must lie between the
                                      # two crossing strands for it to be a real
                                      # riding turn rather than a tail kink
const PINCH_RUN := 2                  # consecutive ticks pinched before locking
const LOCK_WINDOW := 30               # ticks a catch has to produce a pinch
# GRIP IS A TRIGGER, NOT A LATCH. A wrap can only be caught in the moments
# after you CLOSE your hand - not at any time while it happens to be closed.
# Holding the button down used to let the simulation choose the instant of
# engagement itself, which is an auto-catch: the button armed it, the machine
# fired it. Measured, that handed over 78% of all available locks for no
# timing at all, and stretched a 100 ms physical window into a 1900 ms one.
# Closing your hand IS the act of catching - which is also why you can no
# longer collect beams by accident while hanging on to another one.
const GRIP_WINDOW := 15               # ticks after closing your hand in which
                                      # a wrap can take (250 ms)
const COIL_SHED_TICKS := 6            # how fast an over-wound coil pays out
var pin_min_idx := 3                  # earliest chain index that may hold a wrap
var anchor_mu := 0.40                 # chain friction on a beam BEFORE a wrap
                                      # engages: how readily a glancing contact
                                      # grabs instead of skidding past
var external_drive := false           # set true by the headless test harness

# nodes
var cam: Camera2D
var hud: Label
var status: Label
var sfx_crack: AudioStreamPlayer
var sfx_tick: AudioStreamPlayer
var sfx_rasp: AudioStreamPlayer

# ------------------------------------------------------------------- setup --
func _ready() -> void:
	if pos.size() == 0:
		setup_sim()

	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 4.0
	add_child(cam)
	cam.make_current()
	cam.position = (body_pos + Vector2(0.0, -1.4)) * PPM

	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92))
	hud.text = "THE WHIP  |  mouse: move handle   R: restart\nSPACE / LMB = CLOSE YOUR HAND on the rope. It is a grip, not a stiffener:\na wrap only takes in the moment you close it, and only holds while you hold.\nOPEN your hand and you leave the beam that instant - release is your launch.\ngreen ring = the rope has crossed itself and will hold. amber = it will betray."
	canvas.add_child(hud)
	status = Label.new()
	status.position = Vector2(16, 146)
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	canvas.add_child(status)

	sfx_crack = AudioStreamPlayer.new()
	sfx_crack.stream = _make_noise_wav(0.09, 0.018, 26111)
	sfx_crack.volume_db = -4.0
	add_child(sfx_crack)
	sfx_tick = AudioStreamPlayer.new()
	sfx_tick.stream = _make_sine_wav(0.05, 880.0)
	sfx_tick.volume_db = -8.0
	add_child(sfx_tick)
	sfx_rasp = AudioStreamPlayer.new()
	sfx_rasp.stream = _make_noise_wav(0.4, 10.0, 7333, true)
	sfx_rasp.volume_db = -14.0
	add_child(sfx_rasp)

func clear_anchors() -> void:
	for k in a_freelen.size():
		a_freelen[k] = -1.0
		a_lockidx[k] = -1
		a_theta[k] = 0.0
		a_half[k] = 0
		a_pinidx[k] = -1
		a_paytick[k] = 0
		a_locked[k] = -1
		a_armed[k] = 1
		a_lastth[k] = 0.0
		a_shed[k] = 0
		a_prun[k] = 0
		a_pin0[k] = -1
		a_pend[k] = 0
		a_ength[k] = 0.0
		a_minth[k] = 0.0

func setup_sim() -> void:
	_build_level()
	_reset()

func _build_level() -> void:
	# Terrain: y-down, up is negative. Hand-placed, deterministic.
	#
	# GEOMETRY CONTRACT (measured, not assumed - see tests/throw_probe.gd):
	# a 5.25 m whip can only LOCK an anchor about 3 m above the floor you
	# throw from, at roughly 1.5-2.5 m of lead. Every mandatory anchor here
	# sits inside that envelope. Gaps are V-floored so a fall costs ground
	# and time but never the run: the lash gait crawls out either side
	# (measured ~0.37 m/s in tests/ground_probe.gd).
	# LEVEL CONTRACT (all three numbers measured, not assumed):
	#  - one stroke from standing throws the tip ~3.1 m up
	#    (tests/ground_throw.gd), and BEAM HEIGHT - not taper - is what makes
	#    a catch earned: tests/lock_rate.gd fires a grid of blind strokes and
	#    measures, once winding is counted honestly, 50% of blind strokes
	#    locking at a 2.0 m beam, 17% at 2.2 m and 0% at 2.4 m. Beams sit
	#    2.2 m over their floor: half of blind strokes CATCH there but only
	#    one in six LOCKS, so most contacts betray you - which is the texture
	#    the whole wrap model exists to produce;
	#  - the lash gait crawls flat ground at ~0.4 m/s but CANNOT climb even a
	#    20 degree slope (tests/ground_probe.gd, tests/escape_probe.gd) - so
	#    recovery can never depend on walking out of anywhere;
	#  - therefore every surface a body can come to rest on has a beam within
	#    throw range, and the traverse is two flat tiers joined by a drop.
	# Falling costs the height and the momentum you spent earning, never the
	# run: the lower tier is always completable beam by beam from the floor.
	var pts: Array[Vector2] = [
		Vector2(-14, 0), Vector2(20, 0),        # upper tier
		Vector2(20, 3.0),                       # the drop
		Vector2(62, 3.0),                       # lower tier
		Vector2(62, -4.0),                      # seal the far end
	]
	for i in range(pts.size() - 1):
		t_a.append(pts[i])
		t_b.append(pts[i + 1])
	# left wall: wound bottom-to-top so its outward normal points INTO the
	# level (+x), consistently with every other segment
	t_a.append(Vector2(-14, -8)); t_b.append(Vector2(-14, 0))
	t_n.clear()
	for i in t_a.size():
		t_n.append(Vector2((t_b[i] - t_a[i]).y, -(t_b[i] - t_a[i]).x).normalized())

	# Beams come in two kinds, and the split is structural rather than
	# decorative. A hanging body rides ~1.3 m below the hand, so a beam only
	# 2.2 m over its floor CANNOT carry a tether longer than ~1.9 m - the arc
	# would go underground. RECOVERY beams (2.2 m) are therefore incapable of
	# being the fast line no matter how well you throw at them: they exist so
	# that no fall is ever terminal, and crawling the spine is roughly 8x
	# slower than flying. FAST beams (4.5 m over the floor) are out of reach
	# from the ground entirely - you can only catch one from the apex of a
	# swing - and they are the only place a long tether has room to swing.
	# The reward for a long catch needs no score: it IS the tether. A far
	# catch is literally a bigger circle to swing on, and it is fixed for
	# that catch. Fast beams sit ~7.8 m apart, further than a short catch's
	# arc chord can bridge, so a lazy close catch leaves you short.
	var anchors := [
		# UPPER TIER (floor y=0). Radius now means RANGE, not difficulty: a
		# thin beam costs less chain to wrap, so it is the only kind you can
		# still lock from far away.
		[-2.0, -2.2, 0.22],   # school: throw, wrap, grip, hang
		[ 3.6, -2.2, 0.22],   # school: pump, release, chain a second catch
		[10.4, -4.5, 0.10],   # FAST - the first beam your feet cannot reach
		[15.6, -2.2, 0.20],   # recovery, and the run-up to the lip
		[19.6, -2.2, 0.11],   # THE LIP LAUNCHER: 2.2 m over this tier but
		                      # 5.2 m over the next, because the floor falls
		                      # away at x=20. Catch it close and you dangle
		                      # over the drop with nothing in range; catch it
		                      # FAR and you get a 4 m tether swinging in 5 m
		                      # of open air. Same beam, two outcomes.
		# LOWER TIER (floor y=3.0): a slow recovery spine at 2.2 m, and the
		# fast line at 4.5 m - which is the minimum height a 4 m tether can
		# swing under without the arc going underground.
		[24.2,  0.8, 0.18],   # recovery - kept clear of the cliff face at x=20,
		                      # where the trailing whip drapes onto the upper
		                      # tier and spoils the stroke
		[27.2, -1.5, 0.10],   # FAST - the first true hanging arc
		[31.1,  0.8, 0.20],   # recovery
		[35.0, -1.5, 0.10],   # FAST
		[38.9,  0.8, 0.20],   # recovery
		[42.8, -1.5, 0.10],   # FAST
		[46.7,  0.8, 0.20],   # recovery
		[50.6, -1.5, 0.10],   # FAST
		[54.6,  0.8, 0.20],   # recovery, the last before the flag
	]
	for a: Array in anchors:
		a_pos.append(Vector2(a[0], a[1]))
		a_r.append(a[2])
		a_theta.append(0.0)
		a_lockidx.append(-1)
		a_freelen.append(-1.0)
		a_half.append(0)
		a_pinidx.append(-1)
		a_pinpt.append(Vector2.ZERO)
		a_paytick.append(0)
		a_locked.append(-1)
		a_armed.append(1)
		a_pin0.append(-1)
		a_pend.append(0)
		a_ength.append(0.0)
		a_minth.append(0.0)
		a_wlo.append(0)
		a_whi.append(0)
		a_lastth.append(0.0)
		a_shed.append(0)
		a_prun.append(0)

func _reset() -> void:
	pos.resize(NP); prv.resize(NP)
	inv_m.resize(NP); p_rad.resize(NP)
	rest.resize(NSEG); cum_len.resize(NP)

	# geometric mass taper, whip total mass = 1.0. Taper IS the whip: a lighter
	# tip is what makes a wave amplify as it runs out, and it is the single
	# lever controlling both "snap" and how high a stroke can throw the tip.
	# Adjacent-segment ratio stays far inside the solver's safe envelope
	# (taper^(1/24): even 100:1 total is only 1.21:1 between neighbours).
	var t := pow(1.0 / taper, 1.0 / float(NSEG - 1))
	var base := (1.0 - t) / (1.0 - pow(t, NSEG))
	var acc := 0.0
	for i in NP:
		var m := base * pow(t, mini(i, NSEG - 1))
		if i == 0:
			m += 0.10  # grip mass
		inv_m[i] = 1.0 / m
		p_rad[i] = lerpf(0.05, 0.02, float(i) / float(NSEG))
	cum_len[0] = 0.0
	for i in NSEG:
		rest[i] = lerpf(0.28, 0.14, float(i) / float(NSEG - 1))
		acc += rest[i]
		cum_len[i + 1] = acc

	body_pos = spawn
	body_prv = body_pos
	var h := body_pos + Vector2(-0.4, 0.55)
	for i in NP:
		var p := h + Vector2(-cum_len[i] * 0.99, 0.0)  # trailing behind you
		pos[i] = p
		prv[i] = p
	clear_anchors()
	tip_speed = 0.0
	crack_cooldown = 0.0
	crack_flash = 0.0
	slipping = false
	if sfx_rasp != null and sfx_rasp.playing:
		sfx_rasp.stop()
	if cam != null:
		cam.position = (body_pos + Vector2(0.0, -1.4)) * PPM
		cam.reset_smoothing()
	run_ticks = 0
	finished = false
	falls = 0
	tick_count = 0

# ------------------------------------------------------------------- input --
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_reset()
		elif event.keycode == KEY_0:
			coil_mode = 0
		elif event.keycode == KEY_1:
			coil_mode = 1
		elif event.keycode == KEY_3:
			coil_mode = 3
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()

func _physics_process(_d: float) -> void:
	if external_drive:
		return
	var mouse := get_global_mouse_position() / PPM
	var grip := Input.is_key_pressed(KEY_SPACE) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	step_tick(mouse, grip)
	cam.position = (body_pos + Vector2(0.0, -1.4) + _body_vel() * 0.25) * PPM

func _process(_d: float) -> void:
	queue_redraw()
	if status != null:
		var secs := run_ticks / 60.0
		var mode_txt := "0: winding is free"
		if coil_mode == 1:
			mode_txt = "1: winding eats rope"
		elif coil_mode == 3:
			mode_txt = "3: winding eats rope + over-coil sheds"
		var line := "time %.1fs   falls %d   tip %.0f m/s      coil mode [%s]" 			% [secs, falls, tip_speed, mode_txt]
		if finished:
			line = "TRAVERSE COMPLETE in %.1fs - press R to run it again" % secs
		status.text = line

# ---------------------------------------------------------------- sim tick --
func step_tick(cursor_world_m: Vector2, grip: bool) -> void:
	if grip and not taut:
		grip_edge = tick_count        # the hand just closed: this is the catch
	taut = grip
	cursor_m = cursor_world_m
	target_m = body_pos + (cursor_m - body_pos).limit_length(REACH)
	if not finished:
		run_ticks += 1
	tick_count += 1

	var max_tip := 0.0
	for s in SUB:
		_substep()
		var v := (pos[NP - 1] - prv[NP - 1]).length() / SDT
		if v > max_tip:
			max_tip = v
	tip_speed = max_tip

	_measure_wraps()
	_update_locks()
	_events()

func _body_vel() -> Vector2:
	return (body_pos - body_prv) / SDT

func _substep() -> void:
	# --- forces -> integrate (verlet) ---
	var hvel := (pos[0] - prv[0]) / SDT
	var bvel := (body_pos - body_prv) / SDT
	var f := (target_m - pos[0]) * SPRING_K - (hvel - bvel) * SPRING_C
	f = f.limit_length(F_MAX)

	var np := pos[0] + (pos[0] - prv[0]) + (GRAV + f * inv_m[0]) * SDT * SDT
	prv[0] = pos[0]
	pos[0] = np
	for i in range(1, NP):
		np = pos[i] + (pos[i] - prv[i]) + GRAV * SDT * SDT
		prv[i] = pos[i]
		pos[i] = np
	var nb := body_pos + (body_pos - body_prv) \
		+ (GRAV - f / BODY_M) * SDT * SDT
	body_prv = body_pos
	body_pos = nb

	# --- constraints ---
	var sweeps := 4 + (TAUT_EXTRA_SWEEPS if taut else 0)
	var stiff := 1.0 if taut else SLACK_STIFF
	for s in sweeps:
		_solve_arm()
		if s % 2 == 0:
			for i in NSEG:
				_solve_rope(i, stiff)
		else:
			for i in range(NSEG - 1, -1, -1):
				_solve_rope(i, stiff)
		_solve_lra()
	_collide()

func _solve_arm() -> void:
	var d := pos[0] - body_pos
	var l := d.length()
	if l > ARM_MAX and l > 0.0001:
		var w0 := inv_m[0]
		var wb := 1.0 / BODY_M
		var corr := d * ((l - ARM_MAX) / l / (w0 + wb))
		pos[0] -= corr * w0
		body_pos += corr * wb

func _solve_rope(i: int, stiff: float) -> void:
	var d := pos[i + 1] - pos[i]
	var l := d.length()
	if l > rest[i] and l > 0.0001:
		var w1 := inv_m[i]
		var w2 := inv_m[i + 1]
		var corr := d * ((l - rest[i]) / l * stiff / (w1 + w2))
		pos[i] += corr * w1
		pos[i + 1] -= corr * w2

func _solve_lra() -> void:
	for k in a_pos.size():
		# capstan pin: hold the rope's material point at the anchor while
		# the measured angle stays locked (independent of grip state - a
		# committed wrap stays committed until unwound)
		var pi_ := a_pinidx[k]
		if pi_ >= 0:
			pos[pi_] = a_pinpt[k]
		# long-range attachment: only while taut and a wrap is engaged
		if not taut or a_freelen[k] < 0.0:
			continue
		var lockpt: Vector2
		if pi_ >= 0:
			lockpt = a_pinpt[k]
		else:
			var li := a_lockidx[k]
			if li < 0:
				continue
			lockpt = a_pos[k] + (pos[li] - a_pos[k]).normalized() * a_r[k]
		var d := pos[0] - lockpt
		var l := d.length()
		if l > a_freelen[k] and l > 0.0001:
			pos[0] -= d * ((l - a_freelen[k]) / l)

func _collide() -> void:
	# Anti-tunnel sweeps run FIRST, over the whole chain: they need prv to
	# still be the particle's real previous position, and _collide_point
	# rewrites prv - which would leave the sweep examining a fabricated path.
	# Every particle is swept, not just the tip: a particle tunnels once it
	# moves further than its own radius in one substep, which is only ~19 m/s
	# at the tip and ~34 m/s mid-chain, and cracks reach 80.
	for i in NP:
		_swept_anchor(i)
		_swept_terrain(i)
	for i in NP:
		_collide_point(i, p_rad[i])
	_collide_body()

func _collide_point(i: int, pr: float) -> void:
	var p := pos[i]
	for s in t_a.size():
		var A := t_a[s]
		var B := t_b[s]
		var ab := B - A
		var tt := clampf((p - A).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := A + ab * tt
		var d := p - q
		if tt > 0.0 and tt < 1.0:
			# within the segment's span: use the stored OUTWARD normal and a
			# SIGNED depth, so a particle that has ended up inside the solid
			# is lifted back out instead of being pushed further in
			var n := t_n[s]
			var sd := d.dot(n)
			if sd < pr:
				if sd < 0.0:
					# rescue: carry the velocity it arrived with, so the
					# lift-out displacement never becomes velocity
					var v := pos[i] - prv[i]
					pos[i] = q + n * pr
					prv[i] = pos[i] - v
					_friction(i, n, ground_mu, 0.0)
				else:
					pos[i] = q + n * pr
					_friction(i, n, ground_mu, pr - sd)
				p = pos[i]
		else:
			# past an end of the segment: round-cap contact off the endpoint
			var l := d.length()
			if l < pr and l > 0.0001:
				var n2 := d / l
				pos[i] = q + n2 * pr
				_friction(i, n2, ground_mu, pr - l)
				p = pos[i]
	for k in a_pos.size():
		var d2 := p - a_pos[k]
		var l2 := d2.length()
		var rr := a_r[k] + pr
		if l2 < rr and l2 > 0.0001:
			var n2 := d2 / l2
			pos[i] = a_pos[k] + n2 * rr
			# engaged wrap = static contact (the crossing chain pinches the
			# tail in reality; here the whole wrap freezes and ALL slip is
			# expressed through the payout mechanism, so it is deterministic
			# and audible). Free contact = kinetic friction. A traveling
			# wave still frees any wrap by lifting segments OFF contact
			# (no contact -> no friction -> theta drops -> release).
			# static (self-pinch stand-in) applies to the wrap and its tail
			# - the material at and beyond the pin is what holds the turn on
			# the beam. Free chain on the HAND side of the wrap still slides
			# normally, so brushing an engaged anchor elsewhere does not
			# velcro the whip to it.
			# static (self-pinch stand-in) ONLY for the stretch of chain that
			# was in the wrap when it engaged - that window rides along with
			# the pin as material pays through. Chain arriving afterwards is
			# not part of the pinch: it slides, so the coil cannot accrete.
			# static (self-pinch stand-in) for the wrap and its free tail - the
			# tail is what holds the turn on the beam. But NOT for chain on the
			# HAND side of where the wrap began: that boundary rides along with
			# the pin, and it is the side the coil accretes from. Without it,
			# every new contact glues on and the whole whip spools onto the
			# beam (measured: 24 of 26 particles, handle included).
			# Static grip covers ONLY the stretch of chain that was in the
			# wrap when it engaged. Measured: the coil is fed tip-ward, so
			# leaving the tip side unbounded welded every further touch and
			# spooled the whole whip onto the beam.
			var mu := anchor_mu
			if a_freelen[k] >= 0.0 and i >= a_pinidx[k] + a_wlo[k] and i <= a_pinidx[k] + a_whi[k]:
				mu = 8.0
			_friction(i, n2, mu, rr - l2)
			p = pos[i]

func _friction(i: int, n: Vector2, mu: float, pen := 0.0) -> void:
	# inelastic normal + Coulomb tangential: friction is proportional to the
	# normal impulse, NOT a flat percentage bleed (a flat bleed silently eats
	# wave energy from any grounded chain). The impulse proxy is approach
	# speed + penetration depth: a TENSIONED wrap presses into the anchor via
	# constraint projection every substep, and that pressure is what lets a
	# wrap grip - pure approach-speed friction reads a loaded wrap as weightless.
	var v := pos[i] - prv[i]
	var vn_amt := v.dot(n)
	var vt := v - n * vn_amt
	var vt_len := vt.length()
	# only APPROACH counts as normal load - motion away from a surface is not
	# an impulse, and folding it in would grip a particle that is leaving
	var cap := mu * (maxf(-vn_amt, 0.0) + pen + GRAV.y * SDT * SDT)
	if vt_len > 0.000001:
		vt *= maxf(vt_len - cap, 0.0) / vt_len
	prv[i] = pos[i] - vt

func _swept_anchor(i: int) -> void:
	var p0 := prv[i]
	var p1 := pos[i]
	var seg := p1 - p0
	var lsq := seg.length_squared()
	if lsq < 0.0004:
		return
	for k in a_pos.size():
		var c := a_pos[k]
		var tt := clampf((c - p0).dot(seg) / lsq, 0.0, 1.0)
		var q := p0 + seg * tt
		var rr := a_r[k] + p_rad[i]
		if q.distance_to(c) < rr:
			var n := (p1 - c)
			if n.length() < 0.0001:
				n = (q - c)
			if n.length() < 0.0001:
				n = Vector2.UP
			pos[i] = c + n.normalized() * rr
			_friction(i, n.normalized(), anchor_mu)

func _swept_terrain(i: int) -> void:
	var p0 := prv[i]
	var p1 := pos[i]
	var mv := p1 - p0
	if mv.length_squared() < 0.0004:
		return
	for s in t_a.size():
		var A := t_a[s]
		var B := t_b[s]
		var ab := B - A
		# does the particle's path cross this terrain segment this substep?
		var d := mv.cross(ab)
		if absf(d) < 0.000001:
			continue
		var t1 := (A - p0).cross(ab) / d
		var t2 := (A - p0).cross(mv) / d
		if t1 < 0.0 or t1 > 1.0 or t2 < 0.0 or t2 > 1.0:
			continue
		var n := t_n[s]
		pos[i] = p0 + mv * t1 + n * p_rad[i]
		# carry the incoming velocity across the resolution: without this the
		# surviving tangential speed gets scaled by t1 - where in the substep
		# the crossing happened - which is physically meaningless. And pen=0:
		# passing p_rad invented ~19 m/s of normal load, welding the tip down.
		prv[i] = pos[i] - mv
		_friction(i, n, ground_mu, 0.0)
		return

func _collide_body() -> void:
	grounded = false
	var p := body_pos
	for s in t_a.size():
		var A := t_a[s]
		var B := t_b[s]
		if p.x < minf(A.x, B.x) - 1.0 or p.x > maxf(A.x, B.x) + 1.0:
			continue
		if p.y < minf(A.y, B.y) - 1.0 or p.y > maxf(A.y, B.y) + 1.0:
			continue
		var ab := B - A
		var tt := clampf((p - A).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := A + ab * tt
		var d := p - q
		var l := d.length()
		if l < BODY_R and l > 0.0001:
			var n := d / l
			body_pos = q + n * BODY_R
			var v := body_pos - body_prv
			var vn_amt := v.dot(n)
			var vt := v - n * vn_amt
			var vt_len := vt.length()
			var cap := ground_mu * (absf(vn_amt) + GRAV.y * SDT * SDT) * 3.0
			if vt_len > 0.000001:
				vt *= maxf(vt_len - cap, 0.0) / vt_len
			body_prv = body_pos - vt
			grounded = true
			p = body_pos

# ------------------------------------------------------------- wrap logic --
func _measure_wraps() -> void:
	# winding angle of the chain polyline around each anchor, gated to
	# vertices near the surface. Measured fresh every tick from geometry.
	for k in a_pos.size():
		var c := a_pos[k]
		var band := a_r[k] + 0.35
		var theta := 0.0
		var nearest := -1
		var nearest_d := 1e9
		for i in range(NP - 1):
			var v0 := pos[i] - c
			var v1 := pos[i + 1] - c
			var d0 := v0.length()
			var d1 := v1.length()
			if d0 < nearest_d:
				nearest_d = d0
				nearest = i
			# Count winding ONLY for a segment with BOTH ends against the
			# beam. A straight chain merely lying across a beam has at most
			# one vertex in the shell, so it now contributes nothing - it
			# used to be credited 1.4-2.0 rad of "winding" for having wound
			# precisely nothing, which gave away most of a catch before the
			# whip did any work and let a dead-straight throw lock itself.
			if d0 < band and d1 < band:
				if d0 < a_r[k] + p_rad[i] + wrap_shell 						and d1 < a_r[k] + p_rad[i + 1] + wrap_shell:
					theta += v0.angle_to(v1)
		a_theta[k] = theta
		if absf(theta) > 0.3 and nearest >= 0:
			a_lockidx[k] = nearest
		elif a_freelen[k] < 0.0:
			a_lockidx[k] = -1

static func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var r := b - a
	var q := d - c
	var den := r.cross(q)
	if absf(den) < 1e-9:
		return Vector2(INF, INF)
	var t := (c - a).cross(q) / den
	var u := (c - a).cross(r) / den
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return Vector2(INF, INF)
	return a + r * t

func _pinch(k: int) -> bool:
	# Does the chain actually CROSS ITSELF against this beam? That crossing is
	# the self-pinch - the only thing that can physically hold a body on a
	# beam, and what the lock threshold always claimed to stand for. Deciding
	# "held" from bulk winding angle instead was the root defect: a chain
	# merely creased over a beam turns through pi without winding anything, so
	# a fold could catch, and a pinned material point could inflate the angle
	# into a lock the player never earned.
	var c := a_pos[k]
	var near: float = a_r[k] + 0.25
	var idx: Array[int] = []
	for i in range(NP - 1):
		if pos[i].distance_to(c) < near or pos[i + 1].distance_to(c) < near:
			idx.append(i)
	# Winding of the chain BETWEEN the two crossing strands is what separates a
	# real riding turn from a hairpin kink in the tail: measured, turns carry
	# 0.81-1.11 of a turn between strands and kinks carry 0.01-0.27, a clean
	# gulf. Chain-index distance cannot do it - a turn is ~11 segments round a
	# fat beam but only 3-4 round a thin one, so any fixed index gap both
	# admits fat-beam kinks and rejects thin-beam turns.
	var wind := PackedFloat32Array()
	wind.resize(NP)
	wind[0] = 0.0
	for i in range(NP - 1):
		wind[i + 1] = wind[i] + (pos[i] - c).angle_to(pos[i + 1] - c)
	var lim: float = a_r[k] + PINCH_RAD
	for ai in idx.size():
		for bi in range(ai + 1, idx.size()):
			var i: int = idx[ai]
			var j: int = idx[bi]
			if absf(wind[j] - wind[i]) < PINCH_TURN * TAU:
				continue
			var x := _seg_cross(pos[i], pos[i + 1], pos[j], pos[j + 1])
			if x.x == INF:
				continue
			if x.distance_to(c) < lim:
				return true
	return false

func _update_locks() -> void:
	slipping = false
	for k in a_pos.size():
		var th := absf(a_theta[k])
		var engaged := a_freelen[k] >= 0.0
		if not engaged:
			if th < th_rel:
				a_armed[k] = 1        # fully unwound: this anchor can catch again
			if taut and tick_count - grip_edge <= GRIP_WINDOW and th >= th_part and a_lockidx[k] >= pin_min_idx and a_armed[k] == 1:
				# engage: pin the rope's material point at the anchor, tether
				# at the CURRENT distance -> no snap on catch
				var li := a_lockidx[k]
				a_pinidx[k] = li
				a_pin0[k] = li
				a_pinpt[k] = a_pos[k] + (pos[li] - a_pos[k]).normalized() \
					* (a_r[k] + p_rad[li])
				var d := pos[0].distance_to(a_pinpt[k])
				a_freelen[k] = minf(d, cum_len[li])
				a_paytick[k] = 0
				a_locked[k] = -1
				a_pend[k] = 0
				a_minth[k] = th
				a_lastth[k] = th
				a_shed[k] = 0
				a_prun[k] = 0
				# snapshot which chain is in this wrap, as offsets from the pin
				var wlo := li
				var whi := li
				for j in NP:
					if (pos[j] - a_pos[k]).length() 							< a_r[k] + p_rad[j] + wrap_shell + 0.02:
						wlo = mini(wlo, j)
						whi = maxi(whi, j)
				a_wlo[k] = wlo - li
				a_whi[k] = maxi(whi - li, 2)
		else:
			if th < th_rel and not _pinch(k):
				a_freelen[k] = -1.0   # unwound and unpinched - free
				a_pinidx[k] = -1
				a_locked[k] = -1
				a_armed[k] = 1
				continue
			# --- coil economy -------------------------------------------
			if coil_mode > 0 and a_pinidx[k] >= 0:
				# Consume rope only when the wrap passes its previous HIGH
				# WATER MARK of winding. Measured theta jitters by more than a
				# radian tick to tick, and charging every upward wobble (while
				# never refunding the downward ones) is a ratchet on noise: it
				# drains the tether to the floor and the constraint yanks the
				# body into a thrash.
				var dth := th - a_lastth[k]
				if dth > 0.0:
					a_lastth[k] = th
					var arc := dth * (a_r[k] + p_rad[a_pinidx[k]])
					arc = minf(arc, COIL_RATE * DT)   # never yank
					a_freelen[k] = maxf(a_freelen[k] - arc, COIL_MIN_TETHER)
				if coil_mode == 3 and th > th_full + COIL_EXCESS 						and (not grounded):
					# an over-wound coil cannot bear your weight: the excess
					# pays back out, giving the rope back and dropping you
					a_shed[k] += 1
					slipping = true
					if a_shed[k] >= COIL_SHED_TICKS:
						a_shed[k] = 0
						_advance_pin(k)
				else:
					a_shed[k] = 0

			if not taut:
				# HAND OPEN = OFF THE BEAM, THIS TICK.
				# A capstan is a capstan only while something holds the
				# standing part. Open your hand and there is no standing
				# tension, so there is no turn to run out - the rope simply
				# leaves. One frame, every time, whatever the wrap was and
				# wherever along the chain it caught.
				# The old ungripped ratchet paid material through at 3 ticks
				# per index, so a dismount took 3*(25-pin) ticks: 0.05 s to
				# 1.10 s for identical player input, decided by a hidden
				# material index nothing on screen shows. Worse, closing your
				# hand again froze it outright (24 of 27 re-grip trials never
				# came free in 15 s) and any grip reset the run to zero, so
				# feathering the button welded you to the beam. A beam-to-beam
				# line cannot be planned around a release of unknown length.
				a_freelen[k] = -1.0
				a_pinidx[k] = -1
				a_locked[k] = -1
				# You DROPPED the turn - it is not yours any more. Re-catching
				# needs a fresh wrap (theta must fall under th_rel first), so
				# tapping grip cannot reset a partial's betrayal and hang on
				# it forever.
				a_armed[k] = 0
				continue
			if a_locked[k] == -1:
				# Judge the wrap on the WEAKEST winding it actually had, not
				# on whatever it settles into. Contact friction and the pin
				# bed a draped tail onto the beam over ~100 ms, and that creep
				# used to exceed the entire partial-to-locked gap - so most
				# locks were manufactured after the throw was already over.
				# Min also refuses a lock won by a one-tick transient spike.
				# Watch for the pinch over a WINDOW rather than sampling once.
				# Engagement fires while the whip is still landing, but the
				# crossing arrives anywhere from 0 to 20 ticks later, so a
				# single sample at tick 6 permanently misjudged 43% of
				# partials - wraps that really had crossed, sustained for up
				# to 32 ticks, paid out anyway. Only a real crossing can flip
				# the verdict, so this cannot reopen the theta-creep defect
				# that the no-upgrade rule guards against.
				a_pend[k] += 1
				a_minth[k] = minf(a_minth[k], th)
				a_prun[k] = a_prun[k] + 1 if _pinch(k) else 0
				if a_prun[k] >= PINCH_RUN:
					a_locked[k] = 1
					a_ength[k] = a_minth[k]
				elif a_pend[k] >= LOCK_WINDOW:
					a_locked[k] = 0
					a_ength[k] = a_minth[k]
				continue
			# NO upgrade path. A partial used to be able to become locked if
			# theta climbed - but measurement showed the climb was the PIN's
			# doing, not the player's: once a material point is nailed and the
			# weld bites, the still-moving tail winds against a fixed anchor
			# and theta ran 3.78 -> 7.08 during the settle alone. That
			# manufactured 79% of accidental locks. The wrap you threw is the
			# wrap you get.
			if a_locked[k] == 1:
				if th < th_part and not _pinch(k):
					a_locked[k] = 0   # unwound below a full turn: it betrays now
					a_ength[k] = th
				else:
					a_paytick[k] = 0  # locked: committed, no payout
					continue
			# partial wrap under load: material pays through the pin one
			# segment at a time - a slow, audible betrayal, ending with the
			# whip sliding off its own end. "Load" is geometric: the handle
			# is hanging at (or near) the tether's full extension. Constraint
			# strain flags are unreliable here - both the rope sweeps and the
			# LRA clamp the same distance, shielding any strain sensor.
			# "Loaded" cannot be read from tether geometry alone: the pin
			# stays fixed in space while material pays through it, so after a
			# few hops the pin point no longer sits where the chain actually
			# touches, and the distance test goes false while you are plainly
			# hanging off the wrap. Being airborne IS the load.
			var d_now := pos[0].distance_to(a_pinpt[k])
			var loaded := not grounded or d_now > a_freelen[k] - 0.10
			if loaded:
				slipping = true
				a_paytick[k] += 1
				if a_paytick[k] >= PAYOUT_TICKS:
					a_paytick[k] = 0
					_advance_pin(k)

func _advance_pin(k: int) -> void:
	# one segment of material runs through the wrap
	var old := a_pinidx[k]
	if old < 0 or old >= NP - 1 - TAIL_MIN:
		a_freelen[k] = -1.0       # tail too short: the whip slides off
		a_pinidx[k] = -1
		a_locked[k] = -1
		a_armed[k] = 0            # must fully unwind before it can catch again
	else:
		a_pinidx[k] = old + 1
		# RE-SEAT the pin point under the newly pinned material. Handing the
		# pin to the next index while leaving a_pinpt where it was made
		# _solve_lra drag that particle a whole segment - 0.21 m inside one
		# 1 ms substep, an implied 202 m/s - onto the place the previous
		# material used to occupy. The rope sweeps answered with a convulsion
		# that ran down the tail and cracked the tip: measured as an 82-94 px
		# single-frame jump, and seen as the rope twitching on its own.
		a_pinpt[k] = a_pos[k] + (pos[old + 1] - a_pos[k]).normalized() 			* (a_r[k] + p_rad[old + 1])
		a_freelen[k] = minf(a_freelen[k] + rest[old], cum_len[old + 1])

func _events() -> void:
	crack_cooldown = maxf(0.0, crack_cooldown - DT)
	crack_flash = maxf(0.0, crack_flash - DT * 3.0)
	if tip_speed > CRACK_SPEED and crack_cooldown <= 0.0:
		crack_cooldown = 0.3
		crack_flash = 1.0
		if sfx_crack != null:
			sfx_crack.play()
	for k in a_pos.size():
		var half := int(absf(a_theta[k]) / PI)
		if half > a_half[k] and half >= 1:
			if sfx_tick != null:
				sfx_tick.pitch_scale = 1.0 + 0.18 * half
				sfx_tick.play()
		a_half[k] = half
	if sfx_rasp != null:
		if slipping and not sfx_rasp.playing:
			sfx_rasp.play()
		elif not slipping and sfx_rasp.playing:
			sfx_rasp.stop()
	# safety net: below the world (floor tunneling, or running off the end
	# of the map). Move body AND chain rigidly at rest and drop every wrap -
	# teleporting the body alone would leave the whip metres away and the arm
	# tether would fire it across the level.
	if body_pos.y > 6.0:
		falls += 1
		teleport(spawn)
		clear_anchors()
	if body_pos.x > goal_x:
		finished = true

# -------------------------------------------------------------------- draw --
func _draw() -> void:
	# terrain
	for s in t_a.size():
		draw_line(t_a[s] * PPM, t_b[s] * PPM, Color(0.32, 0.35, 0.42), 6.0)
	# goal flag
	var gp := Vector2(goal_x + 1.5, 3.0) * PPM
	draw_line(gp, gp + Vector2(0, -2.2) * PPM, Color(0.5, 0.5, 0.55), 3.0)
	draw_colored_polygon(PackedVector2Array([
		gp + Vector2(0, -2.2) * PPM,
		gp + Vector2(0.8, -1.9) * PPM,
		gp + Vector2(0, -1.6) * PPM,
	]), Color(0.9, 0.55, 0.2))

	# anchors + wrap instrumentation (present-state only)
	for k in a_pos.size():
		var c := a_pos[k] * PPM
		var r := a_r[k] * PPM
		draw_circle(c, r, Color(0.55, 0.48, 0.38))
		draw_circle(c, r * 0.55, Color(0.4, 0.35, 0.28))
		var th := absf(a_theta[k])
		if th > 0.3:
			# Three states, three readings - the amber ring used to mean all of
			# "merely touching", "caught but will betray" and "pending" at once,
			# so a wrap that was about to hold looked exactly like one that never
			# would.
			var engaged := a_freelen[k] >= 0.0
			var locked := engaged and a_locked[k] == 1
			var col := Color(0.55, 0.55, 0.60)              # merely touching
			if locked:
				col = Color(0.3, 0.9, 0.45)                 # pinched: it holds
			elif engaged:
				col = Color(0.95, 0.75, 0.2)                # caught, not pinched
			draw_arc(c, r + 8.0, -PI / 2.0, -PI / 2.0 + th, 24, col, 3.0)
			if engaged and not locked and slipping:
				draw_arc(c, r + 13.0, -PI / 2.0, -PI / 2.0 + th, 24,
					Color(0.95, 0.35, 0.2, 0.8), 2.0)
			for h in range(1, int(th / PI) + 1):
				var ang := -PI / 2.0 + PI * h
				draw_circle(c + Vector2.from_angle(ang) * (r + 8.0), 4.0, col)

	# chain: width tapers with mass, color shows grip state (instrumentation)
	var slack_col := Color(0.78, 0.72, 0.6)
	var taut_col := Color(0.95, 0.45, 0.25)
	var col_now := taut_col if taut else slack_col
	for i in NSEG:
		var w := lerpf(6.0, 2.0, float(i) / float(NSEG - 1))
		draw_line(pos[i] * PPM, pos[i + 1] * PPM, col_now, w)
	# crack flash at the tip (past event, fades)
	if crack_flash > 0.0:
		draw_circle(pos[NP - 1] * PPM, 10.0 * crack_flash,
			Color(1.0, 0.95, 0.7, crack_flash * 0.8))

	# body: a stoic capsule with a face (dignity is the comedy)
	var bp := body_pos * PPM
	draw_circle(bp, BODY_R * PPM, Color(0.85, 0.82, 0.75))
	draw_circle(bp + Vector2(4, -4), 2.2, Color(0.15, 0.15, 0.18))
	draw_circle(bp + Vector2(11, -4), 2.2, Color(0.15, 0.15, 0.18))
	# arm hint: body -> handle
	draw_line(bp, pos[0] * PPM, Color(0.85, 0.82, 0.75, 0.5), 3.0)

	# THE HAND. Grip is a clamp, not rigidity, so draw a fist closing on the
	# rope - and flash it as it closes, because that instant is now the catch.
	var hp := pos[0] * PPM
	if taut:
		var fresh := clampf(1.0 - float(tick_count - grip_edge) / float(GRIP_WINDOW), 0.0, 1.0)
		draw_circle(hp, 9.0, Color(0.95, 0.45, 0.25))
		if fresh > 0.0:
			draw_arc(hp, 11.0 + 9.0 * (1.0 - fresh), 0.0, TAU, 20,
				Color(1.0, 0.85, 0.4, fresh * 0.9), 2.0)
	else:
		draw_arc(hp, 9.0, 0.6, TAU - 0.6, 16, Color(0.80, 0.76, 0.66), 2.5)

	# hand target crosshair (your own input state, not a prediction)
	var tp := target_m * PPM
	draw_line(tp + Vector2(-6, 0), tp + Vector2(6, 0), Color(1, 1, 1, 0.45), 1.5)
	draw_line(tp + Vector2(0, -6), tp + Vector2(0, 6), Color(1, 1, 1, 0.45), 1.5)

# ------------------------------------------------------------------- audio --
func _make_noise_wav(dur: float, decay: float, seed_v: int,
		looped := false) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v          # audio generation only - the SIM has no RNG
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := 1.0 if looped else exp(-float(i) / float(rate) / decay)
		var s := int(clampf(rng.randf_range(-1.0, 1.0) * env, -1.0, 1.0) * 30000.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav

func _make_sine_wav(dur: float, hz: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := exp(-float(i) / float(rate) / 0.015)
		var s := int(sin(TAU * hz * float(i) / float(rate)) * env * 26000.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

# ----------------------------------------------------------------- harness --
func teleport(p: Vector2) -> void:
	# test/debug helper: move body + chain rigidly, at rest
	var d := p - body_pos
	body_pos = p
	body_prv = p
	for i in NP:
		pos[i] += d
		prv[i] = pos[i]

func state_hash() -> int:
	# cheap deterministic digest of the full sim state (for replay regression)
	var h := 1469598103934665603
	for i in NP:
		h = _fnv(h, pos[i].x)
		h = _fnv(h, pos[i].y)
		h = _fnv(h, prv[i].x)
		h = _fnv(h, prv[i].y)
	h = _fnv(h, body_pos.x)
	h = _fnv(h, body_pos.y)
	h = _fnv(h, body_prv.x)
	h = _fnv(h, body_prv.y)
	for k in a_freelen.size():
		h = _fnv(h, a_freelen[k])
		h = _fnv(h, float(a_pinidx[k]))
		h = _fnv(h, float(a_locked[k]))
		h = _fnv(h, a_theta[k])
	return h

func _fnv(h: int, v: float) -> int:
	var bits := PackedFloat64Array([v]).to_byte_array()
	for b in bits:
		h = int((h ^ b) * 1099511628211) & 0x7FFFFFFFFFFFFFFF
	return h
