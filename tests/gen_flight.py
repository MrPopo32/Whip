#!/usr/bin/env python3
"""THE FLIGHT, AS NUMBERS. Writes res://levels/flight.tscn and levels/flight.plan.json.

    python tests/gen_flight.py             # write the scene and the plan, print the stage table
    python tests/gen_flight.py --check     # print the table, write nothing

Everything below is in METRES, y DOWN (a bigger y is lower), x along the route;
the scene is written in pixels at 60 px/m in levels/steps.tscn's format. Edit
STAGES and rerun, or edit the scene in the editor (then this file is stale).
Certify what you made:

    ... -s res://tests/level_gate.gd  -- level=flight quick
    ... -s res://tests/flight_gate.gd -- level=flight     (every beam: catches, landings, on the level itself)

WHY THIS LEVEL. The climb's loop is: walk 8 m, stand still, catch a beam
2.2 m up, pump for seconds, fly for half of one. Playtested: "the main
gameplay happens around swinging rather than landing the swing and flying".
A whip is a momentum tool, and a door asks it for energy from nothing. This
is the other loop, measured on tests/flight_probe.gd with the stretchy rope:

  A beam 2.5 m past the lip, 0.5 m up, r 0.11. 25 of 36 standing strokes
  lock it (the standing map certified this cell 40/40 under trackpad noise).
  The catch hauls you off the lip and the DROP IS THE SWING: the body falls
  2.2 m under the beam and rises up the far side to 70-78 degrees on the
  first pass. Let go on that rise and you land 1 m lower, 4.3-7.1 m past the
  lip - every tick of the rise lands somewhere, earlier is shorter.
  One pull down the rope as you pass under the beam lifts the first rise to
  90-117 degrees, and then a 33-tick window (over half a second) lands at the
  lip's OWN height, 4.4-9.5 m past it, with the apex up to 1.7 m above.

So: throw, step off, (pull), let go, fly, land. No pump. Three kinds of
stage: GLIDE lands 1.5 m lower with no pull; DIP lands 1.0 m lower with one
pull; HOLD lands level with one pull. Shelves are SHELF_W long (the throw lays
5.25 m of whip back behind a 0.4 m stance). Every pit goes below the Bottom
line, and each section starts on a checkpoint.
"""
import argparse
import json
import os

PPM = 60.0
LINE = (0.32, 0.35, 0.42, 1)
FAR = (0.125, 0.135, 0.17, 1)

BEAM_DX = 2.5           # m past the lip
BEAM_R = 0.11
# the beam's height above the lip's floor, per kind: 0.5 m for the level and
# downhill stages; 1.0 m for the uphill ones, where one pull then lifts the
# first rise to 109 deg and the flight's apex to 2.0-2.85 m above the lip
BEAM_UP = {"glide": 0.5, "dip": 0.5, "hold": 0.5, "rise": 1.0, "climb": 1.0}
# The landing shelf's near edge, per kind, m past the lip. The swing's arc dips
# BELOW the shelf's level on its way up, so the edge must sit past where the
# arc crosses that level (tether up to 2.48 m from the beam at 2.5, 0.5):
# the body centre crosses y_top - 0.28 at cos(theta) = (y_top - 0.28 + 0.5)
# / L, i.e. at x 4.17 for a 1.5 m drop, 4.57 for 1.0, 4.97 for level - plus
# the body's radius. Measured: a near edge at 4.0 put every first swing into
# the shelf's face (flight_gate, 0 landings on the glide stages).
NEAR = {"glide": 4.6, "dip": 5.0, "hold": 5.4, "rise": 5.3, "climb": 5.3}
SHELF_W = 8.0           # m of shelf (landing + the next stance + the whip laid back)
LEFT = -16.0
SUMMIT_W = 8.0
SKY = 14.0
CP_IN = 1.5

# (section, kind): GLIDE drops 1.5 m, no pull; DIP drops 1.0 m, one pull;
# HOLD stays level, one pull; RISE lands 1.0 m HIGHER with the beam 1.0 m up
# and a pull on EACH pass under it - the landing is on the second rise;
# CLIMB would be 1.5 m higher the same way. An uphill course: two glides to
# learn the throw and the step-off, three holds to learn the pull, then up.
# CLIMB (1.5 m up) is kept as a kind but not used: on the level, 1 stroke in
# 11 landed it (flight_gate 2026-10-10), which is luck. RISE lands 4-5 of 10.
STAGES = [
    ("glide", "glide"), ("glide", "glide"),
    ("hold", "hold"), ("hold", "hold"), ("hold", "hold"),
    ("rise", "rise"), ("rise", "rise"), ("rise", "rise"), ("rise", "rise"),
    ("rise", "rise"), ("rise", "rise"), ("rise", "rise"), ("rise", "rise"),
    ("mix", "hold"), ("mix", "rise"), ("mix", "hold"), ("mix", "rise"),
]
DROP = {"glide": 1.5, "dip": 1.0, "hold": 0.0, "rise": -1.0, "climb": -1.5}
POLICY = {"glide": "park", "dip": "tug", "hold": "tug", "rise": "tug", "climb": "tug"}


def q(v):
    return round(v, 2)


def plan():
    n = len(STAGES)
    stages, anchors, checkpoints = [], [], []
    lip, near, y = 0.0, LEFT, 0.0
    section = None
    shelves = []            # (x0, x1, y) in order, the ground's floors
    for i, (sec, kind) in enumerate(STAGES):
        if sec != section:
            section = sec
            checkpoints.append({"name": "C%02d_%s" % (i, sec),
                                "x": q(near + CP_IN) if i > 0 else -4.0, "y": q(y - 0.5)})
        beam = (q(lip + BEAM_DX), q(y - BEAM_UP[kind]))
        anchors.append({"name": "B%02d_%s" % (i, kind), "x": beam[0], "y": beam[1], "r": BEAM_R})
        nxt = q(lip + NEAR[kind])
        top = q(y + DROP[kind])
        w = SUMMIT_W if i == n - 1 else SHELF_W
        shelves.append((lip, nxt, top, q(nxt + w)))
        stages.append({"i": i, "section": sec, "kind": kind, "policy": POLICY[kind],
                       "drop": DROP[kind], "lip_x": lip, "shelf_y": y, "beam": list(beam),
                       "target": {"x0": nxt, "x1": q(nxt + w), "y": top}})
        near = nxt
        lip = q(nxt + w)
        y = top
    lowest = max([s[2] for s in shelves] + [0.0])
    bottom = q(lowest + 4.0)
    pit_y = q(bottom + 6.0)
    ground = [(LEFT, -SKY), (LEFT, 0.0)]
    for (lx, nx, top, far) in shelves:
        lip_pt = (lx, ground[-1][1])          # the lip, on the floor the chain is on
        if ground[-1] != lip_pt:              # (a shelf's far end already IS the next lip)
            ground.append(lip_pt)
        ground += [(lx, pit_y), (nx, pit_y), (nx, top), (far, top)]
    ground.append((lip, q(y - SKY)))
    x_end = lip
    hud = ("THE WHIP - THE FLIGHT   (--level flight)   %d beams, %d sections, uphill. Throw at the beam ahead, hold, "
           "step off the edge: the drop is your swing. Let go on the way up and fly.\n"
           "LIFT: pull the mouse DOWN the rope as you pass under the beam, and you fly higher. Earlier = shorter, later = longer.\n"
           "Fall and you are back at the start of the section. R = restart there. F11 = fullscreen."
           % (n, len(checkpoints)))
    backdrop = [{"name": "far_cliff", "color": FAR,
                 "pts": [(LEFT - 30.0, bottom + 20.0), (LEFT - 30.0, -8.0), (x_end + 30.0, -8.0),
                         (x_end + 30.0, bottom + 20.0)]}]
    return {"hud": hud, "ground": ground, "anchors": anchors, "checkpoints": checkpoints,
            "spawn": (-4.0, -0.5), "goal": (q(x_end - SUMMIT_W / 2.0), y),
            "bottom": (0.0, bottom), "backdrop": backdrop, "stages": stages,
            "x_end": x_end, "y_end": y}


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
         '[node name="Islands" type="Node2D" parent="."]', "",
         '[node name="Anchors" type="Node2D" parent="."]', ""]
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
    print("stage  section  kind   policy  drop   lip x   shelf y   beam            lands on")
    for s in p["stages"]:
        t = s["target"]
        print("  %2d   %-7s  %-5s  %-6s  %.1f  %6.2f  %7.2f   (%.2f, %.2f)   x %.1f..%.1f at y %.2f" % (
            s["i"], s["section"], s["kind"], s["policy"], s["drop"], s["lip_x"], s["shelf_y"],
            s["beam"][0], s["beam"][1], t["x0"], t["x1"], t["y"]))
    print("%d beams, %.1f m along, ends %.1f m %s; Bottom at %.1f; %d checkpoints; goal x %.1f" % (
        len(p["stages"]), p["x_end"], abs(p["y_end"]), "lower" if p["y_end"] > 0 else "HIGHER",
        p["bottom"][1], len(p["checkpoints"]), p["goal"][0]))


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
    out = a.out or os.path.join(root, "levels", "flight.tscn")
    write_tscn(p, out)
    with open(os.path.splitext(out)[0] + ".plan.json", "w", newline="\n") as f:
        json.dump({"stages": p["stages"], "spawn": p["spawn"], "goal": p["goal"],
                   "bottom": p["bottom"], "checkpoints": p["checkpoints"], "flight": True}, f, indent=1)
    print("wrote", out, "and its .plan.json")


if __name__ == "__main__":
    main()
