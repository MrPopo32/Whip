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
