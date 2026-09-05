@tool
extends Line2D
## ONE CAMERA VOLUME. A Line2D under the level's Camera node with exactly two
## points, both on the tier's floor: the camera holds this floor's shelf while
## the body's x is between them (main.gd CAM_VOLS / cam_law). Leave the Camera
## node out entirely to get the derived table - one volume per floor, boundary
## 1.0 m before each lip - which is what both shipped levels use.

## The authored zoom for this volume. Every shipped volume is 1.00, and the
## camera section of main.gd says why that column is a budget, not a style.
@export var zoom := 1.0
