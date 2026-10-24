#!/usr/bin/env python3
"""THE MOUNTAIN, AS NUMBERS. Writes res://levels/mountain.tscn.

    python tests/gen_mountain.py                      # write levels/mountain.tscn, print the totals
    python tests/gen_mountain.py --check              # print the totals, write nothing
    python tests/gen_mountain.py --plan steps --out levels/_steps_rt.tscn
                                                      # the round-trip proof: steps.tscn's plan

Everything below is in METRES, y DOWN (a bigger y is lower), x along the route.
The scene is written in pixels at 60 px/m in exactly the format
levels/steps.tscn uses (same ext_resource ids, same node names, types and
scripts), and main.gd's loader divides by 60 and quantises to 0.01 m - so keep
every number on the 0.01 grid and what you type is what the sim runs.

You can edit EITHER side. Change the numbers here and rerun, or open
levels/mountain.tscn in the editor and drag things (then this file is stale:
the scene is the truth once you have edited it by hand, and rerunning this
overwrites it). Either way, certify what you made:

    ... -s res://tests/level_gate.gd -- level=mountain quick      (~2 min)
    ... -s res://tests/level_gate.gd -- level=mountain            (R: every anchor, ~1 h)

THE CONTRACT this plan is written to (README "Building a level"; the gate
checks most of it and this script warns about the rest):
  - every tier is FLAT and every drop faces +x (the lash gait cannot climb 20 deg)
  - a cold catch only <= ~2.4 m over the floor you throw from; a launch needs
    > 3.2 m of air under the arc. So: flat tier, lip, a door 1.4 m past the
    lip 2.2 m up, a 3.0 m drop.
  - 6.5 m between anchors (the rope lives in a 6.40 m circle)
  - rock over a crawled floor clears 1.45 m; islands touch nothing
  - no jam anchors, no captions: a real level teaches by consequence
"""
import argparse
import math
import os
import sys

PPM = 60.0

# steps.tscn's colours, verbatim
LINE = (0.32, 0.35, 0.42, 1)
FAR = (0.125, 0.135, 0.17, 1)
MID = (0.155, 0.17, 0.215, 1)
NEAR = (0.19, 0.205, 0.25, 1)

# ============================================================ THE MOUNTAIN ==
# Six chapters, top to bottom. (name, x0, x1, the pattern it teaches.)
CHAPTERS = [
    ("THE SCHOOL", 0.0, 25.0,
     "one wide flat home tier, three fat beams 2.2 m up; falls are free"),
    ("THE STEPS", 25.0, 55.0,
     "three 10 m tiers, 3 m drops, a door beam 1.4 m past every lip"),
    ("THE SHELVES", 55.0, 91.0,
     "four 9 m tiers; every door wears rock: knob, stalactite, window, branch"),
    ("THE SKY", 91.0, 130.0,
     "five 7.8 m tiers: the fast line - beams 4.5 m over the tier beneath, 7.8 m apart, chained without landing"),
    ("THE NARROWS", 130.0, 160.0,
     "four 7.5 m tiers; a wall beside every door caps the swing"),
    ("THE FLOOR", 160.0, 192.0,
     "the last door, the long floor, three thin beams across it, the flag"),
]

# TIERS: (x0, x1, floor_y). Contiguous; each one 3.0 m under the last. The
# face between two tiers is the lip at x1 of the upper one.
TIERS = [
    (0.0, 25.0, 0.0),        # 1 the school: the home tier
    (25.0, 35.0, 3.0),       # 2 the steps
    (35.0, 45.0, 6.0),
    (45.0, 55.0, 9.0),
    (55.0, 64.0, 12.0),      # 3 the shelves
    (64.0, 73.0, 15.0),
    (73.0, 82.0, 18.0),
    (82.0, 91.0, 21.0),
    (91.0, 98.8, 24.0),      # 4 the sky: 7.8 m tiers, one per fast-line leg
    (98.8, 106.6, 27.0),
    (106.6, 114.4, 30.0),
    (114.4, 122.2, 33.0),
    (122.2, 130.0, 36.0),
    (130.0, 137.5, 39.0),    # 5 the narrows
    (137.5, 145.0, 42.0),
    (145.0, 152.5, 45.0),
    (152.5, 160.0, 48.0),
    (160.0, 192.0, 51.0),    # 6 the floor: the run-out to the flag
]
WALL_TOP = -8.0              # the left wall runs from here down to the home floor
SEAL_TOP = 44.0              # the far seal runs from the last floor up to here

# ANCHORS, in route order: (x, y, radius, kind). The kind decides the rock
# around it (ROCK below) and nothing else - every anchor is an ordinary beam.
#   beam        on a flat floor, 2.2 m up: the school, and the last floor
#   door        1.4 m past a lip, 2.2 m over the tier you throw from
#   knob        a door on a lump 0.60 m under it            (crag D4)
#   stalactite  a door under a brow 1.5 m over it            (crag D6)
#   window      a door inside a hood 0.90 m over, 0.45 m past (crag D2/D7)
#   branch      0.65 m past the lip, a rib 0.45 m past it     (crag D8)
#   sky         1.4 m past a lip, 1.5 m over the tier behind = 4.5 m over the
#               tier beneath, 7.8 m from the next: the traverse's fast-line
#               leg (7.8 m across, 3.0 m down), which the route bot flew 4/4
#   narrows     a door with a wall 1.0 m off the hanging body, on the far side
ANCHORS = [
    # 1 THE SCHOOL (floor 0). The spawn stands at the first one's throwing spot.
    (6.5, -2.2, 0.22, "beam"),
    (13.0, -2.2, 0.22, "beam"),
    (19.5, -2.2, 0.20, "beam"),
    # 2 THE STEPS
    (26.4, -2.2, 0.11, "door"),
    (36.4, 0.8, 0.11, "door"),
    (46.4, 3.8, 0.11, "door"),
    # 3 THE SHELVES
    (56.4, 6.8, 0.14, "knob"),
    (65.4, 9.8, 0.12, "stalactite"),
    (74.4, 12.8, 0.12, "window"),
    (82.65, 15.8, 0.12, "branch"),
    # 4 THE SKY
    (92.4, 19.5, 0.10, "sky"),
    (100.2, 22.5, 0.10, "sky"),
    (108.0, 25.5, 0.10, "sky"),
    (115.8, 28.5, 0.10, "sky"),
    (123.6, 31.5, 0.10, "sky"),
    # 5 THE NARROWS
    (131.4, 33.8, 0.11, "narrows"),
    (138.9, 36.8, 0.11, "narrows"),
    (146.4, 39.8, 0.11, "narrows"),
    (153.9, 42.8, 0.11, "narrows"),
    # 6 THE FLOOR (floor 51)
    (161.4, 45.8, 0.11, "door"),
    (168.0, 48.8, 0.11, "beam"),
    (175.8, 48.8, 0.11, "beam"),
    (183.6, 48.8, 0.11, "beam"),
]
SPAWN = (4.5, -1.0)
GOAL = (189.0, 51.0)
HUD = ("THE WHIP - THE MOUNTAIN   (--level mountain)   six chapters, top to bottom: "
       "school, steps, shelves, sky, narrows, floor")


# ------------------------------------------------------------------ ROCK --
# Each function takes the anchor (x, y) and the floor under its far side and
# returns [(island name suffix, vertex list)] and [(backdrop polygon, colour)].
# The islands are the crag's own measured geometry, relative to the anchor;
# the backdrop is paint (the pillar a lump is the top of, the curtain a rib
# hangs from), read by nothing but _draw.
def rect(x0, y0, x1, y1):
    # clockwise on screen, _crag_rect's order (the loader fixes it anyway)
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def rock_knob(x, y, below):
    lump = rect(x - 0.40, y + 0.74, x + 0.40, y + 1.34)
    pillar = [(x - 0.45, y + 1.20), (x + 0.45, y + 1.20), (x + 0.90, below), (x - 0.90, below)]
    return [("lump", lump)], [(pillar, MID)]


def rock_stalactite(x, y, below):
    brow = rect(x - 2.50, y - 2.70, x + 2.50, y - 1.50)
    spike = [(x - 0.42, y - 1.50), (x + 0.42, y - 1.50), (x, y - 0.05)]
    curtain = [(x - 2.10, y - 2.70), (x + 2.10, y - 2.70), (x + 3.10, y - 5.20), (x - 2.70, y - 5.20)]
    return [("brow", brow)], [(spike, MID), (curtain, MID)]


def rock_window(x, y, below):
    hood = [(x - 1.00, y - 1.30), (x + 1.00, y - 1.30), (x + 1.00, y + 0.70),
            (x + 0.57, y + 0.70), (x + 0.57, y - 0.90), (x - 1.00, y - 0.90)]
    curtain = [(x - 1.30, y - 1.00), (x + 1.30, y - 1.00), (x + 1.50, y - 4.30), (x - 1.50, y - 4.30)]
    return [("hood", hood)], [(curtain, MID)]


def rock_branch(x, y, below):
    rib = rect(x + 0.57, y - 4.80, x + 0.92, y + 0.80)
    curtain = [(x + 0.27, y - 4.50), (x + 1.22, y - 4.50), (x + 1.42, y - 7.80), (x + 0.07, y - 7.80)]
    return [("rib", rib)], [(curtain, MID)]


def rock_narrows(x, y, below):
    # the wall's inner face 1.0 m off the surface of a body hanging under the
    # beam (BODY_R 0.28), from 1.5 m over the beam down to 1.5 m over the
    # floor it swings above - so the crawl under it keeps its 1.45 m
    wall = rect(x + 1.28, y - 1.50, x + 1.63, below - 1.50)
    curtain = [(x + 0.98, y - 1.20), (x + 1.93, y - 1.20), (x + 2.13, y - 4.50), (x + 0.78, y - 4.50)]
    return [("wall", wall)], [(curtain, MID)]


ROCK = {"knob": rock_knob, "stalactite": rock_stalactite, "window": rock_window,
        "branch": rock_branch, "narrows": rock_narrows}
# kinds that must have > 3.2 m of air under their far side (a launch); the
# floor beams are the school's kind and swing over the floor they stand on
LAUNCH = {"door", "knob", "stalactite", "window", "branch", "sky", "narrows"}


def floor_at(tiers, x):
    for (x0, x1, fy) in tiers:
        if x0 <= x < x1:
            return fy
    return tiers[-1][2] if x >= tiers[-1][1] else tiers[0][2]


def ground_points(tiers, wall_top, seal_top):
    pts = [(tiers[0][0], wall_top)]
    for (x0, x1, fy) in tiers:
        pts.append((x0, fy))
        pts.append((x1, fy))
    pts.append((tiers[-1][1], seal_top))
    return pts


def mountain_plan():
    tiers = TIERS
    anchors = []
    islands = []
    paint_mid = []
    for i, (x, y, r, kind) in enumerate(ANCHORS):
        name = "A%02d_%s" % (i, kind.upper())
        anchors.append({"name": name, "x": x, "y": y, "r": r, "kind": kind})
        if kind in ROCK:
            below = floor_at(tiers, x + 1.0)
            isl, paint = ROCK[kind](x, y, below)
            for suffix, pts in isl:
                islands.append({"name": "A%02d_%s" % (i, suffix), "pts": pts})
            paint_mid += paint
    g = ground_points(tiers, WALL_TOP, SEAL_TOP)
    xl = tiers[0][0] - 40.0
    xr = tiers[-1][1] + 40.0
    bot = tiers[-1][2] + 40.0
    # the far cliff: a skyline 8-10 m over each tier, lower as the route goes
    far = [(xl, WALL_TOP - 8.0)]
    for i, (x0, x1, fy) in enumerate(tiers):
        far.append(((x0 + x1) * 0.5, fy - (9.0 if i % 2 else 11.0)))
    far += [(xr, tiers[-1][2] - 6.0), (xr, bot), (xl, bot)]
    near = [(xl, WALL_TOP)] + g + [(xr, SEAL_TOP), (xr, bot), (xl, bot)]
    backdrop = [{"name": "far_cliff", "color": FAR, "pts": far}]
    for j, (pts, col) in enumerate(paint_mid):
        backdrop.append({"name": "paint_%02d" % j, "color": col, "pts": pts})
    backdrop.append({"name": "near_rock", "color": NEAR, "pts": near})
    for isl in islands:
        backdrop.append({"name": isl["name"] + "_fill", "color": NEAR, "pts": isl["pts"]})
    return {"hud": HUD, "ground": g, "tiers": tiers, "islands": islands,
            "anchors": anchors, "spawn": SPAWN, "goal": GOAL, "backdrop": backdrop,
            "chapters": CHAPTERS}


# ============================================== THE STEPS (the round trip) ==
# levels/steps.tscn's own plan, typed from the committed scene. Generating it
# and loading the result must give steps' fingerprint 3144857459313072037:
# that is the proof this writer and the loader agree.
def steps_plan():
    tiers = [(-12.0, 6.0, 0.0), (6.0, 14.0, 3.0), (14.0, 22.0, 6.0), (22.0, 32.0, 9.0)]
    lump = rect(15.0, 1.54, 15.8, 2.14)
    g = ground_points(tiers, -8.0, 3.0)
    return {
        "hud": "THE WHIP - THE STEPS   (--level steps)   three drops, four anchors: a beam, a jam, a knob, a thin beam\n"
               "SPACE / LMB = CLOSE YOUR HAND on the rope. A wrap only takes in the moment you close it,\n"
               "and only holds while you hold. OPEN your hand and you leave the anchor that instant.\n"
               "Green ring = it holds. Amber = it betrays.",
        "ground": g, "tiers": tiers,
        "islands": [{"name": "A2_lump", "pts": lump}],
        "anchors": [
            {"name": "A0_BEAM", "x": -2.0, "y": -2.2, "r": 0.22, "caption": "BEAM", "kind": "beam"},
            {"name": "A1_JAM", "x": 7.4, "y": -2.2, "r": 0.11, "jam": True, "caption": "JAM", "kind": "door"},
            {"name": "A2_KNOB", "x": 15.4, "y": 0.8, "r": 0.14, "caption": "KNOB", "kind": "knob"},
            {"name": "A3_THIN_BEAM", "x": 23.4, "y": 3.8, "r": 0.11, "caption": "THIN BEAM", "kind": "door"},
        ],
        "spawn": (-6.5, -1.0), "goal": (28.0, 9.0),
        "backdrop": [
            {"name": "far_cliff", "color": FAR, "pts": [(-40, -14), (-10, -11), (0, -9), (10, -7), (20, -4),
                                                         (30, -1), (60, 1), (60, 40), (-40, 40)]},
            {"name": "A2_pillar", "color": MID, "pts": [(14.95, 2.0), (15.85, 2.0), (16.3, 6.0), (14.5, 6.0)]},
            {"name": "near_rock", "color": NEAR, "pts": [(-40, -8)] + g + [(60, 3), (60, 40), (-40, 40)]},
            {"name": "A2_lump_fill", "color": NEAR, "pts": lump},
        ],
        "chapters": [("THE STEPS", -12.0, 32.0, "the smallest complete example")],
    }


# ================================================================ WRITER ==
def num(v):
    # pixels, written the way Godot writes them: integers bare, the rest in
    # shortest round-trip digits
    v = round(v * PPM, 4)
    if v == int(v):
        return str(int(v))
    return repr(v)


def raw(v):
    v = round(v, 6)
    return str(int(v)) + ".0" if v == int(v) else repr(v)


def col(c):
    return "Color(%s)" % ", ".join(("%g" % x) for x in c)


def vec_array(pts):
    return "PackedVector2Array(%s)" % ", ".join("%s, %s" % (num(x), num(y)) for (x, y) in pts)


def tscn_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_tscn(plan, path):
    L = []
    L.append("[gd_scene load_steps=4 format=3]")
    L.append("")
    L.append('[ext_resource type="Script" path="res://levels/whip_level.gd" id="1_lvl"]')
    L.append('[ext_resource type="Script" path="res://levels/whip_terrain.gd" id="2_ter"]')
    L.append('[ext_resource type="Script" path="res://levels/whip_anchor.gd" id="3_anc"]')
    L.append("")
    L.append('[node name="Level" type="Node2D"]')
    L.append('script = ExtResource("1_lvl")')
    L.append("hud = " + tscn_string(plan["hud"]))
    L.append("")
    L.append('[node name="Ground" type="Line2D" parent="."]')
    L.append('script = ExtResource("2_ter")')
    L.append("points = " + vec_array(plan["ground"]))
    L.append("width = 6.0")
    L.append("default_color = " + col(LINE))
    L.append("")
    L.append('[node name="Islands" type="Node2D" parent="."]')
    L.append("")
    for isl in plan["islands"]:
        L.append('[node name="%s" type="Line2D" parent="Islands"]' % isl["name"])
        L.append('script = ExtResource("2_ter")')
        L.append("points = " + vec_array(isl["pts"]))
        L.append("closed = true")
        L.append("width = 6.0")
        L.append("default_color = " + col(LINE))
        L.append("")
    L.append('[node name="Anchors" type="Node2D" parent="."]')
    L.append("")
    for a in plan["anchors"]:
        L.append('[node name="%s" type="Marker2D" parent="Anchors"]' % a["name"])
        L.append("position = Vector2(%s, %s)" % (num(a["x"]), num(a["y"])))
        L.append("gizmo_extents = %s" % raw(a["r"] * PPM))
        L.append('script = ExtResource("3_anc")')
        L.append("radius = %s" % repr(a["r"]))
        if a.get("jam"):
            L.append("jam = true")
        if a.get("caption"):
            L.append("caption = " + tscn_string(a["caption"]))
        L.append("")
    L.append('[node name="Spawn" type="Marker2D" parent="."]')
    L.append("position = Vector2(%s, %s)" % (num(plan["spawn"][0]), num(plan["spawn"][1])))
    L.append("")
    if plan.get("goal") is not None:
        L.append('[node name="Goal" type="Marker2D" parent="."]')
        L.append("position = Vector2(%s, %s)" % (num(plan["goal"][0]), num(plan["goal"][1])))
        L.append("")
    L.append('[node name="Backdrop" type="Node2D" parent="."]')
    for b in plan["backdrop"]:
        L.append("")
        L.append('[node name="%s" type="Polygon2D" parent="Backdrop"]' % b["name"])
        L.append("color = " + col(b["color"]))
        L.append("polygon = " + vec_array(b["pts"]))
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(L) + "\n")


# ================================================================ CHECKS ==
# The gate is the law; these are the cheap things it is nice to hear about
# before spending two minutes on it.
def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def check(plan):
    warn = []
    tiers = plan["tiers"]
    for i in range(len(tiers) - 1):
        if abs(tiers[i][1] - tiers[i + 1][0]) > 1e-9:
            warn.append("tiers %d and %d do not meet (%.2f vs %.2f)" % (i, i + 1, tiers[i][1], tiers[i + 1][0]))
        if tiers[i + 1][2] <= tiers[i][2]:
            warn.append("tier %d is not lower than tier %d: every drop faces +x and goes DOWN" % (i + 1, i))
    for x0, x1, fy in tiers:
        if x1 - x0 < 2.0:
            warn.append("tier %.1f..%.1f is under 2 m: it gets no camera volume" % (x0, x1))
    for v in [c for p in plan["ground"] for c in p]:
        if abs(v * 100 - round(v * 100)) > 1e-6:
            warn.append("ground coordinate %r is off the 0.01 m grid" % v)
    an = plan["anchors"]
    for a in an:
        fy = floor_at(tiers, a["x"] - 2.0)
        up = fy - a["y"]
        if up > 2.4:
            warn.append("%s is %.2f m over the floor it is thrown from: above the ~2.4 m cold-catch ceiling" % (a["name"], up))
        if a.get("kind") in LAUNCH:
            air = floor_at(tiers, a["x"] + 1.0) - a["y"]
            if air <= 3.2:
                warn.append("%s has %.2f m of air past it: a launch needs > 3.2" % (a["name"], air))
        if a.get("jam") and plan is not None and plan.get("chapters", [[""]])[0][0] != "THE STEPS":
            warn.append("%s is a jam: jam anchors are lab furniture" % a["name"])
    boxes = [(isl["name"], bbox(isl["pts"])) for isl in plan["islands"]]
    for i in range(len(boxes)):
        n, (x0, y0, x1, y1) = boxes[i]
        # clearance over every floor the island hangs over
        for tx0, tx1, fy in tiers:
            if x1 > tx0 and x0 < tx1:
                if y1 > fy - 1.45 + 1e-9:
                    warn.append("island %s is %.2f m over the floor at y %.1f: rock over a crawled floor clears 1.45"
                                % (n, fy - y1, fy))
        for j in range(i + 1, len(boxes)):
            m, (u0, v0, u1, v1) = boxes[j]
            if x0 < u1 and u0 < x1 and y0 < v1 and v0 < y1:
                warn.append("islands %s and %s overlap" % (n, m))
        for a in an:
            # the anchor inside the island's box, less its radius, is a bug
            if x0 < a["x"] < x1 and y0 < a["y"] < y1:
                # the window's hood box contains its anchor by design; test the solid
                if not point_in_poly((a["x"], a["y"]), plan["islands"][i]["pts"]):
                    continue
                warn.append("anchor %s is inside island %s" % (a["name"], n))
    return warn


def point_in_poly(q, pts):
    x, y = q
    inside = False
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        if (ay > y) != (by > y):
            xi = ax + (y - ay) * (bx - ax) / (by - ay)
            if x < xi:
                inside = not inside
    return inside


def totals(plan):
    tiers = plan["tiers"]
    an = plan["anchors"]
    route = tiers[-1][1] - tiers[0][0]
    descent = tiers[-1][2] - tiers[0][2]
    print("route %.1f m   %d tiers   descent %.1f m   %d anchors   %d islands   %d backdrop polygons"
          % (route, len(tiers), descent, len(an), len(plan["islands"]), len(plan["backdrop"])))
    for (name, x0, x1, what) in plan["chapters"]:
        nt = sum(1 for t in tiers if t[0] >= x0 - 1e-9 and t[0] < x1 - 1e-9)
        na = sum(1 for a in an if x0 <= a["x"] < x1)
        fy0 = floor_at(tiers, x0)
        fy1 = floor_at(tiers, x1 - 0.01)
        print("  %-12s x %6.1f..%6.1f  %5.1f m  %d tiers  floors %4.1f..%4.1f  %d anchors  - %s"
              % (name, x0, x1, x1 - x0, nt, fy0, fy1, na, what))
    print("  anchors (nearest neighbour; the contract wants >= 6.5 m):")
    for i, a in enumerate(an):
        best, bj = 1e9, -1
        for j, b in enumerate(an):
            if j != i:
                d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
                if d < best:
                    best, bj = d, j
        fy = floor_at(tiers, a["x"] - 2.0)
        air = floor_at(tiers, a["x"] + 1.0) - a["y"]
        print("    %-14s (%7.2f, %6.2f) r %.2f  %4.2f m over the throwing floor, %4.1f m of air past  nearest %s %.2f m%s"
              % (a["name"], a["x"], a["y"], a["r"], fy - a["y"], air,
                 an[bj]["name"] if bj >= 0 else "-", best, "  < 6.5" if best < 6.5 - 1e-9 else ""))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="write a whip level scene from a plan in metres")
    ap.add_argument("--plan", default="mountain", choices=["mountain", "steps"])
    ap.add_argument("--out", default=None, help="path of the .tscn (default levels/<plan>.tscn; steps must be given one)")
    ap.add_argument("--check", action="store_true", help="print the totals and warnings, write nothing")
    args = ap.parse_args()
    plan = mountain_plan() if args.plan == "mountain" else steps_plan()
    totals(plan)
    warn = check(plan)
    for w in warn:
        print("WARN  " + w)
    if args.check:
        return 0
    out = args.out
    if out is None:
        if args.plan == "steps":
            print("refusing to overwrite levels/steps.tscn: pass --out for the round trip")
            return 2
        out = os.path.join(here, "..", "levels", "%s.tscn" % args.plan)
    write_tscn(plan, out)
    print("wrote %s" % os.path.normpath(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
