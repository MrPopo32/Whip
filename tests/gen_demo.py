#!/usr/bin/env python3
"""THE DEMO: the flight loop, dressed. Writes levels/demo.tscn and levels/demo.plan.json.

    python tests/gen_demo_art.py        # the textures, first (then one --headless --import)
    python tests/gen_demo.py            # the scene and the plan

The course is tests/gen_flight.py's loop (throw at the beam past the lip,
step off, let go on the way up; one pull per pass under the beam to land
higher) in nine beams: two glides, two holds, five rises. The look is an
Art node over the same collision: a parallax sky and two mountain lines, the
rock mass as one textured polygon that follows the Ground chain exactly, a
lit edge along it, a branch end at every beam, a flag at the goal. greybox
is off, so nothing grey is painted; the instruments (rope, body, rings,
caption) draw as always.

    ... -s res://tests/level_gate.gd  -- level=demo quick
    ... -s res://tests/flight_gate.gd -- level=demo
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_flight as F  # noqa: E402

F.STAGES = [
    ("glide", "glide"), ("glide", "glide"),
    ("hold", "hold"), ("hold", "hold"),
    ("rise", "rise"), ("rise", "rise"), ("rise", "rise"), ("rise", "rise"), ("rise", "rise"),
]
# THE RISE'S BRANCH SITS 1.25 m UP, not gen_flight's 1.0. Measured with
# tests/flight_gate.gd under the shipped feel (lean, crack 45, springy stick,
# stretchy rope): at 1.0 the demo's stage 4 landed 1 stroke of 36 and stage 7
# landed 4; at 1.25, 5 and 9 (best runs 38 and 38 ticks). The rise itself
# stays 1 m: the extra quarter metre of drop is the energy the second rise
# was short of. (Shrinking the rise to 0.75 m instead did not help stage 4.)
F.BEAM_UP["rise"] = 1.25
PPM = F.PPM
EDGE = (0.86, 0.72, 0.56, 1)
EDGE_IN = (0.30, 0.22, 0.26, 1)
SKY_BOTTOM = 40.0        # m under the lowest rock the textured mass extends


def num(v):
    return F.num(v)


def vec_array(pts):
    return F.vec_array(pts)


def write_tscn(p, path):
    # the rock mass: the Ground chain closed far below (y DOWN: bigger = lower)
    g = p["ground"]
    deep = max(y for (_, y) in g) + SKY_BOTTOM
    rock = list(g) + [(g[-1][0], deep), (g[0][0], deep)]
    hud = ("THE WHIP   -   a whip is your only tool and your only way to move\n"
           "Throw it at the branch ahead and HOLD (Space or click). Step off the edge: the drop is your swing. Let go on the way up and fly.\n"
           "To land higher, pull the mouse DOWN the rope each time you pass under the branch. Fall and you are back at the last flag.\n"
           "F1 = more readouts   F11 = fullscreen   R = restart")
    L = ["[gd_scene load_steps=10 format=3]", "",
         '[ext_resource type="Script" path="res://levels/whip_level.gd" id="1_lvl"]',
         '[ext_resource type="Script" path="res://levels/whip_terrain.gd" id="2_ter"]',
         '[ext_resource type="Script" path="res://levels/whip_anchor.gd" id="3_anc"]',
         '[ext_resource type="Texture2D" path="res://levels/art/demo/sky.png" id="4_sky"]',
         '[ext_resource type="Texture2D" path="res://levels/art/demo/far.png" id="5_far"]',
         '[ext_resource type="Texture2D" path="res://levels/art/demo/mid.png" id="6_mid"]',
         '[ext_resource type="Texture2D" path="res://levels/art/demo/rock.png" id="7_rock"]',
         '[ext_resource type="Texture2D" path="res://levels/art/demo/beam.png" id="8_beam"]',
         '[ext_resource type="Texture2D" path="res://levels/art/demo/flag.png" id="9_flag"]', "",
         '[node name="Level" type="Node2D"]', 'script = ExtResource("1_lvl")',
         "hud = " + F.tscn_string(hud), "greybox = false", "",
         '[node name="Ground" type="Line2D" parent="."]', 'script = ExtResource("2_ter")',
         "points = " + vec_array(g), "width = 6.0", "default_color = " + F.col(F.LINE), "",
         '[node name="Islands" type="Node2D" parent="."]', "",
         '[node name="Anchors" type="Node2D" parent="."]', ""]
    for a in p["anchors"]:
        L += ['[node name="%s" type="Marker2D" parent="Anchors"]' % a["name"],
              "position = Vector2(%s, %s)" % (num(a["x"]), num(a["y"])),
              "gizmo_extents = %s" % F.raw(a["r"] * PPM), 'script = ExtResource("3_anc")',
              "radius = %s" % repr(a["r"]), "",
              '[node name="branch" type="Sprite2D" parent="Anchors/%s"]' % a["name"],
              'texture = ExtResource("8_beam")', ""]
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
    L += ['[node name="Art" type="Node2D" parent="."]', "",
          '[node name="Parallax" type="ParallaxBackground" parent="Art"]', "layer = -100", "",
          '[node name="Sky" type="ParallaxLayer" parent="Art/Parallax"]',
          "motion_scale = Vector2(0, 0)", "",
          '[node name="sky" type="Sprite2D" parent="Art/Parallax/Sky"]',
          "scale = Vector2(25, 1)", 'texture = ExtResource("4_sky")', "centered = false", "",
          '[node name="Far" type="ParallaxLayer" parent="Art/Parallax"]',
          "motion_scale = Vector2(0.15, 0.08)", "motion_mirroring = Vector2(1600, 0)", "",
          '[node name="far" type="Sprite2D" parent="Art/Parallax/Far"]',
          "position = Vector2(0, 180)", 'texture = ExtResource("5_far")', "centered = false", "",
          '[node name="Mid" type="ParallaxLayer" parent="Art/Parallax"]',
          "motion_scale = Vector2(0.35, 0.2)", "motion_mirroring = Vector2(1600, 0)", "",
          '[node name="mid" type="Sprite2D" parent="Art/Parallax/Mid"]',
          "position = Vector2(-200, 330)", 'texture = ExtResource("6_mid")', "centered = false", "",
          '[node name="Rock" type="Polygon2D" parent="Art"]',
          "texture_repeat = 2", 'texture = ExtResource("7_rock")',
          "polygon = " + vec_array(rock), "",
          '[node name="EdgeShadow" type="Line2D" parent="Art"]',
          "points = " + vec_array(g), "width = 14.0", "default_color = " + F.col(EDGE_IN),
          "joint_mode = 2", "",
          '[node name="Edge" type="Line2D" parent="Art"]',
          "points = " + vec_array(g), "width = 5.0", "default_color = " + F.col(EDGE),
          "joint_mode = 2", "",
          '[node name="Flag" type="Sprite2D" parent="Art"]',
          # where the game draws its own flag (goal_x + 1.5): one flag, dressed.
          # flag.png's pole is at texture x 4..7 of 40, 14.5 px left of centre,
          # so the offset puts the pole on the game's
          "position = Vector2(%s, %s)" % (num(p["goal"][0] + 1.5), num(p["goal"][1] - 1.15)),
          "offset = Vector2(14.5, 0)", "scale = Vector2(2.4, 2.4)", 'texture = ExtResource("9_flag")', ""]
    # a flag at every checkpoint: the caption says "back at the last flag", so
    # there is one to see. Checkpoint markers sit 0.5 m above their shelf; the
    # sprite is 56 px = 1.5 m tall at 1.6, its base on the shelf
    for c in p["checkpoints"]:
        L += ['[node name="flag_%s" type="Sprite2D" parent="Art"]' % c["name"],
              "position = Vector2(%s, %s)" % (num(c["x"]), num(c["y"] + 0.5 - 0.75)),
              "offset = Vector2(14.5, 0)", "scale = Vector2(1.6, 1.6)", 'texture = ExtResource("9_flag")', ""]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(L) + "\n")


def main():
    root = os.path.dirname(HERE)
    p = F.plan()
    F.table(p)
    out = os.path.join(root, "levels", "demo.tscn")
    write_tscn(p, out)
    with open(os.path.splitext(out)[0] + ".plan.json", "w", newline="\n") as f:
        json.dump({"stages": p["stages"], "spawn": p["spawn"], "goal": p["goal"],
                   "bottom": p["bottom"], "checkpoints": p["checkpoints"], "flight": True}, f, indent=1)
    print("wrote", out, "and its .plan.json")


if __name__ == "__main__":
    main()
