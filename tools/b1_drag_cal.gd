extends SceneTree
## B1 calibration tool: the reference build's rotor H-force (RotorHForce, BET) at a hover and at the calibrated top
## speed, and the REFERENCE_DRAG_AREA_M2 that puts body + rotor drag on that top speed at Build.TOP_SPEED_LEAN_RAD.
## usage: godot --headless --script res://tools/b1_drag_cal.gd [target_kmh]
const DEFAULT_TARGET_KMH := 108.2


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var target := float(args[0]) if args.size() > 0 else DEFAULT_TARGET_KMH
	var b := ReferenceBuild.build()
	var w := b.weight_n()
	var c := b.rotor_h_coeffs()
	print("H coeffs P %s kg, I %s kg/m; lean cap %.1f deg; W %.3f N" % [c.x, c.y, rad_to_deg(Build.TOP_SPEED_LEAN_RAD), w])
	for v in [1.0, 3.0]:
		var h := b.rotor_h_force_n(v, 0.0, w)
		print("level at %.0f m/s: H %.4f N, mu_h %.4f /s" % [v, h, h / v / b.mass_properties.total_mass_kg])
	print("REFERENCE_DRAG_AREA_M2 now %.6f, top speed now %.2f km/h" % [Build.REFERENCE_DRAG_AREA_M2, b.top_speed_kmh()])
	var vt := target / 3.6
	var trim := b.trim_lean(vt, w)
	print("at %.1f km/h now: lean %.2f deg, T %.3f N, rotor H %.3f N, horizontal drag %.3f N" % [target,
		rad_to_deg(trim["lean_rad"]), trim["thrust_n"], trim["rotor_h_n"], trim["drag_h_n"]])
	var ax := b.drag_axes
	var dc := b.drag_coefficient
	var lo := 0.0
	var hi := 20.0
	for _i in 50:
		var f := (lo + hi) * 0.5
		b.drag_axes = ax * f
		b.drag_coefficient = dc * f
		if b.top_speed_kmh() > target:
			lo = f
		else:
			hi = f
	b.drag_axes = ax * lo
	b.drag_coefficient = dc * lo
	var t2 := b.trim_lean(vt, w)
	print("scale %.5f -> REFERENCE_DRAG_AREA_M2 %.6f; top speed %.2f km/h; at it lean %.2f deg, rotor H %.3f N (horiz %.3f N), total horizontal drag %.3f N" % [
		lo, Build.REFERENCE_DRAG_AREA_M2 * lo, b.top_speed_kmh(), rad_to_deg(t2["lean_rad"]), t2["rotor_h_n"],
		float(t2["rotor_h_n"]) * cos(float(t2["lean_rad"])), t2["drag_h_n"]])
	quit()
