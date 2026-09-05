@tool
extends Marker2D
## AN ANCHOR - a beam the rope can wrap. One Marker2D per anchor under the
## level's Anchors node; its position is the beam's centre, in px at 60 px/m.
## In the editor this draws the beam at its real radius, the pale collar of a
## jam, and the caption, so what you see is what main.gd's _draw will show.

## m. The traverse's beams: 0.22 (school), 0.11 (doors), 0.10 (fast line);
## the crag's: 0.12-0.14. Thin = less chain to wrap = lockable from further.
@export var radius := 0.12:
	set(v):
		radius = v
		gizmo_extents = v * 60.0
		queue_redraw()
## A JAM anchor supplies the self-crossing itself (main.gd _pinch). The one
## named assist in the game; it wears its own collar. Lab levels only, by rule.
@export var jam := false:
	set(v):
		jam = v
		queue_redraw()
## Drawn under the anchor in the game. The traverse and the crag carry none.
@export var caption := "":
	set(v):
		caption = v
		queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var r := radius * 60.0
	draw_circle(Vector2.ZERO, r, Color(0.55, 0.48, 0.38))
	draw_circle(Vector2.ZERO, r * 0.55, Color(0.4, 0.35, 0.28))
	if jam:
		draw_arc(Vector2.ZERO, r + 3.0, 0.0, TAU, 20, Color(0.62, 0.72, 0.55, 0.85), 2.0)
	if caption != "":
		draw_string(ThemeDB.fallback_font, Vector2(-70.0, r + 32.0), caption,
			HORIZONTAL_ALIGNMENT_CENTER, 140.0, 15, Color(0.72, 0.76, 0.84, 0.9))
