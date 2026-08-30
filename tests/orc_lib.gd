extends RefCounted
## THE ORACLE: the taut wrap angle, computed from geometry alone.
##
## Reconstructed from the definition written into main.gd's _measure_wraps and
## validated by the closed-loop audit's own theta_err readout: if this and the
## build disagree by more than ~1e-6 rad on any of the 120960 audited ticks the
## audit says so out loud.
##
##   theta = |PHI| - acos(r / d_handle) - acos(r / d_tip)
##
## PHI is the exact continuous lift of the chain's winding about the beam
## centre (summed with angle_to, which is the signed shortest turn and
## therefore the lift). The two acos terms are the tangent legs, which carry
## winding but wrap nothing - subtracting them leaves only the ARC that a
## capstan is written in. A rope merely LYING across a beam scores 0. A limp
## drape scores pi and no more, however deep it hangs, because pi IS the
## pulley wrap.
##
## nc15 / straddle are the VISIBLE CUE, not the measurement: how a player can
## see, on screen, that the tip has gone over. They gate press timing in the
## audit and nothing else.

static func measure(pos, p_rad, c: Vector2, r: float) -> Dictionary:
	var n: int = pos.size()
	var phi := 0.0
	var mind := 1e9
	var nc15 := 0
	var side_pos := false
	var side_neg := false
	for i in range(n - 1):
		var v0: Vector2 = pos[i] - c
		var v1: Vector2 = pos[i + 1] - c
		phi += v0.angle_to(v1)
		mind = minf(mind, c.distance_to(
			Geometry2D.get_closest_point_to_segment(c, pos[i], pos[i + 1])))
		# contact count on a 15 mm shell, both endpoints in
		if v0.length() < r + p_rad[i] + 0.015 \
				and v1.length() < r + p_rad[i + 1] + 0.015:
			nc15 += 1
		if v0.x > 0.0:
			side_pos = true
		else:
			side_neg = true
	var dh: float = maxf((pos[0] - c).length(), r)
	var dt: float = maxf((pos[n - 1] - c).length(), r)
	var arc: float = absf(phi) - acos(clampf(r / dh, -1.0, 1.0)) \
		- acos(clampf(r / dt, -1.0, 1.0))
	return {
		"A": maxf(arc, 0.0),
		"phi": phi,
		"mind": mind,
		"near": mind < r + 0.30,
		"nc15": nc15,
		"straddle": side_pos and side_neg,
	}
