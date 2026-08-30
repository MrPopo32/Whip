extends "res://main.gd"
## INSTRUMENTED COPY of the sim for the false-negative audit. main.gd is NOT
## touched. The only change is that step_tick samples the wrap measurement
## after EVERY substep as well as once at the tick boundary, so the probe can
## ask whether a fast wrap peaks between ticks and is never sampled.
##
## _measure_wraps() is a pure function of (pos, a_freelen): it writes a_theta
## and a_lockidx and nothing else, and a_lockidx is only ever READ at the tick
## boundary (engagement) or in the _solve_lra branch that requires
## a_freelen >= 0 while a_pinidx < 0, which is unreachable. So calling it
## mid-substep cannot perturb the sim. The probe asserts this with state_hash.

var sub_th := PackedFloat32Array()    # |theta| after each of the 16 substeps
var sub_max := 0.0                    # max of the above, this tick
var sub_arg := 0                      # which substep held the max

func step_tick(cursor_world_m: Vector2, grip: bool) -> void:
	if grip and not taut:
		grip_edge = tick_count
	taut = grip
	cursor_m = cursor_world_m
	target_m = body_pos + (cursor_m - body_pos).limit_length(REACH)
	if not finished:
		run_ticks += 1
	tick_count += 1

	var max_tip := 0.0
	sub_th.clear()
	sub_max = 0.0
	sub_arg = 0
	for s in SUB:
		_substep()
		var v := (pos[NP - 1] - prv[NP - 1]).length() / SDT
		if v > max_tip:
			max_tip = v
		_measure_wraps()
		var th := absf(a_theta[0])
		sub_th.append(th)
		if th > sub_max:
			sub_max = th
			sub_arg = s
	tip_speed = max_tip

	_measure_wraps()
	_update_locks()
	_events()

func pinch0() -> bool:
	return _pinch(0)
