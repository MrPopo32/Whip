#!/usr/bin/env python3
"""THE CLIMB, AS NUMBERS. Writes res://levels/climb.tscn and levels/climb.plan.json.

    python tests/gen_climb.py             # write the scene and the plan, print the stage table
    python tests/gen_climb.py --check     # print the table, write nothing

Everything below is in METRES, y DOWN (a bigger y is lower), x along the route.
The scene is written in pixels at 60 px/m in the format levels/steps.tscn uses,
and main.gd's loader divides by 60 and quantises to 0.01 m, so keep every
number on the 0.01 grid. Edit the STAGES table and rerun, or open the scene in
the editor and drag things (then this file is stale: the scene is the truth).
Either way, certify what you made:

    ... -s res://tests/level_gate.gd -- level=climb quick      (the schema, the spacing, the fillets)
    ... -s res://tests/climb_gate.gd  -- level=climb            (every door: the launch window, on the level itself)

THE MOVE. The whip climbs one way: a DOOR - a beam 2.2 m above the floor you
stand on, 1.4 m past its lip, with at least 1.0 m of air under it - is thrown
from a standstill, the body is hauled off the lip, the swing is pumped, and the
hand opens on the way up. Measured on tests/climb_door_map.gd (release ticks
that land and stand, one swing, trackpad-free; 1 tick = 16.7 ms):

    rise h \\ gap G   3.0   3.5   4.0   4.25  4.5   5.0   6.0
      1.0             64     -    35     -     -    18     -
      1.5             15     -    34     -     -    15     -
      2.0              0    39    27     -    13     9     -
      2.5              0    36    29     6     2     0     0
      0.0              -     -    39     -     -    28    16

A gap of 3 m cannot be climbed 2 m (the face is in the way of the arc); a gap
of 5 m cannot be climbed 2.5 m (the arc does not reach). Pit depth makes no
difference from 1.0 m down. Under trackpad-tier hand noise (climb_door_map's
noise mode, 40 throws, the bot releasing at one fixed angle) the landings per
LOCK were: 2.0 up at 4.5 across 95%, at 5.0 80%; 2.5 up at 4.0 across 45%, at
4.25 61%. The rise is the hard axis, not the gap. So the level is written in
(h, G): every 2.0 m rise first, gap opening to 5.0, then the 2.5 m rises.

THE SHAPE. Solid terraces, exactly the bench the numbers came from: a long
flat shelf, a 0.35 m lip, a shaft as wide as the gap, a solid face, the next
shelf. Every shelf is SHELF_W long because the stance is 1.8 m before the lip
with 5.25 m of whip laid back behind it: a shelf shorter than ~7 m hangs the
whip off its back edge and the throw is another throw (measured: a 5 m slab
locked 1 stroke in 36 where the long floor locked 3, and none of them landed).
Two softer shapes were measured and refused: a floor at the shelf's own level
just past a 2.8 m pit - so a miss could be re-thrown from the far side - kills
the launch outright (0 landings against 28 on the same gap with the pit full
width: the swing meets the floor's edge); and a catch of the door from under an
overhanging next shelf, 2.1-3.0 m out, locks 0-1 strokes in 36. So a miss here
is a fall. The shafts all go below the level's Bottom line, so falling in is a
fall to the last CHECKPOINT (each section's first shelf), which is what a fall
costs in Getting Over It: the section, not the game.
"""
import argparse
import json
import os

PPM = 60.0
LINE = (0.32, 0.35, 0.42, 1)
FAR = (0.125, 0.135, 0.17, 1)

DOOR_DX = 1.4           # m past the lip
DOOR_DY = 2.2           # m above the shelf
DOOR_R = 0.11
SHELF_W = 8.0           # m: 1.8 m of stance + 5.25 m of whip laid back, plus the landing
BOTTOM_DEPTH = 6.0      # m under the start floor: the line a fall crosses
SHAFT_DEPTH = 12.0      # m under the start floor: every shaft's floor, below the line
LEFT = -16.0            # start floor from here to the first lip at x = 0
SUMMIT_W = 8.0          # m of floor past the last landing
SKY = 14.0              # m of wall above the ends
CP_IN = 1.5             # m past a shelf's near edge: where its checkpoint stands

# =============================================================== STAGES ==
# (section, h, G): a launch from THIS shelf's lip that climbs h onto the next
# shelf, whose near edge is G past the lip. A section's first shelf carries
# a checkpoint. The last stage lands on the summit.
STAGES = [
    # THE LADDER: 2.0 up, 3.5 across - the widest cell there is (39 ticks)
    ("ladder", 2.0, 3.5),
    ("ladder", 2.0, 3.5),
    ("ladder", 2.0, 3.5),
    # THE REACH: still 2.0 up, the gap opening 4.0 -> 4.5 -> 5.0 (27, 13, 9 ticks;
    # under trackpad noise a bot still lands 95% at 4.5 and 80% at 5.0)
    ("reach", 2.0, 4.0),
    ("reach", 2.0, 4.0),
    ("reach", 2.0, 4.5),
    ("reach", 2.0, 4.5),
    ("reach", 2.0, 4.5),
    ("reach", 2.0, 5.0),
    ("reach", 2.0, 5.0),
    # THE STEPS: the full 2.5 rise, close (36 ticks) - the rise is what costs:
    # the arc only just clears the edge, and a trackpad bot lands 45% at 4.0
    ("steps", 2.5, 3.5),
    ("steps", 2.5, 3.5),
    ("steps", 2.5, 3.5),
    ("steps", 2.5, 4.0),
    ("steps", 2.5, 4.0),
    # THE EDGE: 2.5 up at the last gap that works at all (4.25: 6 ticks, 100 ms)
    ("edge", 2.5, 4.0),
    ("edge", 2.5, 4.25),
    ("edge", 2.5, 4.25),
]

# the measured window, ticks, for the (h, G) cells above (climb_door_map, T 150)
WINDOW = {(2.0, 3.5): 39, (2.0, 4.0): 27, (2.0, 4.5): 13, (2.0, 5.0): 9,
          (2.5, 3.5): 36, (2.5, 4.0): 29, (2.5, 4.25): 6}


def q(v):
    return round(v, 2)


def plan():
    n = len(STAGES)
    stages = []
    ground = [(LEFT, -SKY), (LEFT, 0.0)]
    anchors = []
    checkpoints = []
    lip = 0.0           # this shelf's lip x
    near = LEFT         # this shelf's near edge x
    y = 0.0             # this shelf's top y
    section = None
    for i, (name, h, G) in enumerate(STAGES):
        last = i == n - 1
        if name != section:
            section = name
            checkpoints.append({"name": "C%02d_%s" % (i, name),
                                "x": q(near + CP_IN) if i > 0 else -4.0, "y": q(y - 0.5)})
        door = (q(lip + DOOR_DX), q(y - DOOR_DY))
        anchors.append({"name": "D%02d_%s" % (i, name), "x": door[0], "y": door[1], "r": DOOR_R})
        ground.append((lip, y))
        ground.append((lip, SHAFT_DEPTH))
        nxt = q(lip + G)
        top = q(y - h)
        ground.append((nxt, SHAFT_DEPTH))
        ground.append((nxt, top))
        w = SUMMIT_W if last else SHELF_W
        stages.append({"i": i, "name": name, "h": h, "G": G, "W": w,
                       "lip_x": lip, "shelf_y": y, "door": list(door),
                       "pit": {"x0": lip, "x1": nxt, "y": SHAFT_DEPTH},
                       "target": {"x0": nxt, "x1": q(nxt + w), "y": top},
                       "under": None, "window": WINDOW.get((h, G))})
        near = nxt
        lip = q(nxt + w)
        y = top
    ground.append((lip, y))
    ground.append((lip, q(y - SKY)))
    x_end = lip
    y_top = y
    hud = ("THE WHIP - THE CLIMB   (--level climb)   %d doors, %.0f m up, %d sections. Every door: stand at the lip, "
           "catch the beam, pump, let go on the way up.\n"
           "PUMP: reach DOWN the rope as you pass under the beam (M on: pull UP toward it). STICK: press it into the rock to plant it.\n"
           "M = mouse flip, P = stick (normal / springy / hammer), C [ ] = crack, sensitivity, 1 2 3 L = control modes. F11 = fullscreen.\n"
           "Fall into a shaft and you are back at the start of the section. R = restart there."
           % (n, -y_top, len(checkpoints)))
    backdrop = [{"name": "far_cliff", "color": FAR,
                 "pts": [(LEFT - 30.0, 30.0), (LEFT - 30.0, -6.0), (x_end + 30.0, y_top - 36.0),
                         (x_end + 30.0, 30.0)]}]
    return {"hud": hud, "ground": ground, "islands": [], "anchors": anchors,
            "checkpoints": checkpoints,
            "spawn": (-4.0, -0.5), "goal": (q(x_end - SUMMIT_W / 2.0), y_top),
            "bottom": (0.0, BOTTOM_DEPTH), "backdrop": backdrop,
            "stages": stages, "x_end": x_end, "y_top": y_top}


# ============================================================== WRITING ==
def num(v):
    v = round(v * PPM, 4)
    return str(int(v)) if v == int(v) else repr(v)


def raw(v):
    v = round(v, 6)
    return str(int(v)) + ".0" if v == int(v) else repr(v)


def col(c):
    return "Color(%s)" % ", ".join(("%g" % x) for x in c)


def vec_array(pts):
    return "PackedVector2Array(%s)" % ", ".join("%s, %s" % (num(x), num(y)) for (x, y) in pts)


def tscn_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_tscn(p, path):
    L = ["[gd_scene load_steps=4 format=3]", "",
         '[ext_resource type="Script" path="res://levels/whip_level.gd" id="1_lvl"]',
         '[ext_resource type="Script" path="res://levels/whip_terrain.gd" id="2_ter"]',
         '[ext_resource type="Script" path="res://levels/whip_anchor.gd" id="3_anc"]', "",
         '[node name="Level" type="Node2D"]', 'script = ExtResource("1_lvl")',
         "hud = " + tscn_string(p["hud"]), "",
         '[node name="Ground" type="Line2D" parent="."]', 'script = ExtResource("2_ter")',
         "points = " + vec_array(p["ground"]), "width = 6.0", "default_color = " + col(LINE), "",
         '[node name="Islands" type="Node2D" parent="."]', ""]
    for isl in p["islands"]:
        L += ['[node name="%s" type="Line2D" parent="Islands"]' % isl["name"],
              'script = ExtResource("2_ter")', "points = " + vec_array(isl["pts"]),
              "closed = true", "width = 6.0", "default_color = " + col(LINE), ""]
    L += ['[node name="Anchors" type="Node2D" parent="."]', ""]
    for a in p["anchors"]:
        L += ['[node name="%s" type="Marker2D" parent="Anchors"]' % a["name"],
              "position = Vector2(%s, %s)" % (num(a["x"]), num(a["y"])),
              "gizmo_extents = %s" % raw(a["r"] * PPM), 'script = ExtResource("3_anc")',
              "radius = %s" % repr(a["r"]), ""]
    L += ['[node name="Spawn" type="Marker2D" parent="."]',
          "position = Vector2(%s, %s)" % (num(p["spawn"][0]), num(p["spawn"][1])), "",
          '[node name="Goal" type="Marker2D" parent="."]',
          "position = Vector2(%s, %s)" % (num(p["goal"][0]), num(p["goal"][1])), "",
          '[node name="Bottom" type="Marker2D" parent="."]',
          "position = Vector2(%s, %s)" % (num(p["bottom"][0]), num(p["bottom"][1])), "",
          '[node name="Checkpoints" type="Node2D" parent="."]', ""]
    for c in p["checkpoints"]:
        L += ['[node name="%s" type="Marker2D" parent="Checkpoints"]' % c["name"],
              "position = Vector2(%s, %s)" % (num(c["x"]), num(c["y"])), ""]
    L += ['[node name="Backdrop" type="Node2D" parent="."]']
    for b in p["backdrop"]:
        L += ["", '[node name="%s" type="Polygon2D" parent="Backdrop"]' % b["name"],
              "color = " + col(b["color"]), "polygon = " + vec_array(b["pts"])]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(L) + "\n")


def table(p):
    print("stage  section  rise  gap   window   lip x   shelf y   door")
    for s in p["stages"]:
        w = s["window"]
        print("  %2d   %-7s  %.1f   %.2f   %5s   %6.2f  %7.2f   (%.2f, %.2f)" % (
            s["i"], s["name"], s["h"], s["G"], ("%d t" % w) if w else "?",
            s["lip_x"], s["shelf_y"], s["door"][0], s["door"][1]))
    print("%d doors, %.1f m up, %.1f m along; %d checkpoints at x %s; goal at x %.1f" % (
        len(p["stages"]), -p["y_top"], p["x_end"], len(p["checkpoints"]),
        ", ".join("%.1f" % c["x"] for c in p["checkpoints"]), p["goal"][0]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    p = plan()
    table(p)
    if a.check:
        return
    out = a.out or os.path.join(root, "levels", "climb.tscn")
    write_tscn(p, out)
    with open(os.path.splitext(out)[0] + ".plan.json", "w", newline="\n") as f:
        json.dump({"stages": p["stages"], "spawn": p["spawn"], "goal": p["goal"],
                   "bottom": p["bottom"], "checkpoints": p["checkpoints"],
                   "door_dx": DOOR_DX, "door_dy": DOOR_DY}, f, indent=1)
    print("wrote", out, "and its .plan.json")


if __name__ == "__main__":
    main()
