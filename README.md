# THE WHIP — greybox demo

A playable greybox of the whip-locomotion concept: a fully-simulated tapered
verlet chain is your only tool and only means of movement. No engine physics,
no RNG, no assists.

## Run it

Open the project in Godot 4.7 and press F5, or from a terminal:

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\judeb\Downloads\the-whip"
```

There is a second level, a flat teaching bench - see **THE LAB** below:

```
--path ... -- --level lab
```

## Controls

| Input | Action |
|---|---|
| Mouse | Move the handle (clamped to a reach circle around the body). The OS pointer is hidden and confined; the crosshair the game draws is the only cursor |
| **HOLD** Space or LMB | TAUT grip — bear load, haul, swing |
| release | SLACK — throw, shape waves, crack |
| R | Restart (discards the run) |
| Esc | Quit (the run is saved) |

## How to play

- The whip only *pulls*. To go anywhere: throw the tip over a beam while
  SLACK, and the moment it winds on, HOLD taut to catch.
- The arc drawn at an anchor is the measured wrap angle (present-state
  instrumentation, not a prediction). **Amber** = partial — it will catch you,
  then betray you within a second. **Green** = a full turn — locked, it holds
  anything.
- A locked wrap is a commitment: to leave it, release at the swing's dead
  point and send a wave up the taut chain to unwind it — or just go slack
  and dangle while you think.
- Pump the swing while hanging, release at the dead point, re-throw mid-air.
  That loop is the whole game.
- Crack the whip (a sharp stroke reversal) — the bang is the skill bell.

## The traverse (76 m, five tiers, 12 m of descent)

A staircase that runs DOWNHILL, floors at y = 0, 3, 6, 9, 12. Every drop faces
along the route, so the lash gait - which crawls flat ground at ~0.44 m/s and
cannot climb even a 20 degree slope - can always shuffle on to the next door
beam. Falling costs ground and time; it never costs the run.

**The school** (home tier, x -14..20) - three fat beams 2.2 m up: throw, wrap,
grip, hang, pump, release, chain a second catch. It ends at a lip.

**DOOR beams** - one per lip, 1.4 m past it. 2.2 m over the tier you throw
from and 5.2 m over the tier you swing in: the only beams you can both catch
cold and launch from. That is the safety contract - no fall is ever terminal.

**FAST beams** - 4.5 m over the tier beneath them, 7.8 m apart. Out of reach
from the ground, catchable only from the apex of a swing. They are the skill
ceiling, and the only place you get a real hanging arc instead of a
feet-dragging pump. Both numbers come from the route bot: 4/4 legs at 7.8 m
of gap, 3/4 at 8.6, 0/4 at 10.5; 4/4 at 4.5 m of height, 2/4 at 4.0, 0/4 at 3.0.

Everything about the layout is measured, not assumed — see the probes below.

## Probes (how the level was designed)

The level is built to what the physics actually allows, not to arithmetic:

- `tests/throw_probe.gd` — searches strokes to map the reachability envelope.
  Result: a 5.25 m whip only **locks** a beam about **3 m above the floor**
  you throw from. Every mandatory beam sits inside that.
- `tests/ground_probe.gd` — the lash gait crawls flat ground at ~0.4 m/s.
- `tests/escape_probe.gd` — but it **cannot climb even a 20 degree slope**, so
  recovery never depends on walking out of anywhere.
- `tests/level_probe.gd` — audits every beam in the real level. Every LOW beam
  must lock from a standstill; HIGH beams are expected to fail from the
  ground, by design.
- `tests/debug_classify.gd` — calibration bench for the wrap thresholds.

## Saving: the run *is* the save

There is one slot. It is overwritten every half second while you play and again
on every exit — the window's close button, Esc, and the engine's crash handler
— and loading it puts you back exactly where you were, to the bit. Quit while
falling and you resume falling.

That is the design, not a limitation. This is a Getting Over It lineage game
with diegetic loss and no checkpoints, so **save-scumming is not forbidden by a
rule, it is structurally absent**: there is no earlier state to go back to,
because the game never keeps one. `R` restarts, and it discards the whole run.

```
--path ... -- --fresh          start a new run, ignoring the save
```

## Input tapes — the regression test that needs no oracle

`step_tick(cursor, grip)` is the game's entire input surface. A **tape** is that
input, per tick, plus the state it started from and the hashes it produced.
Replaying one asks the only question that needs no oracle: *does the game still
do what it did yesterday?*

That matters here. In one session three separate probes were caught quietly
lying — a drape test that passed a build which caught drapes on every beam
radius, a stuck-in-floor probe carrying the *old* level geometry hardcoded so it
reported a bug 0.79 m in mid-air, and a level probe certifying the safety
contract from a hand-laid chain state no real run produces. Every one of them
needed an oracle to catch. A replay has none to get wrong.

**Verify (seconds) — the one command:**

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\judeb\Downloads\the-whip" -s res://tests/tape_verify.gd
```

PASS/FAIL per tape, exit 1 on any divergence, and a divergence is reported at
the half-second it began (checkpoint hashes every 30 ticks), not at the end.

**Record (minutes — the throws are searched, not hardcoded):**

```
... -s res://tests/tape_rec.gd            # the whole corpus
... -s res://tests/tape_rec.gd -- door    # just one
```

The corpus in `tapes/`, and what each is shown to contain:

| tape | ticks | what it covers |
|---|---|---|
| `hashrun` | 900 | the golden session — its final hash *is* `hashrun.gd`'s number |
| `crawl` | 660 | the lash gait on flat ground; no beam involved |
| `reset` | 540 | **R** pressed mid-run — the one input that is not (cursor, grip) |
| `school` | 779 | throw A0 from a standstill, catch, **lock**, hang, pump, **dismount** |
| `betray` | 797 | a partial wrap **catches**, **pays out**, **slides off**, you crawl on |
| `door` | 4003 | **crawl 23 m**, catch the door beam over the lip, hang, pump, **fall** 2.7 m to tier 1 |

No tape is written that does not replay, and none that is vacuous: each declares
what it must contain and the recorder refuses to keep one whose census does not
meet it. A gate that passes on nothing is the failure this corpus exists to
answer.

Play or watch a tape in the real game:

```
--path ... -- --record tapes/mine.tape --note "what this is"
--path ... -- --replay tapes/door.tape
```

**A divergence is not automatically a bug.** A deliberate change to the sim
diverges every tape, and that is correct. Re-record and commit the new tapes in
the same change as the sim edit, so the diff shows both.

**Platform caveat, and it is real.** A tape or a save is only guaranteed on the
**same build on the same platform**. The sim has no RNG, a fixed tick and a
fixed substep count, but IEEE 754 does not oblige two architectures to agree on
`sin`/`cos`/`sqrt`/`acos`, and x86 and ARM measurably do not. Nothing here
assumes otherwise.

## THE LAB — a second level, and the anchor vocabulary

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\judeb\Downloads\the-whip" -- --level lab
```

No flag is the traverse, and the traverse is **byte-identical**. `--level` is
read before `_build_level` runs and only ever adds a second branch to it:
`tests/hashrun.gd` still prints `2762505307938286422`, `tests/tape_verify.gd`
still PASSes all 6 tapes, and `tests/lab_gate.gd` L1/L2 assert both from inside
the lab build itself. The three new fields (`level_id`, `a_jam`, `a_name`) are
in `SNAP_SKIP` for a reason worth knowing: `restore()` refuses a state whose key
set has changed, so a var declared outside that list would refuse every
committed tape and the player's save on the next boot.

The lab is a **bench, not a route** — one flat floor from x −12 to x 20, walled
at both ends, four stations 6.5 m apart, nothing to fall off. The cost of a bad
throw is the walk back: 56.9 s end to end with the lash gait, walked rather than
assumed (`lab_gate.gd` L5). It has its own save slot, `user://run_lab.save`, so
a lab session and a traverse session cannot overwrite one another.

| station | what it is | why |
|---|---|---|
| **BEAM** r 0.22 @ 2.2 m | the reference | identical radius, height and lead to the first school beam of the traverse — the throw that works here is the throw that works there |
| **THIN BEAM** r 0.11 @ 2.2 m | same verb, less beam | the door-beam radius. Difficulty, not vocabulary |
| **JAM** r 0.14 @ 2.2 m | the new word | the level supplies the self-crossing. Same height as the BEAM on purpose: the only thing that differs is what it takes to make it hold |
| **JAM HIGH** r 0.14 @ 2.9 m | the same word, thrown hard | the top of the ~3 m envelope `throw_probe.gd` measured |

Every station is captioned on screen under its anchor, and a jam wears a pale
collar outside the instrumentation ring. **The ring itself is unchanged** — it
still goes green on `_holds()` and nothing else. A jam that read differently
from a wrap would give the one instrument the player trusts two dialects.

### What a jam anchor is

`_pinch()` is this file's own definition of *a wrap that can hold a body*, and a
jam anchor answers **yes to it while the rope is touching**. That is the whole
change: one branch, no new state, no new rule. The catch still needs a fresh
grip inside `GRIP_WINDOW`, classification still runs through `PINCH_RUN`, the
ring still gates on `a_locked == 1`, and **opening your hand still drops you in
one frame**. What the player gains is not a new verb but a new promise: *a jam
is a beam you do not have to earn the crossing on.*

### What that is worth, measured

`tests/lab_throw.gd` throws **108 searched strokes** at each station from the
lab's own floor — 3 leads × 6 stroke angles × 3 stroke lengths × pull, nothing
hand-laid — and counts how many of them catch, lock and go green. Read the
number as *how big the set of working strokes is*, not as a hit rate: a bigger
basin is an easier anchor.

The hand shuts on a **present-state cue off the screen**, and the two anchors
offer different ones. On a beam it is route_bot's: shut when the arc reads as a
catch (θ ≥ 2.6). On a jam it is the one a jam actually gives you: shut when the
rope arrives on it.

| station | cue: the arc reads | cue: the rope arrives |
|---|---|---|
| **BEAM** r 0.22 @ 2.2 m | 14 caught / 3 locked / **3 green** | 3 / 3 / 3 |
| **THIN BEAM** r 0.11 @ 2.2 m | 20 / 20 / **20** | 11 / 11 / 11 |
| **JAM** r 0.14 @ 2.2 m | 33 / 33 / **33** | 37 / 37 / **37** |
| *the same anchor, flag OFF* | 19 / 16 / 16 | 13 / 10 / 10 |
| **JAM HIGH** r 0.14 @ 2.9 m | 0 / 0 / 0 | 3 / 3 / **3** |
| *the same anchor, flag OFF* | 0 / 0 / 0 | **0 / 0 / 0** |

Those two *flag OFF* rows are the control, and they are the whole argument: same
radius, same position, same rig, same 108 strokes, one bit different. At 2.2 m
the flag takes the green basin from 16 to 33 on the arc cue and from 10 to 37 on
the arrival cue. At 2.9 m it is the difference between **3 and none at all** —
the jam is reachable where the ordinary anchor is not, which is what "it takes
from angles a wrap will not" means in numbers.

Then the winning stroke is caught for real, **the floor is removed** (rebuilt and
assigned back — a packed array reached through a property is a copy, and
`remove_at()` on one silently does nothing), and the body hangs for 3 seconds:

| station | hand SHUT | ring | hand OPEN | released | tension |
|---|---|---|---|---|---|
| BEAM | +0.010 m | green 180/180 | falls **43.5 m** | tick 0 | 58–126 N |
| THIN BEAM | −0.197 m | green 180/180 | falls **40.4 m** | tick 0 | 62–106 N |
| JAM | −0.149 m | green 180/180 | falls **45.3 m** | tick 0 | 65–108 N |
| JAM HIGH | −0.173 m | green 180/180 | falls **45.6 m** | tick 0 | 65–110 N |

That is `sim_test`'s G7 asked once per anchor, and the jam passes it. The
negative control the reading needs is in `lab_gate.gd` L7: the identical state
with the catch dropped and the hand still shut falls 45.2 m, so the −0.149 m is
the anchor and not the rig.

**One consequence to know about: a jam never ambers.** Caught, locked and green
are the same number in every jam row — 33/33/33, 37/37/37, 3/3/3 — because
`_pinch` is true from the tick it engages, so `PINCH_RUN` is satisfied
immediately and the wrap is classified LOCKED before it can be classified
partial. The same anchor with the flag off does amber (19 caught, 16 locked —
three partials), and so does the BEAM (14 caught, 3 locked — eleven). So a jam
has no betrayal: it either does not take, or it holds. The ring still tells the
truth at one; it just never has the amber to tell.

### Why it is declared and not built

**Geometry was measured and does not work.** Three probes swept 25 terrain and
anchor shapes:

- **The V notch** — the briefed jam, mouth open, narrowing at the back — held
  **0 of 84** cells and **0 of 168** settled placements, against a 0.7 N noise
  floor on a 91 N scale. It is loaded backwards: a hanging body pulls the rope
  toward the *wide* end, so the wedge unloads exactly as it takes load. The
  lateral wall pushes then come out as axial ejection — the tip left a 3–25°
  notch in 0.050 s at 11.4 m/s, twenty times what gravity would give.
- **The fork** — "a slot that pinches the rope against itself" — cannot be built
  at all. **This sim has no rope-on-rope contact**: `_collide()` never tests a
  particle *pair*, and 72.6% of the corpus's 7679 ticks have two non-adjacent
  particles overlapping, deepest 0.0952 m. A hairpin with two strands in the
  throat behaves exactly like one strand.
- **Two shapes did hold** — a two-circle thickness jam (80.3 N for 10 s) and an
  hourglass chockstone (91.0 N, 36/36 from searched throws, 0.0000 m of tip
  drift over 10 s). Both are left out for the same reason: **they hold with the
  hand open.** Over 10 s, taut and open-hand runs are bit-identical to four
  decimals — +0.0280 m vs +0.0280 m, 91.00 N both — while an ordinary wrap on
  the same bench fell 44.1 m when the hand opened. They hold through
  `_solve_rope` and terrain collision alone, so no wrap engages, `a_freelen`
  stays −1, `_holds()` is never true, and not one of the ten voices or their
  visual twins can speak — every one is keyed to an anchor index. That is a
  place in the world where the grip button is decorative, which is exactly what
  the design contract forbids.

```
... -s res://tests/lab_gate.gd     # L1 the shipped level is byte-identical
                                   # L2 all 6 tapes still name it, none names the lab
                                   # L3 lab normals point into air (0/3 reversed)
                                   # L4 the slots do not collide, and each refuses
                                   #    the other's save while accepting its own
                                   # L5 the bench is walkable, the stations are in
                                   #    isolation, the camera never steps
                                   # L6 the jam flag fires on contact, not at 1 m,
                                   #    and not at all when it is off
                                   # L7 G7 asked of the jam, from a THROWN catch
                                   #    with the floor removed: hand shut -0.149 m
                                   #    over 3 s and green 180/180, hand open falls
                                   #    45.3 m on tick 0, and the control - the same
                                   #    state with the catch dropped and the hand
                                   #    still shut - falls 45.2 m
... -s res://tests/lab_throw.gd    # 108 searched strokes per station, thrown from
                                   # the lab floor; then the floor is REMOVED and
                                   # the body hangs 3 s with the hand shut and open
... -s res://tests/lab_shots.gd    # searches one real thrown catch per station and
                                   # writes the states out (headless)
... -s res://tests/lab_view.gd -- in=user://lab_shots.dat out=user://lab
                                   # photographs them through the real _draw. Run
                                   # WINDOWED: the headless driver's root viewport
                                   # has no texture and get_image() returns null,
                                   # which is why cam_view was always run with one
```

## Test gates

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\judeb\Downloads\the-whip" -s res://tests/sim_test.gd
```

G1 stability · G2 bit-determinism · G3 wave amplification ≥3× (the crack)
· G4 full wrap locks and holds · G5 partial wrap catches then betrays
· G6 no free lift from mouse waggle · G7 grip matters.

Sound has its own gate; see "Sound is instrumentation" below.

```
... -s res://tests/save_test.gd
```

Snapshot and resume are bit-identical. Four states, found by replaying the
committed tapes rather than by hand-laying a rig: mid-air, mid-wrap,
mid-betrayal, and coiled past the lock threshold. At each, an uninterrupted run,
a run that was snapshotted, that snapshot restored from memory, and that
snapshot written to a file and loaded into a sim that never played those ticks
must all produce one hash.

## The camera, and the mouse it must never touch

The level is a descending staircase — a home tier, then four 3 m drops — so the
camera is **authored per volume**, one volume per tier, and the vertical is a
function of *which volume the body is in*, i.e. of its **x**, never of its y.

That last clause is the whole design. **A fall barely changes x, so during a
3 m drop the camera does not move vertically at all.** The floor line holds
still and you read your height and your speed against it. A camera that chased
the fall would show a floor rushing up at a body that appears not to move,
which destroys exactly the two readings a drop is asking you to make. Measured
over the corpus and the leaps: the shipped-before camera's vertical range on
the door tape was 3.76 m and on the F1→F2 leap 6.92 m (it rode the swoop);
this one is **3.00 m and 2.94 m — one authored step, and nothing else**. On
every ground-only tape it is **0.00 m** against 0.71–0.97 m of pump bob.

| | |
|---|---|
| **volumes** | 5, spanning the left wall to the far wall, boundaries at lip−1.0 with ±1.5 m of hysteresis. Measured: exactly one step per drop, no flapping, on every trace |
| **shelf** | camera centre at tier floor − 2.2 m. Standing puts the body at 63% of frame height, hanging on a door beam at 47%, swooping at 70% — **the upward bias while hanging costs no state to decide, because nothing decides it** |
| **lead** | 0.40 s of *low-passed body velocity* (τ 0.70 s), clamped −1.2 / +3.2 m, with the follower's own lag cancelled so the lead you author is the lead you get. Deliberately asymmetric: the route is one-way, and a pumping body reverses twice a swing |
| **zoom** | authored **1.00 in every volume**, blended critically damped on ln(zoom) under a hard **8%/s** rate cap |
| **fallback** | one always-live clamp: the body may never come within 2.0 m of a frame edge. No mode, no switch, no edge to fall off |

**Zoom is authored 1.00 everywhere and that is a measurement, not an
omission.** The rope is bounded to a 6.40 m circle around the body by
construction (5.25 m of chain + 1.15 m of arm), so nothing *dynamic* can ever
demand a wider view; the largest must-see box in the game is the F1→F2 leap at
11.1 × 7.1 m against a 26.67 × 15.00 m frame, and every volume has 35–66% of
unused headroom. Read the zoom column as a **budget**: the moment an edit puts
a beam more than ~13 m ahead or ~11 m of vertical content inside one volume, it
stops being optional.

**The camera never reads the whip, and that is enforced rather than requested.**
Its entire input is the body's position, the body's velocity, and a constant
authored table. Zoom driven by rope extension pumps with the rope, and worse,
rescaling mid-stroke regrades the apparent speed of the wave you have spent
hours learning to read. It is also the shape of an assist: a camera that widened
exactly when your momentum was enough to clear the next gap would be a
feasibility oracle. The law is written as **static functions** — a static func
cannot reach instance state, so the rope arrays are not in scope — and
`cam_gate.gd` C1 reads `main.gd` between the camera's own markers and fails if
any of 23 rope identifiers appears inside them.

### The trap: mouse sensitivity is the camera's business, until it isn't

`get_global_mouse_position()` is the mouse run **backwards through the camera**,
so the metres-per-pixel of the control was whatever the camera happened to be
doing. This is a position-mapped control in the Getting Over It line — the whole
skill is motor memory of a stroke — and a sensitivity that shifts under the
player does not read as *the camera changed*, it reads as **the whip getting
worse**, silently, after they have already learned the old one.

So the camera is removed from the expression rather than slowed down:

```
cursor = body + (mouse_px - anchor_px) * m_per_px
```

`get_global_mouse_position` appears nowhere in `main.gd`. Measured through a
real `Camera2D` in a real viewport (`cam_gate.gd` C2): **1.66667 m per 100
physical px of mouse at every zoom from 0.70 to 1.25 and at every window size —
a spread of exactly zero, not merely small.** Through the camera the same sweep
runs 1.111–2.976 m, a 168% swing, with the reach rim moving from 77 px of desk
to 207. It is 138 px at all of them now, nailed to the same patch of desk.

Two consequences worth knowing:

- **Camera *position*, not just zoom, was the load-bearing half.** The framing
  leads by up to 3.2 m and lets the body ride from 21% to 73% of frame height;
  a camera-mapped cursor would drag a *stationary hand* 4.11 m across and
  7.84 m down — 3.6× and 6.8× the entire 1.15 m reach. It never showed before
  only because the shipped camera never left the body.
- **The anchor is 1.4 m below the view centre on purpose.** That is where the
  shipped camera put the body, so this mapping *reproduces* the control every
  hour of practice was done against: over 9045 ticks the two differ by p50
  0.006 m, p90 0.058 m, p99 0.132 m. The one place they part company is
  `reset.tape`, where R teleports the body and the old camera is left 1.33 m
  behind it — 116% of the whole reach — which is the failure mode the framing
  would have made routine.

Because the anchor is on the screen rather than in the world, the OS pointer and
the drawn crosshair no longer coincide once the camera leads or steps (up to
240 px apart), so the pointer is **hidden and confined** and the game's own
crosshair is the only cursor. Past the reach rim the crosshair is pinned and
stops telling you where your hand is; a faint ring and a dot appear then, and
only then, to give that reading back.

```
... -s res://tests/cam_gate.gd    # C1 source ban, C2 mouse invariance, C3 zoom
                                  # rate cap, C4 framing over 9045 ticks, C5 the
                                  # cursor path names no way back to the camera
... -s res://tests/cam_ship.gd    # what the camera DOES: framing percentiles,
                                  # vertical travel, shelf steps, cost
... -s res://tests/cam_live.gd    # the live _physics_process path, and whether
                                  # a save from the previous build still loads
... -s res://tests/cam_view.gd -- --replay tapes/door.tape mode=door out=DIR
                                  # photographs the real frame, and prints a
                                  # manifest of what is inside it in metres
```

The camera costs **2.8 us a tick** — 0.017% of a 16.7 ms frame, and 0.11% of
what one simulation tick already spends.

## Sound is instrumentation, not polish

A real whip is learned by ear, because the tip outruns the eye. This game is
about reading a rope you can only partly see, so its sound is an instrument:
**it renders the past and the present, and never the future.** A cue that told
you a wrap *would* hold would be the same defect as a trajectory ghost.

Everything is generated in code, as the greybox has no asset pipeline. Seeded
RNG builds the waveforms at startup; **no RNG ever reaches the simulation.**

Every curve is fitted to measured data, not guessed — `tests/aud_probe.gd`
replays the tape corpus (7679 ticks) and reports the distribution of each
driver. Two of them contradicted the obvious guess:

- **The bang samples the rising edge, not the peak.** The tip reaches 85.7 m/s
  (3.57x the crack threshold), but the crack fires on the *first* tick past the
  threshold and then waits out a 0.3 s cooldown, so the overshoot *at the bang*
  is only 1.00–2.42x (p50 1.19). A loudness ramp built to 3.57 would have put
  the median crack 8% of the way up it.
- **A wrap you are on is never unloaded.** Measured, tension never falls below
  45.9 N while a wrap is engaged, so the load voice thins at the dead point of a
  swing — it does not go silent.

**Every voice has a visual twin driven by the same number on the same tick**, so
a deaf player reads the same instrument rather than a worse one:

| voice | what it renders (present state) | visual twin |
|---|---|---|
| air whoosh | tip speed, 2–30 m/s | halo at the tip, same ramp |
| load hum | newtons on the wrap, 40–240 N | the loaded leg of the rope glows |
| ground grit | contacts resolved this tick | a pip on each touching particle |
| crack | overshoot past `CRACK_SPEED` | tip flash, sized by the same number |
| winding tick | each half turn on the beam | the half-turn dots on the arc |
| slip rasp | `slipping`, right now | the red outer arc |
| catch | a wrap engaged | white ring leaving the beam |
| verdict | the classification, once made | the arc resolves + a pulse in its colour |
| ratchet | one segment paid through | a red pulse, one per segment |
| slid off / let go | how the wrap ended | a red / pale burst |

The verdict fires when `a_locked` leaves −1 and uses `_holds()` — the arc's *own*
predicate — so the pulse, the ring and the sound cannot say three different
things. **Nothing at all is said while a wrap is pending**, which is the line:
speaking then would be announcing how the classification is going to come out.

```
... -s res://tests/aud_gate.gd
```

A1 no audio node exists headlessly · **A2 the golden hash is unchanged with the
audio pass forced ON** · A3 every audible event raised its ring on the same tick
· A4 no verdict ran ahead of the sim · A5 the voices are actually driven ·
A6 cost. A2 is the one that matters: it runs the audio code rather than
reasoning about it, and the sim still hashes `2762505307938286422`.

```
... -s res://tests/aud_wave.gd     # level, DC, loop seams, sweep frequencies
... -s res://tests/aud_probe.gd    # the distributions the curves are fitted to
... -s res://tests/aud_trace.gd -- betray    # per-tick drivers for one tape
... -s res://tests/aud_shot.gd -- --replay tapes/school.tape 359 366 out=DIR
```

`aud_shot` puts the real node in the tree to photograph the twins. It **must**
be given `--replay`: `_ready` is deferred to the first frame, so a harness that
clears `save_enabled` in `_initialize` has it turned back on a frame later by
`_boot_session` — and then writes a run the player never played over the one
slot. It refuses to step if `save_enabled` is not false.

## Design contracts (do not "improve" these away)

- No RNG in the sim; bit-identical replays on the same build.
- The save IS the run: one slot, continuously overwritten, no rewind. Do not
  add a second slot, a checkpoint, a "load last" or a confirm-on-restart. The
  absence is the rule, and it is the reason no rule is needed.
- No assists: no tip magnetism, no auto-taut, no input smoothing beyond the
  constant arm spring, no trajectory prediction, no slow-mo.
- Rope never pushes. Arm forces are internal pairs (no waggle-flight).
- Dissipation only via contact friction and taut-catch yanks.
- Wrap angle is measured from live geometry every tick, never event-counted.
- **The camera never reads the whip.** Its whole input is the body's position,
  the body's velocity and an authored table. Not zoom, not framing, not a
  bias — a camera that reacts to what the rope is doing pumps with it, and one
  that reacts to whether you *could* make the next gap is a feasibility oracle.
- **The mouse never reads the camera.** Sensitivity is a constant, in metres
  per physical pixel, at every zoom and every window size. Both bans are
  enforced by `tests/cam_gate.gd` reading the source, not by these bullets.
- The capstan pin (material point pinned at TH_FULL) is the documented
  stand-in for rope self-pinch — the pressure-test showed a bare tapered
  tail cannot hold a body by capstan friction alone.
