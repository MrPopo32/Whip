extends Node2D
## THE ROOT OF A SCENE LEVEL. Attach this to the top Node2D of a level under
## res://levels/. The schema - which child nodes to add and what they mean - is
## documented in main.gd under "SCENE LEVELS", and README "Building a level"
## walks through drawing one. In the game nothing here runs: main.gd reads
## these values off the node and frees it. The one thing that does run is
## _ready, and only when THIS scene is the one being played - F6 / "Run
## Current Scene" in the editor, or `godot --path . levels/<name>.tscn` -
## in which case it boots the game on itself, so pressing play on the level
## you are editing plays that level.

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


func _ready() -> void:
	# F6 BOOT. When this scene is the current scene it was run directly, not
	# loaded by main.gd (which instantiates a level scene to read it and never
	# adds it to the tree). Boot the game on this level: instantiate main.tscn,
	# tell it which level before it enters the tree (main.gd's _ready reads
	# level_id first, and only asks the command line when it is empty), hand
	# it the current-scene slot and go away. main.gd loads its own copy of
	# this file by path, so freeing this one loses nothing; keeping it would
	# draw the editor's white Line2Ds over the game.
	if get_tree().current_scene != self:
		return
	# Deferred: during _ready the root is still adding its children and
	# refuses add_child and set_current_scene until the frame settles.
	_boot_f6.call_deferred()

func _boot_f6() -> void:
	var main: PackedScene = load("res://main.tscn")
	var g: Node2D = main.instantiate()
	g.level_id = scene_file_path
	get_tree().root.add_child(g)
	get_tree().current_scene = g
	queue_free()
