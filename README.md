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
| R | Restart |
| Esc | Quit |

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

## Test gates

```
"C:\Users\judeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\judeb\Downloads\the-whip" -s res://tests/sim_test.gd
```

G1 stability · G2 bit-determinism · G3 wave amplification ≥3× (the crack)
· G4 full wrap locks and holds · G5 partial wrap catches then betrays
· G6 no free lift from mouse waggle.

## Design contracts (do not "improve" these away)

- No RNG in the sim; bit-identical replays on the same build.
- No assists: no tip magnetism, no auto-taut, no input smoothing beyond the
  constant arm spring, no trajectory prediction, no slow-mo.
- Rope never pushes. Arm forces are internal pairs (no waggle-flight).
- Dissipation only via contact friction and taut-catch yanks.
- Wrap angle is measured from live geometry every tick, never event-counted.
- The capstan pin (material point pinned at TH_FULL) is the documented
  stand-in for rope self-pinch — the pressure-test showed a bare tapered
  tail cannot hold a body by capstan friction alone.
