@tool
extends Marker2D
## ONE CORNER'S OWN FILLET RADIUS. A child of a terrain Line2D, dragged onto
## one of its vertices (the loader refuses a marker more than 0.02 m from any
## vertex and says which). Overrides the polyline's fillet for that corner
## only; 0 leaves that corner sharp. Drawn in the editor as the circle that
## will be cut into the rock.

## m
@export var radius := 0.35:
	set(v):
		radius = v
		gizmo_extents = maxf(v * 60.0, 6.0)
		queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint() and radius > 0.0:
		draw_arc(Vector2.ZERO, radius * 60.0, 0.0, TAU, 32, Color(0.95, 0.8, 0.4, 0.8), 1.5)
