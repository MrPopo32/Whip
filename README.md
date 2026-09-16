# THE WHIP — greybox demo

A playable greybox of the whip-locomotion concept: a fully-simulated tapered
verlet chain is your only tool and only means of movement. No engine physics,
no RNG, no assists (one named exception, in the lab).

## Run it

Open the project in Godot 4.7 and press F5, or from a terminal:

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\judeb\Downloads\the-whip"
```

There is a second level, a flat teaching bench - see **THE LAB** below:

```
--path ... -- --level lab
```

And a third, where the rock is the thing the whip interacts with - see **THE
CRAG** below:

```
--path ... -- --level crag
```

Any other name is a level drawn in the Godot editor, `res://levels/<name>.tscn`
- see **Building a level** below:

```
--path ... -- --level steps
```

## Controls

| Input | Action |
|---|---|
| Mouse | Move the handle (clamped to a reach circle around the body). The OS pointer is hidden and confined; the crosshair the game draws is the only cursor |
| **HOLD** Space or LMB | TAUT grip — bear load, haul, swing |
| release | SLACK — throw, shape waves, crack |
| R | Restart (discards the run) |
| Esc | Quit (the run is saved) |
| F / G | only while `--record`: stamp this tick on the tape. F = "it was green and it let go", G = "that should have hooked and did not". Inert in an ordinary session |

**On a trackpad, use Space.** The hand opens on a single false tick with no
debounce, by design (release is one frame; `main.gd`'s hand-open branch says
`HAND OPEN = OFF THE BEAM, THIS TICK`), and a trackpad click-hold is the easiest
thing in the world to lose for 17 ms without noticing. `tests/grip_census.gd`
reads the grip byte off a recorded session and separates a release from a slip
by the length of the gap; on the player's own take, 3 of 42 gaps were short
enough to be slips, and each one, if a wrap was live, ended that wrap outright.
Before blaming the sim for a drop, check the byte.

## How to play

- The whip only *pulls*. To go anywhere: throw the tip over a beam while
  SLACK, and **close your hand as it winds on**. Grip is a trigger, not a
  latch: a wrap can only take in the quarter second after your hand shuts,
  never merely because it happens to be shut — holding the button early is a
  throw, not a catch.
- The arc drawn at an anchor is the measured wrap angle (present-state
  instrumentation, not a prediction). **Amber** = partial — it will catch you,
  then betray you: under load it pays one segment of rope through the wrap
  every quarter second (`PAYOUT_TICKS`, 15 ticks — measured 15.0 ticks per
  segment on searched throws), audibly, until the whip runs off its own end.
  How long that takes is how much tail you caught it with: the last pin that
  can advance is chain index 23 of 25, so from the first segment a wrap
  pinned at 21 has at most 0.75 s before it slides off, at 17 1.75 s, at 13
  2.75 s — at most, because only loaded ticks count (touching down pauses
  it) and a slow ratchet leaves time for the wrap to unwind off the beam
  instead. (Until `_advance_pin` re-armed the timer per segment this was one
  quarter second and then one segment per tick — a snap, not a slide; see
  *One-to-beam*.) **Green** = the rope has crossed itself on the
  beam — locked, it holds anything until you unwind it or open your hand.
  Green is exactly the sim's own verdict and nothing more. It used to demand a
  second thing — enough tail past the pin — and on a recorded session that
  clause hid 5 of 25 locks entirely and called amber for 44% of the time the
  whip was carrying the player; scored against whether the wrap actually
  survived, the greens it kept did *worse* than the ones it threw away. It is
  gone (`1aa17d8`). If the ring says green and you fall, your hand opened —
  check the grip byte before anything else.
- A locked wrap holds for exactly as long as your hand is shut. There is no
  dangling on it: open your hand and you leave the beam that tick, wherever
  along the chain it caught (`1f6f83e`). Release is your launch, so time it —
  the dead point of the swing is where the throw goes furthest. The other way
  off is to unwind it, by sending a wave up the taut chain until the measured
  arc falls back under the catch threshold.
- Pump the swing while hanging, release at the dead point, re-throw mid-air.
  That loop is the whole game.
- Crack the whip (a sharp stroke reversal) — the bang is the skill bell, and
  it is only a bell: no energy is shed and nothing in the world is hit.
  **Striking was measured and not built.** The crack can be aimed, but one
  motion covers 87.5% of everything that can be struck — darts, not golf — the
  crack event fires 3–5 m from where you aimed it, and the tip's precision
  floor (see *What determinism buys*) kills any target under about a metre. A
  verb whose whole envelope fits inside one stroke is not a verb; it is a
  button with a windup.

## The traverse (76 m, five tiers, 12 m of descent)

A staircase that runs DOWNHILL, floors at y = 0, 3, 6, 9, 12. Every drop faces
along the route, so the lash gait - which crawls flat ground at ~0.42 m/s and
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
- `tests/debug_classify.gd` — a theta dump: what the wrap measure reads at the
  anchor over 16 ticks for four laid turns, a quick look rather than a gate.

`throw_probe.gd` and `level_probe.gd` search strokes and take minutes, not
seconds; the other three finish in seconds.

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
| `betray` | 825 | a partial wrap **catches**, **pays out**, **slides off**, you crawl on |
| `door` | 4003 | **crawl 23 m**, catch the door beam over the lip, hang, pump, **fall** 2.7 m to tier 1 |

No tape is written that does not replay, and none that is vacuous: each declares
what it must contain and the recorder refuses to keep one whose census does not
meet it. A gate that passes on nothing is the failure this corpus exists to
answer.

**Record your own session, or watch one back:**

```
--path ... -- --record takes/mine.tape --note "what this is"
--path ... -- --replay tapes/door.tape
```

`--record` has always been a live recorder of a real session — the same
recorder `tape_rec.gd` uses, pointed at your hands. Two things about it. Record
into `takes/`, not `tapes/`: `tape_verify` replays everything in `tapes/` and
requires each file to contain what it declares, so a bug recording there is a
gate that fails on purpose. `takes/` is gitignored — a recorded human session is
evidence, not source, and it is kept beside the code rather than in it. And
while recording, **F** and **G** stamp the tick you were looking at: F for "the
ring was green and it let go anyway", G for "that should have hooked and did
not". Two keys because those are questions about different code. The stamps
sit beside the input stream, never in it (a marked tape and an unmarked one
feed the sim the same bytes; `mark_rt.gd` R2 requires it), and
`tests/mark_look.gd -- takes/mine.tape` dumps the full lock state either side
of every one, with the clause of the catch that refused.

**A divergence is not automatically a bug.** A deliberate change to the sim
diverges every tape, and that is correct. Re-record and commit the new tapes in
the same change as the sim edit, so the diff shows both.

**Platform caveat, and it is real.** A tape or a save is only guaranteed on the
**same build on the same platform**. The sim has no RNG, a fixed tick and a
fixed substep count, but IEEE 754 does not oblige two architectures to agree on
`sin`/`cos`/`sqrt`/`acos`, and x86 and ARM measurably do not. Nothing here
assumes otherwise.

### What determinism buys, and what it does not

Bit-identical is not the same as predictable, and the tip is where the two part
company. The tip is chaotic: two runs that differ by a few millimetres of cursor
diverge smoothly and exponentially, with no cliff anywhere to find, and it
cannot be fixed — damping the taper *raises* the divergence rate (26:1 → 1.6:1
takes G3's amplification from 3.22× to 1.49× while the divergence rate goes
from 1.77 to 3.83 /s), because a lighter tip that is also a slower one just has
longer to wander. The floor was measured: a few millimetres of cursor moves the
tip by about 0.9 m, and no input precision brings that under about 0.46 m.
**Any task that asks the tip to be somewhere to better than a metre is a
lottery**, and the game must not set one. It does not, and that is structural
rather than lucky: nothing in the game reads the tip's position. `pos[NP-1]` is
used four times in `main.gd` — once for tip speed, once inside a tangent
correction in the wrap measure, twice to draw it. Everything that decides an
outcome reads the wrap, which is measured where the rope touches the beam, not
where it ends. (`mark_rt.gd` R3 shows the scale: a 10 micron cursor error on one
tick changes the state hash eleven ticks later; a 1 micron one is absorbed by
the reach clamp.) The probe that measured the divergence rate was not kept; its
record is commit `6fdaa44`.

## THE LAB — a second level, and the anchor vocabulary

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\judeb\Downloads\the-whip" -- --level lab
```

No flag is the traverse, and the traverse is **byte-identical**. `--level` is
read before `_build_level` runs and only ever adds a second branch to it:
`tests/hashrun.gd` still prints `2762505307938286422`, `tests/tape_verify.gd`
still PASSes all 6 tapes, and `tests/lab_gate.gd` L1/L2 assert both from inside
the lab build itself. The five lab fields (`level_id`, `a_jam`, `a_name`,
`goal_y`, `jam_min_th`) are in `SNAP_SKIP` for a reason worth knowing:
`restore()` refuses a state whose key set has changed, so a var declared outside
that list would refuse every committed tape and the player's save on the next
boot. `jam_min_th` is there too even though it is a tuning number, because a var
declared anywhere else moves the snapshot layout, and re-recording six tapes for
a constant that never changes inside a run is not a trade.

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
| **JAM HIGH** r 0.14 @ 2.5 m | the same word, thrown harder | 2.5 m, not the 2.9 m this bench first shipped with. At 2.9 it was not difficult, it was luck: 3 winning strokes in 108, a 50 ms press window, and a lead basin of 64 cells in ten separate blocks, two of them 2.5 mm wide. No RNG is involved and every one of those repeats exactly — but a player cannot stand to 2.5 mm, so the same intention took sometimes and not others, which is the one thing this game has ruled out. Difficulty here lives in stroke shape, where it is learnable |

Every station is captioned on screen under its anchor, and a jam wears a pale
collar outside the instrumentation ring. **The ring itself is unchanged** — it
still goes green on `_holds()` and nothing else. A jam that read differently
from a wrap would give the one instrument the player trusts two dialects.

### What a jam anchor is

`_pinch()` is this file's own definition of *a wrap that can hold a body*, and a
jam anchor answers **yes to it while the rope is touching**. That is the whole
change: one branch, one tuning number, no new rule. The catch still needs a
fresh grip inside `GRIP_WINDOW`, classification still runs through `PINCH_RUN`,
the ring still gates on `a_locked == 1`, and **opening your hand still drops you
in one frame**. What the player gains is not a new verb but a new promise: *a
jam is a beam you do not have to earn the crossing on.*

**The one number is a floor, and it had to be earned.** As first built the jam
took on contact alone, and 28 of its 37 catches locked below 0.3 rad — under the
angle at which the arc is drawn at all. It held the player with nothing on the
screen, 76% of the time, in the same week the ring was fixed for lying; across
the whole recorded corpus the traverse has never once held a player without
drawing the ring (0 of 458 locked ticks). So `jam_min_th` = 1.0 rad, checked
before contact. It costs 19% of the catch rate and buys back every dark hold —
structurally, since 1.0 is above the 0.3 the arc starts at. It also puts a jam
on the same dial as a beam at a different number: on a beam you wait for the arc
to close, on a jam you press as it appears.

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
| **BEAM** r 0.22 @ 2.2 m | 13 caught / 3 locked / **3 green** | 3 / 3 / 3 |
| **THIN BEAM** r 0.11 @ 2.2 m | 20 / 20 / **20** | 11 / 11 / 11 |
| **JAM** r 0.14 @ 2.2 m | 32 / 32 / **32** | 29 / 29 / **29** |
| *the same anchor, flag OFF* | 19 / 16 / 16 | 13 / 10 / 10 |
| **JAM HIGH** r 0.14 @ 2.5 m | 7 / 7 / **7** | 7 / 7 / **7** |
| *the same anchor, flag OFF* | 0 / 0 / 0 | 3 / **0** / 0 |

Those two *flag OFF* rows are the control, and they are the whole argument: same
radius, same position, same rig, same 108 strokes, one bit different. At 2.2 m
the flag takes the green basin from 16 to 32 on the arc cue and from 10 to 29 on
the arrival cue. At 2.5 m it is **7 against none**: the plain beam is touched by
three strokes and locked by none of them — the jam is reachable where the
ordinary anchor is not, which is what "it takes from angles a wrap will not"
means in numbers. (The arrival cue read 37 before the arc floor went in; the
floor cost it 8 strokes, and every one of them was a hold the player could not
see.)

### The verdict on the jam

Measured against the beam next to it, a jam is **not a new verb; it is a
discount on the old one.** The press window is the same quarter second, the aim
basin is the same shape in the same place, and the only thing that moves is
conversion — more of the strokes that were nearly right become right. That is
worth having on a teaching bench, where the question is "was that stroke
close?", and it is why the jam stays in the lab as a control against the plain
beam beside it. It is not on the traverse and is not going there: a route built
on discounts teaches the discount. (The measurement is recorded in commit
`6fdaa44`; the rig behind it was not kept.)

Then the winning stroke is caught for real, **the floor is removed** (rebuilt and
assigned back — a packed array reached through a property is a copy, and
`remove_at()` on one silently does nothing), and the body hangs for 3 seconds:

| station | hand SHUT | ring | hand OPEN | released | tension |
|---|---|---|---|---|---|
| BEAM | +0.012 m | green 180/180 | falls **43.4 m** | tick 0 | 58–126 N |
| THIN BEAM | −0.270 m | green 180/180 | falls **41.0 m** | tick 0 | 63–102 N |
| JAM | −0.133 m | green 180/180 | falls **45.3 m** | tick 0 | 65–108 N |
| JAM HIGH | −0.148 m | green 180/180 | falls **47.2 m** | tick 0 | 67–103 N |

Each row hangs on the winning stroke of the arrival cue, except THIN BEAM,
whose row is the arc cue's. That is `sim_test`'s G7 asked once per anchor, and
the jam passes it. The negative control the reading needs is in `lab_gate.gd`
L7: the identical state with the catch dropped and the hand still shut falls
45.3 m, the same distance to the decimetre, so the −0.133 m is the anchor and
not the rig.

**One consequence to know about: a jam never ambers.** Caught, locked and green
are the same number in every jam row — 32/32/32, 29/29/29, 7/7/7 — because
`_pinch` is true from the tick it engages (the 1.0 rad floor is below the
3.4 rad a catch needs, so it is already met by then), so `PINCH_RUN` is
satisfied immediately and the wrap is classified LOCKED before it can be
classified partial. The same anchor with the flag off does amber (19 caught, 16
locked — three partials), and so does the BEAM (13 caught, 3 locked — ten). So a jam
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
                                   # L6 the jam flag is the only thing that changed
                                   #    about an ordinary anchor, and the 1.0 rad arc
                                   #    floor is a real gate both ways: it pinches at
                                   #    0.166 m and 1.10 rad, refuses at 0.90 rad,
                                   #    refuses at 1.00 m, and refuses with the flag off
                                   # L7 G7 asked of the jam, from a THROWN catch
                                   #    with the floor removed: hand shut -0.133 m
                                   #    over 3 s and green 180/180, hand open falls
                                   #    45.3 m on tick 0, and the control - the same
                                   #    state with the catch dropped and the hand
                                   #    still shut - falls the same 45.3 m
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

## THE CRAG — a third level, where the rock decides which throws survive

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\judeb\Downloads\the-whip" -- --level crag
```

The player's brief, in his words: *what I liked about Getting Over It is that
the hammer is fully interactive with the environment so it simulates endless
gameplay, whilst the whip is limited to the beams. I want to expand that.* The
rope has always collided with all of the terrain (`t_a/t_b/t_n`, swept,
outward normals); the traverse simply never put any terrain where the rope
goes, because its beams float in open air over flat floors. The crag puts rock
around and between the anchors, so that each one is a different throw, a
different hang and a different swing.

### Why a corner cannot hold, and what rock can do instead

A rope holds only by a **self-pinch** around something it can go fully round.
The catch engages at `th_part` = 3.4 rad of measured wrap and lets go under
`th_rel` = 1.8, and a rope draped over a terrain corner touches at most
(π − interior angle) of it — **1.57 rad on a 90° lip**, less on anything
blunter. A corner therefore cannot be an anchor, ever, at any radius, and this
level does not try to make one: every convex corner the rope can reach is
**filleted** (`_fillet`), so it is a curve the rope slides round rather than a
point it snags on, and no fillet is in `a_pos`. `crag_gate` C5 proves both
halves — a rope laid over a filleted lip slides clean off with the hand open,
and a rope wound one and a half turns round a fillet, with the hand closing
every ten ticks, engages nothing and measures 0.00 rad.

What rock *can* do is decide **which throws work**: where the tail may fall,
what the tip's arc may pass through, where the body may hang and which way it
may swing. Every feature on the crag is an **ordinary anchor** — `_add_anchor`,
jam 0, r 0.12–0.20, the traverse's own radii — and the only thing that differs
between them is the rock placed around them.

### The vocabulary (a legend, because the level itself carries no captions)

| feature | the rock | what it does to the throw, the hang, the swing |
|---|---|---|
| **HORN** | an anchor standing proud of a ledge on its far side: a shelf whose face is 0.30–0.60 m past the anchor and whose top is 0.60 m under it | the tail has to drop past the horn before it meets the ledge; the body hangs on the near side and the ledge is under the far half of the swing. **The vertical gap is the whole feature**: with the shelf top 0.30 m under the anchor the tail lies on it and nothing catches (0 of 36 strokes); at 0.60 m it drops past, and 9–12 of the same 36 lock |
| **STALACTITE** | an anchor hanging 1.2–1.5 m under a slab of rock (a brow) | reachable only from below and the side — a throw that arcs high hits the ceiling — and a strong pump puts the rope, then the body, into the slab |
| **KNOB** | an anchor on top of a rock: a lump 0.60 m under it | nothing can come at it from below, the tail cannot hang straight down, and the body hangs against the lump's face. **The knob is the betrayer**: 9 catches in 36 strokes and only 3 of them lock — the lump sits exactly where the tail would swing under to cross itself, so most catches are partial and pay out. At 0.30 m under, 9 catches and none held; deeper than 0.60 m, nothing caught at all |
| **WINDOW** | an anchor inside a hood: a bar 0.90 m over it and a bar 0.45 m past it | the rope must go under the one and drop its tail between the anchor and the other — it threads the gap or it does not catch |
| **BRANCH** | an anchor 0.45–0.50 m in front of a rib hanging from above to 0.8 m below it — and not the crag's own wall, which held 0 of 432 strokes | the tail cannot fly past, and the swing has one side |

A knob's lump, a horn's ledge, a stalactite's brow, a window's hood and a
branch's rib are all **islands**: closed loops of terrain in the play plane,
wound solid-inside, that the rope and body collide with like any other rock.
They float, and that is a measurement rather than a style: in a side view a
column that reaches the floor is a wall across the route, and the lash gait
carries the *hand* 1.21 m over the floor (body centre −0.28, hand 0.93 above
it) — a lump whose underside was 0.95 m up stopped the crawl dead at x = −2.9
with the handle pressed against its face. Everything over a floor a body crawls
on clears 1.45 m, and the backdrop draws the pillar the lump is the top of.

### The shape

A gorge that steps down **27 m in nine 3.0 m drops over 59 m of route**, tiers
5.5 m long against the traverse's 10 — it is dense — with a home tier of three
features to warm up on, one feature at every lip, and a run-out to the flag.
The **level contract is the traverse's, unchanged, because it is measured**: an
anchor is catchable from a standstill only at ≤ ~2.4 m over the floor you throw
from and launchable only with > ~3.2 m of air under the arc, so every door sits
2.2 m over the tier it is thrown from and 5.2 m over the one it swings in. The
lash gait cannot climb 20°, so every tier is flat, every drop faces along the
route, and every island top a body can land on is flat and crawled off. There
is no pit: `crag_gate` C7 walks the whole thing with the hand open, spawn to
flag, in 97 s with the out-of-world net never tripping.

| | x | y | r | rock |
|---|---|---|---|---|
| H0 **HORN** | −12.9 | −2.2 | 0.14 | thrown to the LEFT, its ledge toward the wall — the warm-up. This was the wall BRANCH: 0.50 m off the left wall it caught 3 of 216 searched strokes and held none; 1.20 m off it caught none. A wall that runs to the floor leaves the tail no room to swing under and cross, and the branch is the rib |
| H1 **STALACTITE** | −8.3 | −2.2 | 0.12 | a brow 1.2 m over it, over the spawn |
| H2 **WINDOW** | −2.0 | −2.2 | 0.12 | a hood over the home tier: 0.90 m over, 0.45 m past, its far bar 1.5 m clear of the floor |
| D0 **HORN** | 4.4 | −2.2 | 0.14 | lip 3.0; the ledge 0.60 m past and 0.60 m under |
| D1 **STALACTITE** | 9.9 | 0.8 | 0.12 | lip 8.5; a 5 m brow over the second tier |
| D2 **WINDOW** | 15.4 | 3.8 | 0.12 | lip 14.0; hood 0.90 m over, 0.45 m past |
| D3 **BRANCH** | 20.3 | 6.8 | 0.12 | lip 19.5, only 0.8 m past it; a rib 0.50 m past the anchor |
| D4 **KNOB** | 26.4 | 9.8 | 0.14 | lip 25.0; lump 0.60 m under |
| D5 **HORN** | 31.9 | 12.8 | 0.14 | lip 30.5; the ledge only 0.30 m past, 0.60 m under |
| D6 **STALACTITE** | 37.4 | 15.8 | 0.12 | lip 36.0; a brow 1.5 m over it. At 1.0 m it caught at 5–6 rad and betrayed every time (0 of 216 held); at 1.2 m — D1's geometry, which locks on stroke 76 of its grid — it caught 3 of 216 and held none. The basin under a brow is small and the tip is chaotic; 1.5 m is where this one's reappears (stroke 19) |
| D7 **WINDOW** | 42.9 | 18.8 | 0.12 | lip 41.5; hood 0.90 m over, 0.45 m past (it shipped first at 0.80 / 0.38: caught 3 of 36 at 4.27 rad and betrayed all three — a gap the tail cannot swing in is a wall, not difficulty) |
| D8 **BRANCH** | 47.65 | 21.8 | 0.12 | lip 47.0, 0.65 m past it; rib 0.45 m past the anchor |

Own save slot (`user://run_crag.save` — `crag_gate` C3 shows the traverse and
the crag each refuse the other's save and accept their own), own spawn
(−6.5, −1.0), own goal (x 52 on the floor at y 27), own fingerprint (with the
fillets folded in — only when there are any, so the traverse's number does not
move), own camera table (`CRAG_VOLS`, ten volumes, one per tier, the shelf and
zoom of the traverse's), and `world_bottom` derived from the terrain as it is
everywhere else.

### What it cost the sim, and what it did not

- **The rescue depth.** `_collide_point`'s rescue branch lifts a particle found
  on a segment's solid side back onto that segment at *any* depth — right under
  a floor, wrong under a 1 m slab: a tip flying in the air 0.5 m beneath the
  brow is 1.5 m "inside" the brow's top edge, and the rescue put it on top. The
  first build's whole chain crumpled onto the brow's underside inside 30 ticks
  and the body hung off its own jammed handle 2.2 m up. Each segment now has a
  rescue depth `t_deep` — half the distance along −n to the nearest terrain
  behind it, derived in `_finish_terrain` — and INF wherever nothing is behind
  it, which is every segment of the traverse and the lab (`crag_gate` C8), so
  their rescue is the unbounded one they always had.
- **The per-tick cull.** 69 segments and 55 arcs against 26 particles, sixteen
  times a tick, measured 3.1× the traverse's tick. Each particle now lists its
  candidate segments and arcs once a tick, from where it is at the top of the
  tick with `CULL_TICK` = 3.0 m of slack over `CULL_MARGIN`, and the substeps
  walk only those. It cannot change a result — a segment left off the list is
  one the old cull would have skipped on every substep unless the particle
  covered 3 m in a tick, and the fastest thing in the game is the tip at
  85.7 m/s, 1.43 m a tick — and the golden hash and six tapes say it did not.
  Measured alone on the lash gait: **traverse 5.4 ms/tick, crag 8.65 ms/tick**.
- **The backdrop** is paint: `bd_poly` is drawn before the terrain and read by
  nothing. The traverse and the lab leave it empty; the six frames of
  `cam_view`'s door-tape shoot were photographed before and after and are
  byte-identical (md5 equal on all six).
- **Nothing about a catch changed.** `_circle_out` and `_swept_circle` are the
  beam's contact code extracted, not copied, so a fillet cannot drift from a
  beam's contact law; `_body_ground` is the floor's. The default level, the
  lab, the six tapes and the golden hash are unchanged by all of it.

### Reachability, measured

Every feature, thrown at by a body that **crawled** to the standing spot with
the lash gait (from the near end of its tier, or 1.9 m short of the spot as a
second arrival), wound up 120 ticks, and threw `tests/lab_throw.gd`'s grid — 3
leads × 6 stroke angles × 3 stroke lengths × pull, first with the wrap cue
(shut the hand when the arc reads ≥ 2.6 rad) then with the arrival cue — until
one **locked** and survived 55 ticks of holding. "stroke" is how far into the
216 the first lock came: a small number is a big basin. The right-hand column
is what 100 ticks of holding on then did (`crag_shots.gd`): a door hauls the
body off its lip into the air; a home-tier feature holds it with its feet on
the floor; two catches betrayed under the haul, which is the amber mechanic
doing what it does.

| feature | stroke | thrown from | cue | tether | holding on |
|---|---|---|---|---|---|
| H0 HORN (left, by the wall) | 42 | 2.4 m from x -10.50 on the floor at y 0.0 | wrap | 2.14 m | feet dragging on the home floor |
| H1 STALACTITE | 42 | 2.4 m from x -5.89 on the floor at y 0.0 | wrap | 2.18 m | feet dragging on the home floor |
| H2 WINDOW | 55 | 2.4 m from x -4.42 on the floor at y 0.0 | wrap | 2.47 m | feet dragging on the home floor |
| D0 HORN | 19 | 2.0 m from x 2.41 on the floor at y 0.0 | wrap | 1.81 m | hangs in air |
| D1 STALACTITE | 76 | 1.7 m from x 8.20 on the floor at y 3.0 | wrap | 1.58 m | betrayed during the haul, body fell |
| D2 WINDOW | 67 | 2.4 m from x 12.99 on the floor at y 6.0 | wrap | 2.07 m | hangs in air |
| D3 BRANCH (rib) | 19 | 2.0 m from x 18.30 on the floor at y 9.0 | touch | 2.01 m | hangs in air |
| D4 KNOB | 25 (second arrival) | 2.0 m from x 24.42 on the floor at y 12.0 | wrap | 1.57 m | hangs in air |
| D5 HORN | 20 | 2.0 m from x 29.92 on the floor at y 15.0 | wrap | 1.63 m | hangs in air |
| D6 STALACTITE | 19 | 2.0 m from x 35.41 on the floor at y 18.0 | wrap | 1.80 m | held, hauled onto the lip's own fillet (body at x 36.28, y 18.48) |
| D7 WINDOW | 25 | 2.0 m from x 40.91 on the floor at y 21.0 | wrap | 1.74 m | betrayed during the haul, body fell |
| D8 BRANCH (rib) | 24 | 2.0 m from x 45.65 on the floor at y 24.0 | wrap | 1.92 m | hangs in air |

Read the strokes against the traverse: under the same harness the traverse's
own first door D1 locks on strokes 10, 19, 21 and 23 of 36 at one lead, and a
crag horn with its ledge moved out of the way locks on 19, 21 and 23 — the
same strokes. The rock does not change what a throw *is*; it changes which
throws survive.

What did not survive measurement:

- **The rock is not a vocabulary.** The crag was built to test whether terrain
  around an anchor forces a *different throw* — the darts-or-golf question that
  had already retired the jam (same press window, same aim basin as a beam)
  and the crack (one motion covers 87.5% of everything strikeable).
  `tests/route_variety.gd` asks it of a whole level: stand on every reachable
  floor cell, throw the motion grid at every anchor, count how many *distinct
  motions* (cursor paths merged under 50 mm; standing position deliberately not
  a motion, since "same throw, stood elsewhere" is what darts means) cover 90%
  of what can be locked. The traverse: one motion covers 80%, two cover 100%.
  The lab: one covers 100%. **The crag: one covers 75%, two 92%, three 100%** —
  the same shape, and nine of its twelve features share the traverse doors'
  best motion (a0 1.10π, a1 −0.30π, no pull). The instrument reproduces
  `lab_throw`'s station rates to the digit, an anchor lifted 12 m into the air
  gets 0 locks in 1176 throws, the grip-never control locks nothing, and the
  wide grid (224 paths) gives the narrow grid's shape. Brows, hoods, lumps and
  ribs make a feature *harder* — fewer standing cells lock it, the wall branch
  locks from exactly one — but not *different*. The islands prune the basin;
  they do not fork it. That is the third time the vocabulary question has been
  measured and the third time the answer has been one motion: anchor type,
  anchor placement and terrain all decide *where you stand* and *whether it is
  possible*, never *what your hand does*. The crag ships as a harder level,
  which is what the numbers say it is. The one regime no rig has surveyed for
  variety is a throw from a *moving* body mid-swing, which is what the
  traverse's fast line was built for; every survey this week stood still.
  `route_variety.gd` is an overnight instrument (2–4 h per level, sharded),
  not a commit gate; its usage line is in its header.

- **A wall that runs to the floor is not a branch.** An anchor 0.50 m off the
  crag's left wall caught 3 of 216 searched strokes and held none; at 1.20 m
  off it caught none. The rib branches (D3, D8), whose rib stops 0.8 m under
  the anchor, both lock. H0 became a horn.
- **A far-side rib does not change the throw at all.** Six rib geometries on
  D3 (gaps 0.5–2.5 m, rib bottom at the anchor or 0.8 m under it) and the rib
  removed gave *identical* results — 3 caught, 0 locked, 3 betrayed at one
  lead. The strokes that reach a branch never touch its rib; the rib is there
  for the swing, and D3 locks on stroke 19 of the full grid by the arrival cue.
- **A knob is arrival-sensitive.** D4 caught 9 of 36 from a 1.9 m crawl-in and
  0 of 36 from a 3.7 m one on the same tier; the gate's second arrival exists
  because of it, and it locks on stroke 25 from there.
- **Tight is not the same as hard.** A stalactite under 1.0 m of brow and a
  window with 0.38 m past its anchor both *caught* (4–6 rad) and betrayed every
  catch; the tail could not swing under to cross itself. Both were opened up.


```
... -s res://tests/crag_gate.gd [-- quick]   # C1 the shipped level is byte-identical:
                                             #    fingerprint, hash, no arcs, no
                                             #    backdrop, its own camera table
                                             # C2 all 6 tapes still name it; the crag
                                             #    names neither it nor the lab
                                             # C3 own slot; cross-loads refused
                                             # C4 every normal, ground and island,
                                             #    points into the air the loops enclose
                                             #    (derived from t_a/t_b, reversed
                                             #    winding scores 0)
                                             # C5 the fillet is tangent and leaves the
                                             #    normals alone; a laid rope slides off;
                                             #    an arc is never caught
                                             # C6 every feature LOCKS from a searched
                                             #    throw after a crawl-in (minutes)
                                             # C7 walkable end to end, hand open
                                             # C8 rescue depth INF on the shipped level,
                                             #    finite behind every island face
... -s res://tests/crag_shots.gd             # the same searched catches, states written out
... -s res://tests/crag_view.gd -- in=user://crag_shots.dat out=DIR
                                             # photographed through the real _draw (WINDOWED)
```

## Building a level

The Godot editor is the level builder. It already has a polyline with a drag
handle on every point (`Line2D`), a point with a crosshair (`Marker2D`), a
filled shape (`Polygon2D`), grid snapping, undo and a zoom range; what was
missing was a bridge from a scene you draw to the arrays the sim runs on.
`main.gd` has that bridge now (the section headed **SCENE LEVELS**), and the
test of it is the one that matters: open a level in the editor, drag a beam
2 m to the right, save, play it - no code.

```
--path ... -- --level steps          # res://levels/steps.tscn
--path ... -- --level crag.tscn      # the crag, exported to a scene (see below)
```

`lab` and `crag` always mean the builds in `main.gd`; any other name is
`res://levels/<name>.tscn`, and a name with no scene is refused, not silently
played as the traverse. Each scene level owns its own save slot,
`user://run_<name>.save`.

### Drawing one

Duplicate `levels/steps.tscn` (three drops, four anchors, one island - the
smallest complete example) or `levels/crag.tscn`, rename it, open it in the
editor. The scene tree is the schema; node **names** give the roles, node
**types** give the geometry, and every knob is an exported property of one of
the small scripts in `levels/`, so it is typed, has a default, and lives in the
inspector:

| node | what it is | knobs (inspector) |
|---|---|---|
| `Level` (Node2D, root) | the level | `whip_level.gd`: `fillet_ground` 0.35, `fillet_island` 0.10 (m), `hud` (the caption block; empty = a title from the file name) |
| `Ground` (Line2D) | THE one open chain of rock: down the left wall, along the floors, down each face, up the far seal. **The line is the collision** | `whip_terrain.gd`: `fillet` −1 = the level default, 0 = sharp, > 0 = this radius |
| `Islands/…` (Line2D, `closed`) | closed loops of rock: lumps, brows, shelves, hoods, ribs. Same script | as Ground; a `Marker2D` child with `whip_fillet.gd` dragged onto one vertex gives that corner its own radius |
| `Anchors/…` (Marker2D) | one per anchor, in index order | `whip_anchor.gd`: `radius` (m, default 0.12), `jam`, `caption`; the editor draws the beam at size, the jam's collar, the caption |
| `Spawn` (Marker2D) | where the body starts | required |
| `Goal` (Marker2D) | the flag | optional: absent = a bench with no finish, like the lab |
| `Camera/…` (Line2D, 2 points) | optional camera volumes: the two points on a tier's floor, x0 to x1 | `whip_camvol.gd`: `zoom`. **Leave it out** and the table is derived from the floors - see below |
| `Backdrop/…` (Polygon2D) | paint, drawn in order under the terrain | `color` |
| `Art` (Node2D) | optional. **Everything under it renders live, as authored** - a Sprite2D, a textured Polygon2D or Line2D, an AnimatedSprite2D, a ParallaxBackground, particles, a shader material - and the loader reads nothing from it. See **Adding art** | none: it is not read |
| `Anchors/<marker>/…` | children of an anchor's Marker2D render live at the beam (a sprite of it); the marker's own disc does not | as above |

**Units are pixels at 60 px/m** - the scale `_draw` renders at - because the
editor's grid, zoom range and gizmos assume pixel-sized scenes (a 60 m level
authored in metres is 60 units wide, edited at 6000% zoom). The loader divides
by 60 and then **quantises every coordinate to 0.01 m** (radii to 0.001 m).
That is what makes a drag exact: one pixel is 0.016667 m, an odd number, and a
beam dragged 120 px moves exactly 2.00 m rather than 1.9999998 m of float
noise. Set the editor's grid step to **6 px = 0.1 m** (Configure Snap; primary
line every 10 = 1 m) and everything you place is on the metre grid the shipped
levels are written on. The `.tscn` text itself is not the weak link - Godot 4.7
writes reals with shortest-round-trip digits, and `level_fidelity.gd` F4 checks
every value comes back bit-identical - the grid is for the editor's sake.

**The winding rule: the air is on your LEFT as you walk the line.** `t_n` is
derived from segment direction, so a polyline drawn the other way round would
push the rope *into* the rock and park it under the floor. You do not have to
get this right: the loader orients every polyline itself (an island is wound
solid-inside, the ground is closed over the sky and wound air-inside), reverses
one that was drawn backwards, and says so on the console. In the editor the
terrain script draws a short pip on the air side of every segment *as the
loader will wind it* - if a pip points into what you meant as rock, the shape
is not what you think it is. The gate then proves every normal by the
independent air-region method (`crag_gate` C4's, which scores 0 on a reversed
walk), so the loader's rule and the check cannot share a mistake.

**Corners, not tangent points.** The scene stores the corner and the radius; the
loader cuts the fillet with `_fillet` exactly as `_build_crag` does. A tangent
point such as −1.46 + 0.10 is not on the 0.01 grid in float32 and would not
survive a round trip (F4 counts 24 of the crag's 300 post-fillet endpoint
coordinates off the grid), and you move corners, not tangent points. Concave
corners are refused by `_fillet` as always, so "fillet every vertex at 0.35"
on the ground rounds exactly the lips.

**The camera table is derived** from the floors unless you author one: one
volume per horizontal run of the ground ≥ 2 m, each ending **1.0 m before the
lip** (so with `CAM_HYST` 1.5 the shelf steps when the body is 0.5 m past it),
floor y as the shelf, zoom 1.0. That is the rule `CAM_VOLS` and `CRAG_VOLS`
were written to, and `level_fidelity.gd` F3 checks the derivation reproduces
both tables element for element - which is why the crag scene carries no
Camera node. Author one only when a tier needs its own zoom, and read the
camera section's budget first.

### The contract, in numbers you must respect

All measured, none derived by arithmetic; the probes are named in **Probes**
above. `level_gate.gd` prints where every anchor of your level stands against
them.

- **An anchor is catchable from a standstill only ≤ ~2.4 m above the floor you
  throw from.** Every shipped anchor sits at 2.2 m. Higher is a swing-apex
  catch (the traverse's fast line, 4.5 m) or luck (the lab's first JAM HIGH at
  2.9 m: 3 winning strokes in 108).
- **An anchor is launchable only with > ~3.2 m of air under the arc** - you
  hang tether + arm + body below it. Those two contradict each other on one
  floor, which is why every level is a step: a lip, an anchor 1.4 m past it,
  a 3.0 m drop. 2.2 m over the tier you throw from, 5.2 m over the one you
  swing into.
- **The lash gait cannot climb 20°** (0.42 m/s on the flat, nothing on a
  slope), so every tier is flat, every drop faces along the route, and every
  island top a body can land on is flat and can be crawled off. Falling costs
  ground and time; it must never cost the run. The gate walks the whole level
  with the hand open to prove it (W).
- **6.5 m between anchors keeps them out of each other's reach** (the rope
  lives inside a 6.40 m circle round the body). The lab's rule, for learning
  one anchor at a time; the crag packs its home tier to 4.6 m on purpose. The
  gate reports the nearest neighbour of every anchor and flags anything under
  6.5 m, informationally.
- **Rock over a floor a body crawls on must clear 1.45 m**: the gait carries
  the hand 1.21 m over the floor, and a lump whose underside was 0.95 m up
  stopped the crawl dead.
- **A corner cannot be an anchor**, at any radius (a rope over a 90° lip
  touches 1.57 rad of it, against `th_part` 3.4), and a fillet is a corner the
  rope slides off instead of snagging. Only the Marker2Ds under `Anchors` can
  hold. The gate checks no fillet overlaps an anchor (A).

**The art rule: the Line2D is the collision; anything painted behind it is free
and cannot move it.** `Backdrop` polygons are read by `_draw` and nothing else
- not `_collide`, not the wraps, not the camera, not the fingerprint. Draw the
cliff, the pillar under a lump, the curtain over a rib, as paint; the rope
meets the line.

### The one command

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\judeb\Downloads\the-whip" -s res://tests/level_gate.gd -- level=steps
```

`level=<name>`, `level=<x>.tscn`, or `level=lab` / `level=crag` for the
hardcoded ones. **F** the fingerprint is not the traverse's (the tapes would
replay into it), the lab's or the crag's · **T** every committed tape still
names the shipped level and none names yours · **N** every normal into the air,
reversed winding scores 0 · **A** an arc is never an anchor · **D** the rescue
depth is finite behind every island face · **S** your own save slot, a
traverse save refused, your own accepted · **W** walkable with the hand open,
spawn to flag · **R** every anchor **locks** from a searched throw after a
crawl-in (`crag_gate` C6's search; minutes, and `quick` skips it). It also
prints the camera table it derived and the contract table above. The same
checks are what `lab_gate` and `crag_gate` run - they call the same code,
`tests/level_lib.gd` - plus their own.

Two more tools. `tests/level_export.gd -- level=crag out=res://levels/x.tscn`
writes a hardcoded level out in the schema, and `tests/level_fidelity.gd` is
the standing proof that a scene is the same world as the code (below).
`crag_shots.gd -- level=<name>` and `crag_view.gd -- level=<name>` photograph
searched catches on any level.

### The worked example: the crag as a scene

`levels/crag.tscn` is the crag of `_build_crag`, exported by `level_export.gd`:
22 ground points, 12 islands named for their features (`D4_lump`, `D2_hood`,
`D8_rib`…), 12 anchors named for the README's table (`H0_HORN` …
`D8_BRANCH`), 29 backdrop polygons, `fillet_ground` 0.35, `fillet_island` 0.10,
no per-vertex overrides and no Camera node. Loaded back through the scene
loader it fingerprints **1132405890178884573 - the hardcoded crag's own
number** - and `level_fidelity.gd` F1 requires every element of every array to
be bit-identical: `t_a`, `t_b`, `t_n`, the boxes, the rescue depths, the 60
arcs' centres, radii and exposed angles, the 12 anchors, spawn, goal,
`world_bottom`, the 10 camera volumes and all 29 polygons. It is; and the
exporter round-trips the lab the same way (jam flags, captions and its
authored 5-volume table included). So `--level crag.tscn` is the crag: same
fingerprint, same slot (`user://run_crag.save`), a run started in one resumes
in the other. Open it in the editor to see how a horn, a knob, a window and a
branch are made of rock around an ordinary anchor.

The traverse stays in code. Its tapes and the player's run are keyed to its
fingerprint, which hashes segments *in order*, and its left wall is appended
after the floor polyline; an export would put the wall first (one chain) and
move the number. Nothing is lost by that: it is the level that must not move.

### The second example: THE STEPS

`levels/steps.tscn`, drawn by hand in the schema: a home tier, three 3.0 m
drops, four anchors of four kinds - **BEAM** (r 0.22 at 2.2 m, the school's
first beam), **JAM** (r 0.11, the jam flag, the door over the first lip),
**KNOB** (r 0.14 on a lump 0.60 m under it - D4's rock, moved), **THIN BEAM**
(r 0.11, a traverse door) - the flag on the bottom tier. Fingerprint
3144857459313072037, slot `user://run_steps.save`, 13 segments, 7 arcs (three
lips at 0.35, four lump corners at 0.10), a derived table of four volumes, and
it walks spawn to flag with the hand open in 70.5 s. The gate's R, every
anchor locked from a crawled-to standing spot (2 m 40 s for the whole gate):

| anchor | stroke | thrown from | tether | holding on 100 ticks |
|---|---|---|---|---|
| A0 BEAM | 67 | 2.4 m from x −4.42 on the floor at y 0 | 1.83 m | feet on the home floor |
| A1 JAM | 8 | 2.0 m from x 5.42 on the floor at y 0 (pull) | 1.54 m | hauled off the lip |
| A2 KNOB | 31 | 2.0 m from x 13.41 on the floor at y 3 | 1.60 m | **betrayed during the haul** - the knob does on the steps what D4 does on the crag: the lump is where the tail would cross itself |
| A3 THIN BEAM | 19 | 2.0 m from x 21.43 on the floor at y 6 | 1.81 m | hangs in air |

Both levels photographed through the real `_draw` with `crag_shots.gd` /
`crag_view.gd -- level=…`: the crag scene's D0 HORN green on stroke 19 (as the
hardcoded crag's table says), the steps' KNOB green at the catch (θ 7.26 rad)
and amber, paying out, 100 ticks later (θ 3.16).

### Adding art

Until this section existed nothing with a texture could appear. `_build_scene`
instantiates the level, `_level_read` copies the collision into the sim's
arrays, and the instance is **freed** - so a Sprite2D, a textured Polygon2D, a
ParallaxBackground, anything an artist would make, was silently ignored. The
fix follows the audio's contract to the letter (see "Sound is
instrumentation"): art exists only in a real windowed session, it feeds nothing
back, and a probe never sees it. `tests/art_gate.gd` A1-A7 is the proof.

**How it works.** In `_ready`, behind the same `DisplayServer.get_name() !=
"headless"` test that decides whether a session has a screen, `main.gd`'s
`_art_build` instantiates the level scene a **second** time and adds that
instance as a child that draws **behind** the game's own `_draw`
(`show_behind_parent`: same canvas, same z-index, the child's commands first
- so it scrolls with the Camera2D and sits under the HUD layer with no
transform anywhere; the scene is authored at 60 px/m, which is `_draw`'s own
scale). A second instance and not the first kept alive, because the first is
read inside `setup_sim`, which every headless probe runs and which runs before
`_ready`; keeping it would hand every probe a node graph, and the read path
would no longer be the lines it was. As it stands `_build_scene` and
`_level_read` did not change, and `level_fidelity` F1 (the crag round-trips to
1132405890178884573 with every array identical) and `art_gate` A3 prove it
rather than argue it. The cost is one instantiate at boot: **6.0 ms** on
`steps_art`, 0.002 ms on a built-in level.

**What renders and what does not.** In the live instance everything the sim
already represents is removed - `Ground`, `Islands`, `Spawn`, `Goal`,
`Camera`, `Backdrop`, and anything else at the root the schema does not name -
so nothing is drawn twice and the `@tool` helper drawings (the anchor's disc,
the terrain's air-side pips) never reach the game. Two things stay:

- **`Art` (Node2D), whole.** Everything under it is drawn by Godot as
  authored: Sprite2D, Polygon2D with a texture (`texture_repeat` on for a
  tile), Line2D with a texture (`texture_mode` TILE), AnimatedSprite2D,
  ParallaxBackground with ParallaxLayers, CPUParticles2D, a Node2D with a
  shader material. The loader reads **nothing** from it - not a coordinate,
  not a colour - so it cannot reach the fingerprint, the hash or any gate.
  Keep `z_index` at 0 inside it: the layer draws behind `_draw` at the same
  z, and a positive z_index would put art over the rope and the ring.
- **`Anchors`, with each marker's own drawing hidden** (`self_modulate`,
  which stops at the node and does not reach its children). A Sprite2D
  parented to an anchor's Marker2D draws at the beam; the marker's disc does
  not; the ring is drawn over both by `_draw`.

**The one-line rule: the Line2D is the collision; Art is free.**

**The greybox toggle.** Once a level has art, the grey collision band, the
fillet arcs, the flat backdrop and the anchor discs are noise over it. The
root's `whip_level.gd` has `greybox` (default `true`). At `false`, `_draw`
skips the **WORLD** - terrain lines, arcs, backdrop polygons, anchor discs -
and keeps the **INSTRUMENTATION**: the wrap ring and its pulses, the jam
collar, the caption, the goal flag, the rope and the load along it, the
ground contacts, the tip, the body, the hand, the crosshair, the working-zone
ring. `_draw` is written as those two named blocks. An anchor's ring draws at
the anchor whether or not its disc does - the ring is the game's honest
instrument, it has been fixed for lying twice, and art does not get to hide
it. `greybox` is read off the live instance by `_art_build`, never by the
loader, so it cannot touch the fingerprint; the default leaves every existing
level and every rendered frame byte-identical - `art_gate` A4 takes
`tests/art_frame.gd`'s picture of `steps` and of `crag.tscn` and requires the
md5 the same command printed on `main.gd` before the layer existed
(`fc7de3e8a733c941bcc33ca41d335f37`, `9707c2f48d53452be10fffb3726cb0dc`).

**Parallax works under the game's camera.** ParallaxBackground is a
CanvasLayer that listens to the Camera2D of its viewport, and the art layer
is in that viewport. Measured (`art_gate` A6): the camera moved +600 px, the
world moved -600 on screen, the `Far` layer (`motion_scale` 0.3) moved
-180.0 px and the `Mid` layer (0.6) -360.0 - read off the ParallaxLayer nodes,
and again off the pixels, where the far skyline's peak went from x 985 to
805. **Where a layer's content lands on screen** is the part nobody can
derive from Godot's docs, so here it is, measured: a ParallaxLayer at
`motion_scale` *s* puts its own origin at screen position
`s * ((800, 450) - camera_px)`, x wrapped by `motion_mirroring`, where
`camera_px` is the Camera2D's position in pixels. At spawn on `steps` the
camera sits at about (-401, 132), so a layer at *s* = 0.15 has its origin at
screen (180, 87) - and a moon authored at (0, -260) "in screen pixels" is off
the top of the frame (measured: zero pixels). Authored at (20, -17) it sits at
(600, 150) and moves -90 px for +600 px of camera, which is 0.15x. A layer at
motion_scale 0 is glued to the screen. Set `motion_mirroring` to the scaled
texture width to tile it. The camera's spawn position is level-specific; the
quickest way to place a layer is to run the level, note where the camera is
(`cam_st` in a probe, or just look), and put the origin where you want it.

**The placeholder pack and the worked example.** `levels/art/` holds three
generated PNGs - `rock.png` (256 x 256, tileable), `beam.png` (96 x 64, an
iron plate with a wooden bar), `cliff.png` (1024 x 384, a periodic skyline
with one peak) - made by `tests/art_pack.gd` from an integer hash, no RNG, so
the bytes regenerate identically anywhere. They are placeholders; their one
virtue is that each is a colour nothing else in the frame has, which is what
`art_gate` A5 samples. Their `.import` sidecars are committed; a fresh clone
needs one `--headless --import` before a scene can load them.

**Practicalities, each one measured by dropping a PNG in and watching:**

- **PNGs can live anywhere under `res://`**; `levels/art/` is a convention,
  not a requirement. The scene references them by path.
- **A newly added PNG needs an import pass before it will load** - either
  open the project in the editor once, or run
  `--headless --path . --import`. Skip it and the console prints the engine's
  `No loader found for resource ... (expected type: Texture2D)` and the
  sprite is instantiated with no texture while the rest of the level renders.
  It is survivable and it is Godot's message, not ours.
- **Pixel art needs `texture_filter` = Nearest** on the node (or in the import
  preset). The default is linear, and a 15 px checker blends at every cell
  edge.
- **Textures over 16384 px on a side render as a black slab.** The engine
  imports them and then refuses at load with `p_width > 16384`; there is no
  game-side message.
- **Dress `crag.tscn`, not `--level crag`.** The built-in names (`lab`,
  `crag`, and the traverse) never build an art layer - they have no scene. A
  copy of `levels/crag.tscn` with an Art node is the crag with art on it,
  same fingerprint.
- **Three rules are enforced, not advised** (`art_gate` A8-A10). A node under
  `Ground` or an island that is not a fillet marker refuses the level by name
  and says where art goes - before this, a sprite parented to Ground by habit
  was silently read as a fillet of radius 0 and moved the collision
  fingerprint. A positive `z_index` under Art, or a CanvasLayer at layer 0
  or above, is clamped on the console: nothing under Art may draw over the
  rope, the body, the rings or the HUD. And `greybox = false` on a level with
  no Art node keeps the grey world on, because a level where the only sign
  of a floor is where the rope lies is not playable. A root node the schema
  does not name (a `Props`, say) is neither collision nor picture: it is
  dropped with a console line naming it.
`levels/steps_art.tscn` is `steps.tscn` with `greybox = false` and an `Art`
node that uses all of it: a textured Line2D along the ground edge (its points
offset 8 px into the rock, because a Line2D is centred on its points and the
collision line is the band's top edge), a textured Polygon2D face under the
floors, a Sprite2D child on `A0_BEAM` and `A3_THIN_BEAM`, and a
ParallaxBackground with two layers. Its collision is `steps`: fingerprint
**3144857459313072037**, every array identical (A3), so the gate's verdict
on `steps` carries over, and a `steps` save or snapshot restores into it.

```
... -s res://tests/art_gate.gd                  # A1 A2 A3, headless
... -s res://tests/art_gate.gd -- out=DIR       # A1..A7, windowed, frames into DIR
... -s res://tests/art_frame.gd -- level=steps  # one frame and its md5, windowed
```

A1 headless: 0 art nodes on a `steps_art` probe (the scene authors 9 under
Art and 2 under anchors) · A2 the hash of 900 ticks on `steps_art` with the
layer forced on equals the hash with it off equals plain `steps`
(3057385326108183634), and the traverse's golden 2762505307938286422 stands ·
A3 the fingerprint and 15 per-element comparisons · A4 the two md5s · A5
pixels named and sampled: rock under the floor, the edge band, the sprite's
bar at the anchor, its plate, the body over it all, the clear colour where
nothing is authored, the skyline's peak and clear sky 20 px above it, and on
a searched catch (stroke 19 of the 108 grid) the **green ring drawn over the
sprite's plate** with the taut rope beside it · A6 above · A7 a windowed
frame with the layer shown against hidden: **+0.02 ms CPU, +0.17 ms GPU**
(0.14 + 0.63 ms against 0.12 + 0.46, vsync off, median of 80).

What an artist still cannot do: put art anywhere but under `Art` or under an
anchor's marker (a sprite parented to `Ground` is removed with it); draw over
the instruments (the rope, the ring, the body are always on top - by design);
change the HUD, the flag, the ring's colours or the caption font from the
scene; animate anything from the sim's state (art reads nothing, so a beam
cannot flex under load - that would be a new visual twin in `_draw`, by the
audio's parity rule, not a scene node); make the backdrop polygons of the
greybox appear together with art (at `greybox = false` they are off; paint
them as Polygon2Ds under `Art` instead); or see the art in the editor at the
same time as the physics - the editor shows the picture, `level_gate` shows
the reach.

### What you cannot yet do from the editor

- See the physics. The editor draws the rock, the beams at size and the air
  pips; whether a throw can reach a beam is what `level_gate` R measures, and
  only it. Run the gate.
- Make a new *kind* of anchor. An anchor is a radius, a jam flag and a caption;
  a horn, a knob, a window are rock placed around one. That is the finding of
  the crag, not a limitation of the schema.
- Edit the traverse (above), or re-record a tape: the tapes are the
  traverse's, and a scene level has none. `--record` works on any level.
- Move a vertex without moving the fingerprint. Every edit is a new world:
  the run under `user://run_<name>.save` is refused on the next boot and the
  next autosave overwrites it. That is the same rule the hardcoded levels live
  under; the editor just makes edits cheap.
- Keep the `.uid` files out of the tree: the editor generates one beside each
  script in `levels/` on first open. Commit them.

## Test gates, and the instruments that are not gates

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
must all produce one hash. Run it alone: its scratch file is the fixed path
`user://save_test.save`, so a second copy writing it mid-run produces a false
"resumed from disk diverged".

The whole set, each one a single command of the shape above, and every one
must pass before a commit:

| gate | must print | what it holds |
|---|---|---|
| `hashrun.gd` | `hash 2762505307938286422` | the golden session, the number three other tests carry |
| `tape_verify.gd` | `PASS  6 tapes, 7707 ticks` | the game still does what it did yesterday |
| `sim_test.gd` | `PASS` | G1–G7 above |
| `save_test.gd` | `PASS` | snapshot and resume are bit-identical |
| `bb_det.gd` | `PASS` | G2 asked of the body-against-beam path, which the corpus never exercises |
| `cam_gate.gd` | `PASS  camera gate` | C1–C5, see The camera |
| `aud_gate.gd` | `PASS` | A1–A6, see Sound |
| `lab_gate.gd` | `PASS  lab gates L1-L7` | the bench exists without touching the traverse |
| `crag_gate.gd` | `PASS  crag gates C1-C8` | the crag exists without touching either, its rock is wound the right way, its arcs cannot hold, every feature is reached and the whole thing is walked (C6 takes minutes; `-- quick` skips it) |
| `level_fidelity.gd` | `PASS  level fidelity F1-F5` | `levels/crag.tscn` loaded through the scene loader is the hardcoded crag to the bit (fingerprint 1132405890178884573, every array), the exporter round-trips the crag and the lab, the derived camera table is the authored one, and the loader refuses bad scenes by name |
| `level_gate.gd -- level=<name>` | `PASS  level gate <name>: F T N A D S W R` | any level, drawn or hardcoded: see Building a level (R takes minutes; `quick` skips it) |
| `mark_rt.gd` | `PASS  mark_rt` | the recorder and its marker do not lie — and no test writes the player's slot |
| `mark_kind.gd` | `PASS  mark_kind` | F and G latch different kinds, and only under `--record` |
| `art_gate.gd` | `PASS  art is a picture` | A1-A7 headless (A1-A3) or windowed (all): absent headless, inert, the same world, drawn under the instruments; see Adding art |

Every test that puts `main.gd` in the tree sets its scratch `save_path`
**after** `setup_sim()`, because `setup_sim()` re-derives the slot from the
level ("the level owns its slot"), and a redirect made before it is silently
undone. Two gates got that order wrong for a week and one of them wrote the
player's `run.save` on every run; `mark_rt.gd` R7 now asserts the redirect
survived.

Then the instruments. None of these passes or fails; each reads a number off a
recorded tape, and each exists because a number was once repeated to the
player that had not been checked against his own play:

| instrument | reads |
|---|---|
| `ring_census.gd -- takes/x.tape` | of the locks that carried the player, how many the ring ever drew green |
| `ring_score.gd -- takes/x.tape tapes/...` | a candidate ring predicate against the one oracle that needs no judgement: did the wrap survive with the hand never opening |
| `grip_census.gd -- takes/x.tape` | the grip byte: was the hand opened, or did the click slip |
| `hang_census.gd -- takes/x.tape` | how long every lock lasted and how each one ended |
| `mark_look.gd -- takes/x.tape` | the full lock state either side of every F/G stamp, and which clause of the catch refused |

**A probe on a synthetic stroke is not evidence about play.** A bot rig reported
that every hang is temporary — 40 of 41 lost the wrap inside 5 s. On the
player's own recorded session (`takes/bug1.tape`, 22757 ticks) 22 of 25 locks
ended because his hand opened, the longest at 15.17 s, and betrayal was about
12% of locks. A bot throws and then holds a synthetic cursor policy; a player
keeps working the hand. The bot was wrong and the player was right, and the
number had already been said to him. Check against the recorded human session
before repeating a number, and if there is no recorded session, record one
first.

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

The camera costs a few microseconds a tick — **4.88 us** on the last
`cam_ship.gd` run, law plus cursor mapping, and 3.79 on the one before; it is a
timing number and it drifts — three hundredths of a percent of a 16.7 ms frame,
and a tenth of a percent of what one simulation tick already spends.

## Sound is instrumentation, not polish

A real whip is learned by ear, because the tip outruns the eye. This game is
about reading a rope you can only partly see, so its sound is an instrument:
**it renders the past and the present, and never the future.** A cue that told
you a wrap *would* hold would be the same defect as a trajectory ghost.

Everything is generated in code, as the greybox has no asset pipeline. Seeded
RNG builds the waveforms at startup; **no RNG ever reaches the simulation.**

Every curve is fitted to measured data, not guessed — the distributions came
from a probe that replayed the tape corpus (7679 ticks) and reported each
driver's spread. That probe was not kept; the numbers it produced are written
into `main.gd` above the audio constants, which is where they are read from,
and `aud_gate` A5 re-reads the load range on every run. Two of them
contradicted the obvious guess:

- **The bang samples the rising edge, not the peak.** The tip reaches 85.7 m/s
  (3.57x the crack threshold), but the crack fires on the *first* tick past the
  threshold and then waits out a 0.3 s cooldown, so the overshoot *at the bang*
  is only 1.00–2.42x (p50 1.19). A loudness ramp built to 3.57 would have put
  the median crack 8% of the way up it.
- **The load is the arm's, not the pendulum's.** The load voice first rendered
  a rigid-pendulum estimate from the body's kinematics, T = M(v²/L + g cos),
  which over the corpus ran 45.9–232.1 N and never fell below 45.9 N while a
  wrap was engaged — so the hum had a floor and "a wrap you are on is never
  unloaded" was written here. Both were properties of the estimate. The body
  in this sim hangs on an *arm* (`SPRING_K` 340 capped at `F_MAX` 320, plus
  the one-sided tether at `arm_max`), and the rope carries whatever the arm
  delivers. The voice now renders that force — `av_arm`, the spring plus the
  tether's projection impulse summed over the tick's substeps — and on the
  player's own session (`takes/bug1.tape`, 3999 engaged ticks) it reads min
  0.2, p50 43.8, p90 320.0, p95 320.0, p99 594.7, max 3163 N against the
  estimate's p50 79.7, p95 260.3, max 1835 N; per engaged episode the peak is
  p50 407 N, p95 2264 N. The p90 is `F_MAX` exactly — the spring saturates
  there and everything above it is the tether's yank, the catch and the
  fall-arrest — so the ramp tops at 320 N (`LOAD_HI`; the air ramp's rule,
  p90 at the top) and its floor is 0 (`LOAD_LO`), because a wrap engaged with
  the feet on the floor carries 0.2 N and the hum now says so. The sim did
  not move: `aud_gate` A2 still hashes `2762505307938286422` with the pass
  forced on, because `av_arm` is derived from a finished substep, feeds
  nothing back, and sits in `SNAP_SKIP`.

**Every voice has a visual twin driven by the same number on the same tick**, so
a deaf player reads the same instrument rather than a worse one:

| voice | what it renders (present state) | visual twin |
|---|---|---|
| air whoosh | tip speed, 2–30 m/s | halo at the tip, same ramp |
| load hum | newtons through the arm into the wrap, 0–320 N | the loaded leg of the rope glows |
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
reasoning about it, and the sim still hashes `2762505307938286422`. The
waveform, distribution, trace and photograph scripts that were run while the
sound was built were scratch and were not committed; `aud_gate.gd` is the only
audio test in the tree.

## One-to-beam is fundamental, and it was measured, not assumed

The developer put it exactly: the hammer in Getting Over It is one stroke
against a board made of *everything*; the whip is one stroke against a board
made of *posts*. Terrain around a post changes the shot, it does not change
what the whip can touch. Is there a second interaction with the world that is
not holding?

Thirteen designs from seven independent angles were built as feasibility
probes and then attacked by two skeptics each - one on the physics (does it
survive what this sim has already shown to be dead), one on the design (what
does the *hand* do that it cannot today). **Zero survived both.** Three
survived the physics and died on the design; ten died on both. The angles:
things the whip wraps and then *moves* (a trapeze, a trolley on a rail); the
world *reading* the load a wrap carries (a rotten beam, a peg that tears out);
the rope as a *path* (a redirect post, the loaded line bending over ledges);
the handle as a *stick* that pushes like the hammer (a plant, a brace); the
world with a *clock* (a hung log, a rotating wheel); the whip *removing* things
(fatigue, a saw, a brittle beam).

They died on three walls, and the walls are now measured rather than argued:

- **The hold's load is not a dial the player owns.** `_wrap_tension()` is a
  pendulum estimate from the body's kinematics, not the load; the load the
  rope actually carries is set by the arm tether's hard stop, and it is
  dominated by *transients* - the catch yank and the fall-arrest, not the
  pump. Over 2668 locked airborne ticks of the player's own session the peak
  load reads p50 344 N, p95 1596 N, max 2255 N, and a beam rated anywhere
  from 120 to 320 N breaks on 20-21 of 25 episodes. Any world element that
  responds to "how hard you pull" is a coin, and it fires on arrival, not on
  anything the hand chose to do. That kills the whole *force* family and the
  *subtraction* family with it.
- **A free tail cannot follow a moving anchor.** There is no rope-on-rope in
  this sim, so a wrap is held on by the pin and the self-crossing, not by the
  tail's own tension. Accelerate the anchor - a trapeze at 3.7 m/s, a wheel
  rim - and the free tail winds the other way and the measured arc falls
  through `th_part` inside ten ticks, with the hand shut and the wrapped
  window welded in place. Only an anchor drifting slowly *away* from the body
  (under ~0.5 m/s, load side leading) keeps a thrown lock. That kills the
  *dynamics* family and the *time* family: what survives is a conveyor, not a
  ride.
- **Anything the rope wraps that it did not throw at holds with the hand
  open.** A redirect post the loaded line winds itself onto is the hourglass
  again: a non-engaged anchor keeps `anchor_mu`, so the standing part grips it
  whatever the hand does. And the *handle* pushing into rock already lifts the
  body 0.63-1.29 m with the hand open (a latent exploit nobody uses: 351
  planted ticks in the recorded session, 0 of them pushing) - a haft only
  makes it a walking stick. That kills the *topology* family and the *handle*
  family.

And every one of the thirteen, on the design lens, reduced to the same hand:
throw, shut inside `GRIP_WINDOW`, hold, pump, open. The movers changed *when*.
The ratings changed *how much*. The pegs changed what the *world* did to a
swing the hand already makes. None changed what the hand does. The three that
survived the physics - a hung log, a fatiguing beam, a brittle beam - are the
lab's THIN BEAM row in three costumes: same verb, less margin.

**So the whip is one motion, and that is the game.** So is the hammer. Its
depth was never a repertoire of swings; it was a mountain that offered a
thousand *places* to apply one swing, each with different consequences, and
the player's creativity was in choosing a line. The whip's board is the anchor
graph. The traverse is a corridor - one line. So is the crag. Where
approach-creativity lives for a one-motion tool is a level with *branching
routes*: three ways up, each a different anchor sequence with a different
risk, none of them the "right" one. That is level design, not mechanism, and
`tests/route_variety.gd` already measures it - and already found, on the
traverse, a cold catch on the fast line from the tier *behind* it that the
level's own design assumed impossible. The board has more lines than were
drawn on it.

Salvage from the panel that is *not* a verb but is worth keeping:

- A world clock as level furniture - an anchor on a deterministic path, as a
  timing gate on the existing verb - is honest and assist-free. Like the jam,
  it is furniture, and it says so.
- Rock within reach of a hanging body is a swing *limiter*, not an amplifier:
  a pump reaches 179.8 deg in open air and 84.7 deg with a wall 1.0 m off.
  Useful for the crag's hang geometry.
- The loaded line is drawn bending over ledges and then ignored by the tether
  (176 deg of deflection moves the body 2 cm). A path-aware tether would be an
  honesty fix for crag hangs, not a mechanic.

Three things the panel found that are bugs, filed here and deliberately not
fixed in the same breath, because each changes feel and breaks the tapes and
that decision belongs to the developer. Two of them have since been fixed, on
the developer's call, and the measurements are beside them:

1. **The payout ratchet was not a ratchet.** `PAYOUT_TICKS` (15) governed
   only the *first* segment of a betrayal: `_advance_pin` never reset
   `a_paytick[k]`, so every later segment paid on consecutive ticks. The "one
   segment per quarter second, audibly" this file describes did not exist -
   it was one quarter-second, then one per tick until the whip ran off its
   end. Measured on a real thrown lock: pin 19 to 24 in 5 ticks. **Fixed:**
   `_advance_pin` resets the timer per segment, and a fresh catch starts a
   fresh timer (2 of the 30 catches on `takes/bug1.tape` had engaged carrying
   a stale one, which would have paid on their first loaded tick). Measured
   on searched throws at the r 0.22 and r 0.11 beams: 15.0 ticks per segment,
   4.00 segments/s. A pin at 23 now takes 15 ticks from its first segment to
   sliding off where it took 1; the pin-20 rig, which paid four segments in
   4 ticks and slid off, paid two a quarter second apart and unwound at tick
   16. With the last advancing pin at 23, a partial pinned at index 13 has
   at most 165 ticks (2.75 s) of loaded betrayal, at 17 105 ticks (1.75 s),
   at 21 45 ticks (0.75 s). The red ratchet pulse and the rasp already fired
   once per segment; at one segment per tick they merged into a buzz and one
   glow, and a quarter second apart they are countable (`aud_gate` A3: 12
   audible events, 12 twinned, unchanged). Only `betray.tape` carried
   a payout and it was re-recorded (797 → 825 ticks, census unchanged: catch
   1 lock 1 pay 2 slide 1); the other five and the golden hash did not move.
2. **The handle can push into rock with the hand open** and lift the body
   0.63-1.29 m. `push_cap = 0` closes it at ~6% of crawl speed. Not fixed.
3. **The audio rendered a number that was not the load.** The tension voice
   was driven by the pendulum estimate; the true wrap load is the tether's.
   **Fixed:** the voice renders `av_arm`, the force the body puts through the
   arm - see *Sound is instrumentation* for the measured range. The hash did
   not move; the meter costs a vector add per tether projection and one
   length per substep.

## Design contracts (do not "improve" these away)

- No RNG in the sim; bit-identical replays on the same build.
- The save IS the run: one slot, continuously overwritten, no rewind. Do not
  add a second slot, a checkpoint, a "load last" or a confirm-on-restart. The
  absence is the rule, and it is the reason no rule is needed.
- No assists: no tip magnetism, no auto-taut, no input smoothing beyond the
  constant arm spring, no trajectory prediction, no slow-mo. **One named
  exception:** a JAM anchor (`a_jam`, lab only) supplies the self-crossing the
  player would otherwise have to make. It is a property of a marked anchor, not
  of the whip — it cannot follow you around, it wears its own collar, and it
  obeys every other rule, grip included. An assist you can see and walk away
  from is a different animal to one that rides along with you.
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
- The capstan pin — the rope's material point nailed at the anchor from the
  tick a catch engages (θ ≥ `th_part`, or a self-crossing `_pinch` finds) — is
  the documented stand-in for rope self-pinch: the pressure-test showed a bare
  tapered tail cannot hold a body by capstan friction alone. LOCKED is decided
  by `_pinch` over `PINCH_RUN` ticks, never by an angle.
- **Green means exactly `a_locked == 1`.** The ring, the verdict sound and the
  pulse share `_holds()`, and `_holds()` has no second clause. The last one —
  three quarters of a turn of tail past the pin — was scored against recorded
  play and hid 57.5% of the locks that really held while keeping greens that
  survived less often than the ones it threw away. Do not add a clause to the
  ring without `ring_score.gd` saying it scores better.
