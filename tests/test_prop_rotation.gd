class_name TestPropRotation
extends RefCounted
## Turning propellers, and the one thing about them that is an architectural claim rather than a
## visual effect: **PropellerMesh is a renderer of a rate it is given.**
##
## It holds no speed of its own and derives none. In Sim the rate comes from the published
## observables, which is the single source of truth for RPM (architecture.md); in Lab, where there
## is no powertrain yet, Lab supplies a nominal hand-spin — through the same input, so that when the
## thrust stand lands it feeds real RPM into a seam that already exists. A propeller that animated
## itself would be a second source of truth for RPM, which is the exact drift the observables layer
## was drawn to prevent, and it would be invisible: the props would spin convincingly while
## agreeing with nothing.
##
## Two other things are checked here that no screenshot catches.
##
## DIRECTION. Diagonal pairs turn the same way and adjacent pairs oppose. Get it wrong and the
## picture looks completely normal — four spinning props — while the aircraft on screen is one no
## quadcopter could fly. So the visual direction is asserted against MotorLayout.SPIN, which is the
## same table the yaw torque is computed from.
##
## ALIASING. A real prop runs to ~29,000 RPM. Rotating discrete blades by a per-frame delta at 60
## fps means a 3-blade prop crosses its own 120-degree symmetry in a fraction of a frame, and what
## you see is a prop crawling, standing still, or turning backwards. That is not a polish problem;
## it is the render telling the pilot something false about the machine. Above a threshold derived
## from the frame rate and the blade count, the blades stop being drawn and a swept disc is drawn
## instead — which is also what a real rotor looks like.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append(_test_no_speed_of_its_own(catalog))
	results.append(_test_the_source_file_holds_no_speed())
	results.append(_test_a_given_rate_turns_the_prop(catalog))
	results.append(_test_direction_comes_from_motor_layout(catalog))
	results.append(_test_the_blur_disc_takes_over_before_aliasing(catalog))
	results.append(_test_the_threshold_follows_blade_count_and_frame_rate())
	results.append(_test_sim_drives_the_props_from_the_observables(catalog))
	results.append(_test_lab_hand_spins_below_the_threshold(catalog))

	return results


static func _prop(catalog: PartsCatalog, prop_id := "prop_5x43x3") -> PropellerMesh:
	var mesh := PropellerMesh.new()
	mesh.rebuild(catalog.get_part(prop_id))
	return mesh


static func _airframe(catalog: PartsCatalog) -> AirframeModel:
	var airframe := AirframeModel.new()
	airframe.rebuild(Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID))
	return airframe


# ---------------------------------------------------------------------------
# It renders a rate; it does not have one
# ---------------------------------------------------------------------------

## Nobody has said how fast. Nothing turns. A propeller that spins the moment it exists is one that
## chose a speed for itself.
static func _test_no_speed_of_its_own(catalog: PartsCatalog) -> TestResult:
	var mesh := _prop(catalog)
	var start := mesh.rotation.y
	for i in 120:
		mesh.advance(1.0 / 60.0)
	var moved: float = absf(mesh.rotation.y - start)
	var rate := mesh.rate_rad_s()
	mesh.free()

	return TestResult.new(
		"a propeller that has not been given a rate does not turn",
		moved < 1e-9 and rate == 0.0,
		"two seconds of frames moved it %.9f rad, rate reads %.4f rad/s" % [moved, rate]
	)


## The acceptance criterion is literally "grep it and confirm", so this greps it. A constant naming
## an RPM, a revolutions-per-second, or an angular speed inside this file would be a second source
## of truth for how fast a rotor turns, wherever it came from.
##
## The blur THRESHOLD is not such a constant and is deliberately not matched: it is a limit on what
## the renderer can draw at a given frame rate, computed from frame rate and blade count, and it
## never sets how fast anything spins.
static func _test_the_source_file_holds_no_speed() -> TestResult:
	var source := FileAccess.get_file_as_string("res://src/lab/propeller_mesh.gd")
	var offenders: Array[String] = []
	for line in source.split("\n"):
		var text := String(line)
		# Declarations at class level only — an indented `var rpm` inside a function is a local
		# holding a value it was handed, which is the opposite of the thing being looked for.
		if not text.begins_with("const ") and not text.begins_with("var "):
			continue
		var name := text.split(" ")[1].split(":")[0].split("=")[0].to_upper()
		for banned in ["RPM", "SPEED", "REV_PER", "OMEGA"]:
			if name.contains(banned) and not name.contains("THRESHOLD") and not name.contains("FPS"):
				offenders.append(text)

	return TestResult.new(
		"propeller_mesh.gd declares no rotation speed of its own",
		offenders.is_empty(),
		"scanned %d lines, %s" % [source.split("\n").size(),
			"no speed declared" if offenders.is_empty() else str(offenders)]
	)


## Given a rate, it turns at that rate — checked as an angle after a known time rather than as a
## per-frame delta, so a rate applied twice or half would show up.
static func _test_a_given_rate_turns_the_prop(catalog: PartsCatalog) -> TestResult:
	var mesh := _prop(catalog)
	# 600 RPM is 10 rev/s, so a quarter second is two and a half turns: half a turn from where it
	# started, whatever the frame rate the time was taken in.
	mesh.set_rate_rpm(600.0)
	for i in 15:
		mesh.advance(1.0 / 60.0)
	var angle := fposmod(mesh.rotation.y, TAU)
	var expected := PI
	var rate_error: float = absf(mesh.rate_rad_s() - 600.0 / 60.0 * TAU)
	mesh.free()

	return TestResult.new(
		"a propeller given 600 RPM turns two and a half times in a quarter of a second",
		absf(angle - expected) < 1e-4 and rate_error < 1e-6,
		"ended at %.4f rad (expected %.4f), rate %.4f rad/s" % [angle, expected, 600.0 / 60.0 * TAU]
	)


## The invariant MotorLayout states, asserted on what is actually drawn: diagonals together,
## adjacents opposed, and each prop's direction equal to that motor's own SPIN — not merely
## self-consistent, which a table with every sign flipped would also be.
static func _test_direction_comes_from_motor_layout(catalog: PartsCatalog) -> TestResult:
	var airframe := _airframe(catalog)
	airframe.set_all_rates_rpm(300.0)

	var problems: Array[String] = []
	var directions: Dictionary = {}
	for motor_name in MotorLayout.MOTOR_NAMES:
		var prop: PropellerMesh = airframe.propeller_meshes[motor_name]
		var before := prop.rotation.y
		prop.advance(1.0 / 240.0)
		# angle_difference, not a subtraction: the rotation is wrapped into [0, TAU), so a prop
		# turning the negative way from zero lands just under TAU and a plain subtraction reads it
		# as having turned forwards. That mistake makes all four look like they agree.
		var direction: float = signf(angle_difference(before, prop.rotation.y))
		directions[motor_name] = direction
		if direction != signf(MotorLayout.SPIN[motor_name]):
			problems.append("%s turns %+.0f, MotorLayout.SPIN says %+.0f" % [
				motor_name, direction, MotorLayout.SPIN[motor_name]])

	# Said again as the physical invariant, so a plausible-looking SPIN table with a sign wrong in it
	# fails here even though every prop agrees with that table.
	if directions["M1"] != directions["M4"] or directions["M2"] != directions["M3"]:
		problems.append("diagonal pairs do not turn together")
	if directions["M1"] == directions["M2"]:
		problems.append("adjacent motors turn the same way")

	airframe.free()

	return TestResult.new(
		"props turn the way MotorLayout.SPIN says: diagonals together, adjacents opposed",
		problems.is_empty(),
		"M1 %+.0f  M2 %+.0f  M3 %+.0f  M4 %+.0f%s" % [
			directions["M1"], directions["M2"], directions["M3"], directions["M4"],
			"" if problems.is_empty() else " — " + str(problems)]
	)


# ---------------------------------------------------------------------------
# Aliasing
# ---------------------------------------------------------------------------

## Below the threshold you see blades; above it you see the disc they sweep, at the real radius.
## Both halves matter: a prop that switched too eagerly would never show the twist Lab exists to
## show, and one that never switched would strobe through the whole of Sim.
static func _test_the_blur_disc_takes_over_before_aliasing(catalog: PartsCatalog) -> TestResult:
	var mesh := _prop(catalog)
	var threshold := PropellerMesh.max_discrete_rpm(mesh.blade_count, PropellerMesh.DESIGN_FPS)
	var problems: Array[String] = []

	mesh.set_rate_rpm(threshold * 0.5)
	if not mesh.blades_drawn():
		problems.append("blades are hidden at half the threshold")
	if mesh.blur_drawn():
		problems.append("the blur disc is showing at half the threshold")

	mesh.set_rate_rpm(threshold * 2.0)
	if mesh.blades_drawn():
		problems.append("discrete blades are still drawn at twice the threshold")
	if not mesh.blur_drawn():
		problems.append("no blur disc at twice the threshold")

	# A hover on the reference build is thousands of RPM: that case must be the disc.
	mesh.set_rate_rpm(12000.0)
	if mesh.blades_drawn() or not mesh.blur_drawn():
		problems.append("a hover RPM still draws discrete blades")

	# The disc has to be the size of the sweep, or it is a decoration rather than the rotor.
	var disc := mesh.get_node_or_null("BlurDisc") as MeshInstance3D
	if disc == null:
		problems.append("there is no blur disc to draw")
	else:
		var radius: float = (disc.mesh as CylinderMesh).top_radius
		if absf(radius - mesh.radius_m) > 0.0005:
			problems.append("the disc is %.4f m across the radius, the prop sweeps %.4f m" % [
				radius, mesh.radius_m])
		if (disc.material_override as StandardMaterial3D).transparency \
				== BaseMaterial3D.TRANSPARENCY_DISABLED:
			problems.append("the disc is opaque")

	# And back down again — landing after a flight has to bring the blades back.
	mesh.set_rate_rpm(0.0)
	if not mesh.blades_drawn() or mesh.blur_drawn():
		problems.append("a stopped prop does not show its blades again")

	var blades := mesh.blade_count
	mesh.free()

	return TestResult.new(
		"discrete blades below the threshold, a swept disc above it, and back again",
		problems.is_empty(),
		"%d blades, threshold %.0f RPM%s" % [blades, threshold,
			"" if problems.is_empty() else " — " + str(problems)]
	)


## The threshold is a consequence of the frame rate and the blade count, not a taste. A 4-blade prop
## repeats its own pattern every 90 degrees against a 3-blade's 120, so it must switch to the disc
## SOONER, and a higher frame rate must allow discrete blades for longer. Both directions are
## checked, plus the Nyquist bound itself: one frame must never advance the blades by as much as
## half the angle between them.
static func _test_the_threshold_follows_blade_count_and_frame_rate() -> TestResult:
	var problems: Array[String] = []

	var three := PropellerMesh.max_discrete_rpm(3, 60.0)
	var four := PropellerMesh.max_discrete_rpm(4, 60.0)
	var two := PropellerMesh.max_discrete_rpm(2, 60.0)
	if not (two > three and three > four):
		problems.append("more blades does not mean a lower threshold (2:%.0f 3:%.0f 4:%.0f)" % [
			two, three, four])
	if PropellerMesh.max_discrete_rpm(3, 120.0) <= three:
		problems.append("twice the frame rate does not allow a higher rate")

	for blades in [2, 3, 4]:
		for fps in [60.0, 90.0, 120.0]:
			var threshold := PropellerMesh.max_discrete_rpm(blades, fps)
			var radians_per_frame: float = threshold / 60.0 * TAU / fps
			var half_blade_spacing: float = TAU / float(blades) * 0.5
			if radians_per_frame >= half_blade_spacing:
				problems.append("%d blades at %.0f fps: %.4f rad/frame against a %.4f rad limit" % [
					blades, fps, radians_per_frame, half_blade_spacing])

	return TestResult.new(
		"the blur threshold is the aliasing bound for that blade count and frame rate",
		problems.is_empty(),
		"at 60 fps: 2-blade %.0f, 3-blade %.0f, 4-blade %.0f RPM%s" % [two, three, four,
			"" if problems.is_empty() else " — " + str(problems)]
	)


# ---------------------------------------------------------------------------
# Where the rate comes from, in each room
# ---------------------------------------------------------------------------

## In Sim the rate is the published observable, per motor, in MotorLayout order. Four different
## values are used deliberately: a wiring mistake that fed the mean, or motor 1's RPM to all four,
## would pass any test that spun them all at the same speed.
static func _test_sim_drives_the_props_from_the_observables(catalog: PartsCatalog) -> TestResult:
	var airframe := _airframe(catalog)
	var observables := Observables.new()
	observables.rpm = PackedFloat32Array([1000.0, 2000.0, 3000.0, 4000.0])
	airframe.set_rates_rpm(observables.rpm)

	var problems: Array[String] = []
	for i in MotorLayout.MOTOR_NAMES.size():
		var motor_name: String = MotorLayout.MOTOR_NAMES[i]
		var prop: PropellerMesh = airframe.propeller_meshes[motor_name]
		var expected: float = observables.rpm[i] / 60.0 * TAU * MotorLayout.SPIN[motor_name]
		if absf(prop.rate_rad_s() - expected) > 1e-4:
			problems.append("%s runs at %.2f rad/s, observable %.0f RPM implies %.2f" % [
				motor_name, prop.rate_rad_s(), observables.rpm[i], expected])
	airframe.free()

	return TestResult.new(
		"in Sim each prop turns at its own motor's published RPM",
		problems.is_empty(),
		"1000/2000/3000/4000 RPM across the four motors, %s" % (
			"each on its own" if problems.is_empty() else str(problems))
	)


## In Lab there is no powertrain, so Lab supplies a nominal hand-spin — and it has to go in through
## the same input, and be slow enough to actually see. A Lab rate above the aliasing threshold would
## hide the blade twist behind a blur disc, which is the one thing this screen was built to show.
static func _test_lab_hand_spins_below_the_threshold(catalog: PartsCatalog) -> TestResult:
	var lab := LabScreen.new(catalog, AssemblyTweaks.new())
	var prop: PropellerMesh = lab.airframe.propeller_meshes["M1"]
	var rate := prop.rate_rad_s()
	var threshold := PropellerMesh.max_discrete_rpm(prop.blade_count, PropellerMesh.DESIGN_FPS)

	var problems: Array[String] = []
	if rate == 0.0:
		problems.append("Lab's props are not turning at all")
	if LabScreen.HAND_SPIN_RPM >= threshold:
		problems.append("Lab spins at %.0f RPM, above the %.0f RPM threshold" % [
			LabScreen.HAND_SPIN_RPM, threshold])
	if not prop.blades_drawn():
		problems.append("Lab is showing a blur disc instead of blades")

	# And a part change must not leave the new props stopped.
	lab.propeller_picker.select_id("prop_7x35x2")
	var after: PropellerMesh = lab.airframe.propeller_meshes["M1"]
	if after.rate_rad_s() == 0.0:
		problems.append("the props stopped after a prop change")

	lab.free()

	return TestResult.new(
		"Lab hand-spins its props through the same input, slowly enough to see the blades",
		problems.is_empty(),
		"%.0f RPM against a %.0f RPM threshold, blades drawn%s" % [
			LabScreen.HAND_SPIN_RPM, threshold,
			"" if problems.is_empty() else " — " + str(problems)]
	)
