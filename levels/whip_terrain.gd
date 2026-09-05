@tool
extends Line2D
## ROCK. A Line2D named Ground is the one open chain of the level; a Line2D
## under Islands is a closed loop. The line IS the collision - the rope and the
## body meet exactly this polyline, at PPM = 60 px/m - and anything painted
## behind it (Backdrop) is free and cannot touch them.
##
## In the editor this script draws a short pip on the AIR side of every
## segment, as main.gd's loader will wind it: the loader decides the winding
## itself (an island is solid inside, the ground has the sky above), so the
## pips show where it thinks the air is. If a pip points into what you meant
## as rock, the shape is not what you think it is.

## m: fillet radius for every convex corner of this polyline. -1 = the level's
## default (fillet_ground for Ground, fillet_island for an island), 0 = sharp,
## > 0 = this radius. One corner can be given its own radius with a Marker2D
## child carrying whip_fillet.gd, dragged onto that vertex.
@export var fillet := -1.0:
	set(v):
		fillet = v
		queue_redraw()

const PIP := 10.0                     # px, the pip's length
const PIP_COL := Color(0.55, 0.85, 0.95, 0.9)

func _draw() -> void:
	if not Engine.is_editor_hint() or points.size() < 2:
		return
	var is_loop := closed or (get_parent() != null and get_parent().name == "Islands")
	var p := points
	# the loader's own rule, restated: solid inside a loop is a positive
	# shoelace sum in y-down coordinates; the ground, closed over the sky, has
	# the air inside and sums negative. Reverse for the drawing if it is the
	# other way round, exactly as the loader will.
	var q := p.duplicate()
	if not is_loop:
		q.append(Vector2(p[p.size() - 1].x, -1.0e6))
		q.append(Vector2(p[0].x, -1.0e6))
	var s := 0.0
	for i in q.size():
		var a := q[i]
		var b := q[(i + 1) % q.size()]
		s += a.x * b.y - b.x * a.y
	var flip := (s < 0.0) if is_loop else (s > 0.0)
	var n := p.size() - (0 if is_loop else 1)
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		var d := b - a
		if d.length_squared() < 0.000001:
			continue
		var nrm := Vector2(d.y, -d.x).normalized() * (-1.0 if flip else 1.0)
		var mid := (a + b) * 0.5
		draw_line(mid, mid + nrm * PIP, PIP_COL, 2.0)
	# the first point, so the walk direction can be read
	draw_circle(p[0], 4.0, PIP_COL)
