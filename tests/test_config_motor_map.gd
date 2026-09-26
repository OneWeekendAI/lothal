class_name TestConfigMotorMap
extends RefCounted
## Config room slice C3 — the motor map DRAWN ON THE AIRCRAFT, and the props-in/props-out control
## that writes through to the C2 config block.
## Design: plans/2026-09-20-config-room-design.md §4.3, §5 and §7.
##
## C2 made the spin direction an authored value that reaches the physics. It did not reach the
## PICTURE: `AirframeModel` still set each propeller's direction from the `SPIN` constant, so a
## builder could choose props-in, watch four propellers keep turning exactly as before, and learn
## that Lothal's controls are decorative — the one thing §5 names as the most expensive outcome
## this app can produce. So the checks below are in two groups:
##
##   THE PICTURE  — the props turn the authored way, and the map is drawn on the aircraft at the
##                  geometry the physics uses (`MotorLayout.motor_position`), with a swept arrow
##                  whose WINDING follows the sign. The arrow matters: a label alone would let the
##                  drawn rotor and the drawn direction disagree, and the rotor is what is believed.
##   THE CONTROL  — selecting props-in reaches the project, survives a round trip, is per drone,
##                  and lands on the aircraft in the same breath.
##
## §4.3's refusal is checked too: Lothal cannot know your ESC's motor order, and the panel has to
## say so where the order is read rather than in a design document.

const EPS := 1e-9

## An authored map that cannot fly — the C2 suite's own fixture, so the warning this panel shows is
## the one that suite pins.
const UNFLYABLE := {"M1": 1.0, "M2": 1.0, "M3": -1.0, "M4": 1.0}


static func run() -> Array:
	var results: Array = []
	results.append_array(_the_drawn_props_turn_the_authored_way())
	results.append_array(_the_map_is_drawn_on_the_aircraft())
	results.append_array(_the_arrow_winds_the_way_the_motor_turns())
	results.append_array(_the_map_is_shown_in_config_and_nowhere_else())
	results.append_array(_the_room_shows_its_panel())
	results.append_array(_the_control_reaches_the_aircraft_and_the_project())
	results.append(_the_choice_is_per_drone())
	results.append_array(_a_wrong_map_is_warned_about_on_the_panel())
	return results


## The defect C3 exists to close. The default build must draw today's directions bit for bit — the
## literals, not `SPIN`, for §5.2's reason — and a props-in build must draw all four reversed.
static func _the_drawn_props_turn_the_authored_way() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var expected := {"M1": 1.0, "M2": -1.0, "M3": -1.0, "M4": 1.0}

	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, {}))
	var default_ok := true
	var default_detail: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		var prop: PropellerMesh = airframe.propeller_meshes[name]
		default_ok = default_ok and prop.spin == float(expected[name])
		default_detail.append("%s %+.0f" % [name, prop.spin])
	results.append(TestResult.new(
		"the default build's drawn propellers turn the way the constant table always did",
		default_ok, ", ".join(default_detail)))

	airframe.rebuild(_build(catalog, {"motor_spin": "props_in"}))
	var flipped_ok := true
	var flipped_detail: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		var prop: PropellerMesh = airframe.propeller_meshes[name]
		# Signed rate, not just the field: `spin` is only believable if it reaches the rotation the
		# builder actually watches.
		prop.set_rate_rpm(6000.0)
		flipped_ok = flipped_ok and prop.spin == -float(expected[name]) \
			and signf(prop.rate_rad_s()) == -float(expected[name])
		flipped_detail.append("%s %+.0f (%.1f rad/s)" % [name, prop.spin, prop.rate_rad_s()])
	results.append(TestResult.new(
		"a props-in build's drawn propellers all turn the other way, at a reversed rate",
		flipped_ok, ", ".join(flipped_detail)))
	airframe.free()
	return results


## §4.3 — "M1..M4 drawn on THEIR aircraft". Drawn at `MotorLayout.motor_position`, which is the
## point the physics takes its torque arm from, rather than at a second copy of that arithmetic;
## and reading the direction the aircraft is actually configured for.
static func _the_map_is_drawn_on_the_aircraft() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var airframe := AirframeModel.new()
	var build := _build(catalog, {})
	airframe.rebuild(build)

	var placed := true
	var detail: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		var want := MotorLayout.motor_position(name, build.arm_m)
		var got: Vector3 = airframe.motor_map.marker_position_m(name)
		placed = placed and got.distance_to(want) < 1e-9
		detail.append("%s at (%.4f, %.4f)" % [name, got.x, got.z])
	results.append(TestResult.new(
		"each motor's marker sits at the arm-tip position the physics measures its torque from",
		placed, ", ".join(detail)))

	# A frame change moves them, or the map is a picture of a drone nobody built.
	var whoop := Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_4000_liion")
	airframe.rebuild(whoop)
	var moved: Vector3 = airframe.motor_map.marker_position_m("M2")
	results.append(TestResult.new(
		"a smaller frame draws the map on the smaller aircraft",
		moved.distance_to(MotorLayout.motor_position("M2", whoop.arm_m)) < 1e-9
			and absf(moved.x - MotorLayout.motor_position("M2", build.arm_m).x) > 0.01,
		"M2 at x=%.4f on a %.0f mm arm" % [moved.x, whoop.arm_m * 1000.0]))

	airframe.rebuild(_build(catalog, {}))
	var out_text: String = airframe.motor_map.label_text("M2")
	airframe.rebuild(_build(catalog, {"motor_spin": "props_in"}))
	var in_text: String = airframe.motor_map.label_text("M2")
	results.append(TestResult.new(
		"the marker names the motor in Betaflight's numbering and its direction, and the direction follows the config",
		out_text == "M2 CCW" and in_text == "M2 CW",
		"props-out \"%s\", props-in \"%s\"" % [out_text, in_text]))
	airframe.free()
	return results


## The half a label cannot carry. The arrow is drawn geometry, and geometry can disagree with the
## text beside it — so its winding is checked about +Y, which is the axis the propeller itself is
## rotated about, for a map that is neither the default nor its negation.
static func _the_arrow_winds_the_way_the_motor_turns() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var airframe := AirframeModel.new()
	airframe.rebuild(_build(catalog, {"motor_spin": UNFLYABLE}))

	var agree := true
	var detail: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		var points: PackedVector3Array = airframe.motor_map.arrow_points_m(name)
		var winding := 0.0
		if points.size() >= 2:
			winding = signf(points[0].cross(points[1]).y)
		var authored := signf(float(UNFLYABLE[name]))
		agree = agree and points.size() >= 8 and winding == authored \
			and airframe.motor_map.label_text(name) == "%s %s" % [
				name, MotorLayout.direction_name(authored)]
		detail.append("%s %d points, winding %+.0f, authored %+.0f" % [
			name, points.size(), winding, authored])
	results.append(TestResult.new(
		"each arrow is swept the way that motor is configured to turn, on a per-motor authored map",
		agree, " · ".join(detail)))

	# And it is drawn AROUND the motor rather than at some radius of its own: the arrow's radius is
	# taken from the propeller that is fitted, so a 3" and a 5" do not get the same ring.
	var small := Build.from_ids(catalog, "frame_3in_toothpick", "motor_1404_3800kv",
		"prop_3x3x3", "battery_6s_4000_liion")
	var big := Build.from_ids(catalog, "frame_10in_long_range", "motor_2807_1300kv",
		"prop_10x5x2", "battery_6s_4000_liion")
	airframe.rebuild(small)
	var small_r: float = airframe.motor_map.arrow_points_m("M1")[0].length()
	airframe.rebuild(big)
	var big_r: float = airframe.motor_map.arrow_points_m("M1")[0].length()
	airframe.free()
	results.append(TestResult.new(
		"the arrow is sized from the propeller fitted, so a 10\" build's rings are bigger than a 3\" build's",
		big_r > small_r * 1.5 and small_r > 0.0,
		"3\" %.1f mm vs 10\" %.1f mm" % [small_r * 1000.0, big_r * 1000.0]))
	return results


## The markers belong to the section that asks the question. Off by default — a Sim flight with
## four floating labels over the aircraft would be Lab's chrome in the field — and up only while
## Config is the focused system.
static func _the_map_is_shown_in_config_and_nowhere_else() -> Array:
	var results: Array = []
	var fresh := AirframeModel.new()
	fresh.rebuild(_build(PartsCatalog.load_default(), {}))
	results.append(TestResult.new(
		"a freshly assembled airframe carries the map hidden: the aircraft is the default picture",
		not fresh.motor_map.visible, "visible = %s" % fresh.motor_map.visible))
	fresh.free()

	var shell := GlassShell.new()
	shell.apply_project(Project.create("Mapped"))
	shell.select_system_by_name("Config")
	var in_config := shell.lab.airframe.motor_map.visible
	shell.select_system_by_name("Power")
	var in_power := shell.lab.airframe.motor_map.visible
	shell.select_system_by_name("Config")
	var back := shell.lab.airframe.motor_map.visible
	shell.free()
	results.append(TestResult.new(
		"the map is up in Config, down in Power, and up again on the way back",
		in_config and not in_power and back,
		"Config %s, Power %s, Config %s" % [in_config, in_power, back]))
	return results


## §7 — Config stops being a stub, and both halves move together: the panel exists AND the system
## is modelled, so the dropdown stops greying it.
static func _the_room_shows_its_panel() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	shell.apply_project(Project.create("Configured"))
	shell.select_system_by_name("Config")
	var shown: Array = []
	for i in shell.lab.panels.get_tab_count():
		if not shell.lab.panels.is_tab_hidden(i):
			shown.append(shell.lab.panels.get_tab_title(i))
	# C5 added Ports beside Motors, C6 added Failsafe beside those and C8 added Rates. The check is
	# still "these and nothing else" — the point of it is that Config shows Config's panels and no
	# Assembly ones, not that it has exactly one.
	results.append(TestResult.new(
		"selecting Config shows the Motors, Ports, Failsafe, Rates and Sheet panels and nothing else",
		shown == ["Motors", "Ports", "Failsafe", "Rates", "Sheet"], "showing %s" % [shown]))

	var stubbed := false
	for system in GlassShell.SYSTEMS:
		if str(system["name"]) == "Config":
			stubbed = system.has("stub") or (system["panels"] as Array).is_empty()
	results.append(TestResult.new(
		"Config is a modelled system now, so nothing greys it or shows it a stub",
		not stubbed, "stubbed = %s" % stubbed))

	# §4.3's refusal, where the order is read rather than in a design document.
	var note: String = shell.lab.motors_panel.refusal_text()
	results.append(TestResult.new(
		"the panel says Lothal cannot know your ESC's motor order, and how to check it",
		note.to_lower().contains("cannot") and note.to_lower().contains("order")
			and note.to_lower().contains("motors tab"),
		"\"%s\"" % note))
	shell.free()
	return results


## The control, end to end: the panel, the project file, and the propellers on screen.
static func _the_control_reaches_the_aircraft_and_the_project() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	shell.apply_project(Project.create("Flipped"))
	shell.select_system_by_name("Config")
	var panel: ConfigMotorsPanel = shell.lab.motors_panel
	results.append(TestResult.new(
		"an untouched drone reads props-out, the convention §8 ships as a convention",
		panel.selected_spin() == "props_out" and panel.map_row_text("M1") == "M1 CW",
		"selected \"%s\", M1 \"%s\"" % [panel.selected_spin(), panel.map_row_text("M1")]))

	panel.motor_spin_edited.emit("props_in")
	var drawn: float = (shell.lab.airframe.propeller_meshes["M1"] as PropellerMesh).spin
	var rows := "%s / %s" % [panel.map_row_text("M1"), panel.map_row_text("M2")]
	shell._sync_project()
	var reloaded := Project.from_dict(shell.container.project.to_dict())
	var stored := String(reloaded.config.get("motor_spin", ""))
	# The aircraft the sim would fly, from the same edit.
	var flown := MotorLayout.spin_map(shell.lab.current_build().config)
	shell.free()
	results.append(TestResult.new(
		"choosing props-in flips the drawn propellers, the panel's rows, the flown map and the saved project",
		drawn == -1.0 and rows == "M1 CCW / M2 CW" and stored == "props_in"
			and float(flown["M1"]) == -1.0,
		"drawn %+.0f, rows %s, saved \"%s\", flown M1 %+.0f" % [
			drawn, rows, stored, float(flown["M1"])]))
	return results


## Per drone, not per app — §6. Only distinguishable with two drones holding different values, both
## surviving a switch away and back.
static func _the_choice_is_per_drone() -> TestResult:
	var shell := GlassShell.new()
	var a := Project.create("Drone A")
	a.config["motor_spin"] = "props_in"
	var b := Project.create("Drone B")

	shell.apply_project(a)
	var first := shell.lab.motors_panel.selected_spin()
	shell.apply_project(b)
	var second := shell.lab.motors_panel.selected_spin()
	shell.apply_project(a)
	var third := shell.lab.motors_panel.selected_spin()
	shell.free()
	return TestResult.new(
		"the motor map is per drone: A props-in, then B props-out, then A props-in again",
		first == "props_in" and second == "props_out" and third == "props_in",
		"A \"%s\", B \"%s\", A \"%s\"" % [first, second, third])


## Warn, never block (§5.3). The map that cannot fly is shown on the panel where it is chosen, in
## ConfigPlausibility's own words — and the aircraft is still assembled and still drawn.
static func _a_wrong_map_is_warned_about_on_the_panel() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	var project := Project.create("Unflyable")
	project.config["motor_spin"] = UNFLYABLE
	shell.apply_project(project)
	shell.select_system_by_name("Config")
	var panel: ConfigMotorsPanel = shell.lab.motors_panel
	var text := panel.warning_text()
	var rows := "%s / %s" % [panel.map_row_text("M2"), panel.map_row_text("M4")]
	var drawn: float = (shell.lab.airframe.propeller_meshes["M2"] as PropellerMesh).spin
	shell.free()
	results.append(TestResult.new(
		"an unflyable map is said on the panel where it was chosen, and the aircraft is still drawn as configured",
		text.contains("cannot fly") and drawn == 1.0 and rows == "M2 CW / M4 CW",
		"warning \"%s\"; M2 drawn %+.0f; rows %s" % [text, drawn, rows]))

	var quiet := GlassShell.new()
	quiet.apply_project(Project.create("Fine"))
	quiet.select_system_by_name("Config")
	var silence := quiet.lab.motors_panel.warning_text()
	quiet.free()
	results.append(TestResult.new(
		"a props-out drone is accused of nothing — a panel that always warns is not a check",
		silence == "", "\"%s\"" % silence))
	return results


static func _build(catalog: PartsCatalog, config: Dictionary) -> Build:
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID)
	build.set_config(config)
	return build
