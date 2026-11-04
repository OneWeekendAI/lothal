extends SceneTree
## Per-segment electrical power table for the reference build (forward-flight loss gap,
## MOTOR_REBASELINE.md). Reports the model as it stands, then what each candidate missing term
## would do to the profile average if added on top. Analysis only: nothing here is wired in.
## godot --headless --script res://tools/flight_power_table.gd
const V := 14.8
func _avg(b: Build, cda: float, hotel_w: float, esc_eff: float) -> Array:
	b.drag_coefficient = 0.5 * Build.AIR_DENSITY_KGM3 * cda
	var ceiling: float = b.peak_thrust()["throttle"]
	var tot := 0.0
	var rows: Array = []
	for s in Build.FREESTYLE_FLIGHT_PROFILE:
		var a: float = b.flight_current_at_a(float(s["airspeed_mps"]), float(s["load_factor"]), ceiling) / esc_eff + hotel_w / V
		rows.append(a)
		tot += float(s["fraction"]) * a
	return [tot, rows]

func _init() -> void:
	var b := ReferenceBuild.build()
	var cda0: float = b.drag_coefficient / (0.5 * Build.AIR_DENSITY_KGM3)
	print("reference CdA now = %.4f m2, mah=%s" % [cda0, b.battery["specs"]["mah"]])
	var base := _avg(b, cda0, 0.0, 1.0)
	print("%-14s %5s %4s %7s %7s %9s" % ["segment", "v", "n", "A", "W", "share"])
	var i := 0
	for s in Build.FREESTYLE_FLIGHT_PROFILE:
		var a: float = base[1][i]
		print("%-14s %5.1f %4.1f %7.2f %7.1f %8.1f%%" % [s["name"], s["airspeed_mps"], s["load_factor"], a, a * V, 100.0 * float(s["fraction"]) * a / float(base[0])])
		i += 1
	var mah: float = float(b.battery["specs"]["mah"]) * Build.USABLE_CAPACITY_FRACTION
	var cases := [["as modelled", cda0, 0.0, 1.0], ["hotel 7 W", cda0, 7.0, 1.0], ["ESC 96 %", cda0, 0.0, 0.96],
		["CdA 0.012", 0.012, 0.0, 1.0], ["CdA 0.015", 0.015, 0.0, 1.0], ["CdA 0.020", 0.020, 0.0, 1.0],
		["CdA .015+7W+ESC96", 0.015, 7.0, 0.96], ["CdA .020+7W+ESC96", 0.020, 7.0, 0.96]]
	for c in cases:
		var r := _avg(b, c[1], c[2], c[3])
		print("%-20s avg %6.2f A  %5.2f min" % [c[0], r[0], mah / (float(r[0]) * 1000.0) * 60.0])
	quit()
