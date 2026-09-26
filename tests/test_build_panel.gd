class_name TestBuildPanel
extends RefCounted
## Day 5's UI, exercised without a window. The panel is Control nodes built in code, so
## its wiring — dropdowns populated from the catalog, stats re-rendered on change, the
## build_changed signal firing — is all testable headlessly. Only the pixels are not.
##
## The point of testing this at all: week1.md's day 5 gate warns that numbers changing
## while the feel does not means voltage is not reaching the RPM calculation. The mirror
## failure is just as easy — flight changing while the panel does not, because the panel
## quietly kept an old Build. So the panel must hand out the SAME Build object the scene
## flies, and that identity is what is checked here.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	var panel := BuildPanel.new(catalog, {
		"frame": ReferenceBuild.FRAME_ID,
		"motor": ReferenceBuild.MOTOR_ID,
		"propeller": ReferenceBuild.PROPELLER_ID,
		"battery": ReferenceBuild.BATTERY_ID,
	})

	var emitted: Array = []
	panel.build_changed.connect(func(b: Build) -> void: emitted.append(b))
	# _rebuild() directly rather than parenting into the tree: the panel is pure Control
	# wiring, and a headless SceneTree has no reason to be dragged into it.
	panel._rebuild()

	results.append(TestResult.new(
		"build panel builds the reference selection and emits it",
		emitted.size() == 1 and panel.build != null
			and absf(panel.build.all_up_weight_g() - 507.48) < 1.0,
		"emitted %d build(s), %.0f g" % [emitted.size(), panel.build.all_up_weight_g() if panel.build else -1.0]
	))

	# F11 — THE FLIGHT TIME NAMES THE CONDITIONS IT WAS COMPUTED UNDER (F8, design §4.3/§3.3).
	#
	# `part_details.gd` has said this since F8 and this panel did not: `flight_time_min()` picks up
	# the flown Build's own wind, so the NUMBER here was right and the LABEL was missing — "a
	# figure quoted without the conditions it was computed under", in the one file outside F8's
	# scope. The name is DISTINCTIVE and is set on the panel's own Build, so a row that quoted a
	# constant, or the standard name, or nothing, all read differently from a row that quoted the
	# conditions the figure actually came from.
	panel.build.field_conditions_name = "A Very Distinctive Conditions Name"
	panel._refresh_stats()
	var time_row: String = panel._stat_values["time"].text
	results.append(TestResult.new(
		"the flight time this panel quotes names the conditions it was computed under",
		panel.build.can_hover()
			and time_row.contains("A Very Distinctive Conditions Name")
			and time_row.contains("%.1f min" % panel.build.flight_time_min()),
		"the Flight time row reads \"%s\" (hovers %s)" % [time_row, panel.build.can_hover()]))

	results.append(TestResult.new(
		"every dropdown is populated from the catalog",
		panel._selectors["frame"].item_count == catalog.list_category("frame").size()
			and panel._selectors["motor"].item_count == catalog.list_category("motor").size()
			and panel._selectors["propeller"].item_count == catalog.list_category("propeller").size()
			and panel._selectors["battery"].item_count == catalog.list_category("battery").size(),
		"frame=%d motor=%d prop=%d battery=%d" % [
			panel._selectors["frame"].item_count, panel._selectors["motor"].item_count,
			panel._selectors["propeller"].item_count, panel._selectors["battery"].item_count]
	))

	results.append(TestResult.new(
		"stat readout renders the reference build in UI units",
		panel._stat_values["weight"].text == "507 g"
			and panel._stat_values["hover"].text.ends_with("%")
			and panel._stat_values["speed"].text.ends_with("km/h"),
		"%s | %s | %s | %s | %s" % [
			panel._stat_values["weight"].text, panel._stat_values["twr"].text,
			panel._stat_values["hover"].text, panel._stat_values["time"].text,
			panel._stat_values["speed"].text]
	))

	# Switch the pack to 6S the way a user would, and require BOTH the panel and the build
	# it hands out to move together.
	var before_hover: String = panel._stat_values["hover"].text
	var battery_selector: OptionButton = panel._selectors["battery"]
	var six_s_index := _index_of(catalog.list_category("battery"), "battery_6s_1300")
	battery_selector.select(six_s_index)
	panel._on_selection_changed(six_s_index, "battery")

	results.append(TestResult.new(
		"changing a dropdown re-emits a new build and re-renders the stats",
		emitted.size() == 2 and panel._stat_values["hover"].text != before_hover
			and panel.build.battery["part_id"] == "battery_6s_1300",
		"hover %s -> %s, pack now %s" % [before_hover, panel._stat_values["hover"].text, panel.build.battery["name"]]
	))

	results.append(TestResult.new(
		"the build the panel displays is the build it hands to the scene",
		emitted[1] == panel.build,
		"panel.build is the emitted instance: %s" % (emitted[1] == panel.build)
	))

	# A knowingly bad combination must warn rather than be silently prevented (parts.md).
	var prop_selector: OptionButton = panel._selectors["propeller"]
	var seven_inch := _index_of(catalog.list_category("propeller"), "prop_7x4x3")
	prop_selector.select(seven_inch)
	panel._on_selection_changed(seven_inch, "propeller")

	results.append(TestResult.new(
		"an over-sized prop warns and stays selectable (warn, never block)",
		panel._warnings.visible and not panel._warnings.ordered_text().is_empty()
			and panel.build.propeller["part_id"] == "prop_7x4x3",
		"%d warning(s) shown, selection kept" % panel.build.warnings().size()
	))

	panel.free()
	return results


static func _index_of(parts: Array, part_id: String) -> int:
	for i in parts.size():
		if parts[i]["part_id"] == part_id:
			return i
	return -1
