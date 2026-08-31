# THE WHIP — greybox demo

A playable greybox of the whip-locomotion concept: a fully-simulated tapered
verlet chain is your only tool and only means of movement. No engine physics,
no RNG, no assists.

## Run it

Open the project in Godot 4.7 and press F5, or from a terminal:

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\judeb\Downloads\the-whip"
```

## Controls

| Input | Action |
|---|---|
| Mouse | Move the handle (clamped to a reach circle around the body) |
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

## The traverse (~75 m, two tiers)

**Upper tier** — five fat beams 2.5 m up: learn to throw, wrap, hang, pump,
crack. It ends at a drop.

**Lower tier** — after the drop, alternating beams:
- **LOW beams** (2.5 m over the floor) can always be caught from a standstill.
  That is the safety contract: no fall is ever terminal, you just lose the
  height and momentum you had earned.
- **HIGH beams** (5.2 m over the floor) are out of reach from the ground.
  They are the skill ceiling — catchable only from the apex of a swing, and
  the only place you get a real hanging arc instead of a feet-dragging pump.

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

## Test gates

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\judeb\Downloads\the-whip" -s res://tests/sim_test.gd
```

G1 stability · G2 bit-determinism · G3 wave amplification ≥3× (the crack)
· G4 full wrap locks and holds · G5 partial wrap catches then betrays
· G6 no free lift from mouse waggle · G7 grip matters.

```
... -s res://tests/save_test.gd
```

Snapshot and resume are bit-identical. Four states, found by replaying the
committed tapes rather than by hand-laying a rig: mid-air, mid-wrap,
mid-betrayal, and coiled past the lock threshold. At each, an uninterrupted run,
a run that was snapshotted, that snapshot restored from memory, and that
snapshot written to a file and loaded into a sim that never played those ticks
must all produce one hash.

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
- The capstan pin (material point pinned at TH_FULL) is the documented
  stand-in for rope self-pinch — the pressure-test showed a bare tapered
  tail cannot hold a body by capstan friction alone.
