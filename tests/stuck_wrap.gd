extends SceneTree
## The two ways a wrap used to become permanently stuck:
##  1. open the hand briefly, then close it again - the payout froze and the
##     wrap never freed (24 of 27 trials never came off in 15 s)
##  2. feather the button - every grip reset the run, so 7.5 s of open hand
##     made no progress at all
## Both should now be impossible: any ungripped tick takes you off.

func _rig() -> Node2D:
	var m: Node2D = load("res://main.gd").new()
	m.external_drive = true
	m.setup_sim()
	m.t_a.clear(); m.t_b.clear(); m.t_n.clear()
	for k in range(1, m.a_pos.size()):
		m.a_pos[k] = Vector2(0.0, 900.0)
	m.a_pos[0] = Vector2(0.0, -40.0); m.a_r[0] = 0.16
	var helper = load("res://tests/sim_test.gd").new()
	helper._prewrap(m, 0, 1.6)
	m.a_pos[0] = Vector2(0.0, -40.0)
	for t in 60:
		m.step_tick(m.body_pos, true)
	return m

func _initialize() -> void:
	print("1. open the hand for N ticks, then close it again")
	print("   N   freed?   ticks")
	for n in [1, 2, 3, 6, 12]:
		var m := _rig()
		if m.a_freelen[0] < 0.0:
			print("   (setup wrap did not hold)"); m.free(); continue
		var freed := -1
		for t in 900:
			var grip: bool = t >= n              # open for n ticks, then closed
			m.step_tick(m.body_pos, grip)
			if m.a_freelen[0] < 0.0 and freed < 0:
				freed = t
		print("  %2d   %-6s   %s" % [n, "yes" if freed >= 0 else "NEVER",
			str(freed) if freed >= 0 else "-"])
		m.free()
	print("")
	print("2. feathering the button (open/closed alternating)")
	print("   pattern      freed?   ticks")
	for pat in [[1, 1], [2, 2], [2, 6], [3, 12]]:
		var m := _rig()
		if m.a_freelen[0] < 0.0:
			print("   (setup wrap did not hold)"); m.free(); continue
		var freed := -1
		var period: int = pat[0] + pat[1]
		for t in 900:
			var grip: bool = (t % period) >= pat[0]
			m.step_tick(m.body_pos, grip)
			if m.a_freelen[0] < 0.0 and freed < 0:
				freed = t
		print("   %d open/%2d closed   %-6s   %s" % [pat[0], pat[1],
			"yes" if freed >= 0 else "NEVER", str(freed) if freed >= 0 else "-"])
		m.free()
	quit(0)
