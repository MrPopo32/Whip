extends SceneTree
## THE PLACEHOLDER ART PACK, generated. Nothing about the art layer can be
## proved without a texture, and the project has no artist yet, so these three
## PNGs stand in: a tileable rock face, a beam sprite, a cliff skyline for a
## parallax layer. They are PLACEHOLDERS - the point of them is that a pixel
## sampled from the middle of one is a colour no other thing in the frame has,
## so tests/art_gate.gd A5 can say "the texture is on screen" as a number.
##
##   godot --headless --path . -s res://tests/art_pack.gd
##   godot --headless --path . --import          (then: the .import sidecars)
##
## Deterministic by construction: every pixel is a function of (x, y) through
## an integer hash, no RandomNumberGenerator, so the pack regenerates to the
## same bytes on any machine. The lattice noise wraps at the image size, which
## is what makes the rock tile and the skyline mirror without a seam.
const DIR := "res://levels/art/"

# ---------------------------------------------------------------- noise --
static func h2(x: int, y: int, s: int) -> float:
	# a 32-bit integer hash, folded to [0, 1)
	var n := (x * 374761393 + y * 668265263 + s * 982451653) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	n = (n ^ (n >> 16)) & 0x7fffffff
	return float(n & 0xffff) / 65536.0

static func lattice(x: float, y: float, cell: float, wrap_x: int, wrap_y: int, s: int) -> float:
	# value noise on a lattice `cell` px wide, wrapped so the tile repeats
	var gx := x / cell
	var gy := y / cell
	var x0 := int(floor(gx))
	var y0 := int(floor(gy))
	var fx := gx - float(x0)
	var fy := gy - float(y0)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var nx := int(round(float(wrap_x) / cell))
	var ny := int(round(float(wrap_y) / cell))
	var a := h2(posmod(x0, nx), posmod(y0, ny), s)
	var b := h2(posmod(x0 + 1, nx), posmod(y0, ny), s)
	var c := h2(posmod(x0, nx), posmod(y0 + 1, ny), s)
	var d := h2(posmod(x0 + 1, nx), posmod(y0 + 1, ny), s)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)

static func fbm(x: float, y: float, wrap_x: int, wrap_y: int, s: int) -> float:
	# four octaves, 64 px down to 8 px; returns roughly [0, 1]
	var v := 0.0
	var amp := 0.5
	var cell := 64.0
	for o in 4:
		v += amp * lattice(x, y, cell, wrap_x, wrap_y, s + o * 7)
		amp *= 0.5
		cell *= 0.5
	return v / 0.9375

# ---------------------------------------------------------------- the pack --
static func rock() -> Image:
	# 256 x 256, opaque, tileable. Warm grey-brown so it is neither the clear
	# colour (0.09, 0.10, 0.13) nor the greybox backdrop (0.19, 0.205, 0.25)
	# nor the terrain band (0.32, 0.35, 0.42) - A5 samples it by hue.
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var f := fbm(float(x), float(y), n, n, 11)
			var crack := lattice(float(x), float(y), 32.0, n, n, 99)
			var dark := 1.0 if absf(crack - 0.5) > 0.03 else 0.55
			var c := Color(0.36 + 0.22 * f, 0.30 + 0.18 * f, 0.24 + 0.14 * f) * dark
			img.set_pixel(x, y, c)
	return img

static func beam() -> Image:
	# 96 x 64, RGBA: an iron back plate the full size of the sprite, a wooden
	# beam 24 px tall across its middle, two bolts. The plate is deliberately
	# bigger than the beam's collision radius (0.22 m = 13 px) so that the
	# wrap ring at r + 8 px is drawn OVER plate - which is what A5 samples.
	var w := 96
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var f := fbm(float(x), float(y), w, h, 23)
			var c := Color(0.26 + 0.06 * f, 0.25 + 0.05 * f, 0.28 + 0.06 * f, 1.0)
			if y >= 20 and y < 44:
				var grain := 0.5 + 0.5 * sin(float(x) * 0.35 + f * 6.0)
				c = Color(0.58 + 0.10 * grain, 0.40 + 0.07 * grain, 0.22 + 0.05 * grain, 1.0)
				if y == 20 or y == 43:
					c = c.darkened(0.45)
			for bx: int in [16, 80]:
				if Vector2(x - bx, y - 32).length() < 4.0:
					c = Color(0.62, 0.64, 0.68, 1.0)
			img.set_pixel(x, y, c)
	return img

static func cliff() -> Image:
	# 1024 x 384, RGBA: transparent sky over a skyline that is periodic in x
	# (so a ParallaxLayer can mirror it at 1024 px with no step), with ONE
	# tall peak per tile at x = 512 rising to 40 px from the top. A6 finds
	# that peak in two frames and measures how far it moved.
	var w := 1024
	var h := 384
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var t := float(x) / float(w) * TAU
		var top := 250.0 - 30.0 * sin(t * 3.0) - 18.0 * sin(t * 7.0 + 1.3) \
			- 20.0 * lattice(float(x), 0.0, 32.0, w, 32, 41)
		var peak := 210.0 * exp(-pow((float(x) - 512.0) / 70.0, 2.0))
		top -= peak
		for y in h:
			if float(y) >= top:
				var deep := clampf((float(y) - top) / 200.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.17 - 0.04 * deep, 0.18 - 0.04 * deep,
					0.23 - 0.05 * deep, 1.0))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var made: Array = [["rock.png", rock()], ["beam.png", beam()], ["cliff.png", cliff()]]
	for it: Array in made:
		var p: String = DIR + String(it[0])
		var img: Image = it[1]
		var err := img.save_png(p)
		var abs := ProjectSettings.globalize_path(p)
		print("%-10s %4dx%-4d  %s  md5 %s" % [it[0], img.get_width(), img.get_height(),
			"ok" if err == OK else "ERROR %d" % err, FileAccess.get_md5(abs)])
	quit(0)
