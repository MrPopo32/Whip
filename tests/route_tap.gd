extends "res://main.gd"
## SUBSTEP CONTACT TAP for tests/route_variety.gd.
##
## A per-tick point test tunnels: at speed the tip crosses about a metre per
## 60 Hz tick, so a rope that grazes a ceiling between two ticks is a rope
## that, sampled per tick, never touched it. This subclass overrides
## _substep(), calls super(), and then records which terrain segments and
## which anchors every particle is in contact with - sixteen samples per tick,
## which is the resolution the sim itself resolves contacts at.
##
## ALL STORAGE IS STATIC. snapshot() derives its key set from
## get_property_list(), and static vars are not instance properties, so this
## subclass has exactly main.gd's snapshot layout: restore() of a main.gd
## snapshot into it succeeds, and a tapped run hashes identically to an
## untapped one. route_variety.gd asserts both rather than taking this
## paragraph's word for it.
##
## The tap is OFF by default and costs one branch per substep while off.

static var tap_on := false
static var tap_n := 0                          # substeps tapped so far
static var tap_seg := PackedInt32Array()       # substep contacts per terrain seg
static var tap_first := PackedInt32Array()     # substep of first contact, -1 never
static var tap_lo := PackedInt32Array()        # lowest particle index that touched
static var tap_hi := PackedInt32Array()        # highest particle index that touched
static var tap_anc := PackedInt32Array()       # substep contacts per anchor
static var tap_afirst := PackedInt32Array()
static var tap_arc := PackedInt32Array()       # substep contacts per fillet arc
static var tap_arcfirst := PackedInt32Array()

const TAP_EPS := 0.003                          # m past the particle radius

static func tap_reset(nseg: int, nanc: int, narc := 0) -> void:
	tap_n = 0
	tap_arc = PackedInt32Array(); tap_arc.resize(narc); tap_arc.fill(0)
	tap_arcfirst = PackedInt32Array(); tap_arcfirst.resize(narc); tap_arcfirst.fill(-1)
	tap_seg = PackedInt32Array(); tap_seg.resize(nseg); tap_seg.fill(0)
	tap_first = PackedInt32Array(); tap_first.resize(nseg); tap_first.fill(-1)
	tap_lo = PackedInt32Array(); tap_lo.resize(nseg); tap_lo.fill(999)
	tap_hi = PackedInt32Array(); tap_hi.resize(nseg); tap_hi.fill(-1)
	tap_anc = PackedInt32Array(); tap_anc.resize(nanc); tap_anc.fill(0)
	tap_afirst = PackedInt32Array(); tap_afirst.resize(nanc); tap_afirst.fill(-1)

func _substep() -> void:
	super()
	if not tap_on:
		return
	tap_n += 1
	_tap_sample(tap_seg, tap_first, tap_lo, tap_hi, tap_anc, tap_afirst, tap_n)

# The same point test the per-tick control uses, so the two resolutions differ
# in nothing but how often they look.
func _tap_sample(seg: PackedInt32Array, first: PackedInt32Array,
		lo: PackedInt32Array, hi: PackedInt32Array, anc: PackedInt32Array,
		afirst: PackedInt32Array, stamp: int) -> void:
	for i in NP:
		var q := pos[i]
		var pr: float = p_rad[i] + TAP_EPS
		for s in t_a.size():
			if q.x < t_lo[s].x - pr or q.x > t_hi[s].x + pr \
					or q.y < t_lo[s].y - pr or q.y > t_hi[s].y + pr:
				continue
			var cp := Geometry2D.get_closest_point_to_segment(q, t_a[s], t_b[s])
			if q.distance_to(cp) <= pr:
				seg[s] += 1
				if first[s] < 0:
					first[s] = absi(stamp)
				lo[s] = mini(lo[s], i)
				hi[s] = maxi(hi[s], i)
		for k in a_pos.size():
			if q.distance_to(a_pos[k]) <= a_r[k] + pr:
				anc[k] += 1
				if afirst[k] < 0:
					afirst[k] = absi(stamp)
		# the fillet arcs are terrain too (the crag); only the substep tap
		# records them, the per-tick control passes stamp < 0
		if stamp > 0 and tap_arc.size() > 0:
			for j in t_arc_c.size():
				if q.distance_to(t_arc_c[j]) <= t_arc_r[j] + pr and j < tap_arc.size():
					tap_arc[j] += 1
					if tap_arcfirst[j] < 0:
						tap_arcfirst[j] = stamp
