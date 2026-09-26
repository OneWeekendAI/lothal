class_name TestSectionList
extends RefCounted
## The Lab's right-hand list: `SectionRows` (the §4 table as pure functions of a Build) and
## `SectionList` (the control that draws it). Lab dock design §3/§4/§5.2.
##
## ONE TEST PER ROW, never a loop over the table (design §5.2 and the loop-test rule): a row whose
## choice or number broke must be its own red line, not the first failure of a loop that hides the
## other twenty.

## A 5" build with a 7" prop on it: the prop strikes the frame — an IMPOSSIBLE the Propellers row owns.
const PROP_STRIKE := ["frame_5in_freestyle", "motor_2207_1960kv", "prop_7x4x3",
	"battery_4s_1500", Build.DEFAULT_ESC_ID]


static func run() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var warnings: Array = build.warnings()
	var context := {"site": "Open field", "course": "Figure eight", "conditions": "Calm"}
	var rows := {}
	for section in SectionRows.SECTIONS:
		rows[section] = SectionRows.rows(section, build, warnings, context)

	# --- Airframe
	results.append(_frame_row(build, rows["Airframe"]))
	results.append(_arms_row(rows["Airframe"]))
	results.append(_hardware_row_leaves_its_number_empty(rows["Airframe"]))
	results.append_array(_airframe_geometry_rows(build, warnings, context))
	results.append(_arms_page_is_the_arms_alone())
	results.append(_hardware_page_draws_the_joint())
	results.append(_layout_page_is_fit_and_motor_layout())
	results.append(_a_row_carries_its_own_warnings_most_severe_first(build))
	results.append_array(_airframe_page_numbers(build))
	results.append(_layout_row(build, rows["Airframe"]))
	results.append(_straps_row_is_soon(rows["Airframe"]))
	results.append(_airframe_has_no_drone_row())
	# --- Propulsion
	results.append(_motors_row(rows["Propulsion"]))
	results.append(_propellers_row(build, rows["Propulsion"]))
	results.append(_guards_row(rows["Propulsion"]))
	results.append(_soft_mounts_row_is_soon(rows["Propulsion"]))
	# --- Power
	results.append(_battery_row(rows["Power"]))
	results.append(_esc_row(rows["Power"]))
	results.append(_harness_row(rows["Power"]))
	# --- Control
	results.append(_fc_row(rows["Control"]))
	results.append(_receiver_row(build, rows["Control"]))
	results.append(_tune_row(rows["Control"]))
	# --- Video
	results.append(_camera_row(rows["Video"]))
	results.append(_vtx_row(rows["Video"]))
	# --- Printed, Config, Ground kit, Field
	results.append(_printed_rows_are_one_per_part(build, rows["Printed"]))
	results.append(_motor_direction_row(rows["Config"]))
	results.append(_config_has_its_five_rows(rows["Config"]))
	results.append(_ground_kit_is_all_soon(rows["Ground kit"]))
	results.append(_conditions_row(build, rows["Field"]))
	results.append(_site_row(rows["Field"]))
	# --- Status and the one-owner rule
	results.append(_an_impossible_warning_turns_its_row_red())
	results.append(_the_warning_sits_on_one_row_only())
	results.append(_count_is_decided_of_modelled())
	results.append(_every_row_has_a_page_or_is_soon())
	# --- The control
	results.append_array(_the_control())
	return results


static func _row(rows: Array, id: StringName) -> Dictionary:
	for row in rows:
		if row["id"] == id:
			return row
	return {}


static func _show(row: Dictionary) -> String:
	return "choice='%s' number='%s' line3='%s' status=%s" % [row.get("choice"), row.get("number"),
		row.get("line3"), row.get("status")]


static func _frame_row(build: Build, rows: Array) -> TestResult:
	var row := _row(rows, &"frame")
	var arm := float(build.frame["specs"]["arm_mm"])
	var want_choice := "5\" · %d mm" % roundi(arm * 2.0)
	var want_number := "%d g" % roundi(float(build.frame["mass_g"]))
	return TestResult.new("section rows: Frame says the size and wheelbase, then the frame mass",
		row.get("choice") == want_choice and row.get("number") == want_number
			and row.get("pick") == "Frame" and row.get("page") == {"room": "frame"},
		_show(row) + " want '%s' / '%s'" % [want_choice, want_number])


static func _arms_row(rows: Array) -> TestResult:
	var row := _row(rows, &"arms")
	var number := str(row.get("number"))
	return TestResult.new("section rows: Arms quotes a GUESSED first mode, with its ~",
		number.begins_with("~") and number.ends_with("Hz 1st mode") and str(row.get("choice")) != "",
		_show(row))


static func _hardware_row_leaves_its_number_empty(rows: Array) -> TestResult:
	var row := _row(rows, &"hardware")
	return TestResult.new("section rows: Screws & standoffs without a frame document invents no number",
		row.get("number") == "" and row.get("choice") == "", _show(row))


## The rows that read the drawn geometry — the frame document and the assembled airframe — which
## the shell passes in `context` because a Build does not carry them.
static func _airframe_geometry_rows(build: Build, warnings: Array, context: Dictionary) -> Array:
	var out: Array = []
	var document := AirframeDocument.from_catalog_frame(build.frame)
	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var closest := airframe.closest_to_prop()
	var ctx := context.duplicate()
	ctx["frame_document"] = document
	ctx["prop_clearance"] = closest
	var rows := SectionRows.rows("Airframe", build, warnings, ctx)
	var fasteners := FastenersDetails.new()
	fasteners.render(document)

	var hardware := _row(rows, &"hardware")
	out.append(TestResult.new("section rows: Screws & standoffs names the thread and the standoffs",
		hardware.get("choice") == "M3 · 4 standoffs", _show(hardware)))
	var page_mass := float(fasteners.row_text("hardware_mass").split(" ")[0])
	out.append(TestResult.new(
		"section rows: Screws & standoffs quotes the page's hardware mass, as a ~ estimate",
		page_mass > 0.0 and hardware.get("number") == "~%d g hardware" % roundi(page_mass),
		_show(hardware) + " page '%s'" % fasteners.row_text("hardware_mass")))

	# The page and the row read ONE joint check: what the page counts is what the list gets.
	var joint := FrameHardware.joint_warnings(document)
	out.append(TestResult.new("section rows: the Fasteners page counts FrameHardware's joint warnings",
		fasteners.row_text("checks").begins_with("3 of 3 pass") == joint.is_empty(),
		"page '%s' joint=%d" % [fasteners.row_text("checks").left(40), joint.size()]))
	# A hole 1.9 mm from the edge of a 3 mm-screw plate — the Quad X preset's own motor pad.
	var with_joint: Array = warnings.duplicate()
	with_joint.append(HardwareMass.hole_to_edge_warning(1.9, 3.0))
	var flagged := _row(SectionRows.rows("Airframe", build, with_joint, ctx), &"hardware")
	out.append(TestResult.new("section rows: a flagged bolted joint turns Screws & standoffs amber",
		flagged.get("status") == SectionRows.WARN
			and flagged.get("line3") == "⚠ hole too close to the edge", _show(flagged)))

	out.append(TestResult.new("section rows: the closest part to a prop on the reference is the pack, 9 mm",
		closest.get("part") == "pack" and roundi(float(closest.get("mm", -1.0))) == 9, str(closest)))
	var layout := _row(rows, &"layout")
	out.append(TestResult.new("section rows: Layout & fit quotes the worst clearance to a prop in mm",
		layout.get("number") == "pack 9 mm from a prop" and layout.get("status") == SectionRows.OK,
		_show(layout)))

	var tight := AirframeModel.prop_clearance_warning({"part": "antenna", "mm": 2.2})
	out.append(TestResult.new("section rows: 2 mm from a prop is a LIMITING warning on Layout & fit",
		tight != null and tight.severity == BuildWarning.Severity.LIMITING
			and tight.item == &"layout" and tight.short == "antenna 2 mm from a prop disc",
		"%s" % (tight.short if tight != null else "null")))
	out.append(TestResult.new("section rows: 4 mm from a prop (the default drone in the app) is not tight",
		AirframeModel.prop_clearance_warning({"part": "pack", "mm": 4.0}) == null, ""))
	out.append(TestResult.new(
		"section rows: inside the disc is left to the impossible warning, not repeated as tight",
		AirframeModel.prop_clearance_warning({"part": "pack", "mm": -2.0}) == null, ""))
	var tight_list: Array = warnings.duplicate()
	tight_list.append(tight)
	var tight_row := _row(SectionRows.rows("Airframe", build, tight_list, ctx), &"layout")
	out.append(TestResult.new("section rows: a tight clearance turns Layout & fit amber and says so",
		tight_row.get("status") == SectionRows.WARN
			and tight_row.get("line3") == "⚠ antenna 2 mm from a prop disc", _show(tight_row)))

	fasteners.free()
	airframe.free()
	return out


static func _definition(section: String, id: StringName) -> Dictionary:
	for d in SectionRows.DEFINITIONS[section]:
		if d["id"] == id:
			return d
	return {}


## A page shows ONLY its own item: Structure (the whole frame's mass and inertia) is the Frame
## page's, in the designer, not the Arms page's.
static func _arms_page_is_the_arms_alone() -> TestResult:
	var page: Dictionary = _definition("Airframe", &"arms")["page"]
	return TestResult.new("section rows: the Arms page is the Arms sheet beside an arms drawing",
		page == {"panels": ["Arms"], "diagram": "arms"}, str(page))


static func _hardware_page_draws_the_joint() -> TestResult:
	var page: Dictionary = _definition("Airframe", &"hardware")["page"]
	return TestResult.new("section rows: the Screws & standoffs page is Fasteners beside a drawing",
		page == {"panels": ["Fasteners"], "diagram": "hardware"}, str(page))


## The catalogue Frame sheet is not parked here any more: it is the Frame page's (the designer).
static func _layout_page_is_fit_and_motor_layout() -> TestResult:
	var page: Dictionary = _definition("Airframe", &"layout")["page"]
	return TestResult.new("section rows: the Layout & fit page is Fit and Layout beside a drawing, no Frame sheet",
		page == {"panels": ["Fit", "Layout"], "diagram": "layout"}, str(page))


## The page's "Why?" list: every warning the row owns and none it does not, most severe first.
static func _a_row_carries_its_own_warnings_most_severe_first(build: Build) -> TestResult:
	var edge := HardwareMass.hole_to_edge_warning(1.9, 3.0)
	var strip := HardwareMass.thread_engagement_warning(3.0, 3.0, 5.0)
	var foreign := BuildWarning.limiting(&"pack_sag", "sags", {"usable_fraction": 0.6})
	var row := _row(SectionRows.rows("Airframe", build, [edge, foreign, strip]), &"hardware")
	var owned: Array = row.get("warnings", [])
	return TestResult.new("section rows: a row carries only its own warnings, most severe first",
		owned.size() == 2 and owned[0] == strip and owned[1] == edge,
		"%d owned: %s" % [owned.size(), str(owned.map(func(w): return w.id))])


static func _airframe_page_numbers(build: Build) -> Array:
	var out: Array = []
	var document := AirframeDocument.from_catalog_frame(build.frame)
	var context := {"frame_document": document, "prop_clearance": {"part": "pack", "mm": 9.0},
		"pack_side_mm": -12.4}
	var arms := SectionRows.page_numbers(&"arms", build, context)
	var mode := VibrationModel.for_build(build).resonance_hz
	out.append(TestResult.new("page numbers: Arms shows the guessed first mode and the arm stock",
		arms == [["1st mode, motors on", "~%d Hz" % roundi(mode)],
			["Arm stock", "%.1f mm" % FrameHardware.arm_thickness_mm(document)]], str(arms)))
	var hardware := SectionRows.page_numbers(&"hardware", build, context)
	out.append(TestResult.new("page numbers: Screws & standoffs shows ~mass and the screw count",
		hardware == [["Hardware", "~%d g" % roundi(FrameHardware.mass_g(document,
			AirframePanel.materials()))], ["Screws", "24 × M3"]], str(hardware)))
	var layout := SectionRows.page_numbers(&"layout", build, context)
	out.append(TestResult.new("page numbers: Layout & fit shows the closest part and the pack's side margin",
		layout == [["Closest to a prop", "pack · 9 mm"], ["Pack, each side", "12 mm clear"]],
		str(layout)))
	out.append(TestResult.new("page numbers: a row with no page numbers gets none, not placeholders",
		SectionRows.page_numbers(&"printed", build, context).is_empty(), ""))
	return out


static func _layout_row(build: Build, rows: Array) -> TestResult:
	var row := _row(rows, &"layout")
	return TestResult.new("section rows: Layout & fit names the stack pattern",
		row.get("choice") == "stack %s" % build.frame["specs"]["stack_mount"], _show(row))


static func _straps_row_is_soon(rows: Array) -> TestResult:
	var row := _row(rows, &"straps")
	return TestResult.new("section rows: Straps & pads is 'soon' (no pad model yet)",
		row.get("status") == SectionRows.SOON and row.get("line3") == "", _show(row))


static func _airframe_has_no_drone_row() -> TestResult:
	var names: Array = []
	for d in SectionRows.DEFINITIONS["Airframe"]:
		names.append(d["name"])
	return TestResult.new("section rows: Drone is merged into Airframe — the five §4 rows, in order",
		names == ["Frame", "Arms", "Screws & standoffs", "Layout & fit", "Straps & pads"]
			and not SectionRows.SECTIONS.has("Drone"), str(names))


static func _motors_row(rows: Array) -> TestResult:
	var row := _row(rows, &"motors")
	return TestResult.new("section rows: Motors reads '2207 · 1960 KV' and this pack's thrust each",
		row.get("choice") == "2207 · 1960 KV" and str(row.get("number")).ends_with(" g max each on this pack")
			and int(str(row.get("number")).split(" ")[0]) > 100, _show(row))


static func _propellers_row(build: Build, rows: Array) -> TestResult:
	var row := _row(rows, &"propellers")
	var want := "hover %d%%" % roundi(build.hover_throttle() * 100.0)
	return TestResult.new("section rows: Propellers reads '5 × 4.3 × 3' and the hover throttle",
		row.get("choice") == "5 × 4.3 × 3" and row.get("number") == want, _show(row) + " want " + want)


static func _guards_row(rows: Array) -> TestResult:
	var row := _row(rows, &"guards")
	return TestResult.new("section rows: Prop guards reads 'none' and adds no mass when none is fitted",
		row.get("choice") == "none" and row.get("number") == "", _show(row))


static func _soft_mounts_row_is_soon(rows: Array) -> TestResult:
	var row := _row(rows, &"soft_mounts")
	return TestResult.new("section rows: Soft mounts is 'soon'", row.get("status") == SectionRows.SOON,
		_show(row))


static func _battery_row(rows: Array) -> TestResult:
	var row := _row(rows, &"battery")
	var number := str(row.get("number"))
	return TestResult.new("section rows: Battery reads '4S 1500 mAh' and an estimated flight time",
		row.get("choice") == "4S 1500 mAh" and number.begins_with("~") and number.ends_with(" flight")
			and number.contains(":"), _show(row))


static func _esc_row(rows: Array) -> TestResult:
	var row := _row(rows, &"esc")
	return TestResult.new("section rows: ESC reads its rating and a headroom percentage",
		str(row.get("choice")).ends_with(" A") and str(row.get("number")).ends_with("% headroom"),
		_show(row))


static func _harness_row(rows: Array) -> TestResult:
	var row := _row(rows, &"harness")
	return TestResult.new("section rows: Harness reads the main lead gauge and the worst lead drop",
		str(row.get("choice")).contains(" AWG") and str(row.get("number")).begins_with("~")
			and str(row.get("number")).contains(" V lost in leads at "), _show(row))


static func _fc_row(rows: Array) -> TestResult:
	var row := _row(rows, &"fc")
	# The port figure is the class range with its `~` (TestControlPage pins the exact text); a count
	# stated without it would be the invented UART count this row used to refuse.
	return TestResult.new("section rows: Flight controller reads processor and pattern, and UARTs against a ~range",
		str(row.get("choice")).contains(" · ") and str(row.get("number")).contains(" of ~")
			and str(row.get("number")).ends_with(" UARTs used"), _show(row))


static func _receiver_row(build: Build, rows: Array) -> TestResult:
	var row := _row(rows, &"receiver")
	var fitted := build.components.has("receiver")
	var ok: bool
	if fitted:
		ok = row.get("choice") == str(build.components["receiver"]["name"])
	else:
		ok = row.get("choice") == "none" and row.get("line3") == "⚠ no receiver fitted" \
			and row.get("status") == SectionRows.WARN
	return TestResult.new("section rows: Receiver & link names the receiver, or warns there is none",
		ok, _show(row))


static func _tune_row(rows: Array) -> TestResult:
	var row := _row(rows, &"tune")
	return TestResult.new("section rows: Tune reads 'derived'", row.get("choice") == "derived", _show(row))


static func _camera_row(rows: Array) -> TestResult:
	var row := _row(rows, &"camera")
	return TestResult.new("section rows: Camera stands beside the Electronics rail it is picked on",
		str(row.get("choice")) != "" and (row.get("page") as Dictionary).get("column") == "Electronics",
		_show(row))


static func _vtx_row(rows: Array) -> TestResult:
	var row := _row(rows, &"vtx")
	return TestResult.new("section rows: VTX & antenna opens the Electronics page",
		str(row.get("choice")) != "" and (row.get("page") as Dictionary).get("panels") == ["Electronics"]
			and (row.get("page") as Dictionary).get("column") == "Electronics", _show(row))


static func _printed_rows_are_one_per_part(build: Build, rows: Array) -> TestResult:
	var parts := PrintedParts.for_build(build)
	return TestResult.new("section rows: Printed has one row per generated part",
		rows.size() == parts.size() and rows.size() > 0,
		"%d rows for %d parts" % [rows.size(), parts.size()])


static func _motor_direction_row(rows: Array) -> TestResult:
	var row := _row(rows, &"motor_direction")
	return TestResult.new("section rows: Motor direction reads the configured spin and ✓",
		row.get("choice") == "props out" and row.get("line3") == "✓ yaw torques cancel", _show(row))


static func _config_has_its_five_rows(rows: Array) -> TestResult:
	var names: Array = []
	for row in rows:
		names.append(row["name"])
	return TestResult.new("section rows: Config's five rows are its five panels",
		names == ["Motor direction", "Ports", "Failsafe", "Rates", "Sheet"], str(names))


static func _ground_kit_is_all_soon(rows: Array) -> TestResult:
	var soon := 0
	for row in rows:
		if row["status"] == SectionRows.SOON:
			soon += 1
	return TestResult.new("section rows: Ground kit is four 'soon' rows (a stub, not built)",
		rows.size() == 4 and soon == 4, "%d rows, %d soon" % [rows.size(), soon])


static func _conditions_row(build: Build, rows: Array) -> TestResult:
	var row := _row(rows, &"conditions")
	var want := "%.2f kg/m³" % build.air.kgm3()
	return TestResult.new("section rows: Conditions names the set and quotes the air density",
		row.get("choice") == "Calm" and row.get("number") == want, _show(row))


static func _site_row(rows: Array) -> TestResult:
	var row := _row(rows, &"site")
	return TestResult.new("section rows: Site opens the Field room",
		row.get("choice") == "Open field" and row.get("page") == {"room": "field"}, _show(row))


static func _an_impossible_warning_turns_its_row_red() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var ids := PROP_STRIKE
	var build := Build.from_ids(catalog, ids[0], ids[1], ids[2], ids[3], ids[4])
	var rows := SectionRows.rows("Propulsion", build, build.warnings())
	var row := _row(rows, &"propellers")
	return TestResult.new("section rows: a prop that strikes the frame turns Propellers red with ⚠",
		row.get("status") == SectionRows.BAD and str(row.get("line3")).begins_with("⚠ props exceed"),
		_show(row))


## §3: "A warning appears once, on the row of the part that causes it." A pack current limit is
## put through the table directly, so the check does not depend on finding a catalog build that
## happens to be pack-limited today.
static func _the_warning_sits_on_one_row_only() -> TestResult:
	var build := ReferenceBuild.build()
	var limit := BuildWarning.limiting(&"current_limit", "x",
		{"limited_by": "battery", "limit_amps": 40.0, "throttle_cap": 0.78})
	var holders: Array = []
	for section in ["Propulsion", "Power"]:
		for row in SectionRows.rows(section, build, [limit]):
			if str(row["line3"]).contains("78%"):
				holders.append(row["name"])
	return TestResult.new("section rows: a pack current limit appears on Battery and nowhere else",
		holders == ["Battery"], str(holders))


static func _count_is_decided_of_modelled() -> TestResult:
	var rows := [
		{"id": &"a", "status": SectionRows.OK, "choice": "x"},
		{"id": &"b", "status": SectionRows.WARN, "choice": "y"},
		{"id": &"c", "status": SectionRows.BAD, "choice": ""},
		{"id": &"d", "status": SectionRows.SOON, "choice": "", "soon": true},
	]
	return TestResult.new("section rows: the header counts decided of modelled ('2 of 3')",
		SectionRows.header_text(rows) == "2 of 3", SectionRows.header_text(rows))


## NOTHING BECOMES UNREACHABLE (the Quiet Canvas near-miss): every non-soon row names a page, and
## every Lab panel title the old SYSTEMS table routed to is on some row's page.
static func _every_row_has_a_page_or_is_soon() -> TestResult:
	var missing: Array = []
	var covered := {}
	for section in SectionRows.DEFINITIONS:
		for d in SectionRows.DEFINITIONS[section]:
			if bool(d.get("soon", false)):
				continue
			if not d.has("page"):
				missing.append(d["name"])
				continue
			for title in (d["page"] as Dictionary).get("panels", []):
				covered[title] = true
	# Frame (the catalogue sheet) and Structure are the Frame page's, inside the designer's own
	# Details drawer — asserted on the drawer by TestAirframeTabs, not here.
	for title in ["Fit", "Arms", "Fasteners", "Layout", "Motor", "Prop", "Pack",
			"ESC", "Harness", "FC", "Link", "Tune", "Camera", "Electronics", "Print", "Motors", "Ports",
			"Failsafe", "Rates", "Sheet"]:
		if not covered.has(title):
			missing.append("panel %s" % title)
	return TestResult.new("section rows: every row opens a page and every Lab panel is on one",
		missing.is_empty(), "missing: %s" % str(missing))


# ---------------------------------------------------------------------------
# The control
# ---------------------------------------------------------------------------

static func _fixture_rows() -> Array:
	return [
		{"id": &"motors", "name": "Motors", "choice": "2207 · 1960 KV", "number": "1450 g thrust each",
			"line3": "1450 g thrust each", "status": SectionRows.OK, "pick": "Motor",
			"page": {"panels": ["Motor"]}},
		{"id": &"battery", "name": "Battery", "choice": "6S 1300 mAh", "number": "~4:10 flight",
			"line3": "⚠ pack limits you to 78% throttle", "status": SectionRows.WARN,
			"page": {"panels": ["Pack"]}},
		{"id": &"soft", "name": "Soft mounts", "choice": "", "number": "", "line3": "",
			"status": SectionRows.SOON, "soon": true},
	]


static func _the_control() -> Array:
	var out: Array = []
	var list := SectionList.new()
	list.show_section("Propulsion", _fixture_rows())

	out.append(TestResult.new("section list: header shows the section and N of M",
		list.header_text() == "Propulsion 2 of 2", list.header_text()))
	out.append(TestResult.new("section list: a row draws its three lines",
		list.row_lines(&"motors") == PackedStringArray(["Motors", "2207 · 1960 KV", "1450 g thrust each"]),
		str(list.row_lines(&"motors"))))
	out.append(TestResult.new("section list: a limited row draws its ⚠ short on line 3",
		list.row_lines(&"battery")[2] == "⚠ pack limits you to 78% throttle",
		str(list.row_lines(&"battery"))))
	var number := list.row_control(&"battery").find_child("Number", true, false) as Label
	out.append(TestResult.new("section list: the ⚠ line is drawn in the warning colour",
		number != null and number.get_theme_color("font_color") == LothalTheme.WARNING,
		"colour %s" % (str(number.get_theme_color("font_color")) if number != null else "no label")))
	out.append(TestResult.new("section list: a soon row says soon and has no third line",
		list.row_lines(&"soft") == PackedStringArray(["Soft mounts", "soon", ""]),
		str(list.row_lines(&"soft"))))
	var labels_wrap := false
	for label in list.find_children("*", "Label", true, false):
		if (label as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			labels_wrap = true
	out.append(TestResult.new("section list: no label in a row may wrap to another line",
		not labels_wrap, "a label autowraps" if labels_wrap else "none wrap"))

	var opened: Array = []
	list.row_opened.connect(func(id: StringName) -> void: opened.append(id))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	list.row_control(&"battery").gui_input.emit(click)
	out.append(TestResult.new("section list: clicking a row asks for its page", opened == [&"battery"],
		str(opened)))

	var picked: Array = []
	list.pick_requested.connect(func(id: StringName) -> void: picked.append(id))
	var choice := list.row_control(&"motors").find_child("Choice", true, false) as Button
	if choice != null:
		choice.pressed.emit()
	out.append(TestResult.new("section list: the choice line of a part row summons the finder",
		picked == [&"motors"], str(picked)))
	out.append(TestResult.new("section list: a row with no part to pick has no finder button",
		list.row_control(&"battery").find_child("Choice", true, false) == null, ""))

	list.set_open_row(&"battery")
	var box := list.row_control(&"battery").get_theme_stylebox("panel") as StyleBoxFlat
	var other := list.row_control(&"motors").get_theme_stylebox("panel") as StyleBoxFlat
	out.append(TestResult.new("section list: the open row is highlighted and the others are not",
		box != null and other != null and box.border_color == LothalTheme.ACCENT
			and other.border_color != LothalTheme.ACCENT, ""))

	var toggled: Array = []
	list.collapse_toggled.connect(func(value: bool) -> void: toggled.append(value))
	(list.find_child("Collapse", true, false) as Button).pressed.emit()
	var strip := list.find_child("Strip", true, false) as Button
	out.append(TestResult.new("section list: ›| collapses to a thin strip",
		list.collapsed and strip.visible and list.current_width() == SectionList.STRIP_WIDTH
			and toggled == [true], "collapsed=%s width=%s" % [list.collapsed, list.current_width()]))
	out.append(TestResult.new("section list: collapsing keeps the section",
		list.section == "Propulsion", list.section))
	strip.pressed.emit()
	out.append(TestResult.new("section list: the strip restores the list",
		not list.collapsed and not strip.visible and list.current_width() == SectionList.WIDTH
			and toggled == [true, false], "collapsed=%s" % list.collapsed))
	list.free()
	return out
