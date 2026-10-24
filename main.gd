extends Node2D
## THE WHIP - greybox demo.
## Custom fixed-tick verlet sim (no engine physics). One verb: shape the whip.
## Mouse = handle target (clamped to a reach circle around the body).
## HOLD Space (or LMB) = TAUT grip. Release = SLACK. R = restart.
## F / G = mark this tick on the tape (only while --record; inert otherwise).
##
## Design contracts (do not "improve" these away):
##  - No RNG anywhere in the sim. Bit-identical replays on the same build.
##  - No assists: no tip magnetism, no auto-taut, no input smoothing beyond the
##    constant arm spring, no trajectory prediction, no slow-mo. A JAM anchor
##    (a_jam, lab levels only) is the one deliberate exception and is named as
##    one: it supplies the self-crossing the player would otherwise have to
##    make. It is a property of a MARKED anchor, not of the whip - it cannot
##    follow the player around, it is drawn with its own collar, and it still
##    obeys every other rule, grip included. An assist you can see and walk
##    away from is a different animal to one that rides along with you.
##  - Rope never pushes (all rope constraints are one-sided tethers).
##  - Arm spring force is an INTERNAL pair (reaction applied to the body), so
##    mouse waggling can never add net momentum (no helicopter flight).
##  - Wrap angle is MEASURED from live geometry every tick, never event-counted.
##  - Dissipation only via contact friction and the taut-catch yank. No air drag.
##  - The save IS the run: one slot, overwritten every half second and on every
##    exit, no rewind. No second slot, no checkpoint, no "load last", no
##    confirm-on-restart - the absence is the rule (see save / resume below).
##  - The camera never reads the whip: its whole input is the body's position,
##    the body's velocity and an authored table. Not zoom, not framing, not a
##    bias. A camera that reacts to the rope pumps with it; one that reacts to
##    whether you COULD make the next gap is a feasibility oracle.
##  - The mouse never reads the camera: sensitivity is a constant in metres per
##    physical pixel at every zoom and every window size. Both bans are
##    enforced by tests/cam_gate.gd reading the source, not by this list.
##  - The capstan pin - the rope's material point nailed at the anchor from the
##    tick a catch engages (theta >= th_part, or a self-crossing _pinch finds) -
##    is the documented stand-in for rope self-pinch: a bare tapered tail cannot
##    hold a body by capstan friction alone. LOCKED is decided by _pinch, never
##    by an angle.

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
const ALIGN_W := 0.75             # ALIGN: the fraction of the cursor's
                                  # ACROSS-the-load component the shut fist
                                  # refuses. 0.0 = the arm before this fix.
const ALIGN_LOAD_EPS := 0.01      # m: on the ground the tether must be this
                                  # close to taut before the load is real
const ALIGN_DEAD := 0.001         # m: an across-the-load command smaller than
                                  # this is not a command. The control surface
                                  # is REACH across 69 physical pixels of mouse
                                  # travel (PPM_INPUT 60 px/m), so one pixel of
                                  # hand is 16.7 mm: this dead zone is a
                                  # sixteenth of the smallest movement the mouse
                                  # can express.

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
var th_full := 5.5                    # rad. READ NOWHERE. This was the angle a
                                      # wrap had to reach to classify LOCKED
                                      # before the verdict moved to _pinch (a
                                      # self-crossing held PINCH_RUN ticks
                                      # inside LOCK_WINDOW). The calibration it
                                      # carried - settle 2.5-3.9 rad at 1.0
                                      # turn, overlapping the fold range, so a
                                      # single turn could not be told from a
                                      # crease; 6.1-11.3 at 1.3 turns; a hard
                                      # step at ~1.05-1.15 turns, exactly where
                                      # the chain crosses its own standing
                                      # part - is why the verdict became the
                                      # crossing itself. It stays declared
                                      # because it is a script var and so in
                                      # the snapshot key set: deleting it would
                                      # refuse every committed tape and the run
                                      # on file. Setting it changes nothing.
var jam_min_th := 1.0                 # rad: a JAM anchor supplies the crossing,
                                      # but not the SIGHT of it. The arc is only
                                      # drawn above 0.3 rad, so without a floor
                                      # here a jam holds the player with nothing
                                      # whatever on screen - measured at 28 of
                                      # its 37 greens, and 3 of 3 on the high
                                      # station. Against that, the shipped
                                      # traverse has never once held a player
                                      # without drawing the ring: 0 of 458
                                      # locked ticks across the whole corpus.
                                      # 1.0 rad costs 19% of the catch rate
                                      # (37 -> 30 of 108 searched strokes, still
                                      # nearly double the same anchor as a plain
                                      # beam) and buys back 100% of the dark
                                      # holds. It also puts a jam on the SAME
                                      # DIAL as a beam at a different number: on
                                      # a beam you wait for the arc to close, on
                                      # a jam you press as it appears.
var th_rel := 1.8                     # rad: release

const CRACK_SPEED := 24.0         # m/s tip speed -> crack event (sound only,
                                  # NO energy is shed - that would be a governor;
                                  # crack_cooldown and crack_flash reach _events,
                                  # _draw, _av_tick and the tape census, and
                                  # nothing in the solver).
                                  # AND IT IS NOT A STRIKE DETECTOR. Striking -
                                  # the crack as a verb, aimed at a target - was
                                  # measured and not built: this event fires a
                                  # median 3.15-3.65 m from where the player
                                  # aimed, and the tip's precision floor is
                                  # ~0.9 m for a few mm of cursor and never under
                                  # ~0.46 m at any input precision, because the
                                  # tip is chaotic (smooth exponential, no cliff;
                                  # see taper). One motion covers 87.5% of the
                                  # strikeable envelope - darts, not golf - and
                                  # any target under ~1 m is a lottery. Record:
                                  # commit 6fdaa44; the probes were not kept.

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
#  - the pin engages on ANY catch (measured theta >= th_part, or a
#    self-crossing that _pinch finds, inside GRIP_WINDOW of the hand
#    closing), so a partial wrap really does catch you - that is the
#    briefed "it catches, then betrays" and it is what makes a near-miss
#    readable rather than nothing;
#  - a partial wrap pays MATERIAL through the pin, one segment per
#    PAYOUT_TICKS of load (the timer re-arms per segment, measured 15.0
#    ticks/segment): the betrayal is a visible, audible ratchet that ends
#    with the whip sliding off its own tail;
#  - a wrap classified locked (_pinch true for PINCH_RUN consecutive ticks
#    inside LOCK_WINDOW - the self-crossing, never an angle) freezes payout -
#    it is committed;
#  - any wrap releases when measured theta falls below th_rel with no pinch
#    left, so an unwrap wave that lifts segments off contact still frees it,
#    loaded or not - and the hand opening drops it that same tick, whatever
#    the wrap was.
var a_pinidx := PackedInt32Array()
var a_pinpt := PackedVector2Array()
# wrap classification: measured contact-theta creeps upward as a loaded wrap
# beds in against the anchor, so partial-vs-locked is decided ONCE - from the
# WEAKEST theta seen and from whether the chain crosses itself inside
# LOCK_WINDOW - and then FROZEN. There is no upgrade path at all (see
# _update_locks: the climb after a catch was the pin's doing, not the
# player's). The only later change is downward: a locked wrap that unwinds
# under th_part with no pinch left becomes partial and pays out.
var a_locked := PackedInt32Array()    # -1 pending, 0 partial, 1 locked
var a_armed := PackedInt32Array()     # 0 = must fully unwind before re-catching
var a_pin0 := PackedInt32Array()      # pin index at engagement. Read by no
                                      # code here; tests/mark_look.gd dumps it
                                      # (has the pin slipped?), and it is in
                                      # the snapshot key set
var a_pend := PackedInt32Array()      # ticks since engagement (for classify)
var a_ength := PackedFloat32Array()   # theta at classification time. Read by
                                      # no code here; mark_look dumps it, and
                                      # it is in the snapshot key set
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
# A capstan holds only if there is tension on BOTH sides of the wrap. Your hand
# supplies the standing-side tension - that is what gripping IS. Let go and the
# rope simply runs through your hand, the wrap unwinds, and you fall. This is
# what gives SLACK and TAUT genuinely separate purposes: slack shapes waves and
# cannot bear you, taut bears you and cannot shape. Without it the rope is
# inextensible in both modes, a wrap holds whether or not you grip, and the
# grip button is decorative.
const PAYOUT_TICKS := 15              # ticks between one segment paying
                                      # through a slipping partial wrap - a
                                      # ratchet, 4 segments a second, and now
                                      # actually one: _advance_pin resets the
                                      # timer per segment (it did not, and the
                                      # betrayal was one quarter second and
                                      # then a snap). Measured on searched
                                      # throws: 15.0 ticks/segment, and the
                                      # last pin that can advance is 23
                                      # (NP - 2 - TAIL_MIN), so from its
                                      # first segment a partial pinned at 13
                                      # has at most 165 ticks (2.75 s) before
                                      # it slides off, at 17 105 (1.75 s), at
                                      # 21 45 (0.75 s), at 23 15 (measured:
                                      # 15, where it was 1). At most, because
                                      # only loaded ticks count and a slow
                                      # ratchet gives the wrap time to unwind
                                      # under th_rel first - the pin-20 rig
                                      # paid two segments and unwound at
                                      # tick 16, where it used to pay four in
                                      # 4 ticks and slide off. Raised
                                      # from 8 when the pin re-seat landed:
                                      # re-seating removed the wasted
                                      # teleport, which shortened the visible
                                      # betrayal from 56 to 39 ticks.
# THE JAM ANCHOR. 1 = this anchor supplies the self-crossing itself; see
# _pinch. LEVEL data, rebuilt by _build_level on every boot, so it is in
# SNAP_SKIP and deliberately NOT in level_fingerprint: adding a field to that
# hash changes the SHIPPED level's number even when every entry is 0, and the
# shipped number is 2762505307938286422 in three committed tests. The lab's
# terrain and beams differ from the traverse's anyway, so the two levels
# already fingerprint apart without it.
var a_jam := PackedInt32Array()
# What to call this anchor on screen, drawn under it by _draw. Empty on the
# shipped level - it teaches by shape and position, and a traverse with
# captions on it is a different game. The lab is the opposite: it exists to
# name things, and an anchor whose class you cannot read teaches nothing.
var a_name := PackedStringArray()

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
const CLASSIFY_TICKS := 6             # READ NOWHERE. The old single-sample
                                      # settle time. The verdict now watches a
                                      # LOCK_WINDOW of 30 ticks for PINCH_RUN
                                      # consecutive pinches (_update_locks: one
                                      # sample at tick 6 misjudged 43% of
                                      # partials). A const, not a var, so it is
                                      # outside the snapshot key set; kept so
                                      # the number stays findable.
const UPGRADE_JUMP := 1.2             # READ NOWHERE. The old partial->locked
                                      # upgrade on a theta jump. There is no
                                      # upgrade path any more: 79% of
                                      # accidental locks were the pin's climb.
# A locked wrap is DEMOTED to partial only when the measured wrap falls below
# the CATCH threshold th_part with no self-crossing left (_update_locks). It
# cannot be a band just under the lock reading: a wrap tightening under load
# straightens its wrapped segments out of the contact band, so measured theta
# legitimately decays ~1.5 rad while the wrap is physically unchanged, and
# demoting inside that band would betray honest full wraps.

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
var t_deep := PackedFloat32Array()    # m: how deep this segment's rescue may
                                      # reach behind it - half the rock's
                                      # thickness there, INF under a floor.
                                      # Derived in _finish_terrain; see there.
const CULL_MARGIN := 2.5              # m of slack around each segment's box
# TERRAIN ARCS - collision-only circles, the fillet on a convex corner. A
# polyline vertex is an infinitely sharp edge, and the rope snags on it: the
# round-cap branch in _collide_point pushes a particle radially off a point,
# so a chain dragged over a lip is deflected by whichever cap it met first,
# not by the rock's shape. A fillet replaces that point with a circle the rope
# and body collide with EXACTLY as they collide with a beam (the same
# _circle_out / _swept_circle code, not a copy of it) and that the catch
# machinery never sees: not in a_pos, so no winding is measured about it, no
# _pinch, no ring, no lock. That is not a limitation, it is the physics. A
# rope holds only by a self-pinch around something it can go fully round; a
# rope over a corner touches at most (pi - interior angle) of it - 1.57 rad on
# a 90 degree lip - against th_part = 3.4 and th_rel = 1.8, so a corner cannot
# be an anchor whatever its radius, and a fillet is a corner the rope slides
# off smoothly instead of catching on. tests/crag_gate.gd C5 proves both
# halves. The default level has none, and level_fingerprint folds these in
# only when there are some, so its number does not move.
var t_arc_c := PackedVector2Array()   # centre
var t_arc_r := PackedFloat32Array()   # radius
var t_arc_ang := PackedVector2Array() # (start, end) angle of the EXPOSED arc,
                                      # for _draw: the rest of the circle is
                                      # inside the rock
# THE BACKDROP - paint, behind the play plane. Filled polygons _draw lays down
# before the terrain so a horn reads as rock growing out of a cliff and not as
# a disc floating in a void. Nothing in the sim reads these: not _collide, not
# the wraps, not the camera, not the fingerprint. In SNAP_SKIP as level
# furniture. The traverse and the lab leave them empty and draw exactly the
# frame they drew before (checked by photographing both builds of the door
# tape and comparing the PNGs byte for byte).
var bd_poly: Array = []               # PackedVector2Array each, in metres
var bd_col := PackedColorArray()
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
var spawn0 := Vector2(-4.6, -1.0)   # THE AUTHORED SPAWN, set once by setup_sim.
                                      # spawn moves to each checkpoint reached and
                                      # is state; spawn0 is the level's, and is
                                      # what level_fingerprint hashes - a tape
                                      # saved after a checkpoint used to carry the
                                      # moved spawn's fingerprint and be refused
                                      # by the level it was recorded on. In
                                      # SNAP_SKIP (level furniture).
var cp_pos := PackedVector2Array()  # CHECKPOINTS (scene levels): stand within
                                      # CP_R of one and spawn moves there. Level
                                      # furniture, not state: in SNAP_SKIP; the
                                      # spawn it moves IS state, and saved
const CP_R := 1.0                     # m
var goal_x := 58.0
var goal_y := 12.0                    # the floor the flag stands on. Split out
                                      # of _draw's literal 12.0 when the lab
                                      # arrived: the lab is flat at y=0 and a
                                      # hardcoded 12 plants its flag 12 m
                                      # underground. NOT hashed by
                                      # level_fingerprint - adding a field to
                                      # that hash would invalidate all six
                                      # tapes and the player's save, for a
                                      # decoration.

# WHICH LEVEL THIS SIM IS. "" is the shipped traverse and it MUST stay
# byte-identical: level_fingerprint() hashes the terrain, the beams, the spawn
# and the goal, so one moved vertex kills all six tapes and the run on file.
# The lab is therefore a SEPARATE build inside _build_level, chosen by
# --level lab, with its own save slot - two levels sharing one slot would have
# each session refuse and discard the other's run every time you switched.
var level_id := ""

var taper := 26.0                     # handle:tip mass ratio (see _reset).
                                      # Taper sets FEEL, not difficulty: it
                                      # trades heft for snap (tests/taper_sweep
                                      # measures 3.0x amplification at 22:1,
                                      # 4.4x at 35:1; sim_test G3 reads 3.2x at
                                      # this 26:1) but barely moves the lock
                                      # rate (tests/lock_rate.gd). 26:1 keeps
                                      # the whip feeling weighted - a noodle is
                                      # not satisfying to throw - with a little
                                      # more life than the original 22:1.
                                      # DO NOT LOWER IT TO TAME THE TIP. The
                                      # tip is chaotic - a smooth exponential
                                      # divergence, no cliff - and taper is not
                                      # the cure but the opposite: 26:1 -> 1.6:1
                                      # drops G3's amplification 3.22x -> 1.49x
                                      # while the divergence rate RISES 1.77 ->
                                      # 3.83 /s. A limper whip is a MORE chaotic
                                      # whip. And it never reaches the mechanic:
                                      # nothing in the game reads the tip's
                                      # position (pos[NP-1] is read for tip
                                      # speed, one tangent correction and two
                                      # draw calls, and that is all). Record:
                                      # commit 6fdaa44; the probe was not kept.
var ground_mu := 0.30                 # chain/body friction against terrain
# The coil modes (winding consuming tether, an over-wound coil shedding) were
# measured to do nothing and deleted in 7916cf1; a hidden reel was the second
# verb the design bans.
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
var cam_st := {}                      # the camera law's own state. Rendering,
                                      # not simulation: it is in SNAP_SKIP, and
                                      # nothing in it can reach a sim variable.
var zone: Node2D                      # the working-zone ring, screen space
var mouse_owned := false              # this session hid and confined the pointer
var hud: Label
var status: Label
var sfx_crack: AudioStreamPlayer
var sfx_tick: AudioStreamPlayer
var sfx_rasp: AudioStreamPlayer
var sfx_air: AudioStreamPlayer        # the rope moving through air
var sfx_load: AudioStreamPlayer       # what the wrap is carrying
var sfx_grit: AudioStreamPlayer       # rope and body dragging on the ground
var sfx_catch: AudioStreamPlayer      # a wrap engaged
var sfx_lock: AudioStreamPlayer       # the verdict, when it holds
var sfx_part: AudioStreamPlayer       # the verdict, when it does not
var sfx_ratch: AudioStreamPlayer      # one segment paid through the wrap
var sfx_off: AudioStreamPlayer        # the wrap ran out of tail
var sfx_let: AudioStreamPlayer        # you opened your hand / it unwound clean

# ------------------------------------------ audio + visual instrumentation --
# THE ASSIST LINE, applied to sound exactly as it is applied to the screen:
# the PAST and the PRESENT are instrumentation, the FUTURE is an assist. Every
# voice below renders a quantity the simulation has ALREADY produced this tick.
# None of them fires before the state it describes exists, and none of them is
# a function of anything the sim has not yet computed.
#
# ACCESSIBILITY PARITY, also a project ruling: every voice here has a visual
# twin driven by THE SAME NUMBER ON THE SAME TICK, so a deaf player is reading
# the same instrument, not a worse one. The pairs, and where the twin is drawn:
#   air whoosh      <-> tip halo, radius by tip speed            (_draw, tip)
#   load hum        <-> the loaded leg of the rope glows          (_draw, chain)
#   ground grit     <-> a pip on every particle in contact        (_draw, chain)
#   crack           <-> the tip flash, sized by the same overshoot(_draw, tip)
#   winding tick    <-> the half-turn dots on the arc             (existing)
#   slip rasp       <-> the red outer arc                         (existing)
#   catch           <-> a white ring leaving the beam             (_draw, anchor)
#   verdict holds   <-> the arc turns green + a green pulse       (_draw, anchor)
#   verdict betrays <-> the arc turns amber + an amber pulse      (_draw, anchor)
#   ratchet         <-> a red pulse, one per segment paid         (_draw, anchor)
#   slid off        <-> a red burst                               (_draw, anchor)
#   let go          <-> a pale burst                              (_draw, anchor)
#
# EVERY CURVE IS FITTED TO MEASURED DATA, not to a guess. The probe that took
# these numbers (aud_probe: a corpus replay reporting the distribution of each
# driver over the 7679 tape ticks) was NEVER COMMITTED - the numbers stand as
# the record, and tests/aud_gate.gd A5 re-reads the load range on every run.
# What it found, and what the ranges below are built on:
#   tip speed       p50   8.6   p90  29.2   p99  53.2   max  85.7  m/s
#   ground scrape   p50  18.5   p90  54.9   p99 108.9   max 276.8  (sum m/s)
# The load voice's driver was re-measured when it changed from the pendulum
# estimate to the arm force (av_arm, see _substep), on the player's own
# recorded session (takes/bug1.tape, 3999 engaged ticks) and on the corpus:
#   arm force, session   min 0.2  p50  43.8  p90 320.0  p99 594.7  max 3163  N
#   arm force, corpus    min 1.9  p50  10.7  p90 220.7  p99 320.0  max 2362  N
#   pendulum, session    min 0.0  p50  79.7  p90 158.5  p99 617.6  max 1835  N
# The p90 on the session is F_MAX exactly: the spring saturates there, and
# everything above it is the tether's yank - the catch and the fall-arrest.
const AV_AIR := 0
const AV_LOAD := 1
const AV_GRIT := 2
const AV_RASP := 3
const AV_N := 4
const AIR_LO := 2.0                   # m/s of tip: below this, no air noise
const AIR_HI := 30.0                  # m/s: the measured p90 tops the ramp
const AIR_DB := Vector2(-42.0, -12.0)
const AIR_PITCH := Vector2(0.55, 2.40)
# The load ramp tops at F_MAX, for two reasons that turn out to be the same
# number: it is the p90 of the arm force over the player's recorded session
# (the air ramp's rule, AIR_HI at the measured p90), and it is where the
# spring saturates, so a hum at the top of its range means the arm is at
# its cap and any more is the tether. The floor is zero because the arm's
# is: a wrap engaged with the feet on the floor carries 0.2 N, and the old
# 45.9 N floor was a property of the pendulum estimate, not of the load.
const LOAD_LO := 0.0
const LOAD_HI := 320.0
const LOAD_DB := Vector2(-33.0, -13.0)
const LOAD_PITCH := Vector2(0.80, 1.85)
const GRIT_LO := 4.0
const GRIT_HI := 120.0
const GRIT_DB := Vector2(-46.0, -18.0)
const GRIT_PITCH := Vector2(0.60, 1.60)
const RASP_DB := Vector2(-24.0, -13.0)
const CRACK_DB := Vector2(-9.0, -1.0)
const CRACK_PITCH := Vector2(0.85, 1.45)
# CRACK_OVER IS MEASURED AT THE BANG, NOT AT THE PEAK, and the correction
# matters. The obvious number is the top tip speed the game produces - 85.7
# m/s, 3.57x the threshold - and it is the wrong one: the crack fires on the
# FIRST tick past CRACK_SPEED and then sits out a 0.3 s cooldown, so it
# samples the rising edge, never the peak. Measured over the corpus's 168
# real cracks, the overshoot AT THE BANG runs 1.00x to 2.42x, p50 1.19, p90
# 1.59. A ramp built to 3.57 put the median crack 8% of the way up its own
# loudness range and left the top two thirds of it unreachable. The
# distribution is skewed too, so the ramp is square-rooted: p50 lands at
# 0.37 and the loudest crack at 1.0, which uses the range while staying
# monotonic in tip speed - louder still means faster, which is the only
# thing this cue is allowed to mean.
const CRACK_OVER := 2.42

# THE ART LAYER is not simulation state either, by the audio's own argument,
# and it goes one further: it has no per-tick code at all. A live instance of
# the level scene sits in the tree behind _draw (see _art_build) and nothing
# in this file reads a pixel of it. Both names are in SNAP_SKIP.
var art_on := false                   # a windowed session only, like av_on
var art_root: Node                    # the live instance; null in every probe
var greybox := true                   # _draw paints the WORLD - terrain
                                      # lines, arcs, backdrop, anchor discs.
                                      # false = the scene's Art carries it.
                                      # Read off the live instance by
                                      # _art_build, so a probe, which has no
                                      # _ready, keeps the default and paints
                                      # the frame it always painted

# NONE OF THIS IS SIMULATION STATE. It is all named in SNAP_SKIP, which is what
# keeps a save and a tape describing the same simulation they always did.
var av_on := false                    # only a real windowed session; the probes
                                      # build the sim with new() and never enter
                                      # the tree, so _ready never fires, av_on
                                      # stays false and no audio node exists
var av_touch := PackedByteArray()     # per particle: touched terrain this tick
var av_scrape := 0.0                  # m/s summed over particles in contact
var av_tension := 0.0                 # N carried by the load-bearing wrap
var av_arm := 0.0                     # N the body put through the arm this
                                      # tick: |spring + tether impulse| summed
                                      # over the substeps, divided by DT
var av_armc := Vector2.ZERO           # the tether's position correction,
                                      # summed over one substep's sweeps
var av_lidx := -1                     # chain index the load runs out to
var av_over := 0.0                    # last crack's overshoot past CRACK_SPEED
var av_flash0 := 0.0                  # previous crack_flash (the crack's edge)
var av_half := PackedInt32Array()     # previous half-turn count, per anchor
var av_eng := PackedByteArray()       # previous engaged flag, per anchor
var av_hold := PackedByteArray()      # previous _holds(), per anchor
var av_lk := PackedInt32Array()       # previous a_locked, per anchor
var av_pin := PackedInt32Array()      # previous pin index, per anchor
var av_burst := PackedFloat32Array()  # per anchor: 1 -> 0 event flash
var av_bcol := PackedColorArray()     # per anchor: what that flash means
var av_brad := PackedFloat32Array()   # per anchor: how big it gets
var av_lvl := PackedFloat32Array()    # smoothed level per continuous voice
var av_pit := PackedFloat32Array()    # smoothed pitch per continuous voice
var av_lvl_t := PackedFloat32Array()  # this tick's level target
var av_pit_t := PackedFloat32Array()  # this tick's pitch target

# ------------------------------------------------------------------- setup --
func _ready() -> void:
	if pos.size() == 0:
		# WHICH LEVEL, read before the level is built rather than in
		# _boot_session, which runs after it. A harness that builds the sim
		# itself sets level_id directly and never reaches this line. A level
		# scene run on its own (F6, whip_level.gd) sets level_id before it
		# adds this node, and that wins over a command line that has none.
		if level_id == "":
			level_id = _cmdline_level()
		setup_sim()
	if level_err != "":
		# A scene the loader refused is not played and, above all, not saved:
		# _boot_session would turn save_enabled on and the next autosave
		# would write an empty world into user://run_<name>.save.
		print("Nothing to play. Fix the scene and run tests/level_gate.gd -- level=%s" % level_id)
		get_tree().quit(1)
		return
	_boot_session()   # resume the run in progress, or record / replay a tape

	cam = Camera2D.new()
	# NO position_smoothing. The law does its own, and does it with the
	# follower's own lag cancelled so the lead authored is the lead delivered;
	# a second smoother in series would put the lead straight back to zero,
	# which is what the shipped camera was doing by accident.
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()
	cam_reinit()

	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92))
	hud.text = "THE WHIP  |  mouse: move handle   R: restart\nSPACE / LMB = CLOSE YOUR HAND on the rope. It is a grip, not a stiffener:\na wrap only takes in the moment you close it, and only holds while you hold.\nOPEN your hand and you leave the beam that instant - release is your launch.\ngreen ring = the rope has crossed itself and will hold. amber = it will betray."
	if level_id == "lab":
		# THE BENCH SAYS WHAT IT IS. The traverse teaches by consequence and gets
		# no captions; the lab has exactly one job, which is to name two kinds of
		# anchor and the difference between them, so it says so out loud. The last
		# line is the whole point of the jam and is also the thing that had to be
		# MADE true: every geometry that held in the probes held with the hand
		# OPEN too (+0.0280 m taut vs +0.0280 m open over 10 s), and an anchor
		# like that turns this line into a lie.
		hud.text = "THE WHIP - THE LAB   (--level lab)   flat ground, four stations, walk the length of it\n" + "SPACE / LMB = CLOSE YOUR HAND. A wrap only takes in the moment you close it.\n" + "BEAM and THIN BEAM are ordinary: you have to throw a CROSSING onto them.\n" + "JAM (pale collar) makes the crossing for you - it takes from angles a wrap will not.\n" + "Both let go the instant you open your hand. Green ring = it holds. Amber = it betrays."
	elif level_id == "crag":
		# The crag says only what it is. No feature is named on screen: like
		# the traverse it teaches by consequence, and the rock around each
		# anchor is the caption.
		hud.text = "THE WHIP - THE CRAG   (--level crag)   a gorge, nine drops, the rock decides which throws survive\n" + "SPACE / LMB = CLOSE YOUR HAND on the rope. A wrap only takes in the moment you close it,\n" + "and only holds while you hold. OPEN your hand and you leave the anchor that instant.\n" + "Rock cannot be wrapped - only the anchors hold. Green ring = it holds. Amber = it betrays."
	elif level_id != "":
		# A scene level says what its author wrote in the root's hud field,
		# or, if he wrote nothing, its name and the one rule every level shares.
		hud.text = level_hud if level_hud != "" else "THE WHIP - %s   (--level %s)\n" % [level_title(), level_id] + "SPACE / LMB = CLOSE YOUR HAND on the rope. A wrap only takes in the moment you close it,\n" + "and only holds while you hold. OPEN your hand and you leave the anchor that instant.\n" + "Green ring = it holds. Amber = it betrays."
	canvas.add_child(hud)
	status = Label.new()
	status.position = Vector2(16, 146)
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	canvas.add_child(status)

	# THE WORKING ZONE, DRAWN. The cursor is anchored to the screen rather than
	# run back through the camera, so the OS pointer and the crosshair the game
	# draws no longer coincide once the camera leads or steps down a tier -
	# measured, they would separate by up to 240 px. Two pointers in a precision
	# game is worse than none, so the OS one goes (below) and the game's own
	# crosshair and hand become the only cursor.
	#
	# But a hidden pointer whose zone you cannot see is a control you can lose
	# the origin of: past the reach rim the crosshair is pinned and stops
	# telling you where your hand is. So the zone is drawn where it actually is
	# - a ring of exactly REACH, 138 PHYSICAL pixels across at any window size
	# or zoom, nailed to the same patch of desk forever - and past the rim the
	# hand itself is drawn with the slack between them. Present state only:
	# where your hand is this instant, never where it is going.
	zone = Node2D.new()
	zone.draw.connect(_draw_zone)
	canvas.add_child(zone)
	# Only a real windowed session takes the mouse - the same rule the save
	# obeys - so no probe and no replay ever grabs the player's pointer.
	# CONFINED, never CAPTURED: capture gives relative motion only and would
	# destroy the position mapping this whole section exists to protect.
	if save_enabled and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
		mouse_owned = true
	# THE ART, behind the same headless test and not behind save_enabled: a
	# replay is watched on a screen and should look like the game. A headless
	# session - every gate that puts this node in the tree, mark_rt R1,
	# cam_gate C2 - has no screen and gets no art node, and a probe built with
	# new() never reaches this line at all (tests/art_gate.gd A1).
	if DisplayServer.get_name() != "headless":
		_art_build()

	sfx_crack = _player(_make_noise_wav(0.09, 0.018, 26111), -4.0, 2)
	sfx_tick = _player(_make_sine_wav(0.05, 880.0), -8.0, 3)
	sfx_rasp = _player(_make_noise_wav(0.4, 10.0, 7333, true), -80.0, 1)
	# THE THREE CONTINUOUS VOICES. Each is a looping AudioStreamWAV whose
	# volume and pitch are written once a frame, NOT an AudioStreamGenerator
	# pushing samples. That is a deliberate choice and the reason is the tick
	# budget: the sim already costs 2.2-4.3 ms of a 16.7 ms frame (tests/perf),
	# and a generator would put a per-sample synthesis loop in GDScript on the
	# same thread - 735 samples a frame per voice, three voices, against four
	# float writes for the loop-and-drive approach. Resampling a noise loop
	# upward genuinely brightens it, which is the whoosh cue, and resampling a
	# harmonic loop upward genuinely raises its pitch, which is the load cue,
	# so the cheap route also happens to be the expressive one here.
	sfx_air = _player(_make_loop_noise(0.50, 90211, 0.55), -80.0, 1)
	sfx_grit = _player(_make_loop_noise(0.50, 41903, 0.10), -80.0, 1)
	sfx_load = _player(_make_loop_tone(110.25, 0.30, [1.0, 0.5, 0.24, 0.1]),
		-80.0, 1)
	sfx_catch = _player(_make_thock(0.16, 150.0, 0.055, 5501, 0.35), -7.0, 3)
	sfx_lock = _player(_make_chord(0.45, 196.0, 0.16, 0.085), -7.0, 2)
	sfx_part = _player(_make_thock(0.34, 233.0, 0.10, 8117, 0.10), -9.0, 2)
	sfx_ratch = _player(_make_thock(0.07, 520.0, 0.013, 3391, 0.55), -11.0, 4)
	sfx_off = _player(_make_sweep(0.50, 950.0, 90.0, 0.14, 6607, 0.55), -6.0, 2)
	sfx_let = _player(_make_sweep(0.22, 300.0, 720.0, 0.06, 2213, 0.85),
		-13.0, 2)
	# The four continuous voices are ramped, and _av_voice starts and stops
	# each one at the silent end of its own ramp - so none of them is
	# running while the game has nothing to say with it.
	av_on = true
	_av_reset()

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
	spawn0 = spawn
	# THE LEVEL OWNS ITS SLOT. One slot per level, still one slot per level -
	# the "no second save" contract is about there being no earlier state of
	# THIS run to go back to, and a lab run is not an earlier state of the
	# traverse. Sharing the file would make every switch a mutual wipe:
	# load_from already refuses a save whose level_fingerprint does not match
	# (verified in tests/lab_gate.gd L4), and the very next autosave would then
	# overwrite the run it just refused. Refusal alone is not enough; the
	# refused run has to still be somewhere.
	save_path = SAVE_PATH
	if level_id == "lab":
		save_path = SAVE_PATH_LAB
	elif level_id == "crag":
		save_path = SAVE_PATH_CRAG
	elif level_id != "":
		# A SCENE LEVEL OWNS ITS SLOT BY NAME: res://levels/steps.tscn saves to
		# user://run_steps.save. The name, not the fingerprint, because a slot
		# keyed to the fingerprint would move every time the developer nudged
		# a vertex and strand the run he was on under a name nothing reads.
		# The same name is the same slot: --level crag.tscn (the crag exported
		# to a scene) shares run_crag.save with the hardcoded crag, and that is
		# right, because tests/level_fidelity.gd proves they are one world.
		save_path = "user://run_%s.save" % level_name(level_id)
	_reset()
	_av_size()

func _build_level() -> void:
	cp_pos = PackedVector2Array()
	# TWO LEVELS, ONE OF WHICH MAY NOT MOVE. The shipped traverse is hashed by
	# level_fingerprint() into every tape and into the player's save, so this
	# branch exists precisely so that adding a second level cannot touch the
	# first: --level lab builds different arrays, and the default path below is
	# the same statements in the same order it always was.
	# tests/hashrun.gd must still print 2762505307938286422 and
	# tests/tape_verify.gd must still PASS 6 tapes - both checked in
	# tests/lab_gate.gd, L1 and L2.
	t_a.clear(); t_b.clear()
	t_arc_c.clear(); t_arc_r.clear(); t_arc_ang.clear()
	bd_poly.clear(); bd_col.clear()
	cam_vols = CAM_VOLS
	level_err = ""
	level_hud = ""
	if level_id == "lab":
		_build_lab()
	elif level_id == "crag":
		_build_crag()
	elif level_id != "":
		# ANY OTHER NAME IS A SCENE the developer drew in the editor: see
		# "SCENE LEVELS" below _bd for the schema and the loader. The three
		# built-in names always win, so --level crag is this file's crag even
		# after it has been exported to res://levels/crag.tscn; that scene is
		# played as --level crag.tscn.
		_build_scene(level_scene_path(level_id))
	else:
		_build_traverse()

func _build_traverse() -> void:
	# Terrain: y-down, up is negative. Hand-placed, deterministic.
	#
	# GEOMETRY CONTRACT (measured, not assumed - see tests/throw_probe.gd):
	# a 5.25 m whip can only LOCK an anchor about 3 m above the floor you
	# throw from, at roughly 1.5-2.5 m of lead. Every mandatory anchor here
	# sits inside that envelope. Gaps are V-floored so a fall costs ground
	# and time but never the run: the lash gait crawls out either side
	# (measured ~0.42 m/s: tests/ground_probe.gd, 4.22 m in 10 s).
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
	# crawls flat ground at ~0.42 m/s and cannot climb even a 20 degree
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
	_finish_terrain()

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
	# No jam anchors and no captions on the traverse: every beam here is the
	# ordinary kind, and it teaches by shape and position rather than by text.
	for a: Array in anchors:
		_add_anchor(Vector2(a[0], a[1]), a[2], 0, "")

func _finish_terrain() -> void:
	# Shared by both levels, and unchanged from when only one existed: derive
	# the out-of-world line from the terrain rather than hardcoding it (a
	# literal 6.0 survived the level being terraced down to y=12 and teleported
	# anyone standing on the last two tiers back to spawn), then the outward
	# normals and the per-segment boxes.
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
	# HOW THICK IS THE ROCK BEHIND EACH SEGMENT. _collide_point's rescue branch
	# lifts a particle it finds on a segment's solid side back onto that
	# segment, at any depth - the right thing under a floor, where the solid
	# side is rock all the way down. Under a 1.0 m slab of rock it is the
	# wrong thing: a tip flying in the air 0.5 m beneath the slab is 1.5 m
	# "inside" the slab's TOP edge, and the rescue put it on top of the slab.
	# Measured on the crag's first build: the whole chain crumpled onto the
	# underside of the brow over the spawn inside 30 ticks and the body hung
	# off its own jammed handle 2.2 m above the floor for as long as the gait
	# ran. So each segment's rescue reaches only HALF WAY to the nearest
	# terrain behind it: a ray from its midpoint along -n, against every
	# other segment. Past half way the particle is the far face's business.
	# Nothing is behind any segment of the traverse or the lab, so every one
	# of theirs reads INF, which is the unbounded rescue they always had.
	t_deep.clear()
	for i in t_a.size():
		var mid := (t_a[i] + t_b[i]) * 0.5
		var back := -t_n[i]
		var best := INF
		for j in t_a.size():
			if j == i:
				continue
			var e := t_b[j] - t_a[j]
			var den := back.cross(e)
			if absf(den) < 0.000000001:
				continue
			var tt := (t_a[j] - mid).cross(e) / den
			var uu := (t_a[j] - mid).cross(back) / den
			if tt > 0.000001 and uu >= 0.0 and uu <= 1.0:
				best = minf(best, tt)
		t_deep.append(best * 0.5)

func _fillet(v: Vector2, r: float) -> bool:
	# ROUND A CONVEX CORNER. v is a vertex two terrain segments share (one ends
	# there, the next begins there); the corner must be convex toward the air.
	# Both segments are shortened to the tangent points of a circle of radius r
	# that touches each of them from the rock side, and that circle goes into
	# t_arc_c. Call it BEFORE _finish_terrain, which derives the normals and
	# boxes from whatever t_a/t_b then hold.
	#
	# The geometry, so it can be checked rather than trusted (crag_gate C5
	# does): with d1 the direction INTO the vertex along the first segment,
	# d2 the direction OUT along the second, and n1, n2 their outward normals
	# (dy, -dx), the centre c is the point at signed distance -r from both
	# lines, (c - v).n1 = (c - v).n2 = -r, and the tangent points are
	# t1 = c + r n1 on the first line and t2 = c + r n2 on the second. On a
	# 90 degree lip that shortens each segment by exactly r; on a sharper
	# corner by r / tan(theta / 2), which is what the 2x2 solve gives without
	# a special case. The shortened segments keep their direction, so the
	# outward normals _finish_terrain derives from them are unchanged.
	#
	# Convex is decided by the turn: walking the boundary with the air on the
	# normal's side, a corner that sticks INTO the air turns away from the
	# air, which with this winding is d1 x d2 > 0. A concave corner (the foot
	# of a face meeting the floor below it) is refused: rounding it would put
	# a circle in the air, not in the rock.
	var i := -1
	var j := -1
	for s in t_a.size():
		if t_b[s].distance_to(v) < 0.000001:
			i = s
		if t_a[s].distance_to(v) < 0.000001:
			j = s
	if i < 0 or j < 0 or i == j:
		return false
	var d1 := (v - t_a[i]).normalized()
	var d2 := (t_b[j] - v).normalized()
	if d1.cross(d2) <= 0.000001:
		return false
	var n1 := Vector2(d1.y, -d1.x)
	var n2 := Vector2(d2.y, -d2.x)
	var det := n1.x * n2.y - n1.y * n2.x
	if absf(det) < 0.000001:
		return false
	var c := v + Vector2(r * (n1.y - n2.y) / det, r * (n2.x - n1.x) / det)
	var t1 := c + n1 * r
	var t2 := c + n2 * r
	# a fillet may not eat a whole segment
	if t1.distance_to(v) >= t_b[i].distance_to(t_a[i]) \
			or t2.distance_to(v) >= t_b[j].distance_to(t_a[j]):
		return false
	t_b[i] = t1
	t_a[j] = t2
	t_arc_c.append(c)
	t_arc_r.append(r)
	# the exposed part of the circle is the short way round from t1 to t2;
	# the rest is inside the rock and is not drawn
	var a1 := (t1 - c).angle()
	var a2 := (t2 - c).angle()
	var sw := wrapf(a2 - a1, -PI, PI)
	if sw >= 0.0:
		t_arc_ang.append(Vector2(a1, a1 + sw))
	else:
		t_arc_ang.append(Vector2(a2, a2 - sw))
	return true

func _add_anchor(p: Vector2, r: float, jam: int, nm: String) -> void:
	# One place that knows how wide the anchor tables are, so a level cannot
	# add a beam and forget a column - which is the same hand-kept-list defect
	# SNAP_SKIP's comment is about, arriving by copy-paste instead.
	a_pos.append(p)
	a_r.append(r)
	a_jam.append(jam)
	a_name.append(nm)
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

func _clear_anchor_tables() -> void:
	# The other place that knows the width: every table _add_anchor appends
	# to, emptied. Only a refused scene level needs it (a refused level must
	# leave nothing to play - measured: the first version left its anchors
	# standing in an empty world), but it lives beside _add_anchor so the two
	# lists cannot drift apart.
	for t: Variant in [a_pos, a_r, a_jam, a_name, a_theta, a_lockidx, a_freelen,
			a_half, a_pinidx, a_pinpt, a_locked, a_armed, a_pin0, a_pend, a_ength,
			a_minth, a_wlo, a_whi, a_paytick, a_prun, a_clear]:
		t.resize(0)

# --------------------------------------------------------------- THE LAB --
# A BENCH, NOT A TRAVERSE. --level lab. One flat floor you can walk end to
# end, four stations in a row, each anchor alone with nothing else in reach,
# and every one of them inside the envelope tests/throw_probe.gd measured: a
# 5.25 m whip locks an anchor about 3 m above the floor it is thrown from, at
# 1.5-2.5 m of lead. Nothing here can be missed into a fall, because there is
# nothing to fall off; the cost of a bad throw is the walk back.
#
# WHAT IS AND IS NOT IN HERE, and this is the whole result of the probes:
#
# NOT SHIPPED - THE V NOTCH (the briefed jam/slot: mouth open, narrowing at
# the back). Measured dead. 0 of 84 cells on the first sweep and 0 of 168
# placements on the settled re-sweep - every half-angle 0-25 deg, every throat
# 0.015-0.045, every depth 0.15-0.60, on-axis and offset - against a 0.7 N
# noise floor on a 91 N scale. It is loaded backwards: a hanging body pulls
# the rope toward the WIDE end, so the wedge unloads exactly as it takes
# load. Worse, _collide_point's rescue branch passes pen = 0.0 on purpose when
# the far wall finds a particle on its solid side, so a slot NARROWER than the
# rope gets LESS friction, not more, and the lateral wall pushes come out as
# axial ejection: the tip left a 3-25 deg notch in 0.050 s at 11.4 m/s, twenty
# times what gravity would give.
#
# NOT SHIPPED - THE FORK (two circles with a throat, or a slot that pinches
# the rope against itself). The second half of that idea is not buildable at
# all: THIS SIM HAS NO ROPE-ON-ROPE CONTACT. _collide() runs anchors, terrain,
# body and points, and never a particle PAIR - measured, 72.6% of the 7679
# corpus ticks have two non-adjacent particles overlapping, deepest 0.0952 m,
# a whole handle-end rope diameter. A hairpin with two strands in the throat
# behaves identically to one strand. What DOES hold is a thickness jam, and it
# is disqualified rather than unbuilt: hanging on one with the hand SHUT sank
# 0.086 m at 80.3 N, and with the hand OPEN sank 0.000 m at 80.0 N - the same
# rig, the same tick, and an ordinary wrap beside it fell 44.1 m when the hand
# opened. It also destroys the mechanic it was meant to supply: 60 throws at a
# plain beam give 11 pinches / 7 locks / 7 greens, and at a 0.08 m fork 0 / 0
# / 0.
#
# NOT SHIPPED - THE HOURGLASS CHOCKSTONE, which is the one geometry that
# really does hold: wide mouth, funnel narrowing UPWARD to a 0.045 m throat,
# blind pocket above it. 36/36 catches from searched throws, 91.0 N sustained,
# 0.0000 m of tip drift over 10 s. It is left out because of what it holds
# WITH: over 10 s, taut and open-hand runs are bit-identical to four decimals
# on every geometry tested (+0.0280 m taut, +0.0280 m open; 91.00 N both).
# The rope holds through _solve_rope and terrain collision alone, so no wrap
# engages, a_freelen stays -1, _holds() is never true, and not one of the ten
# voices or their visual twins can speak - every one of them is keyed to an
# anchor index. That is a place in the world where the grip button is
# decorative, which is the exact failure the design contract at the top of
# this file names.
#
# SHIPPED - THE JAM ANCHOR, which is the brief's other verb ("make the pinch
# for the player") written as an anchor instead of as geometry. See _pinch.
func _build_lab() -> void:
	# ONE FLOOR, WALLED AT BOTH ENDS, x -12..20 at y = 0.
	#
	# THE RIGHT WALL IS AT 20 for a camera reason that is load-bearing:
	# CAM_VOLS[0] ends at x = 19 with CAM_HYST 1.5, so a body that never gets
	# past x = 20.5 never steps the shelf and the whole bench is one fixed shot
	# at tier-0 height. Put a station past that and the camera drops 3 m to a
	# floor the lab does not have. A wall at 20 stops the body at 19.72
	# (BODY_R 0.28).
	#
	# THE LEFT WALL IS AT -12 for a reason found by photographing it: _reset
	# lays the chain out trailing behind the body, so at tick 0 the tip sits at
	# spawn.x - 0.4 - 5.20 = -10.2 m. A wall at -8 put 2.2 m of whip inside the
	# rock before the first tick ran, and the first frame of the level showed
	# the rope through the wall. -12 clears that by 1.8 m. The traverse has the
	# same clearance and it is not an accident there either - its wall is at
	# -14 against the same spawn.
	var pts: Array[Vector2] = [
		Vector2(-12, -8), Vector2(-12, 0),      # left wall, wound bottom-to-top
		Vector2(20, 0),                         # the bench floor
		Vector2(20, -8),                        # right wall, wound top-to-bottom
	]
	# Wound so that normalize(ab.y, -ab.x) points into the AIR on every segment,
	# which is what _collide_point's rescue branch needs to lift a particle OUT
	# of a solid rather than park it under one: up the left wall gives (1,0),
	# left-to-right along the floor gives (0,-1), down the right wall gives
	# (-1,0). tests/lab_gate.gd L3 tests every segment both ways rather than
	# taking this paragraph's word for it.
	for i in range(pts.size() - 1):
		t_a.append(pts[i])
		t_b.append(pts[i + 1])
	_finish_terrain()

	# NO FLAG AND NO FINISH. A bench is not a route, so goal_x is put past the
	# right wall where the body cannot reach it: nothing here should ever say
	# TRAVERSE COMPLETE, and _draw skips the flag at this distance.
	goal_x = 999.0
	goal_y = 0.0

	# THE STATIONS. 6.5 m apart, which is the smallest spacing that keeps them
	# genuinely in isolation: the whole rope lives inside a 6.40 m circle around
	# the body (5.25 m of chain + 1.15 m of arm), and hanging on one station
	# puts the body ~2.5 m under it, so the next anchor is sqrt(6.5^2+2.5^2) =
	# 6.96 m away and cannot be touched by accident. You learn one anchor at a
	# time because you can only reach one at a time.
	#
	# Heights are 2.2 m, which is what the school beams are and what school.tape
	# catches from a standstill, except the last, which is 2.5 m: it shipped at
	# 2.9, just inside the ~3 m ceiling throw_probe measured, and was brought
	# down for the reason written on the station itself. It is still the only
	# station here that is meant to cost you attempts.
	#
	#          x     y     r    jam  name
	var stations := [
		# 1. THE REFERENCE. Identical in radius and height to the first school
		#    beam of the shipped level (-2.0, -2.2, 0.22), and placed at the same
		#    2.6 m of lead from the same spawn, so the throw that works here is
		#    literally the throw that works there. Nothing is being taught yet.
		[ -2.0, -2.2, 0.22, 0, "BEAM"],
		# 2. SAME VERB, LESS BEAM. The door-beam radius from the traverse. A
		#    thinner beam takes a shorter wrap to turn through the same angle, so
		#    the throw has to arrive with more of the tail past it. Ordinary
		#    anchor: this station is difficulty, not vocabulary.
		[  4.5, -2.2, 0.11, 0, "THIN BEAM"],
		# 3. THE NEW WORD. r = 0.14 sits between the door beams (0.11) and the
		#    school beams (0.20-0.22) so it reads as its own class at a glance
		#    without a caption - the caption is there anyway, because this is a
		#    lab. Same height as station 1 on purpose: the ONLY thing that differs
		#    between them is what it takes to make it hold.
		[ 11.0, -2.2, 0.14, 1, "JAM"],
		# 4. THE SAME WORD, THROWN HARDER - and 2.5 m, not the 2.9 m this bench
		#    first shipped with. At 2.9 the station was not difficult, it was
		#    luck: 3 winning strokes in 108, a press window of 3 ticks (50 ms),
		#    and a lead basin of 64 cells in TEN separate blocks, two of them a
		#    single 2.5 mm wide. There is no RNG in this sim, so every one of
		#    those outcomes is repeatable - but a player cannot stand to 2.5 mm
		#    or press to 50 ms, so the SAME INTENTION took sometimes and not
		#    others, which is the one thing this game has ruled out. Difficulty
		#    here lives in stroke shape, where it is learnable, and not in
		#    height: 121 of 121 lead cells across +/-150 mm hold at every other
		#    station on this bench.
		[ 17.5, -2.5, 0.14, 1, "JAM HIGH"],
	]
	for a: Array in stations:
		_add_anchor(Vector2(a[0], a[1]), a[2], int(a[3]), String(a[4]))

# -------------------------------------------------------------- THE CRAG --
# --level crag. THE ENVIRONMENT IS THE THING THE WHIP INTERACTS WITH. On the
# traverse every beam floats in open air and the terrain is a floor; the rope
# collides with all of it (t_a/t_b/t_n, swept) and never meets any of it
# except by falling on it. The crag puts rock around and between the anchors
# so that each one is a different throw, a different hang and a different
# swing - while every anchor stays an ORDINARY anchor: _add_anchor, jam 0,
# r 0.12-0.20, the traverse's own radii. The difference is only ever the rock.
#
# WHY THE ROCK CANNOT BE THE ANCHOR, and this is the constraint the whole
# level is shaped by rather than against: a rope holds by a self-pinch around
# something it can go fully round. A rope over a terrain corner touches at
# most (pi - interior angle) of it - 1.57 rad on a 90 degree lip - against
# th_part = 3.4 to catch and th_rel = 1.8 to stay caught. A corner cannot be
# an anchor, ever, and nothing here pretends one is: every convex corner the
# rope can reach is filleted (_fillet), so it is a curve the rope slides
# round instead of a point it snags on, and no fillet is in a_pos.
#
# WHAT THE ROCK CAN DO IS SHAPE EVERY THROW. The vocabulary, each one an
# anchor plus the terrain placed around it (the numbers are the gaps the rope
# has to fit through, against a rope radius of 0.02-0.05 m):
#
#   HORN        an anchor standing proud of a ledge, backed by rock: a shelf
#               on the FAR side, its top 0.60 m under the anchor's bottom and
#               its face 0.30-0.60 m past the anchor's edge. Measured (36
#               strokes at one lead): with the top only 0.30 m under, the tail
#               lies on the shelf and NOTHING catches; at 0.60 m under it
#               drops past and 9-12 strokes lock. The body hangs on the near
#               side and the shelf is under the far half of the swing.
#   STALACTITE  an anchor hanging under an overhang: a slab of rock 1.2 m
#               above it. Reachable only from below and the side - a throw
#               that arcs high hits the ceiling - and a strong pump puts the
#               rope, then the body, into the slab.
#   KNOB        an anchor on top of a rock: a lump 0.60 m under it. Nothing
#               can come at it from below, the tail cannot hang straight down,
#               and the body hangs against the lump's face. It is the
#               betrayer: measured 9 catches in 36 strokes and 3 locks - the
#               lump is where the tail would swing under to cross itself, so
#               most catches are partial and pay out. At 0.30 m under, 9
#               catches and none held; deeper than 0.60, nothing caught.
#   WINDOW      an anchor inside a hood: a bar over it (0.9 m clear) and a
#               bar past it (0.45 m clear). The rope must go under the one
#               and drop the tail between the anchor and the other.
#   BRANCH      an anchor beside a vertical wall on its far side: a rib
#               hanging from above to 0.8 m under the anchor, 0.45-0.50 m
#               clear. The tail cannot fly past, and the swing has one
#               side. NOT the crag's own wall: a wall that runs to the
#               floor held 0 of 432 searched strokes (see H0).
#
# THE LEVEL CONTRACT is the traverse's, unchanged, because it is measured: an
# anchor is catchable from a standstill only at <= ~2.4 m over the floor you
# throw from, and launchable only with > ~3.2 m of air under the arc, so the
# floor steps down 3.0 m past every anchor - 2.2 m over the tier you throw
# from, 5.2 m over the one you swing in. The lash gait crawls flat ground at
# ~0.42 m/s and cannot climb 20 degrees, so every tier is flat, every drop
# faces along the route, and every island the body can land on is a flat top
# it can crawl off. There is no pit: crag_gate C7 walks the whole thing with
# the hand open and reaches the flag.
#
# THE SHAPE: a gorge that steps down 27 m in nine 3.0 m drops over 59 m of
# route, tiers 5.5 m long (the traverse's are 10: this one is dense), a
# home tier of three features to warm up on, one feature at every lip, and a
# run-out to the flag. Own save slot (SAVE_PATH_CRAG), own spawn, own goal,
# own camera table, own fingerprint; world_bottom is derived from the terrain
# as it is everywhere else.
#
# ISLANDS. The rock a feature grows out of is a closed loop of terrain in the
# play plane, wound solid-inside (clockwise on screen: top edge left to
# right, so normalize(ab.y, -ab.x) points out of it). In a side view a column
# that reaches the floor is a wall across the route, so every island floats:
# the lowest is 2.05 m over its tier, 3.7x the body's height, and the
# backdrop draws the rock that would join it to the cliff behind. The rope
# and body collide with the loop like any terrain; crag_gate C4 checks every
# normal, ground and island, against the air region the loops enclose.
const CRAG_VOLS := [
	[-15.0,  2.0,  0.0, 1.00],   # the home tier
	[  2.0,  7.5,  3.0, 1.00],
	[  7.5, 13.0,  6.0, 1.00],
	[ 13.0, 18.5,  9.0, 1.00],
	[ 18.5, 24.0, 12.0, 1.00],
	[ 24.0, 29.5, 15.0, 1.00],
	[ 29.5, 35.0, 18.0, 1.00],
	[ 35.0, 40.5, 21.0, 1.00],
	[ 40.5, 46.0, 24.0, 1.00],
	[ 46.0, 54.0, 27.0, 1.00],   # the run-out and the flag
]
const BD_FAR := Color(0.125, 0.135, 0.17)    # the cliff behind the play plane
const BD_MID := Color(0.155, 0.17, 0.215)    # rock joining a feature to it
const BD_ROCK := Color(0.19, 0.205, 0.25)    # the solid the terrain line edges

func _crag_rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	# clockwise on screen = solid inside, see the island winding above
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0),
		Vector2(x1, y1), Vector2(x0, y1)])

func _crag_loop(pts: PackedVector2Array, closed: bool) -> void:
	var n := pts.size() - (0 if closed else 1)
	for i in n:
		t_a.append(pts[i])
		t_b.append(pts[(i + 1) % pts.size()])

func _build_crag() -> void:
	# THE GROUND: one open polyline from the top of the left wall to the top of
	# the far seal, wound left to right along the floors so the outward normal
	# is up on a floor, right on a face you drop off, left on the seal.
	# Tier i has its floor at y = 3i and ends at the lip x = 3 + 5.5i; the home
	# tier is longer so the spawn (-6.5) has the traverse's clearance from its
	# wall (the tip lies at spawn.x - 0.4 - 5.20 = -12.1 at tick 0, the wall is
	# at -15).
	var lips: Array[float] = [3.0, 8.5, 14.0, 19.5, 25.0, 30.5, 36.0, 41.5, 47.0]
	var g := PackedVector2Array([Vector2(-15, -10), Vector2(-15, 0)])
	for i in lips.size():
		g.append(Vector2(lips[i], 3.0 * i))
		g.append(Vector2(lips[i], 3.0 * (i + 1)))
	g.append(Vector2(54, 27))
	g.append(Vector2(54, 17))                # the far seal
	_crag_loop(g, false)
	# THE ISLANDS. Each is [x0, y0, x1, y1]; the feature it serves is named in
	# the anchor table below, with its gap. A lump under a knob is only 0.30 m
	# thick, and that is a measurement: the lash gait carries the HAND 1.21 m
	# over the floor (body centre -0.28, hand 0.93 above it), and a lump whose
	# underside was 0.95 m up stopped the crawl dead at x = -2.9 with the
	# handle pressed against its face. Anything over a floor a body crawls on
	# clears 1.45 m, and the backdrop draws the pillar the lump is the top of.
	var isl: Array = [
		[-10.8, -4.4,  -5.8, -3.4],   # H1 brow:  1.2 m over the anchor
		[-14.7, -1.46, -13.64, -1.25],# H0 shelf: 0.60 past (leftward) / 0.60
		                              #   under; only 0.21 m thick because its
		                              #   underside is over the home floor in a
		                              #   dead-end corner the hand can reach
		[  5.14, -1.46, 6.7, -0.76],  # D0 shelf: 0.60 past / 0.60 under
		[  7.4, -1.6,  12.4, -0.4],   # D1 brow:  1.2 m over
		[ 26.0, 10.54, 26.8, 11.14],  # D4 lump:  0.60 under
		[ 32.34, 13.54, 33.9, 14.24], # D5 shelf: 0.30 past / 0.60 under
		[ 34.9, 13.1,  39.9, 14.3],   # D6 brow:  1.5 m over. At 1.0 it caught
		                              #   and never held (0 of 216 strokes), at
		                              #   1.2 it caught 3 of 216 and held none -
		                              #   D1, the same geometry 15 m up the
		                              #   crag, locks on stroke 76 of its grid.
		                              #   The basin under a brow is small and
		                              #   the tip is chaotic; 1.5 m is where
		                              #   this one's basin reappears.
		[ 20.92, 2.0,  21.27, 7.6],   # D3 rib:   0.50 past the anchor's edge
		[ 48.22, 17.0, 48.57, 22.6],  # D8 rib:   0.45
	]
	for r: Array in isl:
		_crag_loop(_crag_rect(float(r[0]), float(r[1]), float(r[2]),
			float(r[3])), true)
	# the hoods, L-shaped: a bar over the anchor and a bar past it
	var hood_h2 := PackedVector2Array([Vector2(-3.0, -3.5), Vector2(-1.0, -3.5),
		Vector2(-1.0, -1.5), Vector2(-1.43, -1.5), Vector2(-1.43, -3.1),
		Vector2(-3.0, -3.1)])                      # H2: 0.90 over, 0.45 past
	var hood2 := PackedVector2Array([Vector2(14.4, 2.5), Vector2(16.4, 2.5),
		Vector2(16.4, 4.5), Vector2(15.97, 4.5), Vector2(15.97, 2.9),
		Vector2(14.4, 2.9)])                       # D2: 0.90 over, 0.45 past
	var hood7 := PackedVector2Array([Vector2(41.9, 17.5), Vector2(43.9, 17.5),
		Vector2(43.9, 19.5), Vector2(43.47, 19.5), Vector2(43.47, 17.9),
		Vector2(41.9, 17.9)])                      # D7: 0.90 over, 0.45 past.
		# It shipped first at 0.80 / 0.38: caught on 3 of 36 strokes at 4.27
		# rad and betrayed every one inside 55 ticks. A gap the tail cannot
		# swing in is not difficulty, it is a wall.
	_crag_loop(hood_h2, true)
	_crag_loop(hood2, true)
	_crag_loop(hood7, true)
	# FILLETS. Every lip at 0.35 m - the body stands on it and the rope is
	# dragged over it on every crawl - and every island corner at 0.10, so the
	# rope's tail slides round a shelf or a lump instead of snagging on its
	# corner. Applied before _finish_terrain so the normals come from the
	# shortened segments. (The concave inner corner of each hood is refused by
	# _fillet, as it should be.)
	for i in lips.size():
		_fillet(Vector2(lips[i], 3.0 * i), 0.35)
	for r: Array in isl:
		for c: Vector2 in _crag_rect(float(r[0]), float(r[1]), float(r[2]),
				float(r[3])):
			_fillet(c, 0.10)
	for c: Vector2 in hood_h2:
		_fillet(c, 0.10)
	for c: Vector2 in hood2:
		_fillet(c, 0.10)
	for c: Vector2 in hood7:
		_fillet(c, 0.10)
	_finish_terrain()

	spawn = Vector2(-6.5, -1.0)
	goal_x = 52.0
	goal_y = 27.0
	cam_vols = CRAG_VOLS

	# THE FEATURES. Doors sit 1.4 m past their lip (branches 0.8 and 0.65:
	# the wall IS the lip's face), 2.2 m over the tier they are thrown from,
	# at the traverse's door radii. No captions: the crag teaches by
	# consequence, as the traverse does; the legend is in the README.
	#          x      y     r
	var feats := [
		[-12.9, -2.2, 0.14],   # H0 HORN     thrown LEFT, its ledge toward the
		                       #    wall. It was the wall BRANCH: an anchor
		                       #    0.50 m off the left wall caught 3 of 216
		                       #    searched strokes and held none, and at
		                       #    1.20 m off it caught none at all. A wall
		                       #    that runs to the floor leaves the tail no
		                       #    room to swing under and cross; the ribs
		                       #    on D3 and D8, which stop 0.8 m under the
		                       #    anchor, both lock. The branch is the rib.
		[ -8.3, -2.2, 0.12],   # H1 STALACTITE under the brow
		[ -2.0, -2.2, 0.12],   # H2 WINDOW   in a hood, over the home tier
		[  4.4, -2.2, 0.14],   # D0 HORN     lip 3.0
		[  9.9,  0.8, 0.12],   # D1 STALACTITE lip 8.5
		[ 15.4,  3.8, 0.12],   # D2 WINDOW   lip 14.0
		[ 20.3,  6.8, 0.12],   # D3 BRANCH   lip 19.5, 0.8 past it, rib
		[ 26.4,  9.8, 0.14],   # D4 KNOB     lip 25.0
		[ 31.9, 12.8, 0.14],   # D5 HORN     lip 30.5
		[ 37.4, 15.8, 0.12],   # D6 STALACTITE lip 36.0, 1.0 m of ceiling
		[ 42.9, 18.8, 0.12],   # D7 WINDOW   lip 41.5, 0.38 m gap
		[ 47.65, 21.8, 0.12],  # D8 BRANCH   lip 47.0, 0.65 past it, rib
	]
	for a: Array in feats:
		_add_anchor(Vector2(a[0], a[1]), a[2], 0, "")

	# THE BACKDROP. Far cliff, then the rock joining each feature to it, then
	# the near rock whose edge the terrain line is. Paint only.
	var sky := PackedVector2Array([Vector2(-40, -14), Vector2(-9, -11),
		Vector2(-3, -13.5), Vector2(3, -9), Vector2(8.5, -7.5), Vector2(14, -5),
		Vector2(19.5, -3.5), Vector2(25, -1), Vector2(30.5, 1.5),
		Vector2(36, 3.5), Vector2(41.5, 6), Vector2(47, 8), Vector2(54, 9.5),
		Vector2(80, 12), Vector2(80, 60), Vector2(-40, 60)])
	_bd(sky, BD_FAR)
	# a pillar under each knob, a spike over each stalactite, a buttress
	# behind each shelf, a curtain above each rib and hood - in the mid tone,
	# behind the plane, so the feature reads as part of the crag
	_bd(PackedVector2Array([Vector2(25.95, 11.0), Vector2(26.85, 11.0),
		Vector2(27.3, 15.6), Vector2(25.5, 15.6)]), BD_MID)       # D4
	for st: Array in [[-8.3, -3.4, -2.2], [9.9, -0.4, 0.8], [37.4, 14.3, 15.8]]:
		_bd(PackedVector2Array([Vector2(st[0] - 0.42, st[1]),
			Vector2(st[0] + 0.42, st[1]), Vector2(st[0], st[2] - 0.05)]),
			BD_MID)
	for br: Array in [[-10.8, -4.4, -5.8, -3.4], [7.4, -1.6, 12.4, -0.4],
			[34.9, 13.1, 39.9, 14.3]]:
		_bd(PackedVector2Array([Vector2(br[0] + 0.6, br[1]),
			Vector2(br[2] - 0.4, br[1]), Vector2(br[2] + 0.6, br[1] - 2.5),
			Vector2(br[0] - 0.2, br[1] - 2.5)]), BD_MID)
	_bd(PackedVector2Array([Vector2(-13.7, -1.3), Vector2(-14.7, -1.4),
		Vector2(-15.0, 1.0), Vector2(-13.3, 1.0)]), BD_MID)          # H0
	for sh: Array in [[5.14, -1.46, 6.7, -0.76], [32.34, 13.54, 33.9, 14.24]]:
		_bd(PackedVector2Array([Vector2(sh[0] + 0.5, sh[1] + 0.2),
			Vector2(sh[2], sh[1]), Vector2(sh[2] + 1.2, sh[1] - 1.6),
			Vector2(sh[2] + 1.6, sh[3] + 1.4), Vector2(sh[2], sh[3] + 0.5)]),
			BD_MID)
	for rb: Array in [[20.92, 2.0, 21.27, 7.6], [48.22, 17.0, 48.57, 22.6],
			[14.4, 2.5, 16.4, 2.9], [41.9, 17.5, 43.9, 17.9], [-3.0, -3.5, -1.0, -3.1]]:
		_bd(PackedVector2Array([Vector2(rb[0] - 0.3, rb[1] + 0.3),
			Vector2(rb[2] + 0.3, rb[1] + 0.3), Vector2(rb[2] + 0.5, rb[1] - 3.0),
			Vector2(rb[0] - 0.5, rb[1] - 3.0)]), BD_MID)
	# the near rock: everything under the ground polyline and beyond both
	# walls, closed round the outside; then each island, solid
	var near := PackedVector2Array([Vector2(-40, -10)])
	near.append_array(g)
	near.append_array(PackedVector2Array([Vector2(80, 17), Vector2(80, 60),
		Vector2(-40, 60)]))
	_bd(near, BD_ROCK)
	for r: Array in isl:
		_bd(_crag_rect(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
			BD_ROCK)
	_bd(hood_h2, BD_ROCK)
	_bd(hood2, BD_ROCK)
	_bd(hood7, BD_ROCK)

func _bd(poly: PackedVector2Array, col: Color) -> void:
	bd_poly.append(poly)
	bd_col.append(col)

# ---------------------------------------------------------- SCENE LEVELS --
# THE GODOT EDITOR IS THE LEVEL BUILDER. Line2D is a polyline with a drag
# handle on every point, Marker2D is a point with a crosshair, Polygon2D is a
# filled shape, and the editor already has grid snapping, undo and a zoom
# range; what was missing was a bridge from a scene the developer draws to the
# arrays the sim runs on. This is that bridge. --level <name> reads
# res://levels/<name>.tscn into t_a/t_b, the arcs, the anchors, spawn, goal,
# the camera table and the backdrop - the arrays _build_traverse, _build_lab
# and _build_crag fill by hand - THROUGH THE SAME FUNCTIONS (_fillet,
# _add_anchor, _finish_terrain), so a scene level is not a second code path
# with its own defects. tests/level_fidelity.gd is the proof: the crag exported
# to res://levels/crag.tscn by tests/level_export.gd and loaded back here
# fingerprints 1132405890178884573, the hardcoded crag's own number, with every
# element of every array bit-identical. tests/level_gate.gd -- level=<name>
# certifies what he drew.
#
# THE SCHEMA. Node NAMES give the roles, node TYPES give the geometry, and every
# knob is an exported property of one of the small scripts in res://levels/, so
# it is typed, has a default, and is edited in the inspector (a node with no
# script gets the defaults named here). Anything else in the scene is ignored.
#
#   Level (Node2D)          levels/whip_level.gd: fillet_ground 0.35 and
#                           fillet_island 0.10 (m, the per-level defaults),
#                           hud (the caption block drawn top-left; empty =
#                           a title made from the file name)
#     Ground (Line2D)       THE one open chain of rock: down the left wall,
#                           along the floors, down each face, up the far seal.
#                           levels/whip_terrain.gd: fillet -1 = the level
#                           default, 0 = sharp, > 0 = this radius (m)
#       <Marker2D> ...      optional, levels/whip_fillet.gd: one corner's own
#                           radius, dragged onto that vertex (within 0.02 m)
#     Islands (Node2D)      zero or more CLOSED loops of rock, Line2D children
#       <Line2D> ...        with closed = true: lumps, brows, shelves, hoods,
#                           ribs. Same script and fillet rule as Ground
#     Anchors (Node2D)      one Marker2D child per anchor, in the order they
#       <Marker2D> ...      are indexed: levels/whip_anchor.gd gives radius
#                           (m, default 0.12), jam (bool) and caption.
#         <anything> ...    ART ON THE ANCHOR: a Marker2D's children render
#                           live at the beam (a Sprite2D of it, say) and are
#                           read by nothing - see _art_build
#     Spawn (Marker2D)      where the body starts. Required
#     Goal (Marker2D)       the flag. Absent = a bench with no finish (the
#                           lab's goal_x = 999)
#     Bottom (Marker2D)     optional: the out-of-world line. Fall past its y
#                           and you are teleported to Spawn (falls + 1).
#                           Absent = 4 m under the deepest rock, which no
#                           body can reach; present, it lets a pit with a
#                           floor be a fall to the start. In the fingerprint
#     Checkpoints (Node2D)  optional: Marker2D children. Stand within 1.0 m of
#       <Marker2D> ...      one and Spawn moves there (the spawn is state, so
#                           the save carries it). In the fingerprint when any
#     Camera (Node2D)       optional. Absent = derived from the floors (below)
#       <Line2D> ...        one volume each: exactly 2 points on the tier's
#                           floor, x0 to x1; levels/whip_camvol.gd gives zoom
#     Backdrop (Node2D)     optional paint: Polygon2D children, filled with
#       <Polygon2D> ...     their own color, drawn in order under the terrain
#                           and read by nothing else (see bd_poly)
#     Art (Node2D)          optional, and THE ONLY NODE THAT RENDERS AS
#       <anything> ...      AUTHORED: everything under it is drawn live by
#                           Godot, whatever it is - Sprite2D, a Polygon2D or
#                           Line2D with a texture, AnimatedSprite2D, a
#                           ParallaxBackground and its layers, CPUParticles2D,
#                           a shader material. The loader reads NOTHING from
#                           it, not a coordinate, not a colour, so it cannot
#                           reach the fingerprint, the hash or any gate. The
#                           rule in one line: the Line2D is the collision,
#                           Art is free. A level whose Art carries the rock
#                           sets greybox = false on the root (whip_level.gd)
#                           and _draw stops painting the grey world over it.
#                           _art_build below is the mechanism.
#
# PIXELS, NOT METRES, AT PPM = 60 PX/M. The editor's grid, its zoom range,
# Line2D.width and every gizmo assume pixel-sized scenes; a 60 m level authored
# in metres is 60 units wide and would be edited at 6000% zoom with the grid
# unusable. So the scene is drawn at the scale _draw renders it, the loader
# divides by PPM, and then QUANTISES every coordinate to LEVEL_GRID = 0.01 m
# (anchor radii to 0.001 m). The quantisation is what makes an editor drag
# exact: one pixel is 0.016667 m, an odd number in metres, and a beam dragged
# 120 px moves exactly 2.00 m rather than 1.9999998 m of float noise. It is
# also why the crag round-trips: every one of its hand-typed coordinates has two
# decimals, and roundf(px / PPM * 100) / 100 lands on the same float32 the
# GDScript literal did - measured 10 of 10 on the crag's own values. The .tscn
# text itself was measured as well, and it is not the weak link: Godot 4.7
# writes reals with shortest-round-trip digits (0.33333334, 84.85281), and 13 of
# 13 raw float32 values came back bit-identical. The grid is for the editor's
# sake, not the file's.
#
# THE SCENE CARRIES VERTICES, NOT SEGMENTS. A fillet's tangent points and centre
# are computed here by _fillet from the corner and the radius, exactly as
# _build_crag computes them, and not stored: a tangent point such as -1.46 + 0.10
# is not on the 0.01 grid in float32 and would not survive a round trip, and
# more to the point the developer moves corners, not tangent points. All
# segments are appended first and the fillets applied afterwards in node order
# (Ground, then each island, each vertex in turn) - the order _build_crag uses,
# which is what keeps t_arc_* in the same order and the fingerprint the same.
#
# WINDING IS DECIDED HERE, NOT BY THE DEVELOPER. t_n comes from segment
# direction (normalize(ab.y, -ab.x) must point into the air; see t_n), so the
# order of a polyline's points matters, and it is the easiest thing in the
# editor to get backwards - and the consequence is a rope parked under the
# floor. The loader orients every polyline itself: an island is wound with the
# solid inside (clockwise on screen, a positive shoelace sum in y-down
# coordinates - the sign _crag_rect produces), and the ground is closed over the
# sky and wound with the air inside (the same sum, negative). A polyline drawn
# the other way round is reversed, once, and said so on the console.
# tests/level_gate.gd N then proves every normal by the independent air-region
# method (crag_gate C4, which scores 0 on a reversed walk), so the loader's rule
# and the gate's check cannot share a mistake.
#
# THE DEFAULT CAMERA TABLE is the rule CAM_VOLS and CRAG_VOLS were written to,
# read back off them: one volume per FLOOR of the ground chain (a horizontal run
# of at least LEVEL_FLOOR_MIN = 2 m walked left to right), each ending at that
# floor's lip MINUS 1.0 m - so with CAM_HYST 1.5 the shelf steps down when the
# body is 0.5 m past the lip, which is what both tables do - the first starting
# at the leftmost rock, the last ending at the rightmost, the floor's y as the
# shelf and zoom 1.0. On both shipped levels the derivation reproduces the
# hand-written table element for element (tests/level_fidelity.gd F3), which is
# how a scene level gets the committed camera without a table to maintain.
const LEVEL_DIR := "res://levels/"
const LEVEL_GRID := 0.01              # m: every authored coordinate lands here
const LEVEL_RGRID := 0.001            # m: anchor radii
const LEVEL_FLOOR_MIN := 2.0          # m: a horizontal run this long is a floor
                                      # the camera gets a volume for
const LEVEL_FILLET_GROUND := 0.35     # m: the crag's lips
const LEVEL_FILLET_ISLAND := 0.10     # m: the crag's island corners
const LEVEL_ANCHOR_R := 0.12          # m: the door-beam radius
const LEVEL_SNAP := 0.02              # m: a fillet marker must be this close to
                                      # the vertex it overrides
# Neither of these is simulation state: one is why the scene was refused, the
# other is its caption. Both in SNAP_SKIP, or every tape and save is refused.
var level_err := ""
var level_hud := ""

static func level_is_builtin(id: String) -> bool:
	return id == "" or id == "lab" or id == "crag"

static func level_scene_path(id: String) -> String:
	# "steps" -> res://levels/steps.tscn. "crag.tscn" -> res://levels/crag.tscn,
	# which is how a scene whose name a built-in level owns is played.
	# "levels/x.tscn", res://, user:// or an absolute path -> that file.
	if id.ends_with(".tscn"):
		return _res(id) if id.contains("/") else LEVEL_DIR + id
	return LEVEL_DIR + id + ".tscn"

static func level_name(id: String) -> String:
	# The slot's and the title's name: the file's basename, letters, digits,
	# '_' and '-' only, so a path can never write a save somewhere odd.
	var n := id.get_file().get_basename() if id.ends_with(".tscn") else id
	var out := ""
	for c in n:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
				or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
	return out if out != "" else "level"

func level_title() -> String:
	return "TRAVERSE" if level_id == "" else level_name(level_id).to_upper()

func _level_refuse(what: String) -> void:
	# The first refusal is the one that names the mistake; keep it.
	if level_err == "":
		level_err = "LEVEL REFUSED: " + what
		push_error(level_err)
		print(level_err)

func _build_scene(path: String) -> void:
	var bottom := NAN
	if not ResourceLoader.exists(path, "PackedScene"):
		_level_refuse("%s does not exist (a scene level lives in res://levels/)" % path)
	else:
		var ps: PackedScene = ResourceLoader.load(path, "PackedScene")
		if ps == null:
			_level_refuse("%s could not be loaded as a PackedScene" % path)
		else:
			# DETACHED. new_sim() never enters the tree and neither does the
			# level: the scene is instantiated as a free node graph, read, and
			# freed. Nothing in it gets _ready, _process or a draw call, so a
			# headless probe and the windowed game read the same numbers.
			var root: Node = ps.instantiate()
			_level_read(root, path.get_file())
			# THE BOTTOM MARKER, read here and applied after _finish_terrain
			# below, which derives world_bottom from the deepest rock. A
			# level whose first pit leads nowhere puts Bottom above that
			# pit's floor: fall past it and you are back at Spawn.
			var bt := root.get_node_or_null("Bottom")
			if bt != null and bt is Node2D:
				bottom = _lv_point(bt as Node2D, root).y
			root.free()
	if level_err != "":
		# A refused level is not played and not saved: _ready quits on
		# level_err, and a harness reads it. Leave nothing half-built.
		t_a.clear(); t_b.clear()
		t_arc_c.clear(); t_arc_r.clear(); t_arc_ang.clear()
		bd_poly.clear(); bd_col.clear()
		_clear_anchor_tables()
		cam_vols = CAM_VOLS
		goal_x = 999.0
		goal_y = 0.0
	_finish_terrain()
	if level_err == "" and not is_nan(bottom):
		world_bottom = _lv_q(bottom, LEVEL_GRID)

func _level_read(root: Node, fname: String) -> void:
	var fg := float(_lv_get(root, "fillet_ground", LEVEL_FILLET_GROUND))
	var fi := float(_lv_get(root, "fillet_island", LEVEL_FILLET_ISLAND))
	level_hud = String(_lv_get(root, "hud", ""))
	# ---- the rock: Ground, then every island, every segment appended before
	# any fillet is cut (see the order note above)
	var loops: Array = []                 # [{node, pts, closed, role}]
	var ground := root.get_node_or_null("Ground")
	if ground == null or not (ground is Line2D):
		_level_refuse("%s has no Line2D named Ground" % fname)
		return
	var gp := _lv_points(ground as Line2D, root)
	if gp.size() < 2:
		_level_refuse("Ground has %d point(s); a chain needs at least 2" % gp.size())
		return
	var dup := _lv_dup(gp, false)
	if dup >= 0:
		_level_refuse("Ground: points %d and %d are the same place (%.2f, %.2f) - a zero-length segment has no normal"
			% [dup, dup + 1, gp[dup].x, gp[dup].y])
		return
	if _lv_wound_wrong(gp, false):
		gp.reverse()
		print("level: Ground was drawn with the air on its right; reversed so the normals point into the sky")
	loops.append({"node": ground, "pts": gp, "closed": false, "role": fg})
	var isl := root.get_node_or_null("Islands")
	if isl != null:
		for c in isl.get_children():
			if not (c is Line2D):
				continue
			var p := _lv_points(c as Line2D, root)
			# a loop closed by hand (last point on the first) is closed once
			if p.size() >= 2 and p[p.size() - 1] == p[0]:
				p.remove_at(p.size() - 1)
			if p.size() < 3:
				_level_refuse("Islands/%s has %d point(s); a loop needs at least 3" % [c.name, p.size()])
				return
			dup = _lv_dup(p, true)
			if dup >= 0:
				_level_refuse("Islands/%s: points %d and %d are the same place (%.2f, %.2f)"
					% [c.name, dup, (dup + 1) % p.size(), p[dup].x, p[dup].y])
				return
			if _lv_wound_wrong(p, true):
				p.reverse()
				print("level: Islands/%s was drawn with the air inside; reversed so the rock is inside" % c.name)
			loops.append({"node": c, "pts": p, "closed": true, "role": fi})
	for lp: Dictionary in loops:
		var p: PackedVector2Array = lp["pts"]
		var n: int = p.size() - (0 if bool(lp["closed"]) else 1)
		for i in n:
			t_a.append(p[i])
			t_b.append(p[(i + 1) % p.size()])
	for lp: Dictionary in loops:
		var node: Node = lp["node"]
		var p: PackedVector2Array = lp["pts"]
		var r_node := float(_lv_get(node, "fillet", -1.0))
		if r_node < 0.0:
			r_node = float(lp["role"])
		var over := _lv_overrides(node, root, p)
		if level_err != "":
			return
		for i in p.size():
			if not bool(lp["closed"]) and (i == 0 or i == p.size() - 1):
				continue                  # an end of the chain is not a corner
			var r := float(over.get(i, r_node))
			if r > 0.0:
				_fillet(p[i], _lv_q(r, LEVEL_RGRID))
	# ---- anchors, through the one function that knows the table width
	var an := root.get_node_or_null("Anchors")
	if an != null:
		for c in an.get_children():
			if not (c is Node2D):
				continue
			var r := _lv_q(float(_lv_get(c, "radius", LEVEL_ANCHOR_R)), LEVEL_RGRID)
			if r <= 0.0:
				_level_refuse("Anchors/%s has radius %.3f m" % [c.name, r])
				return
			_add_anchor(_lv_point(c as Node2D, root), r,
				1 if bool(_lv_get(c, "jam", false)) else 0,
				String(_lv_get(c, "caption", "")))
	# ---- spawn and goal
	var sp := root.get_node_or_null("Spawn")
	if sp == null or not (sp is Node2D):
		_level_refuse("%s has no Marker2D named Spawn" % fname)
		return
	spawn = _lv_point(sp as Node2D, root)
	var gl := root.get_node_or_null("Goal")
	if gl != null and gl is Node2D:
		var g := _lv_point(gl as Node2D, root)
		goal_x = g.x
		goal_y = g.y
	else:
		goal_x = 999.0
		goal_y = 0.0
	# ---- checkpoints: optional, Marker2D children of Checkpoints
	var cpn := root.get_node_or_null("Checkpoints")
	if cpn != null:
		for c in cpn.get_children():
			if c is Node2D:
				cp_pos.append(_lv_point(c as Node2D, root))
	# ---- the camera table: authored volumes if there are any, else derived
	var vols: Array = []
	var camn := root.get_node_or_null("Camera")
	if camn != null:
		for c in camn.get_children():
			if not (c is Line2D):
				continue
			var p := _lv_points(c as Line2D, root)
			if p.size() != 2:
				_level_refuse("Camera/%s has %d points; a volume is 2, (x0, floor) and (x1, floor)"
					% [c.name, p.size()])
				return
			vols.append([minf(p[0].x, p[1].x), maxf(p[0].x, p[1].x), p[0].y,
				float(_lv_get(c, "zoom", 1.0))])
		vols.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if vols.is_empty():
		vols = level_default_vols(gp)
	cam_vols = vols
	# ---- the backdrop: paint, in tree order
	var bdn := root.get_node_or_null("Backdrop")
	if bdn != null:
		for c in bdn.get_children():
			if not (c is Polygon2D):
				continue
			var poly := _lv_polygon(c as Polygon2D, root)
			if poly.size() >= 3:
				_bd(poly, (c as Polygon2D).color)

static func level_default_vols(g: PackedVector2Array) -> Array:
	# One volume per floor, boundary at the lip - 1.0 m; see the section note.
	var lo := 1e9
	var hi := -1e9
	for p in g:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	var floors: Array = []                # [lip x, floor y]
	for i in range(g.size() - 1):
		var a := g[i]
		var b := g[i + 1]
		if absf(b.y - a.y) < 0.005 and b.x - a.x >= LEVEL_FLOOR_MIN:
			floors.append([b.x, a.y])
	if floors.is_empty():
		return [[lo, hi, g[0].y if g.size() > 0 else 0.0, 1.0]]
	var vols: Array = []
	var x0 := lo
	for i in floors.size():
		var x1: float = hi if i == floors.size() - 1 else float(floors[i][0]) - 1.0
		vols.append([x0, x1, float(floors[i][1]), 1.0])
		x0 = x1
	return vols

static func _lv_get(n: Object, prop: String, dflt: Variant) -> Variant:
	# an exported property if the node carries the script, else the default
	var v: Variant = n.get(prop)
	return dflt if v == null else v

static func _lv_q(v: float, step: float) -> float:
	var inv := roundf(1.0 / step)
	return roundf(v * inv) / inv

static func _lv_qv(v: Vector2) -> Vector2:
	return Vector2(_lv_q(v.x, LEVEL_GRID), _lv_q(v.y, LEVEL_GRID))

static func _lv_xform(n: Node, root: Node) -> Transform2D:
	# The node's own transform composed with every Node2D above it, root
	# included, so moving a group moves what is in it - what the editor shows
	# is what is loaded.
	var xf := Transform2D.IDENTITY
	var c: Node = n
	while c != null:
		if c is Node2D:
			xf = (c as Node2D).transform * xf
		if c == root:
			break
		c = c.get_parent()
	return xf

static func _lv_points(n: Line2D, root: Node) -> PackedVector2Array:
	var xf := _lv_xform(n, root)
	var out := PackedVector2Array()
	for p in n.points:
		out.append(_lv_qv((xf * p) / PPM))
	return out

static func _lv_polygon(n: Polygon2D, root: Node) -> PackedVector2Array:
	var xf := _lv_xform(n, root)
	var out := PackedVector2Array()
	for p in n.polygon:
		out.append(_lv_qv((xf * (p + n.offset)) / PPM))
	return out

static func _lv_point(n: Node2D, root: Node) -> Vector2:
	return _lv_qv(_lv_xform(n, root).origin / PPM)

static func _lv_dup(p: PackedVector2Array, closed: bool) -> int:
	# the first index whose next point (round the loop, if closed) is itself
	var n := p.size() - (0 if closed else 1)
	for i in n:
		if p[i] == p[(i + 1) % p.size()]:
			return i
	return -1

static func _lv_shoelace(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s

static func _lv_wound_wrong(p: PackedVector2Array, closed: bool) -> bool:
	# Solid inside a loop is a positive sum in y-down coordinates (the unit
	# square (0,0) (1,0) (1,1) (0,1) - _crag_rect's order - sums to +2). The
	# ground is closed over the sky, so the region it encloses is AIR and the
	# sum has to be negative.
	if closed:
		return _lv_shoelace(p) < 0.0
	var q := p.duplicate()
	q.append(Vector2(p[p.size() - 1].x, -10000.0))
	q.append(Vector2(p[0].x, -10000.0))
	return _lv_shoelace(q) > 0.0

func _lv_overrides(node: Node, root: Node, p: PackedVector2Array) -> Dictionary:
	# Marker2D children of a terrain node, each sitting on one of its vertices,
	# each carrying that corner's own fillet radius.
	var out := {}
	for c in node.get_children():
		if not (c is Node2D) or c is Line2D:
			continue
		# ONLY A FILLET MARKER MAY SIT UNDER A TERRAIN NODE, and the test is
		# the property that makes it one. Before this line any Node2D here was
		# read as a corner radius: a sprite an artist parented to Ground by
		# habit was refused with a message about vertices if it sat off one,
		# and if it happened to sit ON one it was silently taken as a fillet
		# of radius 0.0 - the corner went sharp and the level's fingerprint
		# moved (measured: steps 3144857459313072037 became 2561825494929403910
		# from one decorative sprite). A picture changing the collision is the
		# exact leak the art layer exists to make impossible, so it is refused
		# by name and told where art goes.
		if c.get("radius") == null:
			_level_refuse("%s/%s is not a fillet marker. A terrain node's children are read as corner radii and nothing else; art belongs under Art, or under an anchor's Marker2D"
				% [node.name, c.name])
			return out
		var q := _lv_point(c as Node2D, root)
		var best := -1
		var bd := 1e9
		for i in p.size():
			var d := q.distance_to(p[i])
			if d < bd:
				bd = d
				best = i
		if best < 0 or bd > LEVEL_SNAP:
			_level_refuse("%s/%s sits %.2f m from the nearest vertex of %s (%.2f, %.2f); drag it onto the corner it rounds"
				% [node.name, c.name, bd, node.name, p[best].x if best >= 0 else 0.0,
				p[best].y if best >= 0 else 0.0])
			return out
		out[best] = float(_lv_get(c, "radius", 0.0))
	return out

# ---------------------------------------------------------------- the art --
# ART SHOWS UP THE WAY SOUND DOES: only in a real windowed session, feeding
# nothing back, invisible to every probe. _build_scene reads the scene into
# arrays and FREES the instance, so a Sprite2D, a textured Polygon2D, a
# ParallaxBackground - anything an artist would actually make - never got a
# draw call. This instantiates the scene a SECOND time, from _ready, and puts
# that instance in the tree as a child that draws BEHIND this node's own
# _draw: show_behind_parent, which is the same canvas and the same z-index
# with the child's commands issued first, so it composes with the Camera2D
# (a world-space child scrolls with the world) and with the HUD CanvasLayer
# (layer 1, above everything in layer 0) without a transform anywhere. The
# scene is authored in pixels at PPM = 60, which is _draw's own scale, so an
# instance at the origin lands on the sim exactly. Measured: a Polygon2D face
# under the floor, a Line2D texture along it, a sprite on a beam, and the
# rope, the body and the green ring are all drawn over them (art_gate A5).
#
# A SECOND INSTANCE, not the first kept alive, for two reasons. The first is
# read inside setup_sim, which every headless probe runs and which runs
# before _ready; keeping it would hand every probe a node graph it has no use
# for. And the read path stays untouched to the byte - _build_scene and
# _level_read are the lines they were - which tests/level_fidelity.gd F1 and
# art_gate A3 then prove rather than argue. The cost is one more instantiate
# at boot, and only there: 6.0 ms on steps_art (18 nodes kept), 0.002 ms on a
# built-in level, and +0.02 ms CPU / +0.17 ms GPU per windowed frame after
# that with the whole placeholder pack on screen (art_gate A7).
#
# WHAT THE LIVE INSTANCE KEEPS. Everything the sim already represents is
# removed from it - Ground, Islands, Spawn, Goal, Camera, Backdrop, and any
# other node at the root the schema does not name - so nothing is drawn
# twice and the @tool helper drawings (the anchor's disc, the terrain's
# air-side pips) do not appear in the game. Two things stay: Art, whole; and
# Anchors, with each Marker2D's OWN drawing hidden through self_modulate,
# which stops at the node and does not reach its children - so a sprite
# parented to an anchor draws at the beam while the marker's disc does not.
# The ring is _draw's, drawn over both.
#
# greybox is read HERE, off the live instance, not in _level_read: it is a
# rendering choice, so it belongs to the rendering set-up, and a probe - no
# _ready, no instance - keeps the default and paints the frame it always did.
func _art_build() -> void:
	if level_is_builtin(level_id):
		return                          # the traverse, the lab, the crag: no scene
	var path := level_scene_path(level_id)
	if not ResourceLoader.exists(path, "PackedScene"):
		return
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene")
	if ps == null:
		return
	var root: Node = ps.instantiate()
	greybox = bool(_lv_get(root, "greybox", true))
	# A LEVEL WITH NOTHING TO SEE IS A MISTAKE, NOT AN INTENT. greybox off
	# with no Art node draws the rope, the body and the rings over the clear
	# colour - the floor is wherever the rope happens to lie. Measured
	# unplayable; so the grey world stays on, and the console says why.
	if not greybox and root.get_node_or_null("Art") == null:
		print("art: greybox is off but %s has no Art node - nothing would be drawn but the instruments, so the greybox stays on" % path.get_file())
		greybox = true
	var drop: Array = []
	for c in root.get_children():
		if c.name == "Art":
			continue
		if not (c.name in ["Ground", "Islands", "Anchors", "Spawn", "Goal", "Bottom", "Checkpoints", "Camera", "Backdrop"]):
			# Not a schema name: the loader never read it, so it was never
			# collision, and it is not under Art, so it is not a picture. Say
			# so rather than free it in silence - a node called Props with a
			# level's worth of sprites in it vanished without a word once.
			print("art: %s/%s is not a schema node and not under Art - it is not drawn. Move it under Art" % [path.get_file(), c.name])
		if c.name == "Anchors":
			for a in c.get_children():
				if a is CanvasItem:
					(a as CanvasItem).self_modulate = Color(1, 1, 1, 0)
			continue
		drop.append(c)
	for c: Node in drop:
		root.remove_child(c)
		c.free()
	# THE INSTRUMENTS STAY ON TOP, as a rule and not as advice. The whole
	# layer draws behind this node's _draw, which is where the rope, the body,
	# the rings and the crosshair live - unless something under Art carries a
	# positive z_index, which lifts it above the default canvas and over all
	# of them (measured: a z_index 5 sprite painted 77 of 85 rope pixels
	# blue, silently). A CanvasLayer at layer 0 or above does the same to the
	# HUD. Both are clamped here, by name, on the console.
	var artn := root.get_node_or_null("Art")
	if artn != null:
		_art_clamp(artn)
	if root is CanvasItem:
		(root as CanvasItem).self_modulate = Color(1, 1, 1, 0)
		(root as CanvasItem).show_behind_parent = true
	root.name = "ArtLayer"
	add_child(root)
	art_root = root
	art_on = true

func art_node_count() -> int:
	# how many nodes the live instance holds, for the gate; 0 without one
	return 0 if art_root == null else _art_count(art_root)

static func _art_count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _art_count(k)
	return c

static func _art_clamp(n: Node) -> void:
	# see _art_build: nothing under Art may draw over the instruments
	if n is CanvasItem:
		var ci := n as CanvasItem
		if ci.z_index > 0:
			print("art: %s had z_index %d - clamped to 0. Nothing under Art may draw over the rope, the body or the rings" % [n.name, ci.z_index])
			ci.z_index = 0
	elif n is CanvasLayer:
		var cl := n as CanvasLayer
		if cl.layer >= 0:
			print("art: %s is a CanvasLayer at layer %d - set to -1. A layer at 0 or above would draw over the HUD" % [n.name, cl.layer])
			cl.layer = -1
	for k in n.get_children():
		_art_clamp(k)
# ------------------------------------------------------ end scene levels --

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
	_av_reset()
	cam_reinit()
	run_ticks = 0
	finished = false
	falls = 0
	tick_count = 0

# ---- CAMERA: a pure function of the body and the level ----
# WHAT THE CAMERA IS ALLOWED TO KNOW, and this is the whole list: where the body
# is, how fast the body is going, and an authored table of volumes. Not the
# rope. A frame driven by the rope pumps with the rope, and a ZOOM driven by the
# rope is worse than that: changing scale mid-stroke regrades the apparent speed
# of the wave, which is the one reading the player has spent hours learning. It
# is also the shape of an assist - a camera that widened exactly when your
# momentum was enough to clear the next gap would be a feasibility oracle, and
# this game does not tell you whether you are going to make it.
#
# THIS IS ENFORCED, NOT REQUESTED. tests/cam_gate.gd C1 reads the source between
# these two markers and fails if any of 23 rope identifiers appears inside them.
# The law is written as static functions on purpose: a static func cannot reach
# instance state, so the rope arrays are not in scope to be read by accident,
# and the only way to reintroduce the bug is to pass one in as an argument -
# which the gate then sees.
const VIEW_W := 1600.0 / PPM          # m across the frame at zoom 1
const VIEW_H := 900.0 / PPM           # m down   the frame at zoom 1

# THE VOLUMES: x0, x1, tier floor y, authored zoom. One per tier of the
# staircase, spanning the whole playable width from the left wall to the far
# wall. The vertical is a function of WHICH VOLUME the body is in - that is, of
# its x - and never of its y. That is what makes a 3 m drop a fixed shot the
# player falls THROUGH: a fall barely changes x, so the camera does not move
# vertically at all during one, the floor line holds still, and height and
# speed stay readable against it. A camera that chased the fall would show a
# floor rushing up at a body that appears not to move, which destroys exactly
# the two readings a 3 m drop asks you to make.
#
# EVERY ZOOM IS 1.00, and that is a measurement, not an omission. The largest
# must-see box in the game is the F1->F2 leap at 11.1 x 7.1 m against a
# 26.67 x 15.00 m frame; every volume has 35-66% of unused headroom and not one
# is short. The rope is bounded to a 6.40 m circle around the body by
# construction (5.25 m of chain + 1.15 m of arm), so nothing DYNAMIC can ever
# demand a wider view - only static authored level features could, and none
# here does. Read the column as a budget: the moment an edit puts a beam more
# than ~13 m ahead or ~11 m of vertical content inside one volume, it stops
# being optional. The mechanism ships regardless, under the rate cap below.
const CAM_VOLS := [
	[-14.0, 19.0,  0.0, 1.00],   # V0 the school
	[ 19.0, 29.0,  3.0, 1.00],   # V1 tier 1
	[ 29.0, 39.0,  6.0, 1.00],   # V2 tier 2
	[ 39.0, 47.0,  9.0, 1.00],   # V3 tier 3 (short - the tightest volume)
	[ 47.0, 62.0, 12.0, 1.00],   # V4 tier 4 / the run-out to the flag
]
# Shelf: the camera centre sits this far above the tier's floor. Uniform only
# because the level is uniform - every tier is the same 3 m step with beams at
# the same two heights - and authored per volume so a tier that is not gets its
# own number. What -2.2 buys per tier: the top edge 4.3 m clear above the door
# beam (a thrown tip measures up to 4.51 m above the body), the bottom edge
# 2.5 m below the next tier down, and a standing body at 63% of frame height.
const CAM_SHELF := -2.2
const CAM_HYST := 1.5                 # m of hysteresis either side of a boundary
const CAM_TAU_V := 0.70               # s, low-pass on body velocity BEFORE use
const CAM_TAU_P := 0.25               # s, the horizontal follower's own pole
const CAM_LEAD := 0.40                # s of body velocity, forward
const CAM_LMAX := 3.2                 # m: 12% of the view = body at 38% back
const CAM_LBACK := 1.2                # m, and deliberately ASYMMETRIC
const CAM_WY := 2.2                   # rad/s, critically damped onto the shelf
const CAM_EDGE := 2.0                 # m the body may never come within of an edge
const CAM_WZ := 2.0                   # rad/s, critically damped on ln(zoom)
const CAM_ZRATE := 0.08               # 1/s, hard cap on |d ln(zoom)/dt|

# THE TABLE IS PER LEVEL. CAM_VOLS above is the traverse's; the lab shares it
# (one volume, by construction - see _build_lab), and the crag has its own,
# because its tiers are 5.5 m long and there are ten of them. The table
# travels INSIDE the camera's own state dictionary, so the law stays a static
# function of (state, body, velocity, dt) with nothing else in scope - the
# same discipline as before, and the same 23 banned names in cam_gate C1.
# Every caller that passes no table gets the traverse's, which is how every
# committed camera test still measures the shipped camera.
var cam_vols: Array = CAM_VOLS

static func cam_vol(x: float, vols: Array = CAM_VOLS) -> int:
	for i in vols.size():
		if x < float(vols[i][1]):
			return i
	return vols.size() - 1

static func cam_new(b: Vector2, vols: Array = CAM_VOLS) -> Dictionary:
	var i := cam_vol(b.x, vols)
	return {"vlp": Vector2.ZERO, "x": b.x,
		"y": float(vols[i][2]) + CAM_SHELF, "vy": 0.0, "vi": i,
		"lz": log(float(vols[i][3])), "vz": 0.0, "vols": vols}

static func cam_scale(st: Dictionary) -> float:
	return exp(float(st["lz"]))

static func cam_law(st: Dictionary, b: Vector2, v: Vector2,
		dt: float) -> Vector2:
	# HORIZONTAL. The velocity is low-passed first: the raw body velocity is a
	# substep difference and goes straight into the frame as shake otherwise
	# (measured: 3.58 px of single-frame departure on the crawl alone, against
	# 0.18 px through this pole). 0.70 s develops 63% of the lead inside a
	# 1.0-1.5 s flight, which is the constraint that sets it.
	var vlp: Vector2 = st["vlp"]
	vlp += (v - vlp) * (dt / CAM_TAU_V)
	st["vlp"] = vlp
	# The +CAM_TAU_P*vlp.x term cancels the follower's OWN lag, so the lead
	# authored is the lead delivered. Without it a 0.25 s lookahead against a
	# 0.25 s pole is algebraically zero - which is precisely what the shipped
	# camera was: measured p50 0.00 m, p90 0.02 m of net lead over 7679 ticks,
	# with the lookahead's only surviving contribution being the shake.
	# CAM_LBACK is asymmetric because the route is one-way by construction and a
	# pumping body reverses twice a swing; a symmetric lead would put 6.4 m of
	# frame travel into every pump cycle.
	var lead := clampf(CAM_LEAD * vlp.x, -CAM_LBACK, CAM_LMAX)
	var tx := b.x + lead + CAM_TAU_P * vlp.x
	st["x"] = float(st["x"]) + (tx - float(st["x"])) * (dt / CAM_TAU_P)
	# WHICH VOLUME, with hysteresis: the shelf steps down when the body first
	# passes the lip, and back only if it returns well past it. Measured over
	# every trace the game can produce: exactly one step per drop, no flapping.
	var vols: Array = st["vols"]
	var vi: int = int(st["vi"])
	while vi + 1 < vols.size() and b.x > float(vols[vi][1]) + CAM_HYST:
		vi += 1
	while vi > 0 and b.x < float(vols[vi][0]) - CAM_HYST:
		vi -= 1
	st["vi"] = vi
	# THE FALLBACK, and it is always live rather than a mode with an edge to
	# fall off: the body may never come within CAM_EDGE of a frame edge. The
	# committed fallback was "frame the body-and-tip bounding box", but that box
	# can never demand a zoom change - the rope is inside a 6.40 m circle by
	# construction - so it collapses to exactly this one clamp. If an expert
	# leaves the authored graph, swings back up a tier or catches something no
	# volume was written for, this takes the camera off the shelf and back onto
	# the body continuously, with no discontinuity to see. On this level it is a
	# net that never fires: worst measured approach to an edge is 3.09 m.
	var ty := float(vols[vi][2]) + CAM_SHELF
	var half := VIEW_H * 0.5 / cam_scale(st) - CAM_EDGE
	ty = clampf(ty, b.y - half, b.y + half)
	# VERTICAL: critically damped, not one-pole. A one-pole step is fastest at
	# t=0 and this step is 3.0 m; fired as the body is hauled off the lip, it
	# starts as you commit and finishes as you land.
	var acc := CAM_WY * CAM_WY * (ty - float(st["y"])) \
		- 2.0 * CAM_WY * float(st["vy"])
	st["vy"] = float(st["vy"]) + acc * dt
	st["y"] = float(st["y"]) + float(st["vy"]) * dt
	return Vector2(float(st["x"]), float(st["y"]))

static func cam_zoom_step(st: Dictionary, target: float, dt: float) -> float:
	# Critically damped on ln(zoom), so a step is scale-symmetric, and then a
	# HARD cap on the rate. 8%/s is the budget: a 300 ms stroke never sees more
	# than 2.4% of scale change. A consequence worth writing down, because the
	# committed design did not state it - a critically damped step of relative
	# size A peaks at 0.368*A*w, so at w=2.0 under an 0.08/s cap the cap binds
	# for any step over 11%. No two ADJACENT volumes may differ by more than
	# that, or the blend silently stops being critically damped and becomes a
	# slew-limited ramp with a corner at each end. With the column flat this is
	# vacuous, which is one more reason to keep it flat.
	var lt := log(target)
	var lz := float(st["lz"])
	var vz := float(st["vz"])
	vz += (CAM_WZ * CAM_WZ * (lt - lz) - 2.0 * CAM_WZ * vz) * dt
	vz = clampf(vz, -CAM_ZRATE, CAM_ZRATE)  # the cap is on the RATE, not the target
	lz += vz * dt
	st["lz"] = lz
	st["vz"] = vz
	return exp(lz)

func cam_apply(dt: float) -> void:
	# The only non-static function here, and all it does is hand the law a body,
	# a velocity and a fixed dt, then write the result to the node.
	if cam == null:
		return
	if cam_st.is_empty():
		cam_st = cam_new(body_pos)
	var c := cam_law(cam_st, body_pos, _body_vel(), dt)
	var z := cam_zoom_step(cam_st, float(cam_st["vols"][int(cam_st["vi"])][3]),
		dt)
	cam.position = c * PPM
	cam.zoom = Vector2(z, z)

func cam_reinit() -> void:
	# The body has jumped - spawn, R, or a save being resumed - so the camera
	# starts ON its shelf rather than sliding onto it from wherever it was.
	cam_st = cam_new(body_pos, cam_vols)
	if cam == null:
		return
	var z := float(cam_vols[int(cam_st["vi"])][3])
	cam.position = Vector2(float(cam_st["x"]), float(cam_st["y"])) * PPM
	cam.zoom = Vector2(z, z)
# ---- end camera ----

# ---- CURSOR: the mouse reaches the world through a constant, not the camera ----
# THE TRAP THIS SECTION EXISTS TO SHUT. get_global_mouse_position() is the mouse
# run BACKWARDS THROUGH THE CAMERA, so the metres-per-pixel of the control is
# whatever the camera happens to be doing. This is a position-mapped control in
# the Getting Over It line: the whole skill is motor memory of a stroke. A
# sensitivity that shifted under the player would not read as "the camera
# changed", it would read as the whip getting worse - silently, and after they
# had already learned the old one.
#
# So the camera is REMOVED FROM THE EXPRESSION rather than slowed down:
#
#     cursor = body + (mouse_px - anchor_px) * m_per_px
#
# There is no get_global_mouse_position anywhere in this file, and nothing the
# camera owns is in this path, so the mapping cannot drift with anything the
# camera does. Measured through the real canvas transform (tests/cam_gate.gd
# C2): 1.66667 m per 100 physical px of mouse at every zoom from 0.70 to 1.25
# and at every window size from 1280 to 2400 wide, identical to the last bit.
# Through the camera the same sweep runs 1.111-2.976 m - a 168% swing in the
# sensitivity of a position-mapped control - with the reach rim, the whole
# control surface, running from 77 px of desk to 207. It is 138 px at every
# one of them here. (Zoom alone, at 1600 wide, is the 1.333-2.381 m / 79%
# half of that.)
#
# CAMERA POSITION, not just zoom, is the load-bearing half. The framing above
# leads by up to 3.2 m and lets the body ride from 21% to 73% of frame height;
# a camera-mapped cursor would sweep a STATIONARY HAND 4.11 m across and
# 7.84 m down (tests/cam_ship.gd D) - 3.6x and 6.8x the entire 1.15 m reach.
# That has never shown up before only because the shipped camera never left
# the body.
const PPM_INPUT := 60.0               # px per metre of MOUSE TRAVEL. A
                                      # constant, and deliberately not PPM:
                                      # they are equal today by choice, not by
                                      # identity, and the render scale is free
                                      # to move without touching the control.
# The anchor is the screen point at which the handle target sits on the body. It
# is 1.4 m below centre because that is where the shipped camera put the body
# (cam = body + (0,-1.4): over the 9045 ticks of corpus plus leaps in
# tests/cam_ship.gd D the two mappings differ by p50 0.006 m, p90 0.058 m,
# p99 0.132 m - the 1.334 m max is R's teleport on reset.tape, where the old
# camera was left 116% of the reach behind the body), so this mapping
# REPRODUCES the control every hour of practice was done against - and then
# keeps reproducing it once the camera starts leading and stepping, which is
# exactly when the old one would have drifted.
const CURSOR_ANCHOR := Vector2(0.0, 1.4 * 60.0)   # design px, from view centre

static func cursor_of(body: Vector2, mouse_px: Vector2, anchor_px: Vector2,
		m_per_px: float) -> Vector2:
	return body + (mouse_px - anchor_px) * m_per_px

func cursor_anchor_px() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5 + CURSOR_ANCHOR

func cursor_m_per_px() -> float:
	# get_mouse_position() speaks the project's 1600x900 DESIGN pixels: the
	# engine has already divided the window's stretch back out of the event
	# (measured in a probe that was not kept: the same physical pointer reads
	# 949 px in a 1600-wide window and 1186.25 px in a 1280-wide one, exactly
	# 1/0.8; tests/cam_gate.gd C2 asserts the consequence at 1280, 1600 and
	# 2400 wide on every run).
	# Multiplying the stretch back in pins the control to PHYSICAL pixels, so a
	# smaller window is a smaller picture of the same world rather than a 25%
	# sensitivity change - the same bug as zoom, through a different door.
	# get_final_transform() is that stretch and nothing else: a Camera2D writes
	# canvas_transform, which is not part of it.
	return get_viewport().get_final_transform().get_scale().x / ppm_input

func cursor_now() -> Vector2:
	return cursor_of(body_pos, get_viewport().get_mouse_position(),
		cursor_anchor_px(), cursor_m_per_px())
# ---- end cursor ----

# ================================================ CONTROL MODES (prototype) ==
# Three candidate answers to a playtest's "pumping from no momentum is insanely
# difficult", switchable live (1 2 3, L) so they can be felt side by side.
# README "Control modes" has the measurements behind them; the short version:
# the arm is an internal pair, so the two gestures a person tries first both
# BRAKE the swing - pointing at the beam lengthens the pendulum, and pushing
# the way you swing moves the body the other way - and the pump that works is
# "reach down the rope as you pass the bottom", which nobody guesses.
#
#   1 CLASSIC       the game as it was. SPACE or LMB held = hand shut.
#   2 PULL & REACH  SPACE (or RMB) held = hand shut. While hanging, LMB held
#                   pulls you up the rope; the mouse can only let rope OUT
#                   (its along-the-rope part is clamped toward the beam), so
#                   the button is the one way to shorten and no mouse rest
#                   hauls in secret.
#   3 PULL-UP       SPACE or LMB closes the hand, and once a wrap takes it
#                   STAYS shut with no button held. LMB held (a fresh click
#                   after the catch) = pull up to your hands; LMB up = arms
#                   straight toward the beam. The mouse keeps only the lean.
#                   SPACE or RMB = let go. A trackpad slip costs a sliver of
#                   pull, never the beam.
#   L  FLIP THE LEAN  (any mode) ALIGN keeps its 25% of the sideways command
#                   but with the sign reversed (align_w 1.25), so pushing the
#                   mouse the way you swing adds swing instead of taking it.
#
# THE PULL MODES ARE INPUT, NOT SIMULATION. ctl_input only decides the
# (cursor, grip) this tick hands step_tick - exactly the pair a tape records -
# so every bench, gate and the golden hash (all of which call step_tick) are
# untouched, and a tape made in any mode replays in any mode. The lean is the
# one change inside the tick; the tape carries it as bit 2 of the grip byte
# (tape_feed, tests/tapelib.gd verify), and bits 3-4 name the control mode
# for whoever reads the tape afterwards. All of this state is in SNAP_SKIP:
# the controls you play with are not the world you are in.
enum Ctl { CLASSIC, PULL_REACH, PULL_UP }
const CTL_NAME := ["CLASSIC", "PULL & REACH", "PULL-UP"]
const CTL_HELP := [
	"hold SPACE or click = hand",
	"hold SPACE (or right mouse) = hand   hanging: hold click = pull up, mouse toward the beam = let rope out",
	"SPACE or click = catch, the hand then stays shut   hold click = pull up, release = arms straight   SPACE or right-click = let go",
]
const ALIGN_W_FLIP := 1.25            # ALIGN_W's mirror about 1: the same 25%
                                      # of sideways authority, the other sign
const CTL_CFG := "user://whip_controls.cfg"
var ctl: int = Ctl.CLASSIC
var align_w := ALIGN_W                # what _align_target refuses; see L
var ctl_prev := 0                     # last tick's buttons: 1 SPACE 2 LMB 4 RMB
var ctl_catch_t := 0                  # PULL-UP: ticks left of a click's catch
var ctl_hold_off := false             # PULL-UP: open after a let-go until all up
var ctl_pull_armed := false           # PULL-UP: the pull wants a fresh click
var ctl_pulling := false              # this tick's pull, for the HUD

# ==================================================== FEEL OPTIONS (prototype) ==
# Three answers to two playtest notes (README "Feel options"; the numbers are
# tests/feel_probe.gd's). Each is a key, each is remembered, and each is OFF by
# default, which is the game exactly as it was.
#   C   CRACK AT 45 m/s instead of 24. Sound and flash only - nothing in the
#       solver reads it. Tiny wiggles top out at 35-43 m/s and every one of
#       them cracked at 24; real throws reach 38-91, and 34 of 36 still crack
#       at 45.
#   [ ] SENSITIVITY. The whole 1.15 m reach is 69 px of mouse at 100%, so a
#       few millimetres of trackpad finger is most of an arm. Lower it and the
#       same finger moves the hand less. Input only: the tape records where
#       the hand was told to go, not the mouse, so replays do not care.
#   P   SPRINGY STICK. While the handle is on rock, the body is off the
#       ground and no wrap is engaged, the arm damps a quarter as much, so a
#       stick planted as you land bounces you back up further: 1.66 m from a
#       2-3 m fall instead of 1.16-1.29, and repeated hops level off under
#       1.7 m, so a 2 m step still needs a door. A change to the tick; tapes
#       carry it.
# The tape's grip byte carries C as bit 5 and P as bit 6 (bits 0-4: grip,
# reset, lean, control mode).
const CRACK_SPEED_HI := 45.0
const SENS_PPM := [60.0, 75.0, 90.0, 120.0]   # px per metre: 100 80 67 50 %
var crack_speed := CRACK_SPEED
var ppm_input := PPM_INPUT
var stick_on := false
var stick_c := 4.0                    # arm damping while planted (SPRING_C 17)
# M  THE MOUSE FLIP (classic only). While your hand holds you on a wrap, the
#    hand goes to the far side of your body from the mouse, so your BODY
#    follows the mouse: pull the mouse up toward the beam and you haul up the
#    rope, lean it the way you swing and you add to the swing - the two
#    gestures that, measured, shrink the swing in plain classic (44 -> ~20 deg)
#    and grow it here (to 105-130, landing the doors). Blended in over MIRROR_T
#    ticks at the catch; held through the flight after a release; unwound
#    over MIRROR_OUT_T once you are standing again with the mouse back near
#    you. Input only.
const MIRROR_T := 6
const MIRROR_OUT_T := 30              # ticks to unwind, standing, mouse near you
const MIRROR_NEAR := 0.35             # m: "near your body"
var mirror_on := false
var mirror_k := 0.0
# P  THE STICK, cycled off -> springy -> HAMMER. The hammer is the handle
#    reworked toward Getting Over It's: while it is on rock and no wrap holds
#    you, the arm is a stiff, strongly damped servo and the handle grips - so
#    with the stick planted your body sits where the mouse says, relative to
#    it, one to one, and moving the mouse moves YOU. It is a SPEED servo, not
#    a stiffer spring: the body is driven toward that spot at no more than
#    hammer_vmax, because a stiff spring stores the whole reach as energy and
#    measured, flung the body 2.7-3.6 m up - over every door's rise. It only
#    engages when the mouse PRESSES the stick into the rock (the target more
#    than hammer_press past the surface), so a whip laid back behind you before
#    a throw is not a plant.
var hammer_on := false
var hammer_gain := 10.0               # 1/s: how hard the error is chased
var hammer_vmax := 4.0                # m/s: the most the stick moves the body (and the hop)
var hammer_tau := 0.05                # s: how fast the body reaches that speed
var hammer_fmax := 560.0              # N  (F_MAX 320)
var hammer_mu := 1.2                  # the planted handle's grip (ground_mu 0.30)
var hammer_press := 0.30              # m past the surface before it is a plant
var arm_damp := SPRING_C              # the arm's damping and force cap, as vars so
var arm_cap := F_MAX                  # a bench can move them; defaults ARE the game
var hang_damp := -1.0                 # < 0 = off. Otherwise the arm's damping and
var hang_cap := F_MAX                 # cap while a wrap is engaged and you are off
var hang_k := SPRING_K                # (and its stiffness, same switch)
# H  FIRM HANG. While a wrap holds you and your feet are off the ground, the
#    arm is firm and critically damped (K 1500, C 219 against 340 and 17), so
#    your body sits 4-8 cm under your hand instead of bouncing 0-0.68 m on a
#    loose spring every 0.6 s - measured, that bob was "super loose", and it
#    was also most of the energy a parked swing lost (44 -> 33 deg over six
#    half-swings with the game's arm, 45 -> 48 with this one). It rides on the
#    tape's options byte, bit 0.
const FIRM_K := 1500.0
const FIRM_C := 219.0
var firm_on := false
# T  LOAD VIEW. Drawing only. While a wrap carries you, the rope from your
#    hand to the wrap pulls thinner and paler as the load rises and shivers
#    under a heavy one, and your body stretches along the rope as its weight
#    hangs on it - more on a hard catch.
var load_view := false
var vis_load := 0.0                   # the load the drawing shows, smoothed per frame
var rec_opt := PackedByteArray()      # the tape's per-tick options byte

func firm_set(on: bool) -> void:
	firm_on = on
	_hang_arm()

# S  STRETCHY ROPE. The rope between your hand and the wrap gives: a spring of
#    STRETCH_K on how far your hand is past the rope's free length (5 cm under
#    your weight), damped by STRETCH_C along the rope, stopped hard at
#    STRETCH_MAX; the loaded run of rope may lengthen by up to STRETCH_SEG of
#    itself so the stretch is in the rope you see. It firms your grip exactly
#    as H does, so the give is in the rope and not in your arm - the soft arm
#    bounced the body 0-0.68 m off the hand, which was the "super loose" part.
#    On the tape's options byte, bit 1.
const STRETCH_K := 1600.0
const STRETCH_C := 40.0
const STRETCH_MAX := 0.25
const STRETCH_SEG := 0.10
var stretch_on := false
# J  THE JUMP (prototype). A hop off whatever floor you stand on: W, the up
#    arrow or the right mouse button, read on the press and applied at the top
#    of the next tick like R, so a tape carries it (options byte, bit 2) and
#    a replay jumps on the same tick. Vertical jump_v plus jump_fwd of it
#    toward the side the mouse is on. Only from a FLOOR (a contact whose
#    outward normal points up), never off a wall or a ceiling, and never while
#    the stick is planted. No cooldown state: one press, one hop, and you are
#    airborne until you land. Timed against a catch, the hop's energy goes
#    into the swing, which is what an uphill FLIGHT stage would ask for.
var hud_full := false                 # F1: the controls and feel readout under the timer
var pending_jump := false
var jump_v := 3.5                     # m/s up: 0.6 m of hop on its own
var jump_fwd := 0.5                   # of jump_v, sideways toward the mouse
var rec_jumped := false               # this tick jumped (for the tape)
var stretch_k := -1                   # this substep's loaded wrap (-1 none)
var stretch_lidx := -1                # ...and the chain index where it holds

func stretch_set(on: bool) -> void:
	stretch_on = on
	_hang_arm()

func _hang_arm() -> void:
	var firm := firm_on or stretch_on
	hang_damp = FIRM_C if firm else -1.0
	hang_k = FIRM_K if firm else SPRING_K
	hang_cap = F_MAX

## The loaded wrap and where on the chain it holds, chosen as ctl_load_point
## chooses: the tightest engaged tether. Asked of this substep's state.
func _stretch_pick() -> void:
	stretch_k = -1
	stretch_lidx = -1
	if not stretch_on or not taut:
		return
	var best_s := 0.0
	for k in a_pos.size():
		if a_freelen[k] < 0.0:
			continue
		var li := a_pinidx[k] if a_pinidx[k] >= 0 else a_lockidx[k]
		if li < 0:
			continue
		var lp: Vector2 = a_pinpt[k] if a_pinidx[k] >= 0 else a_pos[k] + (pos[a_lockidx[k]] - a_pos[k]).normalized() * a_r[k]
		var slack := pos[0].distance_to(lp) - a_freelen[k]
		if stretch_k < 0 or slack > best_s:
			stretch_k = k
			stretch_lidx = li
			best_s = slack

## The rope's pull on the handle: zero until the hand is past the free length.
func _stretch_force(hvel: Vector2) -> Vector2:
	if stretch_k < 0:
		return Vector2.ZERO
	var k := stretch_k
	var lp: Vector2 = a_pinpt[k] if a_pinidx[k] >= 0 else a_pos[k] + (pos[a_lockidx[k]] - a_pos[k]).normalized() * a_r[k]
	var d := pos[0] - lp
	var l := d.length()
	var e := l - a_freelen[k]
	if e <= 0.0 or l < 0.0001:
		return Vector2.ZERO
	var u := d / l
	return -u * (STRETCH_K * e + STRETCH_C * hvel.dot(u))
                                      # the ground (the pump's arm)

func _hanging() -> bool:
	if grounded:
		return false
	for k in a_pos.size():
		if a_freelen[k] >= 0.0:
			return true
	return false
var stick_fmax := F_MAX              # arm force cap while planted: raising it
                                      # measured no higher hop (feel_probe stick)

func feel_save() -> void:
	var cf := ConfigFile.new()
	cf.load(CTL_CFG)
	cf.set_value("controls", "mode", ctl)
	cf.set_value("controls", "lean", ctl_lean())
	cf.set_value("feel", "crack_hi", crack_speed != CRACK_SPEED)
	cf.set_value("feel", "ppm", ppm_input)
	cf.set_value("feel", "stick", stick_on)
	cf.set_value("feel", "hammer", hammer_on)
	cf.set_value("feel", "mirror", mirror_on)
	cf.set_value("feel", "firm", firm_on)
	cf.set_value("feel", "stretch", stretch_on)
	cf.set_value("feel", "load_view", load_view)
	cf.save(CTL_CFG)

func feel_sens_step(d: int, persist := true) -> void:
	var i := SENS_PPM.find(ppm_input)
	if i < 0:
		i = 0
	ppm_input = SENS_PPM[clampi(i + d, 0, SENS_PPM.size() - 1)]
	if persist:
		feel_save()

func feel_hud() -> String:
	return "W / right-click = JUMP (%.1f m/s)   |   FEEL   S stretchy rope %s   |   H firm hang %s   |   T load view %s   |   M mouse flip %s   |   P stick %s   |   C crack %.0f m/s   |   [ ] %d%%" % [jump_v,
		"ON" if stretch_on else "off",
		"ON" if firm_on else "off", "ON" if load_view else "off",
		"ON" if mirror_on else "off",
		"HAMMER" if hammer_on else ("springy" if stick_on else "normal"),
		crack_speed, roundi(PPM_INPUT / ppm_input * 100.0)]

## Is the handle on rock? Stateless: asked of the geometry at the moment of use,
## so it needs no snapshot and a restored run asks the same question.
func _hand_on_rock() -> bool:
	var p := pos[0]
	var pr := p_rad[0] + 0.01
	if cand_seg.size() != NP:
		_cull_tick()
	for sg: int in cand_seg[0]:
		var A := t_a[sg]
		var ab := t_b[sg] - A
		var tt := clampf((p - A).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(A + ab * tt) < pr:
			return true
	for j: int in cand_arc[0]:
		if p.distance_to(t_arc_c[j]) < t_arc_r[j] + pr:
			return true
	return false

## Is the body resting on a FLOOR? The nearest rock within a whisker of the
## body whose outward normal points up. Walls and ceilings do not count.
func _body_on_floor() -> bool:
	# RESTING: a body already rising (a hop one tick ago) is not on the floor,
	# whatever it still touches - measured, two presses one tick apart jumped twice
	if absf((body_pos.y - body_prv.y) / SDT) > 0.5:
		return false
	var p := body_pos
	var lim := BODY_R + 0.03
	for sg in t_a.size():
		var A := t_a[sg]
		var B := t_b[sg]
		if p.x < minf(A.x, B.x) - lim or p.x > maxf(A.x, B.x) + lim:
			continue
		if p.y < minf(A.y, B.y) - lim or p.y > maxf(A.y, B.y) + lim:
			continue
		var ab := B - A
		var tt := clampf((p - A).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p - (A + ab * tt)
		if d.length() <= lim and d.normalized().y < -0.7:
			return true
	for j in t_arc_c.size():
		var dj := p - t_arc_c[j]
		if dj.length() <= t_arc_r[j] + lim and dj.normalized().y < -0.7:
			return true
	return false

func _engaged_any() -> bool:
	for k in a_pos.size():
		if a_freelen[k] >= 0.0:
			return true
	return false

## Where the planted hammer wants your body, as the handle-to-body command.
## At rest it stays short of full reach: at full reach the spot is met exactly,
## the press reads zero, the plant lets go, the body sags and the press returns
## - a 4 cm bob, measured; short of it the plant holds dead still. Moving fast
## with the mouse at the rim - a flick - it aims PAST full reach, so the servo
## is still pushing at full speed when the plant lets go: that is the hop, as
## fast as the flick and never faster than hammer_vmax (feet ~0.6 + v^2/2g).
func _hammer_cmd(bvel: Vector2) -> Vector2:
	var raw := target_m - body_pos
	var l := raw.length()
	if l < 0.0001:
		return raw
	var fast := clampf((bvel.length() - 0.5) / 1.0, 0.0, 1.0)
	var rim := clampf((l - (REACH - 0.15)) / 0.15, 0.0, 1.0)
	var still_reach := REACH - hammer_press - 0.10
	return raw / l * minf(l, lerpf(still_reach, REACH + 0.4 * rim, fast))

func _hammer_planted() -> bool:
	if not hammer_on or _engaged_any():
		return false
	var nrm := _hand_rock_normal()
	if nrm == Vector2.ZERO:
		return false
	return (target_m - pos[0]).dot(nrm) < -hammer_press

## The outward normal of the rock the handle is touching, or ZERO. Stateless,
## like _hand_on_rock: asked of the geometry at the moment of use.
func _hand_rock_normal() -> Vector2:
	var p := pos[0]
	var pr := p_rad[0] + 0.01
	if cand_seg.size() != NP:
		_cull_tick()
	for sg: int in cand_seg[0]:
		var A := t_a[sg]
		var ab := t_b[sg] - A
		var tt := clampf((p - A).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := A + ab * tt
		if p.distance_to(q) < pr:
			return t_n[sg] if tt > 0.0 and tt < 1.0 else (p - q).normalized()
	for j: int in cand_arc[0]:
		var d := p - t_arc_c[j]
		if d.length() < t_arc_r[j] + pr:
			return d.normalized()
	return Vector2.ZERO

## the friction a particle meets on rock: the planted hammer's handle grips
func _mu(i: int) -> float:
	if i == 0 and hammer_on and _hammer_planted():
		return hammer_mu
	return ground_mu

func _stick_planted() -> bool:
	# Only with the BODY off the ground: a stick planted under a falling or
	# bouncing body. A body standing on the floor while the handle drags
	# through a throw's wind-up is not a plant, and measured, letting it count
	# cost the first door one of its seven locking strokes.
	if not stick_on or grounded:
		return false
	for k in a_pos.size():
		if a_freelen[k] >= 0.0:
			return false
	return _hand_on_rock()

func ctl_set(mode: int, lean: bool, persist := true) -> void:
	ctl = mode
	align_w = ALIGN_W_FLIP if lean else ALIGN_W
	ctl_catch_t = 0
	ctl_hold_off = false
	ctl_pull_armed = false
	if persist:
		feel_save()

func ctl_lean() -> bool:
	return align_w != ALIGN_W

func ctl_boot() -> void:
	# the last mode you chose, then the command line over it:
	#   -- --controls classic|pull-reach|pull-up  [--lean | --no-lean]
	var mode := int(Ctl.CLASSIC)
	var lean := true                      # the flipped lean playtested better
	load_view = true                      # ...and so did the load view
	crack_speed = CRACK_SPEED_HI          # a new player starts on the 45 m/s crack
	stick_on = true                       # ...and the springy stick (playtested best)
	hammer_on = false
	stretch_set(true)                     # ...and the stretchy rope
	var cf := ConfigFile.new()
	if cf.load(CTL_CFG) == OK:
		mode = clampi(int(cf.get_value("controls", "mode", 0)), 0, 2)
		lean = bool(cf.get_value("controls", "lean", true))
		crack_speed = CRACK_SPEED_HI if bool(cf.get_value("feel", "crack_hi", true)) else CRACK_SPEED
		var pp := float(cf.get_value("feel", "ppm", PPM_INPUT))
		ppm_input = pp if SENS_PPM.has(pp) else PPM_INPUT
		stick_on = bool(cf.get_value("feel", "stick", true))
		hammer_on = bool(cf.get_value("feel", "hammer", false)) and not stick_on
		mirror_on = bool(cf.get_value("feel", "mirror", false))
		firm_set(bool(cf.get_value("feel", "firm", false)))
		stretch_set(bool(cf.get_value("feel", "stretch", true)))
		load_view = bool(cf.get_value("feel", "load_view", true))
		lean = bool(cf.get_value("controls", "lean", true))
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--controls" and i + 1 < args.size():
			mode = maxi(0, ["classic", "pull-reach", "pull-up"].find(args[i + 1]))
		elif args[i] == "--lean":
			lean = true
		elif args[i] == "--no-lean":
			lean = false
	ctl_set(mode, lean, false)

func ctl_load_point() -> Vector2:
	# The far end of the rope you hang from: the tightest ENGAGED tether's pin
	# or lock point, chosen as _align_target chooses its load line but without
	# the "loaded" test - a pull on the lip, where the floor still carries you,
	# is the pull that matters most. NAN when nothing is engaged.
	var best := -1
	var best_s := 0.0
	var pt := Vector2(NAN, NAN)
	for k in a_pos.size():
		if a_freelen[k] < 0.0:
			continue
		var lp: Vector2
		if a_pinidx[k] >= 0:
			lp = a_pinpt[k]
		else:
			var li := a_lockidx[k]
			if li < 0:
				continue
			lp = a_pos[k] + (pos[li] - a_pos[k]).normalized() * a_r[k]
		var slack := pos[0].distance_to(lp) - a_freelen[k]
		if best < 0 or slack > best_s:
			best = k
			best_s = slack
			pt = lp
	return pt

func _ctl_along(cur: Vector2, lp: Vector2, pull: bool, straight: bool) -> Vector2:
	# Rebuild the hand command about the rope. u runs from the rope's far end
	# to the body, i.e. DOWN the rope. The across part stays the mouse's (and
	# step_tick's ALIGN still refuses align_w of it). The along part:
	#   pull      +REACH down the rope - the arm pair hauls the body up to the
	#             handle (bot_pump's sign check); the one way to shorten
	#   straight  -REACH, arms straight toward the beam (PULL-UP, button up)
	#   neither   the mouse's own along part, clamped to point toward the beam:
	#             the mouse can let rope out and can no longer haul in
	# Every result lies inside the reach circle, so it is a target the mouse
	# could already produce: nothing here is a new capability, only a new
	# way to reach an old one.
	var r := body_pos - lp
	var l := r.length()
	if l < 0.05:
		return cur
	var u := r / l
	var d := (cur - body_pos).limit_length(REACH)
	var along := d.dot(u)
	var across := d - u * along
	var room := sqrt(maxf(REACH * REACH - across.length_squared(), 0.0))
	if pull:
		along = room
	elif straight:
		along = -room
	else:
		along = minf(along, 0.0)
	ctl_pulling = pull
	return body_pos + across + u * along

func ctl_input(cur: Vector2, sp: bool, lmb: bool, rmb: bool) -> Array:
	# (mouse cursor, buttons) -> the [cursor, grip] step_tick is fed this tick
	var btn := (1 if sp else 0) | (2 if lmb else 0) | (4 if rmb else 0)
	var edge := btn & ~ctl_prev
	ctl_prev = btn
	ctl_pulling = false
	if ctl == Ctl.CLASSIC:
		if not mirror_on and mirror_k <= 0.0:
			return [cur, sp or lmb]
		var grip := sp or lmb
		# On while a wrap holds you, and it STAYS on through the flight after
		# you let go, until your body is back on the ground. Unwinding it in
		# the air swings the hand across your body and the arm kicks you the
		# other way - measured, every release with the mouse left where it was
		# then fell short into the shaft.
		# And on the ground it unwinds only once the mouse is back near your
		# body, slowly: unwinding with the mouse held out swings the hand
		# across and shoves you back off the edge you just landed on.
		var near := (cur - body_pos).length() < MIRROR_NEAR
		var hang := mirror_on and ((grip and not is_nan(ctl_load_point().x))
			or (mirror_k > 0.0 and (not grounded or not near)))
		mirror_k = clampf(mirror_k + (1.0 / float(MIRROR_T) if hang else -1.0 / float(MIRROR_OUT_T)), 0.0, 1.0)
		if mirror_k > 0.0:
			cur = cur.lerp(body_pos * 2.0 - cur, mirror_k)
		return [cur, grip]
	var lp := ctl_load_point()
	var engaged := not is_nan(lp.x)
	if ctl == Ctl.PULL_REACH:
		var hand := sp or rmb
		if hand and taut and engaged:
			return [_ctl_along(cur, lp, lmb, false), true]
		return [cur, hand]
	# PULL-UP
	if taut and engaged:
		ctl_catch_t = 0
		if (edge & 5) != 0:
			# a fresh SPACE or right click: let go, and stay open until every
			# button is up, so the same press cannot catch the next beam
			ctl_hold_off = true
			ctl_pull_armed = false
			return [cur, false]
		if not lmb:
			ctl_pull_armed = true
		return [_ctl_along(cur, lp, lmb and ctl_pull_armed, true), true]
	ctl_pull_armed = false
	if ctl_hold_off:
		if btn == 0:
			ctl_hold_off = false
		return [cur, false]
	if (edge & 3) != 0:
		# a press closes the hand for the whole catch window even if the
		# button is already back up - a trackpad tap is a catch
		ctl_catch_t = GRIP_WINDOW
	var shut := sp or lmb or ctl_catch_t > 0
	if ctl_catch_t > 0:
		ctl_catch_t -= 1
	return [cur, shut]

func ctl_hud() -> String:
	if ctl == Ctl.CLASSIC and not ctl_lean():
		return "controls 1 CLASSIC: hold SPACE or click = hand      [1 2 3 = control modes   L = lean   S H T M P C [ ] = feel]\n" + feel_hud()
	return feel_hud() + "\n" + "CONTROLS %d %s%s: %s%s      [1 2 3 = controls   L = lean %s]" % [
		int(ctl) + 1, CTL_NAME[ctl], "  + FLIPPED LEAN" if ctl_lean() else "",
		CTL_HELP[ctl], "   PULLING" if ctl_pulling else "",
		"flipped: push the way you swing" if ctl_lean() else "normal"]

# ------------------------------------------------------------------- input --
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not play_on:
		if event.button_index == MOUSE_BUTTON_RIGHT and ctl == Ctl.CLASSIC:
			pending_jump = true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			# DEFERRED, so that restarting is part of a TICK. R is the one verb
			# that is not (cursor, grip), and a tape that could not carry it
			# would replay a session containing an R press as a session that
			# never restarted - silently, and wrongly. Applying it at the top of
			# step_tick puts it inside the recorded input stream instead.
			pending_reset = true
		elif event.keycode == KEY_1 or event.keycode == KEY_2 or event.keycode == KEY_3:
			if not play_on:
				ctl_set(event.keycode - KEY_1, ctl_lean())
		elif event.keycode == KEY_L:
			if not play_on:
				ctl_set(ctl, not ctl_lean())
		elif event.keycode == KEY_C and not play_on:
			crack_speed = CRACK_SPEED if crack_speed != CRACK_SPEED else CRACK_SPEED_HI
			feel_save()
		elif event.keycode == KEY_BRACKETLEFT and not play_on:
			feel_sens_step(1)             # [ = less sensitive
		elif event.keycode == KEY_BRACKETRIGHT and not play_on:
			feel_sens_step(-1)            # ] = more sensitive
		elif event.keycode == KEY_P and not play_on:
			# off -> springy -> hammer -> off
			if not stick_on and not hammer_on:
				stick_on = true
			elif stick_on:
				stick_on = false
				hammer_on = true
			else:
				hammer_on = false
			feel_save()
		elif event.keycode == KEY_M and not play_on:
			mirror_on = not mirror_on
			feel_save()
		elif event.keycode == KEY_H and not play_on:
			firm_set(not firm_on)
			feel_save()
		elif event.keycode == KEY_T:
			load_view = not load_view
			feel_save()
		elif event.keycode == KEY_S and not play_on:
			stretch_set(not stretch_on)
			feel_save()
		elif (event.keycode == KEY_W or event.keycode == KEY_UP) and not play_on:
			pending_jump = true
		elif event.keycode == KEY_F1:
			hud_full = not hud_full
		elif event.keycode == KEY_F11:
			# FULLSCREEN, toggled. A window matter and not a tick: the sim
			# never reads the window, and the cursor keeps its 16.7 mm per
			# PHYSICAL pixel whatever the size (cursor_m_per_px multiplies the
			# stretch back in; cam_gate C2 asserts it at three widths).
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN 				or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
				else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif (event.keycode == KEY_F or event.keycode == KEY_G) and rec_on:
			# MARK THIS MOMENT, AND SAY WHICH KIND IT WAS. Guarded on rec_on, so
			# the keys are inert in an ordinary session and the game is
			# byte-for-byte the game it was; --record is the whole opt-in. LATCHED
			# rather than acted on, because _input runs on the FRAME: stamping a
			# tick from here would stamp whichever tick happened to be next, or
			# none at all on a dropped frame. _rec_tick spends it on the next tick
			# it records.
			#
			# TWO KEYS RATHER THAN ONE, because the two complaints are questions
			# about different code and want different evidence. F is "it was green
			# and it let go anyway" - a question about _holds and the exits out of
			# a lock. G is "that should have caught and did not" - a question
			# about the five clauses of the catch. One key would leave the player
			# to remember afterwards which mark was which, and a mark whose meaning
			# is recalled an hour later is worth less than one that names itself at
			# the instant it is pressed.
			rec_mk = MARK_GREEN if event.keycode == KEY_F else MARK_NOHOOK
		elif event.keycode == KEY_ESCAPE:
			_av_stop()   # leave quietly; see _notification
			get_tree().quit()

func _physics_process(_d: float) -> void:
	if external_drive:
		return
	if play_on:
		_play_tick()
		cam_apply(DT)
		return
	if play_done:
		_av_hush()                    # ...but it does not hold its last NOISE
		return                        # a finished replay holds its last frame
	var io := ctl_input(cursor_now(), Input.is_key_pressed(KEY_SPACE),
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	step_tick(io[0], io[1])
	# Stepped with the FIXED tick, not the frame delta: the camera advances once
	# per simulation tick, so the same run frames identically every time it is
	# replayed, and a dropped frame cannot smear the shot.
	cam_apply(DT)
	save_due -= 1
	if save_enabled and save_due <= 0:
		save_due = AUTOSAVE_TICKS
		save_to(save_path)

func _process(d: float) -> void:
	queue_redraw()
	if zone != null and mouse_owned:
		zone.queue_redraw()
	# The DRIVERS are sampled once a tick (they are tick quantities); the
	# smoothing and the writes to the mixer happen per FRAME, so a voice glides
	# rather than stepping at 60 Hz. This is a smoothing of the OUTPUT only -
	# nothing here can reach an input or a sim variable, so it is not the kind
	# of smoothing the no-assists contract bans.
	if av_on:
		_av_frame(d)
	if status != null:
		var secs := run_ticks / 60.0
		var line := "time %.1fs   falls %d   tip %.0f m/s" % [secs, falls, tip_speed]
		if finished:
			line = "%s COMPLETE in %.1fs - press R to run it again" % [
				level_title(), secs]
		if rec_on:
			line += "   [REC %d   F = green dropped me   G = should have hooked   marks %d]" % [rec_cur.size(), rec_mark.size()]
			# A MARK THAT IS NOT ACKNOWLEDGED GETS PRESSED TWICE, and two presses
			# a second apart are two different moments to whoever reads the tape.
			# Two seconds of the mark's own number and the second it landed on:
			# enough to know it registered, and it names the thing the player is
			# about to describe.
			if rec_mark.size() > 0 \
					and rec_cur.size() - rec_mark[rec_mark.size() - 1] < 120:
				line += "   MARK %d %s @ %.1fs" % [rec_mark.size(),
					MARK_NAME[rec_mkind[rec_mkind.size() - 1]],
					rec_mark[rec_mark.size() - 1] / 60.0]
		elif play_on:
			line += "   [REPLAY %d/%d]" % [play_at, int(play_tape["n"])]
		elif play_done:
			line += "   [REPLAY ENDED]"
		status.text = line + ("\n" + ctl_hud() if hud_full else "")

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
	rec_jumped = false
	if pending_jump:
		pending_jump = false
		if _body_on_floor() and not (hammer_on and _hammer_planted()):
			var side := signf(cursor_m.x - body_pos.x)
			var jv := Vector2(jump_fwd * jump_v * side, -jump_v)
			body_prv -= jv * SDT          # verlet: velocity lives in the gap
			rec_jumped = true
	_align_target()
	if not finished:
		run_ticks += 1
	tick_count += 1

	if av_on:
		av_touch.fill(0)
	_cull_tick()

	var max_tip := 0.0
	av_arm = 0.0
	for s in SUB:
		_substep()
		var v := (pos[NP - 1] - prv[NP - 1]).length() / SDT
		if v > max_tip:
			max_tip = v
	tip_speed = max_tip
	av_arm /= DT    # impulse over the tick -> the tick's mean force, N

	_measure_wraps()
	_update_locks()
	_events()
	if rec_on:
		_rec_tick()
	_av_tick()      # reads the finished tick; writes no simulation state

func _body_vel() -> Vector2:
	return (body_pos - body_prv) / SDT

func _align_target() -> void:
	# THE FIST LIES ALONG THE PULL. While the hand is shut on an engaged wrap
	# that is actually CARRYING, the arm is not free to point wherever the mouse
	# says. You can slide your grip along a loaded rope; you cannot hold your
	# fist a metre off the line of the load, and for 22757 ticks of the player's
	# own session it held one 0.771 m off it (p90 1.101, max 1.150 = REACH) with
	# the rope leaving the fist backwards at a median 75.9 degrees. The tether
	# in _solve_lra fixes the handle's DISTANCE from the pin and exerts NO
	# tangential force, so the handle slides round that circle to wherever the
	# arm spring's tangential pull vanishes - the pin->cursor line - and the
	# rope's first segment is left to flail against a fist that turns a third
	# as fast as it does. That is the jank, in one number: turn ratio 0.33.
	#
	# So drop the part of the commanded target that lies ACROSS the load line
	# pin->body and keep the part ALONG it. ALONG is where the pump lives: the
	# pump is a pendulum-LENGTH command, radial about the pin, and radial IS the
	# load line - which is why this costs the pump nothing.
	#
	# ONCE PER TICK, from this tick's target_m and this tick's body_pos, BEFORE
	# the substep loop. A per-substep version was written first and is wrong:
	# body_pos travels 3-5 cm inside one tick, so by the last substep a PARKED
	# cursor sits that far off the body and the projection threw the offset
	# away - the state hash diverged at tick 1 on a player who was doing
	# nothing. Computed here, a parked cursor gives target_m == body_pos, the
	# across component is exactly zero, and the tick is bit-identical to the
	# arm without this fix.
	if not taut or align_w <= 0.0:
		return
	var d := target_m - body_pos
	if d.length_squared() < 1e-12:
		return
	# The tightest LOADED tether is the one carrying you.
	var best := -1
	var best_s := 0.0
	var pt := Vector2.ZERO
	for k in a_pos.size():
		if a_freelen[k] < 0.0:
			continue                       # not engaged: no load line to lie on
		var lp: Vector2
		if a_pinidx[k] >= 0:
			lp = a_pinpt[k]
		else:
			var li := a_lockidx[k]
			if li < 0:
				continue
			lp = a_pos[k] + (pos[li] - a_pos[k]).normalized() * a_r[k]
		var slack := pos[0].distance_to(lp) - a_freelen[k]
		# LOADED. Airborne IS the load - the same ruling the payout ratchet
		# makes at _update_locks - or the tether is within ALIGN_LOAD_EPS of
		# full extension. A hand resting on the ground with rope to spare is
		# untouched, and so is a crawl.
		if grounded and slack < -ALIGN_LOAD_EPS:
			continue
		if best < 0 or slack > best_s:
			best = k
			best_s = slack
			pt = lp
	if best < 0:
		return
	var r := body_pos - pt
	var l := r.length()
	if l < 0.05:
		return
	var u := r / l
	var across := d - u * d.dot(u)
	# THE DEAD ZONE, and it is not a fudge: a command already ON the load line
	# must be left alone EXACTLY, not to within a rounding error. The pump is
	# such a command - a pendulum-LENGTH stroke, radial about the pin - and
	# without this line the projection returned float dust on every pumping
	# tick. Dust is not nothing here: this sim is chaotic, and its own pump
	# bench moves "over the top" from 2.0 s to 3.8 s under a 1e-4 DEGREE change
	# in the start angle (tests/pump4.gd). A micron of dust per tick was enough
	# to walk the bench off its trajectory and make it unreadable. At a
	# sub-pixel dead zone tests/bot_pump.gd's pump with the starter off - the
	# pure radial parametric drive - is BIT-IDENTICAL on all four rigs to the
	# arm without this fix, and every difference the bench does show is
	# attributable to the one command ALIGN means to refuse.
	if across.length() < ALIGN_DEAD:
		return
	target_m -= across * align_w

func _substep() -> void:
	# --- forces -> integrate (verlet) ---
	var hvel := (pos[0] - prv[0]) / SDT
	var bvel := (body_pos - body_prv) / SDT
	var arm_k := SPRING_K
	var arm_c := arm_damp
	var arm_fmax := arm_cap
	var hammered := hammer_on and _hammer_planted()
	if hang_damp >= 0.0 and _hanging():
		arm_c = hang_damp              # PUMP prototype: the arm on a hang
		arm_fmax = hang_cap
		arm_k = hang_k
	if stick_on and _stick_planted():
		arm_c = stick_c                # P: the springy stick, planted
		arm_fmax = stick_fmax
	var f := (target_m - pos[0]) * arm_k - (hvel - bvel) * arm_c
	f = f.limit_length(arm_fmax)
	if hammered:
		# P: the hammer. Where the mouse puts your body relative to the planted
		# handle is pos[0] - (target_m - body_pos); chase it at <= hammer_vmax.
		# f is the force on the handle; the body gets -f, as always.
		var vd := ((pos[0] - _hammer_cmd(bvel) - body_pos) * hammer_gain).limit_length(hammer_vmax)
		f = (-(vd - bvel) * (BODY_M / hammer_tau)).limit_length(hammer_fmax)

	var rope_f := Vector2.ZERO
	if stretch_on:
		_stretch_pick()
		rope_f = _stretch_force(hvel)
	var np := pos[0] + (pos[0] - prv[0]) + (GRAV + (f + rope_f) * inv_m[0]) * SDT * SDT
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
	# WHAT THE ARM DELIVERED THIS SUBSTEP, as a force on the handle: the
	# spring (already capped) plus the tether's projection, which is a
	# position correction and converts back to a force as corr / SDT^2 (the
	# body's share is corr * wb, its impulse BODY_M * corr * wb / SDT =
	# corr / SDT, and the two shares are one internal pair). Summed as an
	# impulse over the tick and read by _av_tick alone; it is in SNAP_SKIP
	# and nothing in the sim reads it (aud_gate A2 holds the hash).
	av_arm += (f - av_armc / (SDT * SDT)).length() * SDT
	av_armc = Vector2.ZERO

func _solve_arm() -> void:
	var d := pos[0] - body_pos
	var l := d.length()
	if l > arm_max and l > 0.0001:
		var w0 := inv_m[0]
		var wb := 1.0 / BODY_M
		var corr := d * ((l - arm_max) / l / (w0 + wb))
		pos[0] -= corr * w0
		body_pos += corr * wb
		av_armc += corr

func _solve_rope(i: int, stiff: float) -> void:
	var d := pos[i + 1] - pos[i]
	var l := d.length()
	var r := rest[i]
	if stretch_on and i < stretch_lidx:
		r *= 1.0 + STRETCH_SEG            # S: the loaded run of rope gives
	if l > r and l > 0.0001:
		var w1 := inv_m[i]
		var w2 := inv_m[i + 1]
		var corr := d * ((l - r) / l * stiff / (w1 + w2))
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
		var lim := a_freelen[k] + (STRETCH_MAX if stretch_on else 0.0)
		if l > lim and l > 0.0001:
			pos[0] -= d * ((l - lim) / l)

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

const CULL_TICK := 3.0                # m a particle is allowed to travel in
                                      # ONE TICK for the per-tick candidate
                                      # lists to be exact. The fastest thing
                                      # the game produces is the tip at
                                      # 85.7 m/s, which is 1.43 m a tick.
var cand_seg: Array = []              # per particle: the segments within
                                      # CULL_MARGIN + CULL_TICK of it at the
                                      # top of the tick, in index order
var cand_arc: Array = []              # the same for the terrain arcs

func _cull_tick() -> void:
	# ONCE A TICK, NOT SIXTEEN TIMES. The per-substep box cull below is what
	# kept 26 particles x 11 segments x 16 substeps affordable on the
	# traverse; the crag has 69 segments and 55 arcs, and measured 51.6 ms a
	# tick against the traverse's 16.4 on the same contended run - 3.1x, and
	# past the 16.7 ms frame. So each particle's candidates are listed once,
	# from where it is at the top of the tick, with CULL_TICK of slack on top
	# of CULL_MARGIN, and the substeps walk only those. This cannot change a
	# result: a segment left off the list is one the old cull would have
	# skipped on every substep of this tick unless the particle covered
	# CULL_TICK metres inside it, and nothing here moves at 180 m/s. The
	# golden hash and the six tapes are the proof, and they held.
	if cand_seg.size() != NP:
		cand_seg.resize(NP)
		cand_arc.resize(NP)
	var mg := CULL_MARGIN + CULL_TICK
	for i in NP:
		var p := pos[i]
		var cs := PackedInt32Array()
		for s in t_a.size():
			if p.x < t_lo[s].x - mg or p.x > t_hi[s].x + mg \
					or p.y < t_lo[s].y - mg or p.y > t_hi[s].y + mg:
				continue
			cs.append(s)
		cand_seg[i] = cs
		var ca := PackedInt32Array()
		for j in t_arc_c.size():
			var c := t_arc_c[j]
			var rr: float = t_arc_r[j] + p_rad[i] + CULL_TICK
			if p.x < c.x - rr or p.x > c.x + rr or p.y < c.y - rr \
					or p.y > c.y + rr:
				continue
			ca.append(j)
		cand_arc[i] = ca

func _collide_point(i: int, pr: float) -> void:
	var p := pos[i]
	if cand_seg.size() != NP:
		_cull_tick()              # a probe stepping the substeps by hand
	for s: int in cand_seg[i]:
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
					# Deeper than half the rock behind this segment: the
					# particle is in the air on the far side of a slab, or
					# nearer its far face. Not this segment's contact. Inside
					# the rescue branch so the in-span path pays nothing for
					# it; t_deep is INF wherever nothing is behind a segment,
					# which is everywhere on the shipped level, and the size
					# guard is for the probes that rebuild t_a by hand.
					if s < t_deep.size() and sd < -t_deep[s]:
						continue
					# rescue: carry the velocity it arrived with, so the
					# lift-out displacement never becomes velocity.
					#
					# THE PENETRATION IS CONTINUOUS ACROSS sd = 0, and it did
					# not used to be. This branch handed _friction pen = 0.0
					# while the branch a hair away handed it pr - sd, so a
					# particle crossing the surface lost its entire friction
					# cap in one step: measured 4.26 m/s of tangential speed at
					# the tip, 14.40 at the handle, invariant under 10^8 of
					# refinement. A particle DEEPER in the solid gripped LESS
					# than one resting on it, which is the "a narrow slot grips
					# less, not more" result from the jam investigation, and it
					# is backwards. Capping the lift at pr keeps the deep case
					# from inflating the cap without bound.
					#
					# BE CLEAR ABOUT WHAT THIS BUYS, WHICH IS NOTHING TODAY.
					# Across all six tapes plus the player's own recorded
					# session - 30436 ticks, 486976 substeps - this branch
					# fires ZERO times, against 5.8M in-span contacts beside
					# it. The golden hash and all six tapes are unchanged by
					# this edit, which is the proof that it is unreachable in
					# play. It is written down because the next person to build
					# geometry that DOES reach it (a slot, a notch, a corner)
					# would otherwise meet a 14 m/s step and spend a day on it.
					var v := pos[i] - prv[i]
					var lift := minf(pr - sd, pr)
					pos[i] = q + n * pr
					prv[i] = pos[i] - (v + n * lift)
					_friction(i, n, _mu(i), lift)
				else:
					pos[i] = q + n * pr
					_friction(i, n, _mu(i), pr - sd)
				p = pos[i]
				if av_on:
					av_touch[i] = 1   # instrumentation only; see _av_tick
		else:
			# past an end of the segment: round-cap contact off the endpoint
			var l := d.length()
			if l < pr and l > 0.0001:
				var n2 := d / l
				pos[i] = q + n2 * pr
				_friction(i, n2, _mu(i), pr - l)
				p = pos[i]
				if av_on:
					av_touch[i] = 1
	for k in a_pos.size():
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
		# The mu is decided before the contact is tested: it is integer
		# state and costs nothing, and it is what lets the push itself be
		# one function shared with the terrain arcs below.
		var mu := anchor_mu
		if a_freelen[k] >= 0.0 and i >= a_pinidx[k] + a_wlo[k] and i <= a_pinidx[k] + a_whi[k]:
			mu = 8.0
		elif a_armed[k] == 0:
			mu = RELEASED_MU      # let go of: it slides, it does not grip
		_circle_out(i, a_pos[k], a_r[k] + pr, mu)
	# A FILLET IS TERRAIN: ground friction, the grit voice, and nothing the
	# catch machinery reads. Same push as a beam, by the same function.
	for j: int in cand_arc[i]:
		if _circle_out(i, t_arc_c[j], t_arc_r[j] + pr, _mu(i)) and av_on:
			av_touch[i] = 1

func _circle_out(i: int, c: Vector2, rr: float, mu: float) -> bool:
	# Push particle i out of the circle (c, rr), rr already including the
	# particle's own radius, and apply Coulomb friction to the contact. This
	# is the anchor push verbatim - the beam loop above and the arc loop
	# below both call it, so a fillet cannot drift from a beam's contact law.
	var d2 := pos[i] - c
	if d2.length_squared() >= rr * rr:
		return false
	var l2 := d2.length()
	if l2 > 0.0001:
		var n2 := d2 / l2
		pos[i] = c + n2 * rr
		_friction(i, n2, mu, rr - l2)
	return true

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
	# p0, p1 and seg describe the path ONCE, before any beam is resolved -
	# that was always so (a contact rewrote pos[i], never these), and it is
	# why they are handed to the helper rather than re-read from it.
	for k in a_pos.size():
		_swept_circle(i, p0, p1, seg, lsq, slo, shi, a_pos[k], a_r[k],
			anchor_mu)
	if cand_arc.size() != NP:
		_cull_tick()
	for j: int in cand_arc[i]:
		_swept_circle(i, p0, p1, seg, lsq, slo, shi, t_arc_c[j], t_arc_r[j],
			ground_mu)

func _swept_circle(i: int, p0: Vector2, p1: Vector2, seg: Vector2,
		lsq: float, slo: Vector2, shi: Vector2, c: Vector2, r: float,
		mu: float) -> void:
	# Anti-tunnel for one particle's substep path against one circle: the
	# beam sweep verbatim, shared with the terrain arcs.
	var rk: float = r + p_rad[i]
	if shi.x < c.x - rk or slo.x > c.x + rk 			or shi.y < c.y - rk or slo.y > c.y + rk:
		return
	var tt := clampf((c - p0).dot(seg) / lsq, 0.0, 1.0)
	var q := p0 + seg * tt
	var rr := r + p_rad[i]
	if q.distance_to(c) < rr:
		var n := (p1 - c)
		if n.length() < 0.0001:
			n = (q - c)
		if n.length() < 0.0001:
			n = Vector2.UP
		pos[i] = c + n.normalized() * rr
		_friction(i, n.normalized(), mu)

func _swept_terrain(i: int) -> void:
	var p0 := prv[i]
	var p1 := pos[i]
	var mv := p1 - p0
	if mv.length_squared() < 0.0004:
		return
	var mlo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var mhi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
	if cand_seg.size() != NP:
		_cull_tick()
	for s: int in cand_seg[i]:
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
		if av_on:
			av_touch[i] = 1
		return

func _swept_body() -> void:
	# Anti-tunnel for the body against the beams, same role as _swept_anchor
	# does for the chain, and it runs in the same sweeps-before-discrete phase.
	# The discrete test below only sees a body that ENDS a substep overlapping,
	# so what it misses is set by how long a chord the path cuts, not by the
	# beam's size. Measured (bb -- tunnel: a scratch probe, phase-scanned, per
	# substep, NOT COMMITTED; tests/bb_det.gd is the determinism gate for this
	# code, not that probe - 0.10 m beam), the discrete pass ALONE first misses
	# a contact of depth
	#     0.3 mm at  30 m/s   2 mm at  81 m/s   5 mm at 128 m/s
	#      20 mm at 255 m/s  50 mm at 391 m/s   the whole beam at 762 m/s
	# and the fastest body the game produces is 31.7 m/s (bb -- speed:
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
			_body_ground(n)
			p = body_pos
	# A FILLET IS GROUND. The body standing on a rounded lip is standing on
	# terrain: same friction as the segment it joins, and it counts as
	# grounded, because _update_locks reads grounded to decide a partial wrap
	# is unloaded, and a body resting on the lip's own curve is not hanging.
	# (A beam, below, deliberately sets neither - see there.)
	for j in t_arc_c.size():
		var dj := p - t_arc_c[j]
		var rj: float = t_arc_r[j] + BODY_R
		if dj.length_squared() >= rj * rj:
			continue
		var lj := dj.length()
		if lj <= 0.0001:
			continue
		var nj := dj / lj
		body_pos = t_arc_c[j] + nj * rj
		_body_ground(nj)
		p = body_pos
	# THE BEAMS ARE SOLID. This loop used to be missing entirely: the body was
	# tested against terrain and nothing else, so it passed clean through the
	# very beam it was hanging from - measured at up to 0.50 m of overlap, the
	# whole beam swallowed, on every radius in the level (bb -- ghost).
	# Anchors are convex circles, so unlike the terrain polyline there is no
	# "which side is solid" question and no rescue branch is needed: outward is
	# always radially away from the centre.
	#
	# NO TANGENTIAL FRICTION, and that is the design ruling, not laziness. A
	# beam that grips is a PLATFORM: Coulomb friction holds a body at rest
	# anywhere inside atan(mu) of the apex, which at ground_mu is 17 degrees -
	# a 0.11 m half-width on the thinnest beam, and wider than that in practice
	# because a body that ARRIVES with momentum beds in. Measured both ways
	# (bb -- rest, this build against the same patch with the
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
	# nothing else - the least a solid can take. Measured (bb
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

func _body_ground(n: Vector2) -> void:
	# The body's contact with TERRAIN, after body_pos has been placed on the
	# surface: Coulomb friction on the tangential part, capped by the normal
	# impulse proxy, and grounded = true. Verbatim from the segment branch
	# above; shared with the arcs so a rounded lip is the same ground as the
	# flat it joins.
	var v := body_pos - body_prv
	var vn_amt := v.dot(n)
	var vt := v - n * vn_amt
	var vt_len := vt.length()
	var cap := ground_mu * (absf(vn_amt) + GRAV.y * SDT * SDT) * 3.0
	if vt_len > 0.000001:
		vt *= maxf(vt_len - cap, 0.0) / vt_len
	body_prv = body_pos - vt
	grounded = true

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
	# truth over 576 thrown wraps (commit 40731bf, "The taut wrap angle"). The
	# rig that took them - feat_dump collected the features, score.py scored
	# them, closed_loop audited the whole loop with the hand actually closing,
	# refusal_stress2 threw the drapes - was scratch from the catch
	# investigation, depended on an ignored tests/orc_lib.gd, and was not kept;
	# the commit message carries the scores of the three rejected fixes
	# (contact hysteresis FN 99 / FP 1440, widened shell FN 33 / FP 2112, span
	# measure FN 234 / FP 690, against the shipped FN 327 / FP 635).
	#
	#  - THE COUNT CHATTERS. It moves 0.47 rad in an average tick while the
	#    rope is wrapped, and up to 5.25 rad in one tick. On a wrap rigged so
	#    it CANNOT change (orc_valid - scratch under the ignored tests/orc_*
	#    pattern, not kept) it ranges over 1.88 to 7.47 rad
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
	#    (refusal_stress2, the same rig) at a true wrap of 0.12-0.78 rad.
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
	# THE JAM ANCHOR: the level has made the crossing for you.
	#
	# This is the ONE new rule the lab adds, and it is one line of physics
	# rather than one of geometry, because geometry was measured and does not
	# work. Three separate probes swept 25 terrain and anchor shapes for a
	# jam the rope could not escape; the two that held - an hourglass
	# chockstone and a two-circle throat - both hold by collision alone, so
	# neither engages a wrap, and hanging on one with the hand OPEN is
	# bit-identical to hanging on it with the hand SHUT (+0.0280 m vs
	# +0.0280 m over 10 s, 91.00 N both). A shape that holds you regardless of
	# your hand is a shape where the grip button is decorative.
	#
	# So the jam is declared instead of built. _pinch is this file's own
	# definition of "a wrap that can hold a body", every consequence of a hold
	# hangs off it, and a jam anchor simply answers yes while the rope is
	# genuinely touching. NOTHING ELSE CHANGES, and that is the point: the
	# catch still needs a fresh grip inside GRIP_WINDOW, a_lockidx still has to
	# clear pin_min_idx, PINCH_RUN still has to run, _holds() still gates the
	# ring on a_locked == 1, and _update_locks' hand-open branch still drops
	# a_freelen, a_pinidx and a_locked in one frame. Measured on the bench from
	# a THROWN catch with the floor removed (tests/lab_gate.gd L7): hand shut,
	# the body hangs (-0.133 m over 3 s, green 180/180); hand open, it falls
	# 45.3 m on tick 0. L6 is the flag itself: it fires on contact above the
	# jam_min_th floor, not at 1 m, and not at all when it is off.
	#
	# WHAT THE PLAYER GAINS is not a new verb but a new promise - a jam anchor
	# is a beam you do not have to earn the crossing on, so it takes from
	# angles a wrap will not. What they DO NOT gain is a second set of rules.
	#
	# "Touching" is the same band _update_locks uses to decide which chain was
	# in the wrap when it engaged (a_r + p_rad + wrap_shell + 0.02), and not
	# the far looser wrap_near of 0.30 m: winding measured about a beam the
	# rope is nowhere near is not a wrap on it, and a jam that fired at 0.30 m
	# would catch on a whip merely flying past.
	# k < size, because this repo is full of probes that build an anchor by
	# appending to a_pos alone; a jam column they never heard of must not
	# crash them, it must read as 0.
	if k < a_jam.size() and a_jam[k] == 1:
		# THE FLOOR COMES FIRST, so a jam can never hold what it cannot show.
		if absf(a_theta[k]) < jam_min_th:
			return false
		var cj := a_pos[k]
		for i in NP:
			if (pos[i] - cj).length() < a_r[k] + p_rad[i] + wrap_shell + 0.02:
				return true
		return false
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
				# A fresh catch starts a fresh ratchet. The timer used to
				# survive a slide-off, so an anchor that had already betrayed
				# once paid its first segment on the first loaded tick of the
				# next catch: 2 of the 30 catches on the player's recorded
				# session (takes/bug1.tape) engaged carrying a stale timer.
				a_paytick[k] = 0
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
				# THE COUNTER RACE IS REAL AND DECIDES NOTHING. PINCH_RUN = 2
				# consecutive pinches against a LOCK_WINDOW of 30: a crossing
				# that flickers, or arrives on tick 29, is in principle a
				# partial by one tick. Measured on the player's own recorded
				# session (takes/bug1.tape, 22757 ticks, 25 locks): 0 outcomes
				# decided by it. Checked; do not re-open it on a synthetic
				# stroke.
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
					# Unwound below a full turn with no crossing left: it betrays
					# now. Measured on the player's recorded session
					# (tests/hang_census.gd on takes/bug1.tape): of 25 locks, 22
					# ended by the hand opening, 2 here, 1 by the tail running out
					# - ~12% betray - and the longest hold was 15.17 s. "Every
					# hang is temporary" was a bot's synthetic stroke, not play.
					a_locked[k] = 0
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
		# THE RATCHET RE-ARMS HERE, and for a long time it did not. The timer
		# was reset only at level reset and while locked, so PAYOUT_TICKS
		# governed the FIRST segment of a betrayal and every later one paid on
		# the next tick: measured on a searched throw, pin 19 to 24 in 5
		# ticks, and the betrayal the player felt was a snap. Reset per
		# segment it is the ratchet the comment above always described - one
		# segment every PAYOUT_TICKS, measured 15.0 ticks/segment (4.00
		# segments/s) on the r 0.22 and r 0.11 beams alike.
		a_paytick[k] = 0

func _events() -> void:
	crack_cooldown = maxf(0.0, crack_cooldown - DT)
	crack_flash = maxf(0.0, crack_flash - DT * 3.0)
	if tip_speed > crack_speed and crack_cooldown <= 0.0:
		crack_cooldown = 0.3
		crack_flash = 1.0
	for k in a_pos.size():
		# The half-turn count is simulation-visible state (it is in the
		# snapshot), so it is kept here. Every voice that STEPS on it reads the
		# transition from its own copy in _av_tick, which is why nothing about
		# sound is left in the tick's own arithmetic.
		a_half[k] = int(absf(a_theta[k]) / PI)
	# safety net: below the world (floor tunneling, or running off the end
	# of the map). Move body AND chain rigidly at rest and drop every wrap -
	# teleporting the body alone would leave the whip metres away and the arm
	# tether would fire it across the level.
	# CHECKPOINTS: standing within CP_R of one moves spawn there, so the
	# fall below is to the last one reached, not the level's start. Only the
	# body's own feet count: a swing through one changes nothing.
	if grounded and cp_pos.size() > 0:
		for c in cp_pos:
			if c != spawn and c.distance_to(body_pos) < CP_R:
				spawn = c
	if body_pos.y > world_bottom:
		falls += 1
		teleport(spawn)
		clear_anchors()
	if body_pos.x > goal_x:
		finished = true

# -------------------------------------------------------------------- draw --
func _draw() -> void:
	# ================================================== THE WORLD (greybox) ==
	# What the level IS: the backdrop, the terrain band, the fillets, and -
	# inside the anchor loop below, for draw order - each anchor's disc. All
	# of it painted only while greybox is true. A scene whose Art node carries
	# the rock (greybox = false on its root, whip_level.gd) carries this
	# itself, live, behind this node (_art_build), and grey lines painted over
	# an artist's cliff are noise. The disc is the one WORLD item that lives
	# in the INSTRUMENTATION loop rather than here: a pulse ring of anchor k
	# is drawn before the disc of anchor k + 1, and that order is in every
	# frame ever photographed, so it is kept to the byte rather than tidied
	# (art_gate A4: the md5 of the steps frame, before this split and after).
	if greybox:
		# the backdrop first, so everything that matters is drawn over it
		for j in bd_poly.size():
			var poly: PackedVector2Array = bd_poly[j]
			var px := PackedVector2Array()
			px.resize(poly.size())
			for q in poly.size():
				px[q] = poly[q] * PPM
			draw_colored_polygon(px, bd_col[j])
		# terrain. THE BAND IS PAINTED INTO THE ROCK, so the line the rope rests
		# on is the band's TOP EDGE and not its middle. Centred, half of a 6 px
		# band (0.05 m) sat above the collision line - and a rope at rest sits
		# at y = -p_rad, which tapers 0.05 m at the handle to 0.02 m at the tip
		# while its own drawn width tapers 6 px to 2. So a resting rope was
		# painted 50% inside the floor at the handle, 70% by mid-chain, and 100%
		# from about segment 16 to the tip: the thin end of the whip was
		# invisible against the rock it was lying on. The player reported it
		# exactly - a tail skidding at 25 m/s read as "momentum running up it
		# parallel THROUGH the floor" - and it was true of the paint and not of
		# the sim, which never once put a particle below a surface (measured
		# over the whole corpus: 0 of 2720 substeps per run). Half the stroke
		# along -n; a fillet is convex rock, so its band moves inward by
		# shrinking the same amount.
		var half := 3.0 / PPM
		for s in t_a.size():
			var o := -t_n[s] * half
			draw_line((t_a[s] + o) * PPM, (t_b[s] + o) * PPM,
				Color(0.32, 0.35, 0.42), 6.0)
		# and the fillets, as terrain: the same colour and weight, only the
		# exposed arc, so a rounded lip reads as one continuous edge of rock
		for j in t_arc_c.size():
			draw_arc(t_arc_c[j] * PPM, (t_arc_r[j] - half) * PPM, t_arc_ang[j].x,
				t_arc_ang[j].y, 12, Color(0.32, 0.35, 0.42), 6.0)

	# ============================================ THE INSTRUMENTATION (always) ==
	# What the game is DOING, drawn whatever the level looks like: the flag,
	# the jam collar and the caption (what an anchor IS - authored, and the
	# author clears the caption if the art says it), the wrap ring and its
	# pulses, the rope and the load along it, the ground contacts, the tip,
	# the crack, the body, the hand, the crosshair. An anchor's ring draws at
	# the anchor whether or not its grey disc does: the ring is the game's
	# honest instrument, this project has fixed it for lying twice, and art
	# does not get to hide it. Measured: on steps_art the green ring is drawn
	# over the beam sprite's plate (art_gate A5 samples the ring pixel).
	# goal flag. Skipped where there is no goal: the lab parks goal_x past its
	# own right wall, and a flag no one can reach is a promise the level is not
	# making.
	if goal_x < 900.0:
		var gp := Vector2(goal_x + 1.5, goal_y) * PPM
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
		if greybox:
			# THE DISC is world, not instrument (the WORLD block says why it is
			# drawn from here); with art on the beam it is the artist's
			draw_circle(c, r, Color(0.55, 0.48, 0.38))
			draw_circle(c, r * 0.55, Color(0.4, 0.35, 0.28))
		# A JAM ANCHOR IS A DIFFERENT MARK AT THE SAME ANCHOR, never a different
		# truth value: the ring above still goes green on _holds() and nothing
		# else, because the moment a jam's arc means something a wrap's arc does
		# not, the one instrument the player trusts has two dialects. So the
		# class is drawn OUTSIDE the instrumentation radius - a pale collar at
		# r + 3 px, under the arc's r + 8 - and it says what this thing IS, not
		# how it is going.
		if k < a_jam.size() and a_jam[k] == 1:
			draw_arc(c, r + 3.0, 0.0, TAU, 20, Color(0.62, 0.72, 0.55, 0.85), 2.0)
		# THE NAME, under the anchor. Present on the lab bench and empty on the
		# traverse, which is not a compromise: a lab exists to name things and a
		# route does not, and captions on the traverse would also change what a
		# shipped frame looks like in every camera test that photographs one.
		if k < a_name.size() and a_name[k] != "":
			var fnt := ThemeDB.fallback_font
			# r + 32 px, not r + 20: the wrap arc lives at r + 8 and its slip
			# ring at r + 13, and at 20 the caption was drawn straight through
			# the green - seen in the first frame of station 3. The instrument
			# wins the space it needs; the label goes under it.
			draw_string(fnt, c + Vector2(-70.0, r + 32.0), a_name[k],
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, 15,
				Color(0.72, 0.76, 0.84, 0.9))
		var th := absf(a_theta[k])
		if th > 0.3:
			# Three states, three readings - the amber ring used to mean all of
			# "merely touching", "caught but will betray" and "pending" at once,
			# so a wrap that was about to hold looked exactly like one that never
			# would.
			var engaged := a_freelen[k] >= 0.0
			var locked := _holds(k)
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
		# THE VISUAL TWIN OF EVERY ONE-SHOT AT THIS BEAM. A ring that leaves
		# the beam as it fades, in the colour of what just happened: white for
		# a catch, green for a verdict that holds, amber for one that does not,
		# red per segment paid and for the tail running out, pale for letting
		# go. Same tick, same event, same information as the sound - which is
		# the parity rule, and the reason none of these is audio-only.
		if av_on and av_burst[k] > 0.0:
			var bf := av_burst[k]
			var bc: Color = av_bcol[k]
			bc.a = bf * bf * 0.95
			draw_arc(c, r + 6.0 + (1.0 - bf) * 30.0 * av_brad[k], 0.0, TAU, 28,
				bc, 1.0 + 2.5 * bf)

	# chain: width tapers with mass, color shows grip state (instrumentation)
	var slack_col := Color(0.78, 0.72, 0.6)
	var taut_col := Color(0.95, 0.45, 0.25)
	var col_now := taut_col if taut else slack_col
	# T: the load the drawing shows, eased per frame so a one-tick spike reads
	# as a jolt rather than a flicker. 0 at no load, 1 at the arm's cap
	# (320 N), up to 2 on a hard catch.
	var lidx := -1
	var want := 0.0
	if load_view:
		for k in a_pos.size():
			if a_freelen[k] >= 0.0:
				lidx = a_pinidx[k] if a_pinidx[k] >= 0 else a_lockidx[k]
				want = clampf(av_tension / LOAD_HI, 0.0, 2.0)
				break
	vis_load = lerpf(vis_load, want, 0.35 if want > vis_load else 0.12)
	var vl := clampf(vis_load, 0.0, 1.0)
	var strain_col := Color(1.0, 0.94, 0.82)
	var shiver := 1.8 * clampf((vis_load - 0.5) / 0.5, 0.0, 1.0)
	# THE BELLY, DRAWN OUT. The tether is the chord at the catch, so the rope
	# you threw past it stays in the loaded span as a wavy belly forever - the
	# catch-at-chord contract, kept because the honest tether killed the pump.
	# A loaded rope that wanders reads as an unloaded one, so under load the
	# drawing pulls that span toward the chord, more as the load rises. The
	# particles are where they are; only the picture straightens.
	var dp := PackedVector2Array()
	if load_view and lidx > 0:
		var lp := ctl_load_point()
		var straighten := 0.9 * smoothstep(0.08, 0.45, vis_load)
		var span := maxf(cum_len[mini(lidx, NP - 1)], 0.001)
		for i in mini(lidx, NP - 1) + 1:
			var chord: Vector2 = pos[0].lerp(lp, cum_len[i] / span) if not is_nan(lp.x) else pos[i]
			dp.append(pos[i].lerp(chord, straighten) * PPM)
	for i in NSEG:
		var w := lerpf(6.0, 2.0, float(i) / float(NSEG - 1))
		if load_view and lidx > 0 and i < lidx and i + 1 < dp.size():
			# the loaded rope: straighter, thinner, paler, shivering when heavy
			var a := dp[i]
			var b := dp[i + 1]
			var nrm := (b - a).orthogonal().normalized()
			var jig := nrm * shiver * sin(float(tick_count) * 1.9 + float(i) * 1.3)
			draw_line(a + jig, b - jig, col_now.lerp(strain_col, vl),
				w * lerpf(1.0, 0.55, vl))
		else:
			draw_line(pos[i] * PPM, pos[i + 1] * PPM, col_now, w)
	if av_on and not load_view:
		# TENSION, drawn along the rope that is carrying it - the twin of the
		# load hum, from the same newtons on the same tick. It runs from your
		# hand to the wrap because that is the stretch under load; the tail
		# past the wrap carries none of it and is not lit.
		if av_tension > 0.0 and av_lidx > 0:
			var lf := clampf((av_tension - LOAD_LO) / (LOAD_HI - LOAD_LO),
				0.0, 1.0)
			var lc := Color(1.0, 0.86, 0.45, 0.22 + 0.55 * lf)
			for i in mini(av_lidx, NSEG):
				draw_line(pos[i] * PPM, pos[i + 1] * PPM, lc, 1.0 + 3.0 * lf)
		# THE GROUND, on the particles that are actually touching it - the twin
		# of the grit voice, and the same contacts that fed it.
		if av_scrape > GRIT_LO:
			var gf := clampf((av_scrape - GRIT_LO) / (GRIT_HI - GRIT_LO),
				0.0, 1.0)
			var gc := Color(0.95, 0.90, 0.78, 0.12 + 0.45 * gf)
			for i in NP:
				if av_touch[i] != 0:
					draw_circle(pos[i] * PPM, 1.5 + 2.5 * gf, gc)
		# TIP SPEED. The whole reason the air voice exists is that the tip
		# outruns the eye; this is the same number made visible, so the reading
		# is available without hearing it. It is present state - where the tip
		# is and how fast it is going THIS tick, never where it is headed.
		var af := clampf((tip_speed - AIR_LO) / (AIR_HI - AIR_LO), 0.0, 1.0)
		if af > 0.0:
			draw_circle(pos[NP - 1] * PPM, 2.5 + 9.0 * af,
				Color(0.88, 0.92, 1.0, 0.08 + 0.30 * af))
	# crack flash at the tip (past event, fades). Sized by HOW FAR past
	# CRACK_SPEED the tip went, which is the same overshoot the bang is
	# pitched and levelled by - so the flash is loud when the crack is.
	if crack_flash > 0.0:
		draw_circle(pos[NP - 1] * PPM, (8.0 + 13.0 * av_over) * crack_flash,
			Color(1.0, 0.95, 0.7, crack_flash * 0.8))

	# body: a stoic capsule with a face (dignity is the comedy)
	var bp := body_pos * PPM
	if load_view and vis_load > 0.01:
		# T: the body stretches along the line of the load, area kept
		var u := pos[0] - body_pos
		var st := 1.0 + 0.12 * vis_load
		draw_set_transform(bp, u.angle() if u.length() > 0.01 else 0.0, Vector2(st, 1.0 / st))
		draw_circle(Vector2.ZERO, BODY_R * PPM, Color(0.85, 0.82, 0.75))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
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

func _draw_zone() -> void:
	# SCREEN SPACE, on the HUD layer - so this ring is the mouse's own ruler and
	# not the world's, and it does not move, scale or drift with the camera. Its
	# radius is REACH converted through the SAME m_per_px the control uses, so
	# it is always exactly 138 physical pixels across: the whole control
	# surface, drawn at 1:1 with the desk.
	if zone == null or not mouse_owned:
		return
	var mpp := cursor_m_per_px()
	var a := cursor_anchor_px()
	var rim := REACH / mpp
	var off := get_viewport().get_mouse_position() - a
	var d := off.length()
	# NOTHING IS DRAWN WHILE THE HAND IS INSIDE THE RIM, and that is the whole
	# rule. Inside it the crosshair the game already draws IS the hand, 1:1 and
	# to scale, so a permanent ring would add no reading and would be misread as
	# an object in the world (it was, when it was always on - it sat next to the
	# body and looked like a beam). Past the rim the crosshair is pinned and has
	# stopped telling the truth about where the hand is, and once the pointer is
	# hidden nothing else recovers that. So the zone appears exactly when it
	# starts carrying information, and fades up with how far past you are.
	if d <= rim:
		return
	var f := clampf((d - rim) / rim, 0.0, 1.0)   # a whole radius past = full
	zone.draw_arc(a, rim, 0.0, TAU, 48, Color(1, 1, 1, 0.05 + 0.10 * f), 1.0)
	zone.draw_line(a + off * (rim / d), a + off,
		Color(1, 1, 1, 0.06 + 0.14 * f), 1.0)
	zone.draw_circle(a + off, 2.5, Color(1, 1, 1, 0.10 + 0.25 * f))

# ------------------------------------------------------------------- audio --
# WHY AUDIO IS NOT POLISH HERE. A real whip crack is learned by ear, because the
# tip moves faster than the eye can follow, and this game is about reading a
# rope you can only partly see. Several of its load-bearing states were, until
# this section existed, invisible or nearly so: how fast the tip is actually
# going, what the wrap you are hanging on is carrying, that a wrap is paying out
# right now, how much tail is left before it slides off you.
#
# WHAT IS ALLOWED, and it is the project's own line: the past and the present
# are instrumentation, the future is an assist. Read every voice below against
# it. The air voice says how fast the tip IS. The load voice says what the wrap
# IS carrying. The verdict says what the wrap HAS BEEN CLASSIFIED as - fired at
# the same tick the ring changes colour, from the same predicate (_holds), never
# before the classification the simulation has already made. The ratchet says a
# segment HAS just run through. Nothing here is a function of a state the sim
# has not computed yet, and nothing announces an outcome before it happens.
#
# ONE THING WAS DELIBERATELY NOT BUILT: a cue during the pending window, while
# a_locked is still -1 and the sim is watching for a self-crossing. A sound
# there would be exactly the banned thing - it would be telling you how the
# classification is going to come out before it has come out. The pending state
# is silent, and its ring stays grey, which is honest in both channels.

func _av_size() -> void:
	av_touch.resize(NP)
	var na := a_pos.size()
	av_half.resize(na)
	av_eng.resize(na)
	av_hold.resize(na)
	av_lk.resize(na)
	av_pin.resize(na)
	av_burst.resize(na)
	av_bcol.resize(na)
	av_brad.resize(na)
	av_lvl.resize(AV_N)
	av_pit.resize(AV_N)
	av_lvl_t.resize(AV_N)
	av_pit_t.resize(AV_N)
	for i in AV_N:
		av_pit[i] = 1.0
		av_pit_t[i] = 1.0
	for k in na:
		av_lk[k] = -1
		av_pin[k] = -1

func _av_reset() -> void:
	if not av_on:
		return
	av_scrape = 0.0
	av_tension = 0.0
	av_lidx = -1
	av_over = 0.0
	av_flash0 = 0.0
	av_touch.fill(0)
	for i in AV_N:
		av_lvl[i] = 0.0
		av_lvl_t[i] = 0.0
	for k in a_pos.size():
		av_half[k] = 0
		av_eng[k] = 0
		av_hold[k] = 0
		av_lk[k] = -1
		av_pin[k] = -1
		av_burst[k] = 0.0

func _av_hush() -> void:
	if not av_on:
		return
	for i in AV_N:
		av_lvl_t[i] = 0.0

func _av_stop() -> void:
	for p in [sfx_air, sfx_grit, sfx_load, sfx_rasp, sfx_crack, sfx_tick,
			sfx_catch, sfx_lock, sfx_part, sfx_ratch, sfx_off, sfx_let]:
		if p == null:
			continue
		p.stop()
		p.stream = null

func _holds(k: int) -> bool:
	# THE RING'S OWN PREDICATE, in one place, so the sound and the arc cannot
	# drift apart - a voice that disagreed with its twin would break parity
	# silently, and only for the players who cannot hear it.
	#
	# Green means the sim has classified this wrap LOCKED, and that is the whole
	# rule. A locked wrap does not pay out and does not let go: the only ways out
	# of one are to unwind it back under th_part or to open your hand. That is a
	# fact about the state as it stands - present, not predicted: a tell, not a
	# trap.
	#
	# THERE WAS A SECOND CLAUSE HERE AND IT WAS MEASURED OUT. It demanded three
	# quarters of a turn of chain PAST the pin, reasoning that a wrap made from
	# far away can pinch on its own draped tail, classify green, and tear off
	# when a swing straightens that tail out. The instinct was sound. The test
	# was not: it asks whether enough tail is LEFT to make a pinch, when _pinch
	# has already run and already said one exists. What it actually measured was
	# WHERE ALONG THE WHIP YOU CAUGHT - catch near the tip and no tail remains to
	# satisfy it, however good the wrap.
	#
	# Scored on a recorded human session plus the corpus (tests/ring_score.gd)
	# against the one oracle that needs no judgement - did the wrap survive, with
	# the hand never opening:
	#
	#     candidate                    trust 0.5s   1.5s     4s    reach
	#     locked + tail past pin           96.5%  99.1%   100%    42.5%
	#     locked                           98.0%  99.6%   100%   100.0%
	#
	# It was not a cautious guard that cost a little coverage. It was LESS
	# truthful than no clause at all - the greens it kept survived less often
	# than the greens it threw away - while hiding 57.5% of the locks that really
	# held. Over that session the player was locked on for 3654 ticks and the
	# ring was green for 2049: for 44% of the time the whip was carrying them,
	# the ring said it would betray. Two catches held for nine seconds in amber,
	# and the player reported it as the whip failing to hook.
	#
	# The draped tail it was aimed at is a real shape and is NOT answered here.
	# Nothing in the corpus reproduces one. When a case turns up it wants a test
	# of what the CROSSING IS MADE OF - tail against tail, or tail around beam -
	# and not of how much rope happens to be left over.
	return a_freelen[k] >= 0.0 and a_locked[k] == 1

func _wrap_tension() -> float:
	# THE PENDULUM ESTIMATE of what the wrap is carrying, in newtons: your
	# weight resolved along the rope plus the centripetal term of the arc you
	# are on, as if the body hung on the rope itself.
	#
	#     T = M ( v_perp^2 / L  +  g cos(rope, down) )
	#
	# IT IS NOT THE LOAD, and it no longer drives the load voice. The body in
	# this sim does not hang on the rope; it hangs on an ARM - SPRING_K capped
	# at F_MAX plus the one-sided tether at arm_max - and the rope carries
	# whatever the arm delivers, which is dominated by transients the pendulum
	# never sees: the catch yank and the fall-arrest. Measured on the player's
	# own session (takes/bug1.tape, 3999 engaged ticks) this estimate reads
	# p50 79.7 N, p95 260.3 N, max 1835 N while the arm reads p50 43.8 N,
	# p95 320.0 N, max 3163 N - lower in the hang, where the arm is slack and
	# this formula still charges the full weight, and far higher in the yank.
	# The two disagree most exactly when the load matters. The voice renders
	# av_arm (see _substep); this stays as the instrument tests/lab_throw.gd
	# reads the swing with - a pure function of the finished tick, writing
	# nothing.
	var best := 0.0
	for k in a_pos.size():
		if a_freelen[k] < 0.0:
			continue
		var ap: Vector2 = a_pinpt[k] if a_pinidx[k] >= 0 else a_pos[k]
		var rv := body_pos - ap
		var l := maxf(rv.length(), 0.05)
		var u := rv / l
		var bv := (body_pos - body_prv) / SDT
		var vp := maxf(bv.length_squared() - pow(bv.dot(u), 2.0), 0.0)
		var t := BODY_M * (vp / l + GRAV.y * u.y)
		if t > best:
			best = t
	return best

func _av_tick() -> void:
	# Everything here READS the finished tick. It writes no simulation state,
	# and it is skipped entirely unless a real window exists.
	if not av_on:
		return

	# ---- the three continuous voices: what the rope is doing right now ----
	# AIR. The tip outruns the eye at 30 m/s and reaches 86; this is the only
	# honest readout of it there has ever been.
	var a := clampf((tip_speed - AIR_LO) / (AIR_HI - AIR_LO), 0.0, 1.0)
	av_lvl_t[AV_AIR] = sqrt(a)
	av_pit_t[AV_AIR] = lerpf(AIR_PITCH.x, AIR_PITCH.y, a)

	# GROUND. Summed over the particles that _collide_point actually resolved
	# against terrain this tick, plus the body when it is on the floor - so the
	# lash gait, every drag and every landing come from real contacts rather
	# than from a guess at where the floor is.
	var sc := 0.0
	for i in NP:
		if av_touch[i] != 0:
			sc += (pos[i] - prv[i]).length() / SDT
	if grounded:
		sc += (body_pos - body_prv).length() / SDT
	av_scrape = sc
	var g := clampf((sc - GRIT_LO) / (GRIT_HI - GRIT_LO), 0.0, 1.0)
	av_lvl_t[AV_GRIT] = sqrt(g)
	av_pit_t[AV_GRIT] = lerpf(GRIT_PITCH.x, GRIT_PITCH.y, g)

	# LOAD. Silent with no wrap; while there is one it renders THE FORCE THE
	# BODY IS PUTTING THROUGH THE ARM - the spring plus the tether's impulse,
	# summed over the tick's substeps - because in this sim that is what the
	# rope carries. The body does not hang on the rope; it hangs on an arm,
	# and the wrap gets whatever the arm delivers. The voice used to render
	# _wrap_tension's pendulum estimate instead, and the two are not the
	# same number: on the player's own session the pendulum ran p50 80 N,
	# p95 260 N, while the arm - dominated by the catch yank and the
	# fall-arrest, not by the pump - reads what the range below records.
	# Honest about the yank, and still not a warning: the load has no bearing
	# on whether the wrap survives.
	av_tension = 0.0
	av_lidx = -1
	for k in a_pos.size():
		if a_freelen[k] >= 0.0:
			av_tension = av_arm
			av_lidx = a_pinidx[k] if a_pinidx[k] >= 0 else a_lockidx[k]
			break
	# The ramp is the air and grit voices' shape, square-rooted from zero:
	# the old 0.28 floor encoded "a wrap you are on is never unloaded", which
	# was true of the pendulum estimate (45.9 N at the dead point) and is not
	# true of the arm - a wrap engaged with the feet on the floor carries
	# 0.2 N, and a hum that said otherwise would be the twin of nothing.
	var ld := clampf((av_tension - LOAD_LO) / (LOAD_HI - LOAD_LO), 0.0, 1.0)
	av_lvl_t[AV_LOAD] = sqrt(ld)
	av_pit_t[AV_LOAD] = lerpf(LOAD_PITCH.x, LOAD_PITCH.y, ld)

	# SLIP. The sim's own flag, which is already binary: it either is paying
	# out or it is not.
	av_lvl_t[AV_RASP] = 1.0 if slipping else 0.0

	# ---- the crack, and HOW HARD it was ----
	# The bang used to be one flat sample at any speed past the threshold. The
	# tip reaches 3.6x the threshold, so a flat bang threw away the whole top
	# of the range - and that range IS the skill bell.
	if crack_flash >= 1.0 and av_flash0 < 1.0:
		av_over = sqrt(clampf((tip_speed / crack_speed - 1.0)
			/ (CRACK_OVER - 1.0), 0.0, 1.0))
		if sfx_crack != null:
			sfx_crack.volume_db = lerpf(CRACK_DB.x, CRACK_DB.y, av_over)
			sfx_crack.pitch_scale = lerpf(CRACK_PITCH.x, CRACK_PITCH.y, av_over)
			sfx_crack.play()
	av_flash0 = crack_flash

	# ---- per beam: winding, and the four things that can happen to a wrap ----
	for k in a_pos.size():
		av_burst[k] = maxf(0.0, av_burst[k] - DT * 3.0)
		var eng := 1 if a_freelen[k] >= 0.0 else 0
		var hold := 1 if _holds(k) else 0
		# WINDING, half turn by half turn: how much rope is on this beam. Its
		# twin is the row of dots on the arc, which is drawn from the same
		# count.
		var half := int(absf(a_theta[k]) / PI)
		if half > av_half[k] and half >= 1 and sfx_tick != null:
			sfx_tick.pitch_scale = 1.0 + 0.18 * float(half)
			sfx_tick.play()
		av_half[k] = half

		if eng == 1 and av_eng[k] == 0:
			# THE CATCH. Neutral on purpose: at this instant the simulation has
			# not classified the wrap either (a_locked is -1), so a catch that
			# sounded confident would be inventing information.
			_av_flash(k, Color(1.0, 0.97, 0.90), 1.0)
			if sfx_catch != null:
				sfx_catch.pitch_scale = lerpf(1.40, 0.85,
					clampf((a_r[k] - 0.09) / 0.14, 0.0, 1.0))
				sfx_catch.play()
		elif eng == 0 and av_eng[k] == 1:
			# HOW THE WRAP ENDED, told apart exactly the way _update_locks and
			# the tape census tell them apart: an open hand is a dismount, a
			# re-armed anchor unwound on its own, anything else ran out of tail.
			if not taut:
				_av_flash(k, Color(0.86, 0.88, 0.96), 0.8)
				if sfx_let != null:
					sfx_let.pitch_scale = 1.0
					sfx_let.volume_db = -13.0
					sfx_let.play()
			elif a_armed[k] == 1:
				_av_flash(k, Color(0.75, 0.95, 1.0), 0.9)
				if sfx_let != null:
					sfx_let.pitch_scale = 0.70
					sfx_let.volume_db = -10.0
					sfx_let.play()
			else:
				# it slid off its own end. This is the loss, and it stings.
				_av_flash(k, Color(1.0, 0.32, 0.18), 1.5)
				if sfx_off != null:
					sfx_off.play()
		elif eng == 1:
			# THE VERDICT. It fires at the tick the simulation's own
			# classification RESOLVES - a_locked leaving -1 - and again if that
			# reading later changes. It reports a decision the sim has ALREADY
			# made from settled geometry six or more ticks earlier; it does not
			# anticipate one, which is exactly why nothing at all is said while
			# a_locked is still -1 and the pinch window is still open.
			#
			# THE ABSENCE OF A SOUND IS NOT A READING. Firing only on 'it holds'
			# would leave every other verdict announced by silence, and silence
			# is not something a player can time. (When this was written the
			# ring's tail clause turned 2 of the corpus's 3 locks amber, so two
			# thirds of its verdicts would have been delivered by nothing
			# happening. That clause is gone - see _holds - and tests/aud_gate.gd
			# now reads catch 3, hold 3 over the corpus; the amber verdict that
			# remains in it is betray.tape's, a lock that unwound under th_part,
			# went amber, paid out twice and slid off.) Both outcomes get a
			# voice, and both get a pulse.
			#
			# WHICH one plays is decided by _holds, the ARC's own predicate, so
			# the pulse, the ring and the sound cannot end up saying three
			# different things. Since 1aa17d8 that predicate is exactly
			# a_locked == 1, so a green that goes amber is now only the
			# demotion in _update_locks - and it sounds amber the tick the
			# ring does.
			var res := a_locked[k] != -1 and av_lk[k] == -1
			if res or hold != av_hold[k]:
				if hold == 1:
					_av_flash(k, Color(0.30, 0.95, 0.50), 1.1)
					if sfx_lock != null:
						sfx_lock.play()
				else:
					# a green that GOES amber is worse news than one that was
					# amber from the start, so it is the same tone pitched down
					# rather than a second sound to learn.
					_av_flash(k, Color(0.95, 0.75, 0.20), 1.0)
					if sfx_part != null:
						sfx_part.pitch_scale = 0.76 if av_hold[k] == 1 else 1.0
						sfx_part.play()
			if av_pin[k] >= 0 and a_pinidx[k] > av_pin[k]:
				# ONE SEGMENT HAS JUST RUN THROUGH THE WRAP. The betrayal was
				# audible only as an undifferentiated rasp; now it is countable,
				# and it rises as the tail shortens, because the tail left IS
				# present state (measured 0.29 m and 0.14 m at the two payouts
				# in the corpus - the second click of a slide is already high).
				var tail: float = cum_len[NP - 1] - cum_len[a_pinidx[k]]
				var f := clampf(1.0 - tail / 1.2, 0.0, 1.0)
				_av_flash(k, Color(1.0, 0.45, 0.25), 0.7)
				if sfx_ratch != null:
					sfx_ratch.pitch_scale = lerpf(0.90, 2.10, f)
					sfx_ratch.play()
		av_eng[k] = eng
		av_hold[k] = hold
		av_lk[k] = a_locked[k] if eng == 1 else -1
		av_pin[k] = a_pinidx[k] if eng == 1 else -1

func _av_flash(k: int, c: Color, rad: float) -> void:
	av_burst[k] = 1.0
	av_bcol[k] = c
	av_brad[k] = rad

func _av_frame(dt: float) -> void:
	# Per-frame glide toward this tick's targets. Attack is fast and release is
	# slow, which is what a whoosh does: the rope arrives before it leaves.
	for i in AV_N:
		var tau_l := 0.020 if av_lvl_t[i] > av_lvl[i] else 0.085
		av_lvl[i] = _av_glide(av_lvl[i], av_lvl_t[i], dt, tau_l)
		av_pit[i] = _av_glide(av_pit[i], av_pit_t[i], dt, 0.030)
	_av_voice(sfx_air, av_lvl[AV_AIR], av_pit[AV_AIR], AIR_DB)
	_av_voice(sfx_grit, av_lvl[AV_GRIT], av_pit[AV_GRIT], GRIT_DB)
	_av_voice(sfx_load, av_lvl[AV_LOAD], av_pit[AV_LOAD], LOAD_DB)
	_av_voice(sfx_rasp, av_lvl[AV_RASP], av_pit[AV_RASP], RASP_DB)

static func _av_glide(v: float, t: float, dt: float, tau: float) -> float:
	return t + (v - t) * exp(-dt / maxf(tau, 0.001))

func _av_voice(p: AudioStreamPlayer, lvl: float, pit: float,
		db: Vector2) -> void:
	if p == null:
		return
	p.pitch_scale = clampf(pit, 0.05, 4.0)
	# A LOOP RUNS ONLY WHILE IT HAS SOMETHING TO SAY. Riding the volume on
	# four permanently-running loops is the obvious way to avoid the click
	# that start/stop puts on a noise loop - but that click only exists at an
	# AUDIBLE level. The ramp is exponential toward zero and this gate is at
	# 0.002, which is below the bottom of every ramp declared above (-42 dB
	# at the quietest), so a voice is stopped and started in silence and
	# there is nothing to click. Riding the volume also had a second cost
	# that measurement found and reasoning did not: a looping playback still
	# running at teardown stays held by the audio server, and the game was
	# exiting with three of them running every single time.
	if lvl <= 0.002:
		p.volume_db = -80.0
		if p.playing:
			p.stop()
		return
	# The bottom of a ramp is not silence - the quietest declared level is
	# -42 dB, and starting a noise loop AT -42 dB is exactly the click the
	# ramp exists to avoid. So the last twentieth of the ramp fades the
	# whole voice out to -80 dB, and the start/stop above therefore happens
	# at -78 dB rather than at -42.
	var db_now := lerpf(db.x, db.y, clampf(lvl, 0.0, 1.0))
	if lvl < 0.05:
		db_now = lerpf(-80.0, db_now, lvl / 0.05)
	p.volume_db = db_now
	if not p.playing:
		p.play()

func _player(st: AudioStream, db: float, poly: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	p.max_polyphony = maxi(poly, 1)
	add_child(p)
	return p

func _wav_of(data: PackedByteArray, rate: int, n: int,
		looped: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w

func _make_loop_noise(dur: float, seed_v: int, lp: float) -> AudioStreamWAV:
	# A LOOP THAT DOES NOT TICK. Filtered noise has a step at the seam, and a
	# 0.5 s loop repeats that step twice a second - which the ear hears as a
	# pitch sitting on top of the whoosh, not as noise. So generate past the
	# loop point and cross-fade the tail back over the head: the buffer then
	# joins itself, and the voice is air rather than air plus a 2 Hz tick.
	var rate := 22050
	var n := int(dur * rate)
	var xf := int(0.012 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v          # audio generation only - the SIM has no RNG
	var s := PackedFloat32Array()
	s.resize(n + xf)
	var y := 0.0
	for i in n + xf:
		y += lp * (rng.randf_range(-1.0, 1.0) - y)
		s[i] = y
	for i in xf:
		var f := float(i) / float(xf)
		s[i] = s[i] * f + s[n + i] * (1.0 - f)
	var pk := 0.0001
	for i in n:
		pk = maxf(pk, absf(s[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(s[i] / pk, -1.0, 1.0) * 30000.0))
	return _wav_of(data, rate, n, true)

func _make_loop_tone(hz: float, dur: float, harm: Array) -> AudioStreamWAV:
	# An EXACT integer number of cycles, so the loop point continues the
	# waveform instead of clicking - the tonal half of the same problem, and
	# free: pick the period in whole samples and make the buffer a multiple.
	var rate := 22050
	var per := maxi(int(round(float(rate) / hz)), 2)
	var cyc := maxi(int(round(dur * float(rate) / float(per))), 1)
	var n := per * cyc
	var s := PackedFloat32Array()
	s.resize(n)
	var pk := 0.0001
	for i in n:
		var ph := TAU * float(i) / float(per)
		var v := 0.0
		for h in harm.size():
			v += float(harm[h]) * sin(ph * float(h + 1))
		s[i] = v
		pk = maxf(pk, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(s[i] / pk * 28000.0))
	return _wav_of(data, rate, n, true)

func _make_thock(dur: float, hz: float, decay: float, seed_v: int,
		noise: float) -> AudioStreamWAV:
	# A struck body: a short noise transient (the impact) over a decaying tone
	# (the thing that was struck). Wood on wood, not a beep - the catch is rope
	# arriving on a beam and it should sound like a physical event.
	var rate := 22050
	var n := int(dur * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t / decay)
		y += 0.30 * (rng.randf_range(-1.0, 1.0) - y)
		var v := sin(TAU * hz * t) * (1.0 - noise) \
			+ y * 3.0 * noise * exp(-t / (decay * 0.22))
		data.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 29000.0))
	return _wav_of(data, rate, n, false)

func _make_chord(dur: float, hz: float, decay: float,
		gap: float) -> AudioStreamWAV:
	# THE VERDICT THAT HOLDS: two notes, the second a fifth BELOW the first and
	# a beat later. A falling interval reads as settled, which is exactly what
	# the ring says at the same instant, in green. Its partner (the wrap that
	# does not hold) is a single unresolved tone - one note, going nowhere.
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := sin(TAU * hz * t) * exp(-t / decay)
		v += 0.40 * sin(TAU * hz * 3.0 * t) * exp(-t / (decay * 0.30))
		if t > gap:
			var t2 := t - gap
			v += 1.05 * sin(TAU * hz * 0.6667 * t2) * exp(-t2 / (decay * 1.6))
		data.encode_s16(i * 2, int(clampf(v * 0.55, -1.0, 1.0) * 29000.0))
	return _wav_of(data, rate, n, false)

func _make_sweep(dur: float, hz0: float, hz1: float, decay: float,
		seed_v: int, tone: float) -> AudioStreamWAV:
	# A glide, for the two ways a wrap ENDS. Down = it was taken off you (the
	# tail ran out). Up = you took it off. Phase is INTEGRATED rather than
	# evaluated at sin(TAU*hz(t)*t), which would fold the sweep back on itself
	# and produce a warble instead of a glide.
	var rate := 22050
	var n := int(dur * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var y := 0.0
	for i in n:
		var f := float(i) / float(n)
		var t := float(i) / float(rate)
		var hz: float = hz0 * pow(hz1 / hz0, f)
		ph += TAU * hz / float(rate)
		y += 0.25 * (rng.randf_range(-1.0, 1.0) - y)
		var v := sin(ph) * tone + y * 3.5 * (1.0 - tone)
		data.encode_s16(i * 2,
			int(clampf(v * exp(-t / decay), -1.0, 1.0) * 28000.0))
	return _wav_of(data, rate, n, false)

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
const SAVE_PATH_LAB := "user://run_lab.save"
const SAVE_PATH_CRAG := "user://run_crag.save"
const AUTOSAVE_TICKS := 30            # half a second: the most a crash can cost

# WHAT IS THE SIMULATION is answered by the object, not by a list kept by hand.
# Every script variable is state unless it is named here or is a node. A
# hand-kept list goes stale in silence, which is not hypothetical: the planner
# in tests/bot_leap.gd used to copy state through its own STATE_KEYS, which
# still named a_lastth and a_shed after both were deleted with the coil modes
# and had never heard of a_clear, which drives the re-arm - so every planning
# candidate it restored carried one field from another timeline and nothing
# anywhere said so. It now calls snapshot() and restore(). Declare a var and it
# is in the snapshot.
const SNAP_SKIP := ["external_drive", "save_enabled", "save_path", "save_due",
	# WHICH LEVEL IS LOADED IS NOT SIMULATION STATE, it is what the simulation
	# was built FROM. _build_level has already run by the time restore() is
	# reached, so these are correct for the level in front of you; restoring a
	# lab's a_jam into a traverse would be the partial-restore defect this
	# whole key-set rule exists to refuse. It also keeps the key SET identical
	# to the one every committed tape's start state was written with - three
	# new vars outside SNAP_SKIP would refuse all six tapes and the player's
	# save on the next boot, which is a steep price for a caption.
	# LAB FURNITURE, not simulation. jam_min_th sits here with them for the same
	# reason: snapshot() derives its key set from get_property_list(), so a new var
	# moves the layout and restore() refuses every tape and save on disk. A tuning
	# constant that never changes inside a run is not worth re-recording the corpus
	# for - and re-recording is not free, it is the deliberate loss of the only
	# regression test this project has against the behaviour it has today.
	"level_id", "a_jam", "a_name", "goal_y", "jam_min_th",
	# CRAG FURNITURE, by the same rule: the terrain arcs are level geometry
	# rebuilt by _build_level on every boot (as t_a/t_b would be, were they
	# not older than the snapshot), the backdrop is paint, and the camera's
	# volume table is authored per level and read by nothing in the sim.
	"t_arc_c", "t_arc_r", "t_arc_ang", "t_deep", "bd_poly", "bd_col",
	"cam_vols",
	# SCENE-LEVEL FURNITURE: why a scene was refused, and its caption block.
	"level_err", "level_hud", "spawn0",
	# THE ART LAYER: a picture, and whether _draw paints the grey world under
	# it. Neither is read by a tick (art_gate A2 runs the hash with the layer
	# forced on), and the instance itself is an Object, which snap_keys skips.
	"art_on", "greybox",
	# and the per-tick candidate lists, rebuilt at the top of every tick from
	# the particles' positions - derived, never carried
	"cand_seg", "cand_arc",
	# THE CAMERA IS NOT THE SIMULATION either, and by the same argument as the
	# audio below it: cam_st is a pure function of a finished tick's body
	# position and velocity, it feeds nothing back, and a save that carried it
	# would be a save whose key set no longer matched the tapes on disk.
	"cam_st", "mouse_owned",
	"rec_on", "rec_path", "rec_cur", "rec_grip", "rec_chk", "rec_start",
	"rec_note", "rec_cen", "rec_prev", "rec_rst", "rec_mark", "rec_mkind",
	"rec_mk",
	"play_on", "play_done", "play_tape", "play_at",
	"cp_pos",
	"ctl", "align_w", "ctl_prev", "ctl_catch_t", "ctl_hold_off",
	"ctl_pull_armed", "ctl_pulling",
	"crack_speed", "ppm_input", "stick_on", "stick_c", "stick_fmax",
	"mirror_on", "mirror_k", "hammer_on", "hammer_gain", "hammer_vmax", "hammer_tau",
	"hammer_fmax", "hammer_mu", "hammer_press",
	"arm_damp", "arm_cap", "hang_damp", "hang_cap", "hang_k",
	"firm_on", "load_view", "vis_load", "rec_opt",
	"stretch_on", "stretch_k", "stretch_lidx",
	"pending_jump", "jump_v", "jump_fwd", "rec_jumped", "hud_full",
	# AUDIO AND ITS VISUAL TWINS ARE NOT THE SIMULATION. Every one of these is
	# derived from a finished tick and feeds nothing back, so none of them
	# belongs in a save - and leaving them out is not merely tidy, it is what
	# keeps the key set identical. restore() refuses a state whose key set has
	# changed, by design, so a var added here without this line would refuse
	# every committed tape and every save on disk, and it would be right to:
	# it could not tell an audio field from a physics field.
	"av_on", "av_touch", "av_scrape", "av_tension", "av_arm", "av_armc",
	"av_lidx", "av_over",
	"av_flash0", "av_half", "av_eng", "av_hold", "av_lk", "av_pin", "av_burst",
	"av_bcol", "av_brad", "av_lvl", "av_pit", "av_lvl_t", "av_pit_t"]

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
	h = _fnv(h, spawn0.x); h = _fnv(h, spawn0.y)
	h = _fnv(h, goal_x); h = _fnv(h, world_bottom)
	if cp_pos.size() > 0:
		h = _fnv(h, float(cp_pos.size()))
		for c in cp_pos:
			h = _fnv(h, c.x); h = _fnv(h, c.y)
	# The arcs are folded in ONLY when there are any. Folding in an empty
	# count would still be one more _fnv on the shipped level, and its number
	# is 8896234646103814336 in six tapes and the player's save.
	if t_arc_c.size() > 0:
		h = _fnv(h, float(t_arc_c.size()))
		for j in t_arc_c.size():
			h = _fnv(h, t_arc_c[j].x); h = _fnv(h, t_arc_c[j].y)
			h = _fnv(h, t_arc_r[j])
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
# THE BUG MARKER, and the reason it exists. A tape is worth exactly as much as
# your ability to find the moment inside it, and the moment belongs to the
# player: "it lit green and it still unhooked" is a report about one tick, not
# about a session. F stamps the tick the player was looking at when they said
# so; the tape carries the stamps beside the input rather than inside it, and
# tests/mark_look.gd replays the tape and dumps the full lock state either side
# of every stamp.
#
# NEITHER OF THESE IS SIMULATION STATE, which is not a claim but the reason
# they are in SNAP_SKIP two hundred lines up: rec_mk is an edge latched by
# _input and consumed by _rec_tick AFTER the tick has already been computed,
# and rec_mark is an index list that nothing in the sim ever reads. A marked
# tape and an unmarked one feed step_tick the same bytes in the same order.
const MARK_GREEN := 1                 # F: the ring was green and it let go
const MARK_NOHOOK := 2                # G: that should have caught and did not
const MARK_NAME := ["", "GREEN DROPPED ME", "SHOULD HAVE HOOKED"]
var rec_mark := PackedInt32Array()    # tape indices the player marked
var rec_mkind := PackedInt32Array()   # MARK_* per entry of rec_mark
var rec_mk := 0                       # kind latched since the last recorded tick
var play_on := false
var play_done := false
var play_tape := {}
var play_at := 0

func rec_begin(note := "") -> void:
	rec_start = snapshot()
	rec_note = note
	rec_cur = PackedVector2Array()
	rec_grip = PackedByteArray()
	rec_opt = PackedByteArray()
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
	rec_mark = PackedInt32Array()
	rec_mkind = PackedInt32Array()
	rec_mk = 0
	rec_on = true

func rec_end() -> void:
	rec_on = false

func _rec_tick() -> void:
	rec_cur.append(cursor_m)
	rec_opt.append((1 if firm_on else 0) | (2 if stretch_on else 0) | (4 if rec_jumped else 0))
	rec_grip.append((1 if taut else 0) | (2 if rec_rst else 0)
		| (4 if ctl_lean() else 0) | (int(ctl) << 3)
		| (32 if crack_speed != CRACK_SPEED else 0) | (64 if stick_on else 0)
		| (128 if hammer_on else 0))
	# Stamped against the tick that has JUST FINISHED - the same tick the ring
	# the player is complaining about was drawn from - and stored beside the
	# stream, never in it, so the mark cannot change what the sim was fed.
	if rec_mk != 0:
		rec_mark.append(rec_cur.size() - 1)
		rec_mkind.append(rec_mk)
		rec_mk = 0
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
		"cur": rec_cur.duplicate(), "grip": rec_grip.duplicate(),
		"mark": rec_mark.duplicate(), "mkind": rec_mkind.duplicate(),
		"opt": rec_opt.duplicate(),
		"ok": true, "err": ""}

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
	# APPENDED, AND LAST, ON PURPOSE. Everything above is byte-for-byte the v1
	# layout, so the six tapes already on disk still load and still verify - a
	# reader that runs out of file simply has no marks. Bumping TAPE_VERSION
	# would have refused every one of them, which is a steep price for a field
	# the simulation never reads.
	f.store_var(t["mark"])
	f.store_var(t["mkind"])
	# The per-tick OPTIONS byte, appended last for the same reason as the
	# marks: bit 0 = firm hang. A tape without it is a tape with every option
	# off, which is exactly what it was recorded with.
	f.store_var(t["opt"])
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
	# A tape written before the marker existed ends here, and that is not an
	# error: no marks is a fact about the tape, not a fault in it.
	t["mark"] = PackedInt32Array()
	t["mkind"] = PackedInt32Array()
	if f.get_position() < f.get_length():
		var mk: Variant = f.get_var()
		if typeof(mk) == TYPE_PACKED_INT32_ARRAY:
			t["mark"] = mk
	# The KIND of each mark is a second appended field, read the same way and
	# for the same reason: a tape written by the one-key build has marks but no
	# kinds, and that is a fact about the tape rather than a fault in it. A
	# missing kind reads as 0, which MARK_NAME renders as the empty string.
	if f.get_position() < f.get_length():
		var mi: Variant = f.get_var()
		if typeof(mi) == TYPE_PACKED_INT32_ARRAY:
			t["mkind"] = mi
	# Assigned back through a local ON PURPOSE: a PackedInt32Array is a value
	# type here, so appending to t["mkind"] in place would grow a temporary
	# and leave the dictionary untouched - a loop with no exit.
	var mkinds: PackedInt32Array = t["mkind"]
	var nmark := (t["mark"] as PackedInt32Array).size()
	while mkinds.size() < nmark:
		mkinds.append(0)
	t["mkind"] = mkinds
	var opt := PackedByteArray()
	if f.get_position() < f.get_length():
		var ov: Variant = f.get_var()
		if typeof(ov) == TYPE_PACKED_BYTE_ARRAY:
			opt = ov
	t["opt"] = opt
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
	align_w = ALIGN_W_FLIP if (grp[play_at] & 4) != 0 else ALIGN_W
	crack_speed = CRACK_SPEED_HI if (grp[play_at] & 32) != 0 else CRACK_SPEED
	stick_on = (grp[play_at] & 64) != 0
	hammer_on = (grp[play_at] & 128) != 0
	var opt: PackedByteArray = play_tape.get("opt", PackedByteArray())
	firm_set(play_at < opt.size() and (opt[play_at] & 1) != 0)
	stretch_set(play_at < opt.size() and (opt[play_at] & 2) != 0)
	pending_jump = play_at < opt.size() and (opt[play_at] & 4) != 0
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
		elif a == "--level" or a == "--controls":
			# already consumed (_cmdline_level before the level was built,
			# ctl_boot below); swallow the argument so it is not read as a flag
			i += 1
		i += 1
	ctl_boot()
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

static func _cmdline_level() -> String:
	# godot --path . -- --level lab | crag | <scene>. Static, and read straight
	# from the command line, because _build_level needs it and _build_level
	# runs before _boot_session does. No flag is the shipped traverse - the
	# default is the default. "lab" and "crag" are this file's own builds;
	# any other name is res://levels/<name>.tscn (see SCENE LEVELS), and a
	# name that is not there is refused by the loader, not silently played as
	# the traverse.
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--level" and i + 1 < args.size():
			return args[i + 1]
	return ""

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
	# A GAME THAT IS LEAVING STOPS MAKING NOISE, and it does so before the
	# save_enabled gate rather than after: a replay session never writes a save,
	# so anything behind that early return does not run for one. Three of the
	# four continuous voices are looping streams that are deliberately never
	# stopped while playing (ramped instead, because start/stop on noise is a
	# click), and a still-running playback is a live reference at teardown -
	# measured, it left 8 objects held at exit, which the engine reports as a
	# leak and which this project does not otherwise print.
	_av_stop()
	# and it gives the pointer back, for the same reason: a game that is leaving
	# does not keep the player's mouse hidden inside a window that is closing.
	if mouse_owned:
		mouse_owned = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not save_enabled:
		return
	save_to(save_path)
	if rec_on and rec_path != "":
		rec_end()
		if tape_save(rec_path):
			print("tape written: %s (%d ticks, %d marks)" % [rec_path,
				rec_cur.size(), rec_mark.size()])
