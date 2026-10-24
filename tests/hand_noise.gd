extends RefCounted
## THE HAND-NOISE MODEL, in one place, so every skill probe scatters the same
## way and their numbers can be laid side by side.
##
## THE SIM HAS NO RNG. THIS PROBE DOES. Every random number here comes from a
## RandomNumberGenerator seeded from (tag, sample index), so a given sample of a
## given stroke is the same bytes every time the probe runs, and any number in
## a report can be reproduced by naming its (tag, sample). Sample 0 of a tier
## whose sigmas are all zero is the noise-free run, bit-identical to the rig
## that has no noise model at all - that is the instrument's null, and the
## probes assert it.
##
## FOUR SOURCES, each one thing a human hand does that a script does not:
##
##   OFFSET   one Gaussian vector per throw, sigma off_px in x and y
##            independently: WHERE you put your whole hand this time.
##   TREMOR   a per-tick Gaussian process, low-passed at TREMOR_HZ (an AR(1)
##            with pole exp(-2 pi f dt) = 0.592 at 5 Hz, innovation scaled so
##            the STATIONARY sd is trem_px), added to the cursor every tick:
##            the wobble in a hand that is trying to hold still.
##   SPEED    one Gaussian scalar per throw, sd speed_sd (0.05 = 5%), that
##            multiplies the DURATION of the stroke: the same gesture, a little
##            faster or slower.
##   TIMING   one integer per throw, uniform in [-jit, +jit] ticks, added to
##            the tick the hand closes: the press landing early or late.
##
## THE PIXEL. main.gd's control is a constant in metres per PHYSICAL pixel of
## mouse: 1 / PPM_INPUT = 16.67 mm per px, "1.66667 m per 100 physical px at
## every zoom and every window size" (README, cam_gate C2; the 138 px figure
## there is the reach circle's DIAMETER, 2 x 1.15 m). The brief that commissioned
## this probe wrote "1 px = 8.3 mm", which is that diameter read as a radius;
## the source's own constant is used here, which makes every tier below TWICE
## as harsh in millimetres as the brief intended. Read the mm column.

const M_PER_PX := 1.0 / 60.0          # main.gd PPM_INPUT, physical px -> m
const DT := 1.0 / 60.0
const TREMOR_HZ := 5.0

# The tiers. offset and tremor in px, speed as a fraction, timing in ticks.
const TIERS := {
	"null":     {"off": 0.0, "trem": 0.0, "speed": 0.0,  "jit": 0},
	"mouse03":  {"off": 0.3, "trem": 0.3, "speed": 0.05, "jit": 1},
	"mouse1":   {"off": 1.0, "trem": 1.0, "speed": 0.05, "jit": 2},
	"trackpad": {"off": 2.0, "trem": 2.0, "speed": 0.05, "jit": 3},
	# the trackpad tier split into its parts, for attribution
	"off_only":  {"off": 2.0, "trem": 0.0, "speed": 0.0,  "jit": 0},
	"trem_only": {"off": 0.0, "trem": 2.0, "speed": 0.0,  "jit": 0},
	"speed_only": {"off": 0.0, "trem": 0.0, "speed": 0.05, "jit": 0},
	"jit_only":  {"off": 0.0, "trem": 0.0, "speed": 0.0,  "jit": 3},
}

var rng := RandomNumberGenerator.new()
var tier: Dictionary
var tag: String
var sample: int
var offset := Vector2.ZERO            # m, this throw's whole-hand offset
var speed := 1.0                      # this throw's duration scale
var jit := 0                          # this throw's press shift, ticks
var trem := Vector2.ZERO              # m, the tremor's current value
var alpha := 0.0                      # AR(1) pole
var innov := 0.0                      # AR(1) innovation sd, m

static func seed_of(t: String, s: int) -> int:
	# String.hash() is Godot's own deterministic 32-bit string hash; mixing the
	# sample in through a second term keeps neighbouring samples uncorrelated.
	return int(("%s#%d" % [t, s]).hash()) * 2654435761 + s

func _init(tier_name: String, t: String, s: int) -> void:
	tier = TIERS[tier_name]
	tag = t
	sample = s
	rng.seed = seed_of(t + "/" + tier_name, s)
	var off_m: float = float(tier["off"]) * M_PER_PX
	var trem_m: float = float(tier["trem"]) * M_PER_PX
	# draw order is fixed, so the same seed gives the same throw whatever the
	# caller does with the tremor afterwards
	offset = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * off_m \
		if off_m > 0.0 else Vector2.ZERO
	speed = clampf(1.0 + rng.randfn(0.0, 1.0) * float(tier["speed"]), 0.8, 1.2) \
		if float(tier["speed"]) > 0.0 else 1.0
	jit = rng.randi_range(-int(tier["jit"]), int(tier["jit"])) \
		if int(tier["jit"]) > 0 else 0
	alpha = exp(-2.0 * PI * TREMOR_HZ * DT)
	innov = trem_m * sqrt(1.0 - alpha * alpha)
	# start the tremor from its stationary distribution
	trem = Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * trem_m \
		if trem_m > 0.0 else Vector2.ZERO

func is_null() -> bool:
	return float(tier["off"]) == 0.0 and float(tier["trem"]) == 0.0 \
		and float(tier["speed"]) == 0.0 and int(tier["jit"]) == 0

## advance the tremor one tick and return the cursor error to add this tick
## (offset + tremor), in metres
func tick() -> Vector2:
	if innov > 0.0:
		trem = trem * alpha + Vector2(rng.randfn(0.0, 1.0),
			rng.randfn(0.0, 1.0)) * innov
	return offset + trem

## the noise's own state, so a two-pass probe can rewind it with the sim
func save_state() -> Dictionary:
	return {"state": rng.state, "trem": trem}

func restore_state(d: Dictionary) -> void:
	rng.state = int(d["state"])
	trem = d["trem"]

func describe() -> String:
	return "off %.2fpx (%.1fmm) trem %.2fpx (%.1fmm) speed sd %.0f%% jit +/-%d ticks" % [
		float(tier["off"]), float(tier["off"]) * M_PER_PX * 1000.0,
		float(tier["trem"]), float(tier["trem"]) * M_PER_PX * 1000.0,
		float(tier["speed"]) * 100.0, int(tier["jit"])]
