#!/usr/bin/env python3
"""THE DEMO'S ART, GENERATED. Writes levels/art/demo/*.png: a dusk palette,
every texture made here so the repository carries no licence it did not
write. Tileable where it tiles (the rock is a sum of integer-frequency
waves plus per-pixel grain), transparent where the sky shows through.

    python tests/gen_demo_art.py

    sky.png        64 x 900   vertical gradient, scaled 25x wide in the scene
    far.png      1600 x 600   far mountains, hazed, alpha above the skyline
    mid.png      1600 x 500   nearer ridge, darker, alpha above the skyline
    rock.png      256 x 256   the rock mass tile (Polygon2D, repeat)
    beam.png       48 x 48    a branch end-on: the beam
    flag.png       40 x 56    the summit flag
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

random.seed(7)
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "levels", "art", "demo")
os.makedirs(OUT, exist_ok=True)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def gradient(w, h, stops):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                c = lerp(c0, c1, (t - t0) / max(t1 - t0, 1e-6))
                break
        for x in range(w):
            px[x, y] = c
    return im


def skyline(w, h, base_y, amp, octaves, seed, col_top, col_base, haze):
    """A mountain strip: alpha 0 above a jagged line, a vertical tint below."""
    rnd = random.Random(seed)
    phases = [(rnd.uniform(0, math.tau), rnd.uniform(0.7, 1.3)) for _ in range(octaves)]
    line = []
    for x in range(w):
        y = base_y
        for k, (ph, a) in enumerate(phases):
            f = 2 ** k
            y += amp * a / (1.6 ** k) * math.sin(math.tau * f * x / w + ph)
        y += amp * 0.12 * math.sin(math.tau * 23 * x / w + 1.3) * math.sin(math.tau * 7 * x / w)
        line.append(y)
    # transparent pixels carry the ridge's top colour (alpha 0): a blur or a
    # bilinear sample at the rim then mixes the ridge with itself, not with black
    im = Image.new("RGBA", (w, h), (col_top[0], col_top[1], col_top[2], 0))
    px = im.load()
    for x in range(w):
        top = int(line[x])
        for y in range(max(top, 0), h):
            t = (y - top) / max(h - top, 1)
            c = lerp(col_top, col_base, min(1.0, t * 1.4))
            # haze: the base fades toward the sky colour
            a = 255 if t < 0.55 else int(255 * (1.0 - (t - 0.55) / 0.45 * haze))
            px[x, y] = (c[0], c[1], c[2], max(a, 0))
    return im


def value_noise(n, cells, rnd):
    """Tileable value noise: a random lattice of `cells` x `cells`, wrapped,
    bilinear between the knots. Returns an n x n list of floats in 0..1."""
    lat = [[rnd.random() for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * n for _ in range(n)]
    for y in range(n):
        fy = y * cells / n
        y0 = int(fy)
        ty = fy - y0
        ty = ty * ty * (3 - 2 * ty)
        y1 = (y0 + 1) % cells
        for x in range(n):
            fx = x * cells / n
            x0 = int(fx)
            tx = fx - x0
            tx = tx * tx * (3 - 2 * tx)
            x1 = (x0 + 1) % cells
            a = lat[y0][x0] * (1 - tx) + lat[y0][x1] * tx
            b = lat[y1][x0] * (1 - tx) + lat[y1][x1] * tx
            out[y][x] = a * (1 - ty) + b * ty
    return out


def rock_tile(n=256):
    """Layered tileable noise with a hard-edged crack layer and faint strata."""
    rnd = random.Random(11)
    layers = [(4, 1.0), (8, 0.55), (16, 0.3), (32, 0.16), (64, 0.08)]
    fields = [(value_noise(n, c, rnd), w) for c, w in layers]
    cracks = value_noise(n, 12, rnd)
    im = Image.new("RGB", (n, n))
    px = im.load()
    base = (70, 62, 72)
    light = (122, 104, 100)
    dark = (30, 26, 36)
    warm = (138, 104, 76)
    for y in range(n):
        for x in range(n):
            v = sum(f[y][x] * w for f, w in fields) / sum(w for _, w in layers)
            t = (v - 0.5) * 2.4
            strata = 0.12 * math.sin(math.tau * 4 * y / n + 2.0 * fields[0][0][y][x])
            t += strata + rnd.uniform(-0.08, 0.08)
            t = max(-1.0, min(1.0, t))
            c = lerp(base, dark, -t) if t < 0 else lerp(base, light, t)
            # cracks: where the coarse crack field sits near 0.5, a dark seam
            k = abs(cracks[y][x] - 0.5)
            if k < 0.018:
                c = lerp(c, dark, 0.8)
            elif k < 0.03:
                c = lerp(c, dark, 0.35)
            if rnd.random() < 0.01:
                c = lerp(c, warm, 0.5)
            px[x, y] = c
    return im


def beam_sprite(n=48):
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n // 2
    r = n // 2 - 2
    d.ellipse((c - r, c - r, c + r, c + r), fill=(78, 54, 34, 255))
    d.ellipse((c - r + 4, c - r + 4, c + r - 4, c + r - 4), fill=(126, 92, 56, 255))
    for k, rr in enumerate(range(r - 8, 2, -4)):
        col = (104, 74, 44, 255) if k % 2 == 0 else (138, 102, 62, 255)
        d.ellipse((c - rr, c - rr, c + rr, c + rr), fill=col)
    d.ellipse((c - 3, c - 3, c + 3, c + 3), fill=(92, 64, 40, 255))
    # a lit edge, top-left
    d.arc((c - r, c - r, c + r, c + r), 200, 300, fill=(190, 150, 100, 255), width=3)
    return im


def flag_sprite(w=40, h=56):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((4, 2, 7, h - 1), fill=(214, 200, 180, 255))
    d.polygon([(8, 3), (w - 2, 12), (8, 22)], fill=(214, 72, 60, 255))
    d.polygon([(8, 5), (w - 8, 12), (8, 19)], fill=(236, 96, 80, 255))
    return im


if __name__ == "__main__":
    sky = gradient(64, 900, [(0.0, (16, 20, 38)), (0.45, (62, 46, 74)), (0.78, (206, 112, 78)), (1.0, (240, 170, 112))])
    sky.save(os.path.join(OUT, "sky.png"))
    far = skyline(1600, 600, 230, 95, 5, 3, (70, 54, 88), (150, 96, 104), 0.9)
    far = far.filter(ImageFilter.GaussianBlur(0.6))
    far.save(os.path.join(OUT, "far.png"))
    mid = skyline(1600, 500, 170, 120, 5, 9, (44, 36, 58), (82, 60, 76), 0.6)
    mid.save(os.path.join(OUT, "mid.png"))
    rock_tile().save(os.path.join(OUT, "rock.png"))
    beam_sprite().save(os.path.join(OUT, "beam.png"))
    flag_sprite().save(os.path.join(OUT, "flag.png"))
    print("wrote", OUT, sorted(os.listdir(OUT)))
