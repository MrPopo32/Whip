#!/usr/bin/env python3
"""docs/demo.gif and docs/demo.png from a folder of --write-movie frames.

    godot --path . --write-movie <dir>/f.png --quit-after 3000 -- --level demo --replay levels/demo.tape
    python tests/make_gif.py <dir> [--start 0] [--end 1200] [--step 3] [--width 800] [--shot 300]

Every `step`-th frame between start and end (frame indices), scaled to
`width`, at 60/step fps; frame `shot` becomes the still. The top `crop-top`
px (the caption) are cropped off the GIF so it opens on the mountain, not
the text. One palette for the whole GIF, built from a sample of the frames,
and no dithering, so the writer can store each frame as the part that
changed.
"""
import argparse
import os
import sys

from PIL import Image, ImageFilter


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--end", type=int, default=10 ** 9)
    ap.add_argument("--step", type=int, default=3)
    ap.add_argument("--width", type=int, default=800)
    ap.add_argument("--shot", type=int, default=300)
    ap.add_argument("--crop-top", type=int, default=175)
    ap.add_argument("--colors", type=int, default=128)
    ap.add_argument("--out", default="demo")
    ap.add_argument("--blur", type=float, default=0.0,
                    help="Gaussian radius after the downscale; the rock texture is noise the "
                         "GIF cannot compress, and 0.5 px is below what the eye keeps")
    ap.add_argument("--dither", action="store_true",
                    help="Floyd-Steinberg; off by default: dither noise changes on every frame "
                         "and a 42 s GIF went from 8 MB to 66 MB with it on")
    a = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    docs = os.path.join(root, "docs")
    os.makedirs(docs, exist_ok=True)
    names = sorted(f for f in os.listdir(a.dir) if f.endswith(".png"))
    picked = [n for i, n in enumerate(names) if a.start <= i <= a.end and (i - a.start) % a.step == 0]
    if not picked:
        print("no frames", file=sys.stderr)
        sys.exit(1)

    def load(n):
        im = Image.open(os.path.join(a.dir, n)).convert("RGB")
        w, h = im.size
        im = im.crop((0, a.crop_top, w, h))
        im = im.resize((a.width, int(im.size[1] * a.width / w)), Image.LANCZOS)
        return im.filter(ImageFilter.GaussianBlur(a.blur)) if a.blur > 0 else im

    # the palette: a strip of every 12th picked frame, quantized once
    sample = [load(n) for n in picked[:: max(1, len(picked) // 12)]]
    strip = Image.new("RGB", (sample[0].width, sample[0].height * len(sample)))
    for i, im in enumerate(sample):
        strip.paste(im, (0, i * im.height))
    pal = strip.quantize(colors=a.colors, method=Image.Quantize.MEDIANCUT)
    dither = Image.Dither.FLOYDSTEINBERG if a.dither else Image.Dither.NONE
    frames = [load(n).quantize(palette=pal, dither=dither) for n in picked]
    out = os.path.join(docs, a.out + ".gif")
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=int(1000 * a.step / 60),
                   loop=0, optimize=True, disposal=1)
    shot_name = names[min(a.shot, len(names) - 1)]
    shot = Image.open(os.path.join(a.dir, shot_name)).convert("RGB")
    shot.save(os.path.join(docs, a.out + ".png"), optimize=True)
    print("wrote %s (%d frames, %.1f s, %.2f MB) and docs/%s.png (frame %s)" % (
        out, len(frames), len(frames) * a.step / 60.0, os.path.getsize(out) / 1e6, a.out, shot_name))


if __name__ == "__main__":
    main()
