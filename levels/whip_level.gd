extends Node2D
## THE ROOT OF A SCENE LEVEL. Attach this to the top Node2D of a level under
## res://levels/. The schema - which child nodes to add and what they mean - is
## documented in main.gd under "SCENE LEVELS", and README "Building a level"
## walks through drawing one. Nothing here runs in the game: main.gd reads
## these three values off the node and frees it.

## m: every convex corner of Ground gets this fillet (the crag's lips: 0.35).
## 0 = sharp corners. A Ground with a whip_terrain.gd fillet > 0 overrides it.
@export var fillet_ground := 0.35
## m: every convex corner of every island (the crag's lumps and hoods: 0.10).
@export var fillet_island := 0.10
## The caption block drawn top-left in the game. Empty = a title made from the
## file name and the one rule every level shares.
@export_multiline var hud := ""
## true: main.gd's _draw paints the WORLD - the grey terrain band, the fillet
## arcs, the flat Backdrop polygons, each anchor's disc - over whatever the
## scene's Art node draws. false: it paints none of that and the Art carries
## the look. The INSTRUMENTATION - the wrap ring and its pulses, the jam
## collar, the caption, the flag, the rope, the body, the crosshair - is drawn
## either way; art does not get to hide the ring. Read off the live instance
## by _art_build, never by the loader, so it cannot touch the fingerprint.
@export var greybox := true
