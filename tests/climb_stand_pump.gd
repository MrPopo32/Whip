extends SceneTree
## MOVE 1b - WHAT CAN A STANDING CATCH PUMP? For every cell of climb_stand_map
## with a lock, the certified stroke is thrown again noise-free (it must lock
## again - determinism), then tests/bot_pump.gd's servo drives flat out for
## PUMP_T ticks with the hand shut. Reported (climb_stand_lib.pump_after):
## SWING = half the peak-to-peak body angle about the beam over the last 3 s
## (a body lying still off to one side has |theta| and no swing), the peak
## tangential speed (whole run and last 3 s: what a release would launch),
## ticks grounded / ticks with the feet > 2 cm off the floor, the feet's
## highest point, whether the wrap was lost or went over the top.
## Three hands, each from a fresh noise-free replay of the same catch:
## "park" (cursor on the body, hand shut: the CONTROL - whatever swing it shows
## is the catch's own), "full" (bot_pump flat out), "short" (bot_pump with its
## lengthen half clipped, so it never drives a low-hung body into the floor).
##   godot --headless --path . -s res://tests/climb_stand_pump.gd -- <mapdir> <outdir> <shard> <nshards>
const CL := preload("res://tests/climb_stand_lib.gd")
const PUMP_T := 900
func _initialize() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var md := String(a[0]); var od := String(a[1])
	var shard := int(a[2]); var ns := int(a[3])
	var files: Array = []
	for f in DirAccess.get_files_at(md):
		if f.ends_with(".json"): files.append(f)
	files.sort()
	var i := -1
	for fn: String in files:
		i += 1
		if i % ns != shard: continue
		var outp := "%s/%s" % [od, fn]
		if FileAccess.file_exists(outp): continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [md, fn]))
		var bs: Dictionary = d["best"]
		var res := {"dx": d["dx"], "dy": d["dy"], "r": d["r"]}
		if not bs.is_empty():
			var s: Dictionary = bs["stroke"]
			var c := {"a0": PI * float(s["a0_pi"]), "a1": PI * float(s["a1_pi"]),
				"sd": int(s["sd"]), "pull": bool(s["pull"]), "w": 120}
			var b = CL.new(float(d["dx"]), float(d["dy"]), float(d["r"]))
			var r1: Dictionary = b.throw_fast(c)
			res["lock"] = bool(r1["lock"])
			res["feet0"] = float(r1["body_up"]); res["tether0"] = float(r1["tether"])
			if bool(r1["lock"]):
				for pol in ["park", "full", "short"]:
					b.throw_fast(c)
					res[pol] = b.pump_after(PUMP_T, 0.0, pol)
			b.free_sim()
		var f := FileAccess.open(outp, FileAccess.WRITE)
		f.store_string(JSON.stringify(res)); f.close()
		if res.has("full"):
			var line := "r %.2f dx %.1f dy %.2f feet0 %.2f teth %.2f |" % [float(d["r"]),
				float(d["dx"]), float(d["dy"]), float(res["feet0"]), float(res["tether0"])]
			for pol in ["park", "full", "short"]:
				var q: Dictionary = res[pol]
				line += " %s swing %.0f vt %.1f/%.1f grd %d lost %d t90 %d over %d |" % [pol,
					float(q["swing"]), float(q["peak_vt"]), float(q["vt_late"]),
					int(q["ground"]), int(q["lost"]), int(q["t90"]), int(q["over"])]
			print(line)
	quit(0)
