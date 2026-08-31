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
var arm_max := 1.15                   # m, one-sided body<->handle tether.
                                      # NOTE this is longer than REACH (1.15):
                                      # the arm hangs further than it reaches,
                                      # which deepens every hang by 0.15 m.
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
var wrap_near := 0.30                 # m past the surface: winding measured
                                      # about a beam the rope is nowhere near
                                      # is not a wrap ON it. The same outer
                                      # band the old contact rule used.
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
var a_paytick := PackedInt32Array()   # payout timer for a betraying wrap
var a_prun := PackedInt32Array()      # consecutive ticks this wrap has pinched
var a_clear := PackedInt32Array()     # consecutive ticks the rope has been off
var a_wlo := PackedInt32Array()
var a_whi := PackedInt32Array()
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
const PAYOUT_TICKS := 15              # ticks between one segment paying
                                      # through a slipping partial wrap
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
# Per-segment bounding box, so a particle can skip terrain it cannot possibly
# be touching. Without this every one of 26 particles tests every segment and
# every beam, twice, 16 times a tick - about 21,600 checks a frame, which
# measured at 8-10 ms and half a 60 Hz budget before a single sprite exists.
# The margin is deliberately generous: _collide_point acts at ANY depth on the
# solid side (that is the rescue path for a particle found inside terrain), so
# the cull must never hide a particle it would have lifted out.
var world_bottom := 6.0               # y past which the body is out of the
                                      # world. DERIVED from the terrain, never
                                      # hardcoded: it was a literal 6.0 and the
                                      # level was later terraced down to y=12,
                                      # so standing on either of the last two
                                      # tiers tripped the out-of-world net and
                                      # teleported the player to spawn.
var t_lo := PackedVector2Array()
var t_hi := PackedVector2Array()
const CULL_MARGIN := 2.5              # m of slack around each segment's box
# A beam you have LET GO OF is not something your rope grips, and not something
# it can be caught by. A capstan multiplies the tension you are holding; with
# an open hand there is nothing to multiply, so the rope should simply slide
# off. Shipping without this, a released beam kept full kinetic friction and
# the capstan went on amplifying it: measured, ~80% of the drag on a dismount
# was friction on a rope nobody was holding - 1.27 m/s of the launch, 1.42 m/s
# of it aimed straight back at the beam, still acting ~950 ms after release.
# Worse, it was invisible: a rope merely DRAPED along a beam reads as almost no
# wrap yet touches over 17-20 particles, so the throws the ring showed as
# barely wrapped dragged MORE than clean ones. That is randomness, not skill.
# The same disarm also stops the beam re-taking the rope when you press for the
# NEXT one - 25 of 108 attempts, 24 of them through the self-crossing branch at
# a wrap angle far below the catch bar.
const RELEASED_MU := 0.04             # friction on a beam you have let go of
const CLEAR_TICKS := 10               # ticks with no contact before it re-arms

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
                                      # way to the beam - it is a drift, not a
                                      # docking mechanism.
                                      # tether. This has to read as being
                                      # slowly drawn in; anything brisk both
                                      # yanks the body into a thrash and makes
                                      # landing a good whip pointless, because
                                      # stirring would beat throwing.
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
	_boot_session()   # resume the run in progress, or record / replay a tape

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
		a_locked[k] = -1
		a_armed[k] = 1
		a_paytick[k] = 0
		a_prun[k] = 0
		a_clear[k] = 0
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
	# LEVEL CONTRACT - measured, not assumed.
	#
	# THE GOVERNING FACT: a beam cannot be both catchable from a standstill
	# (needs <= ~2.4 m above the floor you THROW from) and launchable (you
	# hang tether + arm + body below it, so it needs > ~3.2 m of air under
	# the arc). Those contradict each other only while both refer to the SAME
	# floor - the contradiction is a property of flat ground, not of beams.
	# A step dissolves it, because the beam then has TWO heights.
	#
	# So the level is that step, repeated: a flat tier, a lip, a beam hung
	# 1.4 m PAST the lip, then a 3 m drop to the next tier. Each such beam is
	# 2.2 m over the tier you throw from and 5.2 m over the one you swing in.
	# Catch it standing on the tier and holding it hauls you off the edge -
	# the tether is fixed at handle-to-wrap and your handle is out ahead of
	# you, so the rope comes up shorter than you stand.
	#
	# Every drop faces DOWNHILL along the route, so the lash gait (which
	# crawls flat ground at ~0.44 m/s and cannot climb even a 20 degree
	# slope) can always shuffle forward to the next door beam. Falling costs
	# ground and time; it never costs the run.
	var pts: Array[Vector2] = [
		Vector2(-14, 0), Vector2(20, 0),        # home tier: the school
		Vector2(20, 3.0), Vector2(30, 3.0),     # tier 1
		Vector2(30, 6.0), Vector2(40, 6.0),     # tier 2
		Vector2(40, 9.0), Vector2(48, 9.0),     # tier 3 (short, so the last
		Vector2(48, 12.0), Vector2(62, 12.0),   # fast beam clears its lip)
		                                        # tier 4, the run out
		Vector2(62, 5.0),                       # seal the far end
	]
	for i in range(pts.size() - 1):
		t_a.append(pts[i])
		t_b.append(pts[i + 1])
	# left wall, wound bottom-to-top so its outward normal points into the level
	t_a.append(Vector2(-14, -8)); t_b.append(Vector2(-14, 0))
	t_n.clear()
	t_lo.clear()
	t_hi.clear()
	var deepest := -1e9
	for i in t_a.size():
		deepest = maxf(deepest, maxf(t_a[i].y, t_b[i].y))
	world_bottom = deepest + 4.0

	for i in t_a.size():
		t_n.append(Vector2((t_b[i] - t_a[i]).y, -(t_b[i] - t_a[i]).x).normalized())
		t_lo.append(Vector2(minf(t_a[i].x, t_b[i].x), minf(t_a[i].y, t_b[i].y)))
		t_hi.append(Vector2(maxf(t_a[i].x, t_b[i].x), maxf(t_a[i].y, t_b[i].y)))

	# Beams. DOOR beams sit 1.4 m past each lip: 2.2 m over the tier you
	# throw from, 5.2 m over the tier you swing in - the only kind you can
	# both catch cold and launch from. FAST beams sit 4.5 m over the tier
	# beneath them, out of reach from the ground, catchable only from the
	# apex of a swing, spaced 7.8 m - both numbers verified by the route bot
	# (4/4 legs at 6.8 and 7.8 m, 3/4 at 8.6, 0/4 at 10.5; 4/4 at 4.5 m of
	# height, 2/4 at 4.0, 0/4 at 3.0).
	var anchors := [
		# THE SCHOOL, on the home tier (floor y=0)
		[-2.0, -2.2, 0.22],   # throw, wrap, grip, hang
		[ 3.6, -2.2, 0.22],   # pump, release, chain a second catch
		[15.6, -2.2, 0.20],   # the run-up to the first lip
		# THE DOORS - one per lip, each 1.4 m past it
		[21.4, -2.2, 0.11],   # onto tier 1
		[31.4,  0.8, 0.11],   # onto tier 2
		[41.4,  3.8, 0.11],   # onto tier 3
		[49.4,  6.8, 0.11],   # onto tier 4
		# THE FAST LINE - 4.5 m over the tier below, 7.8 m apart
		[27.2, -1.5, 0.10],
		[35.0,  1.5, 0.10],
		[42.8,  4.5, 0.10],
		[50.6,  7.5, 0.10],
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
		a_locked.append(-1)
		a_armed.append(1)
		a_pin0.append(-1)
		a_pend.append(0)
		a_ength.append(0.0)
		a_minth.append(0.0)
		a_wlo.append(0)
		a_whi.append(0)
		a_paytick.append(0)
		a_prun.append(0)
		a_clear.append(0)

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
			# DEFERRED, so that restarting is part of a TICK. R is the one verb
			# that is not (cursor, grip), and a tape that could not carry it
			# would replay a session containing an R press as a session that
			# never restarted - silently, and wrongly. Applying it at the top of
			# step_tick puts it inside the recorded input stream instead.
			pending_reset = true
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()

func _physics_process(_d: float) -> void:
	if external_drive:
		return
	if play_on:
		_play_tick()
		cam.position = (body_pos + Vector2(0.0, -1.4) + _body_vel() * 0.25) * PPM
		return
	if play_done:
		return                        # a finished replay holds its last frame
	var mouse := get_global_mouse_position() / PPM
	var grip := Input.is_key_pressed(KEY_SPACE) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	step_tick(mouse, grip)
	cam.position = (body_pos + Vector2(0.0, -1.4) + _body_vel() * 0.25) * PPM
	save_due -= 1
	if save_enabled and save_due <= 0:
		save_due = AUTOSAVE_TICKS
		save_to(save_path)

func _process(_d: float) -> void:
	queue_redraw()
	if status != null:
		var secs := run_ticks / 60.0
		var line := "time %.1fs   falls %d   tip %.0f m/s" % [secs, falls, tip_speed]
		if finished:
			line = "TRAVERSE COMPLETE in %.1fs - press R to run it again" % secs
		if rec_on:
			line += "   [REC %d]" % rec_cur.size()
		elif play_on:
			line += "   [REPLAY %d/%d]" % [play_at, int(play_tape["n"])]
		elif play_done:
			line += "   [REPLAY ENDED]"
		status.text = line

# ---------------------------------------------------------------- sim tick --
func step_tick(cursor_world_m: Vector2, grip: bool) -> void:
	rec_rst = pending_reset
	if pending_reset:
		pending_reset = false
		_reset()
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
	if rec_on:
		_rec_tick()

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
	if l > arm_max and l > 0.0001:
		var w0 := inv_m[0]
		var wb := 1.0 / BODY_M
		var corr := d * ((l - arm_max) / l / (w0 + wb))
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
	_swept_body()
	for i in NP:
		_collide_point(i, p_rad[i])
	_collide_body()

func _collide_point(i: int, pr: float) -> void:
	var p := pos[i]
	for s in t_a.size():
		if p.x < t_lo[s].x - CULL_MARGIN or p.x > t_hi[s].x + CULL_MARGIN 				or p.y < t_lo[s].y - CULL_MARGIN or p.y > t_hi[s].y + CULL_MARGIN:
			continue
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
		var rr := a_r[k] + pr
		if d2.length_squared() >= rr * rr:
			continue
		var l2 := d2.length()
		if l2 > 0.0001:
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
			elif a_armed[k] == 0:
				mu = RELEASED_MU      # let go of: it slides, it does not grip
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
	var slo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var shi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
	for k in a_pos.size():
		var c := a_pos[k]
		var rk: float = a_r[k] + p_rad[i]
		if shi.x < c.x - rk or slo.x > c.x + rk 				or shi.y < c.y - rk or slo.y > c.y + rk:
			continue
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
	var mlo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var mhi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
	for s in t_a.size():
		# exact: two segments cannot cross if their boxes do not overlap
		if mhi.x < t_lo[s].x or mlo.x > t_hi[s].x 				or mhi.y < t_lo[s].y or mlo.y > t_hi[s].y:
			continue
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

func _swept_body() -> void:
	# Anti-tunnel for the body against the beams, same role as _swept_anchor
	# does for the chain, and it runs in the same sweeps-before-discrete phase.
	# The discrete test below only sees a body that ENDS a substep overlapping,
	# so what it misses is set by how long a chord the path cuts, not by the
	# beam's size. Measured (tests/bb.gd -- tunnel, phase-scanned, per substep,
	# 0.10 m beam), the discrete pass ALONE first misses a contact of depth
	#     0.3 mm at  30 m/s   2 mm at  81 m/s   5 mm at 128 m/s
	#      20 mm at 255 m/s  50 mm at 391 m/s   the whole beam at 762 m/s
	# and the fastest body the game produces is 31.7 m/s (tests/bb.gd -- speed:
	# a hard crack while hanging, sustained per tick, not a one-substep spike).
	# So the discrete pass alone would already be right to within a third of a
	# millimetre and could not be walked through short of 24x the game's top
	# speed - but 31.7 > 30, the margin is gone at the top of the range, and
	# this closes it for nothing: it arms only above 19.2 m/s of substep travel
	# and then only inside a beam's own bounding box. With it, no speed tested
	# up to 30 km/s gets past any beam at any depth.
	# Terrain gets no body sweep because it genuinely does not need one: a
	# half-space has no chord to graze, so the body has to cover its own 0.28 m
	# radius in one substep to tunnel it - 269 m/s.
	var p0 := body_prv
	var p1 := body_pos
	var seg := p1 - p0
	var lsq := seg.length_squared()
	if lsq < 0.0004:
		return
	var slo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var shi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
	# Find the FIRST beam the path enters and resolve only that one. Resolving
	# each beam in turn (which is what _swept_anchor does for the chain) would
	# leave seg and the path box describing a journey the body no longer took,
	# and there is no need: this is a single substep, and what happens after
	# the body stops at the first beam is the next substep's business.
	var best := 2.0
	var bk := -1
	for k in a_pos.size():
		var c := a_pos[k]
		var rk: float = a_r[k] + BODY_R
		if shi.x < c.x - rk or slo.x > c.x + rk 			or shi.y < c.y - rk or slo.y > c.y + rk:
			continue
		var e := p0 - c
		var b := e.dot(seg)
		var cc := e.length_squared() - rk * rk
		if cc < 0.0:
			continue                    # started inside: the discrete pass owns it
		var disc := b * b - lsq * cc
		if disc <= 0.0:
			continue                    # the path misses the circle entirely
		var tt := (-b - sqrt(disc)) / lsq
		if tt < 0.0 or tt > 1.0 or tt >= best:
			continue
		best = tt
		bk = k
	if bk < 0:
		return
	# Resolve at the ENTRY point, not at wherever the body ended up:
	# _swept_anchor pushes a chain particle out along (p1 - c), which for a
	# tunnelling particle is the FAR side - fine for a 0.02 m rope vertex
	# nobody can see, wrong for the body, because it hands you a free pass
	# through the beam. A beam you hit is a beam you do not get to be behind.
	var rr: float = a_r[bk] + BODY_R
	var n := (p0 + seg * best) - a_pos[bk]
	if n.length() < 0.0001:
		return
	n = n.normalized()
	body_pos = a_pos[bk] + n * rr
	# Carry the INCOMING velocity across the resolution, minus its inward
	# normal part. Same reasoning as _swept_terrain: scaling what survives by
	# the crossing fraction - where in the substep it happened - is physically
	# meaningless, and the place-out displacement must never become velocity.
	# Only approach is removed, so a body already leaving is not glued on.
	body_prv = body_pos - (seg - n * minf(seg.dot(n), 0.0))

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
	# THE BEAMS ARE SOLID. This loop used to be missing entirely: the body was
	# tested against terrain and nothing else, so it passed clean through the
	# very beam it was hanging from - measured at up to 0.50 m of overlap, the
	# whole beam swallowed, on every radius in the level (tests/bb.gd -- ghost).
	# Anchors are convex circles, so unlike the terrain polyline there is no
	# "which side is solid" question and no rescue branch is needed: outward is
	# always radially away from the centre.
	#
	# NO TANGENTIAL FRICTION, and that is the design ruling, not laziness. A
	# beam that grips is a PLATFORM: Coulomb friction holds a body at rest
	# anywhere inside atan(mu) of the apex, which at ground_mu is 17 degrees -
	# a 0.11 m half-width on the thinnest beam, and wider than that in practice
	# because a body that ARRIVES with momentum beds in. Measured both ways
	# (tests/bb.gd -- rest, this build against the same patch with the
	# tangential Coulomb cap switched on at ground_mu):
	#        dropped on it        a player actively trying to perch
	#   0.30   17-18 of 20 stay,   14 of 15 with the hand held overhead,
	#          out to 0.18 m       15 of 15 with it held still or below
	#   0.00   1 of 20 - and       0 of 15, on every beam, every hand
	#          that one is the
	#          exact float apex
	# The apex case is the exact-zero offset; one micrometre off it and the
	# body slides away (worst 3.3 s), so it is unreachable in play rather than
	# merely unlikely. mu = 0.30 is a second way to be somewhere the whip is
	# supposed to be the only way to reach - a free rest on the HIGH beams the
	# README calls the skill ceiling, and one the "a fall costs ground, never
	# the run" contract has no answer for. It is an assist, so it is out.
	# It is also what a smooth round bar and a body with no arms actually do:
	# the rope is how you hold a beam. That is the whole game.
	#
	# So the beam takes the APPROACH component of the body's velocity and
	# nothing else - the least a solid can take. Measured (tests/bb.gd
	# -- swing) at 8 m/s past a beam: exactly 0.000% and 0.0 degrees at any
	# clearance at or above zero - a beam you miss is bit-for-bit invisible -
	# 10-13% if you clip it by 0.05 m, 40-52% if you bury 0.20 m into it. Flown
	# past the real beams on the real level, patched against the build at HEAD:
	# 0.00% wherever the old body would not have overlapped either, 0.6% on a
	# graze. What is left is not drag, it is the beam being in the way.
	#
	# grounded is deliberately NOT set here. It means "standing on the floor",
	# and it is what _update_locks reads to decide a partial wrap is unloaded
	# and may stop paying out. Letting a beam set it would freeze the betrayal
	# of any partial wrap you happened to be leaning on - a stuck state built
	# out of the anti-stuck mechanism.
	for k in a_pos.size():
		var dk := p - a_pos[k]
		var rr: float = a_r[k] + BODY_R
		if dk.length_squared() >= rr * rr:
			continue
		var lk := dk.length()
		if lk <= 0.0001:
			continue
		var nk := dk / lk
		# v is read BEFORE the push-out, so the depenetration displacement never
		# becomes velocity (the same discipline _collide_point's rescue branch
		# and _swept_terrain use, and stricter than the terrain branch above,
		# which reads v after). Only the approach half is removed: zeroing the
		# whole normal component would also cancel a body that is LEAVING, and
		# since the arm tether can push the body into a beam every substep,
		# that would read as glue.
		var vk := body_pos - body_prv
		body_pos = a_pos[k] + nk * rr
		body_prv = body_pos - (vk - nk * minf(vk.dot(nk), 0.0))
		p = body_pos

# ------------------------------------------------------------- wrap logic --
func _measure_wraps() -> void:
	# THE TAUT WRAP ANGLE. Pull the chain tight without letting it pass through
	# the beam. The plane minus a disc has fundamental group Z, so the taut
	# path in the chain's own homotopy class is unique - tangent leg, arc,
	# tangent leg - and its ARC is the only winding that survives pulling. That
	# arc is the angle a capstan is written in, and it is what this measures:
	#
	#     theta = |PHI| - acos(r / d_handle) - acos(r / d_tip)
	#
	# with PHI the lifted winding of the whole chain about the beam centre,
	# summed with angle_to, which is the exact continuous lift.
	#
	# It replaces a COUNT of chain segments with both endpoints inside a 4 mm
	# shell, times a constant. Every number below is measured against ground
	# truth over 576 thrown wraps - tests/jb2/feat_dump.gd collects it,
	# tests/jb2/score.py scores it, tests/jb2/closed_loop.gd audits the whole
	# loop with the hand actually closing.
	#
	#  - THE COUNT CHATTERS. It moves 0.47 rad in an average tick while the
	#    rope is wrapped, and up to 5.25 rad in one tick. On a wrap rigged so
	#    it CANNOT change (tests/orc_valid.gd) it ranges over 1.88 to 7.47 rad
	#    while the geometry is frozen; this reads 0.000 rad of movement on
	#    that same wrap, and 0.18 rad in an average thrown tick.
	#  - THE COUNT GOES BLIND. It is silent on 327 of 3606 wrapped ticks, in
	#    unbroken runs of up to 17 ticks - longer than the entire 15-tick
	#    press window. Two of the 106 wrapped throws had no press window at
	#    all and four had a hole in the middle of one. This has no blind tick
	#    anywhere and no holes: all 106 get one unbroken window.
	#  - AND THE COUNT OVER-READS, which is the worse half, because it is the
	#    half that catches you on nothing. It fires on 635 ticks where the
	#    rope is not wrapped - 64% of all its firings on a 0.24 m beam - it
	#    lets 27 throws that never wrap at all be caught anyway, and it
	#    catches a LIMP DRAPE on every beam radius in the level
	#    (tests/jb2/refusal_stress2.gd) at a true wrap of 0.12-0.78 rad.
	#
	# What makes this trustworthy where a count is not: it is continuous in
	# every vertex position, so it cannot chatter, and it needs no shell.
	#
	# It does not loosen what counts as a catch - it TIGHTENS it, and provably.
	# A rope merely LYING across a beam scores 0: all of its winding is tangent
	# legs, which is exactly what the subtraction removes. A limp DRAPE scores
	# pi and no more, however deep it hangs, because pi IS the pulley wrap -
	# the exact boundary between "lies on" and "is wound on". Getting past pi
	# needs an end of the rope to have gone round the far side. Measured:
	# over the 113895 corpus ticks with the chain entirely on ONE side of a
	# beam, or not touching it at all, this never once exceeded 2.933 rad.
	# th_part = 3.4 therefore asks for a real hook a sixth of a turn past a
	# half turn, and no drape in the corpus reaches it.
	for k in a_pos.size():
		var c := a_pos[k]
		var r := a_r[k]
		var phi := 0.0
		var mind := 1e9
		var nearest := -1
		var nearest_d := 1e9
		for i in range(NP - 1):
			var v0 := pos[i] - c
			var v1 := pos[i + 1] - c
			phi += v0.angle_to(v1)
			var d0 := v0.length()
			if d0 < nearest_d:
				nearest_d = d0
				nearest = i
			mind = minf(mind, c.distance_to(
				Geometry2D.get_closest_point_to_segment(c, pos[i], pos[i + 1])))
		# strip the two tangent legs: they carry winding but no wrap
		var dh: float = maxf((pos[0] - c).length(), r)
		var dt: float = maxf((pos[NP - 1] - c).length(), r)
		var arc: float = absf(phi) - acos(clampf(r / dh, -1.0, 1.0)) \
			- acos(clampf(r / dt, -1.0, 1.0))
		if arc <= 0.0 or mind >= r + wrap_near:
			a_theta[k] = 0.0
		else:
			a_theta[k] = arc if phi >= 0.0 else -arc
		# The lock index answers "which material point would take this wrap",
		# which is a fact about PROXIMITY, not about winding. Gating it on the
		# winding angle refused 33 of the corpus's 3606 wrapped ticks outright:
		# a self-crossing can hold a body while the taut wrap is still under
		# 0.3 rad, and on those ticks the index read -1 and the catch was
		# refused no matter how well the wrap itself was measured.
		if nearest >= 0 and mind < r + wrap_near:
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
			# Re-arm on the rope being CLEAR, not on the wrap angle dropping.
			# The angle falls the instant you let go while the rope is still
			# lying across the beam - which is how the beam you just left was
			# re-catching you on the press meant for the next one.
			var touching := 0
			for i in NP:
				if (pos[i] - a_pos[k]).length_squared() 						< pow(a_r[k] + p_rad[i] + 0.06, 2.0):
					touching += 1
					break
			a_clear[k] = 0 if touching > 0 else a_clear[k] + 1
			if a_clear[k] >= CLEAR_TICKS and th < th_rel:
				a_armed[k] = 1        # rope is off it: this beam can catch again
			# A CATCH FIRES ONLY ON A ROPE THAT IS WRAPPED RIGHT NOW.
			# The look-back that used to sit here ("...or it qualified within
			# the last 15 ticks") was a bridge over the dead ticks the contact
			# count produced. The taut wrap has none: measured over 576 thrown
			# wraps, every single one now has an unbroken press window, and
			# there is not one tick in 120960 where the rope is wrapped and
			# this test is silent. So the bridge can no longer rescue anything
			# - it can only admit rope that has stopped being wrapped, which it
			# did on 449 ticks with the taut wrap between 1.80 and 3.40 rad,
			# under a HALF TURN on 383 of them. It is gone.
			# What remains is the FORWARD buffer, which is the honest half: you
			# close your hand and the sim honours that press for GRIP_WINDOW
			# ticks, taking the wrap the instant it exists and never before.
			# A self-crossing also qualifies: _pinch is this file's own
			# definition of a wrap that can hold a body, and it is STRICTER
			# evidence than th_part, not looser.
			if taut and tick_count - grip_edge <= GRIP_WINDOW and a_armed[k] == 1 and a_lockidx[k] >= pin_min_idx and (th >= th_part or _pinch(k)):
				# engage: pin the rope's material point at the anchor, tether
				# at the CURRENT distance -> no snap on catch
				var li := a_lockidx[k]
				a_pinidx[k] = li
				a_pin0[k] = li
				a_pinpt[k] = a_pos[k] + (pos[li] - a_pos[k]).normalized() \
					* (a_r[k] + p_rad[li])
				var d := pos[0].distance_to(a_pinpt[k])
				a_freelen[k] = minf(d, cum_len[li])
				a_locked[k] = -1
				a_pend[k] = 0
				a_minth[k] = th
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
	if body_pos.y > world_bottom:
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
	var gp := Vector2(goal_x + 1.5, 12.0) * PPM
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
			# A wrap made from far away pinches on its own draped TAIL, so it
			# classifies green and then tears off the moment a real swing
			# straightens that tail out. On flat ground a dead hang never
			# loads it enough to show; off the door it decides everything.
			# If there is less chain past the wrap than a pinch needs, say so
			# now - present state, not prediction: a tell, not a trap.
			if locked and a_pinidx[k] >= 0:
				var tail: float = cum_len[NP - 1] - cum_len[a_pinidx[k]]
				if tail < PINCH_TURN * TAU * (a_r[k] + 0.02):
					locked = false
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

# ------------------------------------------------------------ save / resume --
# THE RUN IS THE SAVE. One slot, overwritten continuously while you play, and
# loading it puts you back exactly where you were - mid-fall, mid-wrap,
# mid-betrayal, mid-coil. That is the design and not a shortcut: this is a
# Getting Over It lineage game with diegetic loss and no checkpoints, so
# save-scumming is not forbidden by a rule, it is structurally absent. There is
# no earlier state to go back to, because the game never keeps one. Quit while
# falling and you resume falling. R restarts, and it discards the whole run.
#
# PLATFORM CAVEAT, and it is a real one. A save (and a tape) resumes
# bit-identically on the SAME BUILD on the SAME PLATFORM, and nowhere else. The
# sim has no RNG, a fixed tick and a fixed substep count, but IEEE 754 does not
# oblige two architectures to agree on sin/cos/sqrt/acos and x86 and ARM
# measurably do not. Nothing here assumes otherwise: state carried to a
# different machine simply diverges, and the tape verifier says so out loud
# rather than passing quietly.
const SAVE_MAGIC := 0x57485031        # "WHP1"
const SAVE_VERSION := 1
const SAVE_PATH := "user://run.save"
const AUTOSAVE_TICKS := 30            # half a second: the most a crash can cost

# WHAT IS THE SIMULATION is answered by the object, not by a list kept by hand.
# Every script variable is state unless it is named here or is a node. A
# hand-kept list goes stale in silence, which is not hypothetical: the planner's
# own STATE_KEYS in tests/bot_leap.gd still names a_lastth and a_shed - deleted
# fields, both - and has never heard of a_clear, which drives the re-arm, so
# every planning candidate it restores carries one field from another timeline
# and nothing anywhere says so. Declare a var and it is in the snapshot.
const SNAP_SKIP := ["external_drive", "save_enabled", "save_path", "save_due",
	"rec_on", "rec_path", "rec_cur", "rec_grip", "rec_chk", "rec_start",
	"rec_note", "rec_cen", "rec_prev", "rec_rst",
	"play_on", "play_done", "play_tape", "play_at"]

var save_enabled := false             # only a real windowed session writes to
                                      # disk. The probes build the sim with
                                      # new() and never enter the tree, so
                                      # _ready never fires and no test can
                                      # touch a save file by accident.
var save_path := SAVE_PATH
var save_due := 0
var pending_reset := false            # R, applied at the top of the next tick

static func _dup(v: Variant) -> Variant:
	# A packed array handed out by get() shares its buffer with the field it
	# came from, so a snapshot that did not copy would be rewritten by the very
	# ticks it is supposed to outlive.
	match typeof(v):
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, \
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY, \
		TYPE_PACKED_STRING_ARRAY, TYPE_ARRAY, TYPE_DICTIONARY:
			return v.duplicate()
	return v

func snap_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for p in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if int(p["type"]) == TYPE_OBJECT:
			continue
		var n: String = p["name"]
		if SNAP_SKIP.has(n):
			continue
		out.append(n)
	return out

func snapshot() -> Dictionary:
	var s := {}
	for k in snap_keys():
		s[k] = _dup(get(k))
	return {"v": SAVE_VERSION, "lvl": level_fingerprint(), "h": state_hash(),
		"s": s}

func restore(d: Dictionary) -> bool:
	# Bit-identical, and asserted rather than asserted-by-comment:
	# tests/save_test.gd snapshots mid-air, mid-wrap, mid-betrayal and while the
	# whip is coiled, runs 300 ticks on from each, restores, runs the same 300,
	# and requires one hash - matching an uninterrupted run as well.
	if int(d.get("v", -1)) != SAVE_VERSION:
		return false
	var s: Dictionary = d.get("s", {})
	if s.is_empty():
		return false
	# THE KEY SET HAS TO MATCH EXACTLY. A var added, renamed or deleted since
	# this state was written means the file describes a different simulation,
	# and applying the keys that happen to still exist would restore a body from
	# one build wearing another build's wrap state - the same partial-restore
	# defect as a stale hand-kept list, arriving by file instead. Refuse it and
	# say so. If the new var is not simulation state, it belongs in SNAP_SKIP;
	# if it is, the state genuinely is not portable and the tapes want
	# re-recording anyway.
	var keys := snap_keys()
	if s.size() != keys.size():
		return false
	for k in keys:
		if not s.has(k):
			return false
	for k in s:
		set(k, _dup(s[k]))
	return true

func level_fingerprint() -> int:
	# Identity of the WORLD a save or a tape was taken in: terrain, beams,
	# spawn, goal, and the fixed shape of the sim. Deliberately NOT of the sim's
	# BEHAVIOUR - hashing this file would make every edit invalidate every tape,
	# and tapes that are thrown away on every edit test nothing. A behaviour
	# change is meant to surface as a hash divergence at the tick it starts. A
	# LEVEL change is a different failure - the recorded cursor no longer refers
	# to anything - so that one is refused up front with its own message.
	var h := 1469598103934665603
	h = _fnv(h, float(NP))
	h = _fnv(h, float(SUB))
	h = _fnv(h, float(t_a.size()))
	h = _fnv(h, float(a_pos.size()))
	for i in t_a.size():
		h = _fnv(h, t_a[i].x); h = _fnv(h, t_a[i].y)
		h = _fnv(h, t_b[i].x); h = _fnv(h, t_b[i].y)
	for k in a_pos.size():
		h = _fnv(h, a_pos[k].x); h = _fnv(h, a_pos[k].y); h = _fnv(h, a_r[k])
	h = _fnv(h, spawn.x); h = _fnv(h, spawn.y)
	h = _fnv(h, goal_x); h = _fnv(h, world_bottom)
	return h

func save_to(path: String) -> bool:
	# Write beside the save and rename over it, so a crash mid-write costs the
	# last half second and not the run.
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(SAVE_MAGIC)
	f.store_32(SAVE_VERSION)
	f.store_var(snapshot(), false)
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	return dir.rename(path.get_file() + ".tmp", path.get_file()) == OK

func load_from(path: String) -> int:
	# 1 resumed, 0 nothing to resume, -1 refused (wrong build or wrong level).
	# The .tmp fallback catches the one crash window the rename leaves open.
	for p: String in [path, path + ".tmp"]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		if f.get_32() != SAVE_MAGIC or f.get_32() != SAVE_VERSION:
			continue
		var d: Variant = f.get_var(false)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		if int((d as Dictionary).get("lvl", 0)) != level_fingerprint():
			return -1
		return 1 if restore(d) else -1
	return 0

# ------------------------------------------------------------- input tapes --
# A tape is the game's ENTIRE input surface - (cursor, grip) per tick, plus the
# one deferred R - together with the state it started from and the hashes it
# produced. Replaying it asks the only question that needs no oracle: does the
# game still do what it did yesterday?
#
# That matters here more than another probe would. In one session three separate
# gates were found to be quietly lying - a drape test that passed a build which
# caught drapes on every beam radius, a stuck-in-floor probe carrying the old
# level geometry hardcoded so it reported a bug 0.79 m in mid-air, and a level
# probe certifying a safety contract from a hand-laid chain state no real run
# ever produces. Every one of them needed an oracle to catch. A replay needs
# none, and it cannot certify a hand-laid state, because its start state and its
# inputs both came from a run that actually happened.
#
# Checkpoint hashes every TAPE_CHECK ticks localise a divergence to half a
# second instead of "somewhere in this minute". The census is recorded so a tape
# cannot be vacuous without saying so: a tape whose census reads zero locks is
# not testing locks, and it prints that at you.
const TAPE_MAGIC := 0x57545031        # "WTP1"
const TAPE_VERSION := 1
const TAPE_CHECK := 30                # ticks between checkpoint hashes

var rec_on := false
var rec_path := ""
var rec_cur := PackedVector2Array()
var rec_grip := PackedByteArray()     # bit 0 = grip, bit 1 = R this tick
var rec_chk := PackedInt64Array()
var rec_start := {}
var rec_note := ""
var rec_cen := {}
var rec_prev := {}
var rec_rst := false
var play_on := false
var play_done := false
var play_tape := {}
var play_at := 0

func rec_begin(note := "") -> void:
	rec_start = snapshot()
	rec_note = note
	rec_cur = PackedVector2Array()
	rec_grip = PackedByteArray()
	rec_chk = PackedInt64Array()
	rec_cen = {"catch": 0, "lock": 0, "pay": 0, "slide": 0, "dismount": 0,
		"unwind": 0, "fall": 0, "crack": 0, "gnd": 0, "air": 0, "wrapped": 0,
		"airrun": 0, "maxdrop": 0.0, "maxtip": 0.0, "crawl": 0.0,
		"reset": 0, "x0": 0.0, "x1": 0.0}
	# Seed the transition detectors from the state the tape STARTS in. Left
	# empty, an anchor that is already engaged when recording begins reads as a
	# fresh catch on tick 1 - a census that counts a catch no one made is the
	# same species of lie as a gate that passes on nothing.
	var e0 := PackedByteArray()
	var l0 := PackedByteArray()
	var p0 := PackedInt32Array()
	e0.resize(a_pos.size()); l0.resize(a_pos.size()); p0.resize(a_pos.size())
	for k in a_pos.size():
		e0[k] = 1 if a_freelen[k] >= 0.0 else 0
		l0[k] = 1 if (e0[k] == 1 and a_locked[k] == 1) else 0
		p0[k] = a_pinidx[k] if e0[k] == 1 else -1
	rec_prev = {"eng": e0, "lk": l0, "pin": p0, "falls": falls,
		"flash": crack_flash, "bx": body_pos.x, "airtop": body_pos.y,
		"airrun": 0}
	rec_on = true

func rec_end() -> void:
	rec_on = false

func _rec_tick() -> void:
	rec_cur.append(cursor_m)
	rec_grip.append((1 if taut else 0) | (2 if rec_rst else 0))
	if rec_rst:
		rec_cen["reset"] = int(rec_cen["reset"]) + 1
	rec_rst = false
	# --- census: what this tape actually contains, counted from the same code
	# on the way in and on the way out, so record and replay cannot disagree
	# about the question they are asking.
	var c := rec_cen
	var n := a_pos.size()
	var pe: PackedByteArray = rec_prev.get("eng", PackedByteArray())
	var pp: PackedInt32Array = rec_prev.get("pin", PackedInt32Array())
	var pl: PackedByteArray = rec_prev.get("lk", PackedByteArray())
	if pe.size() != n:
		pe.resize(n); pl.resize(n); pp.resize(n)
		for k in n:
			pp[k] = -1
	var wrapped := false
	for k in n:
		var e := 1 if a_freelen[k] >= 0.0 else 0
		if e == 1:
			wrapped = true
		if e == 1 and pe[k] == 0:
			c["catch"] = int(c["catch"]) + 1
		elif e == 0 and pe[k] == 1:
			# how the wrap ended, told apart the way _update_locks tells them
			# apart: an open hand is a dismount, a re-armed anchor unwound on
			# its own, and anything else ran out of tail and slid off.
			if not taut:
				c["dismount"] = int(c["dismount"]) + 1
			elif a_armed[k] == 1:
				c["unwind"] = int(c["unwind"]) + 1
			else:
				c["slide"] = int(c["slide"]) + 1
		var lk := 1 if (e == 1 and a_locked[k] == 1) else 0
		if lk == 1 and pl[k] == 0:
			c["lock"] = int(c["lock"]) + 1
		if e == 1 and pp[k] >= 0 and a_pinidx[k] > pp[k]:
			c["pay"] = int(c["pay"]) + 1
		pe[k] = e
		pl[k] = lk
		pp[k] = a_pinidx[k] if e == 1 else -1
	rec_prev["eng"] = pe
	rec_prev["lk"] = pl
	rec_prev["pin"] = pp
	if wrapped:
		c["wrapped"] = int(c["wrapped"]) + 1
	var run := int(rec_prev.get("airrun", 0))
	var top := float(rec_prev.get("airtop", body_pos.y))
	var px := float(rec_prev.get("bx", body_pos.x))
	if grounded:
		c["gnd"] = int(c["gnd"]) + 1
		c["crawl"] = float(c["crawl"]) + maxf(body_pos.x - px, 0.0)
		run = 0
		top = body_pos.y
	else:
		c["air"] = int(c["air"]) + 1
		if run == 0:
			top = body_pos.y
		run += 1
		c["airrun"] = maxi(int(c["airrun"]), run)
		c["maxdrop"] = maxf(float(c["maxdrop"]), body_pos.y - top)
	rec_prev["airrun"] = run
	rec_prev["airtop"] = top
	rec_prev["bx"] = body_pos.x
	c["maxtip"] = maxf(float(c["maxtip"]), tip_speed)
	c["fall"] = int(c["fall"]) + maxi(falls - int(rec_prev.get("falls", falls)), 0)
	rec_prev["falls"] = falls
	if crack_flash >= 1.0 and float(rec_prev.get("flash", 0.0)) < 1.0:
		c["crack"] = int(c["crack"]) + 1
	rec_prev["flash"] = crack_flash
	if rec_cur.size() == 1:
		c["x0"] = body_pos.x
	c["x1"] = body_pos.x
	if rec_cur.size() % TAPE_CHECK == 0:
		rec_chk.append(state_hash())

func tape_of() -> Dictionary:
	return {"v": TAPE_VERSION, "lvl": level_fingerprint(), "n": rec_cur.size(),
		"h": state_hash(), "chk": rec_chk.duplicate(), "note": rec_note,
		"cen": rec_cen.duplicate(), "start": rec_start,
		"cur": rec_cur.duplicate(), "grip": rec_grip.duplicate(), "ok": true,
		"err": ""}

func tape_save(path: String) -> bool:
	var t := tape_of()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(TAPE_MAGIC)
	f.store_32(TAPE_VERSION)
	f.store_64(int(t["lvl"]))
	f.store_32(int(t["n"]))
	f.store_64(int(t["h"]))
	f.store_var(t["chk"])
	f.store_var(t["note"])
	f.store_var(t["cen"])
	f.store_var(t["start"], false)
	f.store_var(t["cur"])       # 8 bytes a tick: the cursor, exactly as passed
	f.store_var(t["grip"])      # 1 byte a tick
	f.close()
	return true

static func tape_load(path: String) -> Dictionary:
	var bad := {"ok": false, "err": "", "n": 0}
	if not FileAccess.file_exists(path):
		bad["err"] = "no such tape"
		return bad
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		bad["err"] = "unreadable"
		return bad
	if f.get_32() != TAPE_MAGIC:
		bad["err"] = "not a tape"
		return bad
	var ver := f.get_32()
	if ver != TAPE_VERSION:
		bad["err"] = "tape format v%d, this build reads v%d" % [ver, TAPE_VERSION]
		return bad
	var t := {"ok": true, "err": ""}
	t["lvl"] = f.get_64()
	t["n"] = f.get_32()
	t["h"] = f.get_64()
	t["chk"] = f.get_var()
	t["note"] = f.get_var()
	t["cen"] = f.get_var()
	t["start"] = f.get_var(false)
	t["cur"] = f.get_var()
	t["grip"] = f.get_var()
	if typeof(t["cur"]) != TYPE_PACKED_VECTOR2_ARRAY \
			or typeof(t["grip"]) != TYPE_PACKED_BYTE_ARRAY \
			or (t["cur"] as PackedVector2Array).size() != int(t["n"]) \
			or (t["grip"] as PackedByteArray).size() != int(t["n"]):
		bad["err"] = "truncated tape"
		return bad
	return t

func tape_begin_play(t: Dictionary) -> bool:
	# restore the state the tape was recorded from, then feed its inputs back
	# through the ONE input surface the game has
	if not bool(t.get("ok", false)):
		return false
	if int(t.get("lvl", 0)) != level_fingerprint():
		return false
	if not restore(t["start"]):
		return false
	play_tape = t
	play_at = 0
	play_on = true
	play_done = false
	return true

func tape_feed() -> bool:
	# one recorded tick; false when the tape has run out
	var cur: PackedVector2Array = play_tape["cur"]
	var grp: PackedByteArray = play_tape["grip"]
	if play_at >= cur.size():
		return false
	pending_reset = (grp[play_at] & 2) != 0
	step_tick(cur[play_at], (grp[play_at] & 1) != 0)
	play_at += 1
	return true

func _play_tick() -> void:
	if tape_feed():
		return
	play_on = false
	play_done = true
	var ok := state_hash() == int(play_tape["h"])
	print("REPLAY %s  %d ticks  hash %d (recorded %d)" % [
		"PASS" if ok else "FAIL - DIVERGED", play_at, state_hash(),
		int(play_tape["h"])])
	# On a screen the last frame is left up to be looked at. With no screen
	# there is nothing to look at and a verdict to return, so report and go.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if ok else 1)

# ---------------------------------------------------------- session set-up --
func _boot_session() -> void:
	# godot --path . -- [--fresh] [--record FILE [--note TEXT]] [--replay FILE]
	var args := OS.get_cmdline_user_args()
	var fresh := false
	var rp := ""
	var pp := ""
	var note := ""
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		if a == "--fresh":
			fresh = true
		elif a == "--record":
			rp = nxt; i += 1
		elif a == "--replay":
			pp = nxt; i += 1
		elif a == "--note":
			note = nxt; i += 1
		i += 1
	if pp != "":
		# A REPLAY NEVER WRITES YOUR SAVE. Watching a tape is not playing - and
		# a replay that FAILS to start does not write it either, which is why
		# every branch here leaves save_enabled false rather than falling
		# through to a normal session that would overwrite the run on file.
		pp = _res(pp)
		var t := tape_load(pp)
		var why := ""
		if not bool(t.get("ok", false)):
			why = str(t.get("err", "unreadable"))
		elif int(t.get("lvl", 0)) != level_fingerprint():
			why = "recorded on a different level"
		elif not tape_begin_play(t):
			why = "the tape's start state was refused"
		if why == "":
			print("REPLAY %s: %d ticks - %s" % [pp, int(t["n"]), str(t["note"])])
		else:
			push_error("replay: %s (%s)" % [why, pp])
			print("replay: %s (%s). Not playing, and NOT saving - " % [why, pp] \
				+ "your run on file is untouched.")
			if DisplayServer.get_name() == "headless":
				get_tree().quit(1)
		return
	if fresh:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(save_path + ".tmp"))
	else:
		match load_from(save_path):
			1:
				print("resumed at %.1fs, %d falls, x %.2f" % [
					run_ticks / 60.0, falls, body_pos.x])
			-1:
				print("save refused: it was written for another level or " \
					+ "another format. Starting a fresh run.")
	save_enabled = true
	save_due = AUTOSAVE_TICKS
	if rp != "":
		rec_path = _res(rp)
		rec_begin(note)
		print("RECORDING to %s" % rec_path)

static func _res(p: String) -> String:
	# a bare "tapes/door.tape" means the project, not the shell's directory
	if p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path():
		return p
	return "res://" + p

func _notification(what: int) -> void:
	# Persist on every exit path there is: the window's close button, Esc (which
	# tears the tree down), and the engine's own crash handler. Between those
	# and the half-second autosave there is no ordinary way to leave the game
	# that rewinds the run.
	if what != NOTIFICATION_WM_CLOSE_REQUEST and what != NOTIFICATION_EXIT_TREE \
			and what != NOTIFICATION_CRASH:
		return
	if not save_enabled:
		return
	save_to(save_path)
	if rec_on and rec_path != "":
		rec_end()
		if tape_save(rec_path):
			print("tape written: %s (%d ticks)" % [rec_path, rec_cur.size()])
