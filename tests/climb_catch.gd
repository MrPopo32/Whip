extends SceneTree
## CLIMB: which thrown lock does a door beam give you? Stand at a lead, throw
## route_bot's plan_throw grid (via tapelib.try_throw), list every result.
const TL := preload("res://tests/tapelib.gd")
const RIG := preload("res://tests/climb_rig.gd")

func _initialize() -> void:
	var leads := [2.0, 2.9]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("leads="):
			leads = []
			for s in a.substr(6).split(","):
				leads.append(float(s))
	for lead: float in leads:
		var m: Node2D = TL.new_sim()
		RIG.door_world(m)
		m.spawn = Vector2(-lead, 2.2 - 0.28)
		m._reset()
		for t in 60:
			m.step_tick(m.body_pos, false)
		var snap: Dictionary = m.snapshot()
		var idx := 0
		for a0 in [PI * 0.85, PI * 1.10]:
			for a1 in [-PI * 0.42, -PI * 0.30, -PI * 0.18]:
				for sd in [5, 9, 14]:
					for pull in [false, true]:
						m.restore(snap)
						var c := {"a0": a0, "a1": a1, "sd": sd, "pull": pull, "w": 120}
						var r: Dictionary = TL.try_throw(m, 0, c)
						if bool(r["caught"]):
							print("lead %.1f stroke %2d a0 %.2f a1 %.2f sd %2d pull %-5s -> locked %2d tether %.2f held %s pay %d body %s gnd %s" % [
								lead, idx, a0, a1, sd, str(pull), int(r["locked"]),
								float(r["tether"]), str(r["held"]), int(r["pay"]),
								str(m.body_pos), str(m.grounded)])
						idx += 1
		m.free()
	quit(0)
