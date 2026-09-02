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
#    PAYOUT_TICKS, while loaded: the betrayal is a visible, audible ratchet
#    that ends with the whip sliding off its own tail;
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
                                      # through a slipping partial wrap.
                                      # Raised from 8 when the pin re-seat
                                      # landed: re-seating removed the wasted
                                      # teleport, which shortened the visible
                                      # betrayal from 56 to 39 ticks. This
                                      # restores it - the betrayal has to be
                                      # long enough to read as losing.
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
# the record, and tests/aud_gate.gd A5 re-reads the load range on every run
# (45.8-232.1 N today; the 45.9 below is the same floor at the other rounding).
# What it found, and what the ranges below are built on:
#   tip speed       p50   8.6   p90  29.2   p99  53.2   max  85.7  m/s
#   wrap tension    min  45.9   p50  67.7   p90 157.1   max 232.1  N (wrapped)
#   ground scrape   p50  18.5   p90  54.9   p99 108.9   max 276.8  (sum m/s)
const AV_AIR := 0
const AV_LOAD := 1
const AV_GRIT := 2
const AV_RASP := 3
const AV_N := 4
const AIR_LO := 2.0                   # m/s of tip: below this, no air noise
const AIR_HI := 30.0                  # m/s: the measured p90 tops the ramp
const AIR_DB := Vector2(-42.0, -12.0)
const AIR_PITCH := Vector2(0.55, 2.40)
# The tension floor is MEASURED, not chosen: over the corpus a wrap that is
# engaged at all never carries less than 45.9 N, so the hum does not fall
# silent at the dead point of a swing - it thins. That is the honest reading;
# a rope you are hanging on is never unloaded.
const LOAD_LO := 40.0
const LOAD_HI := 240.0
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

# NONE OF THIS IS SIMULATION STATE. It is all named in SNAP_SKIP, which is what
# keeps a save and a tape describing the same simulation they always did.
var av_on := false                    # only a real windowed session; the probes
                                      # build the sim with new() and never enter
                                      # the tree, so _ready never fires, av_on
                                      # stays false and no audio node exists
var av_touch := PackedByteArray()     # per particle: touched terrain this tick
var av_scrape := 0.0                  # m/s summed over particles in contact
var av_tension := 0.0                 # N carried by the load-bearing wrap
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
		# itself sets level_id directly and never reaches this line.
		level_id = _cmdline_level()
		setup_sim()
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
	# THE LEVEL OWNS ITS SLOT. One slot per level, still one slot per level -
	# the "no second save" contract is about there being no earlier state of
	# THIS run to go back to, and a lab run is not an earlier state of the
	# traverse. Sharing the file would make every switch a mutual wipe:
	# load_from already refuses a save whose level_fingerprint does not match
	# (verified in tests/lab_gate.gd L4), and the very next autosave would then
	# overwrite the run it just refused. Refusal alone is not enough; the
	# refused run has to still be somewhere.
	save_path = SAVE_PATH_LAB if level_id == "lab" else SAVE_PATH
	_reset()
	_av_size()

func _build_level() -> void:
	# TWO LEVELS, ONE OF WHICH MAY NOT MOVE. The shipped traverse is hashed by
	# level_fingerprint() into every tape and into the player's save, so this
	# branch exists precisely so that adding a second level cannot touch the
	# first: --level lab builds different arrays, and the default path below is
	# the same statements in the same order it always was.
	# tests/hashrun.gd must still print 2762505307938286422 and
	# tests/tape_verify.gd must still PASS 6 tapes - both checked in
	# tests/lab_gate.gd, L1 and L2.
	t_a.clear(); t_b.clear()
	if level_id == "lab":
		_build_lab()
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

static func cam_vol(x: float) -> int:
	for i in CAM_VOLS.size():
		if x < float(CAM_VOLS[i][1]):
			return i
	return CAM_VOLS.size() - 1

static func cam_new(b: Vector2) -> Dictionary:
	var i := cam_vol(b.x)
	return {"vlp": Vector2.ZERO, "x": b.x,
		"y": float(CAM_VOLS[i][2]) + CAM_SHELF, "vy": 0.0, "vi": i,
		"lz": log(float(CAM_VOLS[i][3])), "vz": 0.0}

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
	var vi: int = int(st["vi"])
	while vi + 1 < CAM_VOLS.size() and b.x > float(CAM_VOLS[vi][1]) + CAM_HYST:
		vi += 1
	while vi > 0 and b.x < float(CAM_VOLS[vi][0]) - CAM_HYST:
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
	var ty := float(CAM_VOLS[vi][2]) + CAM_SHELF
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
	var z := cam_zoom_step(cam_st, float(CAM_VOLS[int(cam_st["vi"])][3]), dt)
	cam.position = c * PPM
	cam.zoom = Vector2(z, z)

func cam_reinit() -> void:
	# The body has jumped - spawn, R, or a save being resumed - so the camera
	# starts ON its shelf rather than sliding onto it from wherever it was.
	cam_st = cam_new(body_pos)
	if cam == null:
		return
	var z := float(CAM_VOLS[int(cam_st["vi"])][3])
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
	return get_viewport().get_final_transform().get_scale().x / PPM_INPUT

func cursor_now() -> Vector2:
	return cursor_of(body_pos, get_viewport().get_mouse_position(),
		cursor_anchor_px(), cursor_m_per_px())
# ---- end cursor ----

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
	var grip := Input.is_key_pressed(KEY_SPACE) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	step_tick(cursor_now(), grip)
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
			line = "TRAVERSE COMPLETE in %.1fs - press R to run it again" % secs
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

	if av_on:
		av_touch.fill(0)

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
	_av_tick()      # reads the finished tick; writes no simulation state

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
					_friction(i, n, ground_mu, lift)
				else:
					pos[i] = q + n * pr
					_friction(i, n, ground_mu, pr - sd)
				p = pos[i]
				if av_on:
					av_touch[i] = 1   # instrumentation only; see _av_tick
		else:
			# past an end of the segment: round-cap contact off the endpoint
			var l := d.length()
			if l < pr and l > 0.0001:
				var n2 := d / l
				pos[i] = q + n2 * pr
				_friction(i, n2, ground_mu, pr - l)
				p = pos[i]
				if av_on:
					av_touch[i] = 1
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

func _events() -> void:
	crack_cooldown = maxf(0.0, crack_cooldown - DT)
	crack_flash = maxf(0.0, crack_flash - DT * 3.0)
	if tip_speed > CRACK_SPEED and crack_cooldown <= 0.0:
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
	for i in NSEG:
		var w := lerpf(6.0, 2.0, float(i) / float(NSEG - 1))
		draw_line(pos[i] * PPM, pos[i + 1] * PPM, col_now, w)
	if av_on:
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
	# WHAT THE WRAP IS CARRYING, in newtons, this tick: your weight resolved
	# along the rope plus the centripetal term of the arc you are actually on.
	#
	#     T = M ( v_perp^2 / L  +  g cos(rope, down) )
	#
	# THIS IS NOT A WARNING, and it is worth being exact about why, because a
	# tension cue is the obvious place to smuggle in a prediction. In this sim
	# a partial wrap betrays on a fixed timer (PAYOUT_TICKS) and a locked one
	# never lets go at all, so tension has NO bearing whatever on whether the
	# wrap survives. It cannot forecast a failure because it does not cause
	# one. What it renders is the single thing a hanging player has no way to
	# see: how hard they are pulling, and therefore where in the swing they
	# are. Measured over the corpus it runs 45.9 N at the thinnest to 232.1 N
	# at the bottom of a hard swing - a 5x span that a static hang sits in the
	# lower third of.
	var best := 0.0
	av_lidx = -1
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
			av_lidx = a_pinidx[k] if a_pinidx[k] >= 0 else a_lockidx[k]
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

	# LOAD. Silent with no wrap; while there is one it never falls silent,
	# because a wrap you are on is never unloaded (measured floor 45.9 N).
	av_tension = _wrap_tension()
	var ld := clampf((av_tension - LOAD_LO) / (LOAD_HI - LOAD_LO), 0.0, 1.0)
	av_lvl_t[AV_LOAD] = 0.0 if av_tension <= 0.0 else lerpf(0.28, 1.0, ld)
	av_pit_t[AV_LOAD] = lerpf(LOAD_PITCH.x, LOAD_PITCH.y, ld)

	# SLIP. The sim's own flag, which is already binary: it either is paying
	# out or it is not.
	av_lvl_t[AV_RASP] = 1.0 if slipping else 0.0

	# ---- the crack, and HOW HARD it was ----
	# The bang used to be one flat sample at any speed past the threshold. The
	# tip reaches 3.6x the threshold, so a flat bang threw away the whole top
	# of the range - and that range IS the skill bell.
	if crack_flash >= 1.0 and av_flash0 < 1.0:
		av_over = sqrt(clampf((tip_speed / CRACK_SPEED - 1.0)
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
	# THE CAMERA IS NOT THE SIMULATION either, and by the same argument as the
	# audio below it: cam_st is a pure function of a finished tick's body
	# position and velocity, it feeds nothing back, and a save that carried it
	# would be a save whose key set no longer matched the tapes on disk.
	"cam_st", "mouse_owned",
	"rec_on", "rec_path", "rec_cur", "rec_grip", "rec_chk", "rec_start",
	"rec_note", "rec_cen", "rec_prev", "rec_rst", "rec_mark", "rec_mkind",
	"rec_mk",
	"play_on", "play_done", "play_tape", "play_at",
	# AUDIO AND ITS VISUAL TWINS ARE NOT THE SIMULATION. Every one of these is
	# derived from a finished tick and feeds nothing back, so none of them
	# belongs in a save - and leaving them out is not merely tidy, it is what
	# keeps the key set identical. restore() refuses a state whose key set has
	# changed, by design, so a var added here without this line would refuse
	# every committed tape and every save on disk, and it would be right to:
	# it could not tell an audio field from a physics field.
	"av_on", "av_touch", "av_scrape", "av_tension", "av_lidx", "av_over",
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
	rec_grip.append((1 if taut else 0) | (2 if rec_rst else 0))
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
		elif a == "--level":
			# already consumed by _cmdline_level() before the level was built;
			# swallow its argument here so it cannot be read as another flag
			i += 1
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

static func _cmdline_level() -> String:
	# godot --path . -- --level lab. Static, and read straight from the command
	# line, because _build_level needs it and _build_level runs before
	# _boot_session does. Anything other than "lab" is the shipped traverse,
	# which is also what no flag at all means - the default is the default.
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
