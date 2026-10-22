class_name TestStackMount
extends RefCounted
## Standard mounts by name — airframe gaps build plan, slice G2 (airframe.md §5.3, §10 q5).
## `FrameEdits.add_stack_mount`, the shared parser `AirframeDocument.stack_mount_spec` /
## `stack_mount_holes`, the hole-to-edge check on bolt holes off the arms
## (`FrameHardware.mount_hole_warnings`, reached through `FrameWarnings.of`), and the workbench's
## "+ Stack mount" button and picker.
##
## Where each check could pass while proving nothing, and what stops it:
##   - hole centres are asserted against numbers written HERE (centre ± pitch/2), on a mount placed
##     OFF the origin, so a mount that ignored `centre` or halved the pitch twice fails.
##   - diameters are asserted against a literal table here (2.2 / 2.2 / 3.2 / 3.2), not the code's.
##   - the mass drop is asserted EXACT against four tessellated circles × t × ρ, positive, and under
##     4·πr², so a hole that adds mass (wrong winding) or a wrong radius fails.
##   - every edge assertion is made BOTH ways (warns near the edge, silent when centred), and the
##     M2/M3 pair at one 3.5 mm margin proves the thread is read off the hole, not assumed.
##   - one result per pattern, never a loop that fails once (feedback: loop tests hide coverage).
##   Mutation-checked in src/ for the G2 report: see the MUTATIONS block at the end of this file.

const EPS := 1.0e-6

## Patterns, and the hole each must cut, written here rather than read from the code under test.
const CASES := [
	{"pattern": "20x20", "pitch": 20.0, "hole_d": 2.2},
	{"pattern": "25.5x25.5", "pitch": 25.5, "hole_d": 2.2},
	{"pattern": "25.5x25.5 M3", "pitch": 25.5, "hole_d": 3.2},
	{"pattern": "30.5x30.5", "pitch": 30.5, "hole_d": 3.2},
]

const FIXTURE_FRAME := "5\" Freestyle"


static func run() -> Array:
	var sections := {}
	var centres: Array = []
	var masses: Array = []
	for case in CASES:
		centres.append(_holes_land_where_the_pattern_says(case))
		masses.append(_mass_drops_by_exactly_the_holes(case))
	sections["centres and diameters"] = centres
	sections["mass"] = masses
	sections["preset parity"] = _a_preset_and_a_drawn_frame_cut_the_same_holes()
	sections["refusal"] = _a_mount_that_will_not_fit_is_refused_whole()
	sections["edge"] = _the_edge_check_runs_on_stack_holes()
	sections["workbench"] = _the_workbench_adds_one_undo_step_per_mount()
	var out: Array = []
	for name in sections:
		var list: Array = sections[name]
		if list.is_empty():
			out.append(TestResult.new("stack mount: section '%s' produced results" % name, false,
				"empty — it aborted"))
		out.append_array(list)
	return out


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

static func _holes_land_where_the_pattern_says(case: Dictionary) -> TestResult:
	var document := _plate_doc(60.0)
	var centre := Vector2(7.0, -4.0)
	var added := FrameEdits.add_stack_mount(document, 0, centre, str(case["pattern"]))
	var holes := AirframeDocument.plate_holes(document.plates[0])
	var half := float(case["pitch"]) * 0.5
	var expected := [centre + Vector2(half, half), centre + Vector2(half, -half),
		centre + Vector2(-half, -half), centre + Vector2(-half, half)]
	var found := 0
	var worst_d_error := 0.0
	var got: Array = []
	for hole in holes:
		var c := PolygonProps.centroid(hole)
		got.append("(%.3f, %.3f)" % [c.x, c.y])
		for e in expected:
			if c.distance_to(e) < 1.0e-4:
				found += 1
				break
		var r := 0.0
		for p in hole:
			r = maxf(r, p.distance_to(c))
		worst_d_error = maxf(worst_d_error, absf(2.0 * r - float(case["hole_d"])))
	return TestResult.new("stack mount %s: four holes at centre ± %.2f mm, %.1f mm across" % [
			case["pattern"], half, case["hole_d"]],
		added and holes.size() == 4 and found == 4 and worst_d_error < 1.0e-4,
		"added %s, %d holes, %d at the expected centres %s, worst diameter error %.5f mm" % [
			added, holes.size(), found, ", ".join(got), worst_d_error])


static func _mass_drops_by_exactly_the_holes(case: Dictionary) -> TestResult:
	var document := _plate_doc(60.0)
	var thickness := 2.0
	var solid := _mass_g(document)
	FrameEdits.add_stack_mount(document, 0, Vector2.ZERO, str(case["pattern"]))
	var drilled := _mass_g(document)
	var r := float(case["hole_d"]) * 0.5
	var one_hole := absf(PolygonProps.area(PolygonProps.tessellate_circle(
		Vector2.ZERO, r, PolygonProps.DEFAULT_CHORD_TOLERANCE_MM, true)))
	var expected := _plate_mass_g(4.0 * one_hole, thickness)
	var circle := _plate_mass_g(4.0 * PI * r * r, thickness)
	var removed := solid - drilled
	return TestResult.new("stack mount %s: mass drops by exactly 4 holes × t × ρ" % case["pattern"],
		# Exact to 1e-5 of the removed mass: hole vertices pass through float32 `Vector2` on their way
		# in, which costs ~1e-6 relative. A 0.01 mm radius error moves it ~1%, a thousand times more.
		# Below the true circles, never above: the hole is an INSCRIBED polygon (a coarse one at
		# r = 1.1 mm, ~10% under πr²), and removing more than the circle means a wrong radius.
		absf(removed - expected) < 1.0e-5 * expected and removed > 0.0 and removed <= circle,
		"%.6f g -> %.6f g, removed %.8f g, expected %.8f g (true circles %.8f g)" % [
			solid, drilled, removed, expected, circle])


## The catalog presets and "+ Stack mount" go through one parser, so the same pattern name cuts the
## same four holes, vertex for vertex. One result per pattern the catalog uses.
static func _a_preset_and_a_drawn_frame_cut_the_same_holes() -> Array:
	var out: Array = []
	var seen := {}
	for frame in PartsCatalog.load_default().list_category("frame"):
		var specs: Dictionary = frame.get("specs", {})
		var pattern := str(specs.get("stack_mount", ""))
		if pattern == "" or seen.has(pattern) or str(specs.get("construction", "plate")) == "moulded":
			continue
		seen[pattern] = true
		var preset := AirframeDocument.from_catalog_frame(frame)
		var bottom: Dictionary = {}
		for plate in preset.plates:
			if str(plate.get("role", "")) == AirframeDocument.ROLE_BOTTOM:
				bottom = plate
		var preset_holes := AirframeDocument.plate_holes(bottom)
		var drawn := _plate_doc(80.0)
		FrameEdits.add_stack_mount(drawn, 0, Vector2.ZERO, pattern)
		var drawn_holes := AirframeDocument.plate_holes(drawn.plates[0])
		var worst := INF if preset_holes.size() != drawn_holes.size() else 0.0
		if worst == 0.0:
			for i in preset_holes.size():
				var a: PackedVector2Array = preset_holes[i]
				var b: PackedVector2Array = drawn_holes[i]
				if a.size() != b.size():
					worst = INF
					break
				for k in a.size():
					worst = maxf(worst, a[k].distance_to(b[k]))
		out.append(TestResult.new(
			"stack %s: the preset (%s) and \"+ Stack mount\" cut identical holes" % [
				pattern, frame.get("name", "")],
			preset_holes.size() == 4 and worst < 1.0e-9,
			"%d preset holes, %d drawn, worst vertex gap %s mm" % [
				preset_holes.size(), drawn_holes.size(), str(worst)]))
	return out


static func _a_mount_that_will_not_fit_is_refused_whole() -> Array:
	var out: Array = []
	var document := _plate_doc(25.0)
	var refused := FrameEdits.add_stack_mount(document, 0, Vector2.ZERO, "30.5x30.5")
	out.append(TestResult.new("a 30.5 pattern on a 25 mm plate is refused and cuts nothing",
		not refused and AirframeDocument.plate_holes(document.plates[0]).is_empty(),
		"returned %s, %d holes" % [refused, AirframeDocument.plate_holes(document.plates[0]).size()]))
	var nameless := FrameEdits.add_stack_mount(document, 0, Vector2.ZERO, "stack")
	out.append(TestResult.new("a pattern name with no pitch is refused",
		not nameless and AirframeDocument.plate_holes(document.plates[0]).is_empty(),
		"returned %s" % nameless))
	return out


# ---------------------------------------------------------------------------
# The §5.3 tear-out check on holes placed this way
# ---------------------------------------------------------------------------

static func _the_edge_check_runs_on_stack_holes() -> Array:
	var out: Array = []
	# 40 mm plate, 30.5 pattern: centred, each hole sits 20 - 15.25 = 4.75 mm from the edge, over the
	# 4.5 mm (1.5 × M3) it needs. Moved 2 mm along u, the near pair sits at 2.75 mm.
	var centred := _plate_doc(40.0)
	FrameEdits.add_stack_mount(centred, 0, Vector2.ZERO, "30.5x30.5")
	var near := _plate_doc(40.0)
	FrameEdits.add_stack_mount(near, 0, Vector2(2.0, 0.0), "30.5x30.5")
	var near_edge := _edge_warning(near)
	out.append(TestResult.new("a 30.5 stack mount 2.75 mm from the edge raises hole_to_edge",
		near_edge != null and absf(float(near_edge.values["edge_distance_mm"]) - 2.75) < 0.01
			and is_equal_approx(float(near_edge.values["hole_d_mm"]), 3.0),
		"warning %s" % ("none" if near_edge == null else str(near_edge.values))))
	out.append(TestResult.new("the same mount centred (4.75 mm) raises no hole_to_edge",
		_edge_warning(centred) == null, _ids(centred)))

	# One 3.5 mm margin, two screws: a 25.5 pattern centred on a 32.5 mm plate. An M2 needs 3.0 mm
	# and passes; an M3 needs 4.5 mm and warns. Proves the screw is read off the hole that was cut.
	var m2 := _plate_doc(32.5)
	FrameEdits.add_stack_mount(m2, 0, Vector2.ZERO, "25.5x25.5")
	var m3 := _plate_doc(32.5)
	FrameEdits.add_stack_mount(m3, 0, Vector2.ZERO, "25.5x25.5 M3")
	var m3_edge := _edge_warning(m3)
	out.append(TestResult.new("at a 3.5 mm margin the M2 stack passes", _edge_warning(m2) == null,
		_ids(m2)))
	out.append(TestResult.new("at the same 3.5 mm margin the M3 stack warns",
		m3_edge != null and is_equal_approx(float(m3_edge.values["hole_d_mm"]), 3.0),
		"warning %s" % ("none" if m3_edge == null else str(m3_edge.values))))

	# A strap slot near the edge is not a bolt hole and must not be read as one.
	var slotted := _plate_doc(40.0)
	var plate: Dictionary = slotted.plates[0]
	plate["holes"] = [AirframeDocument.flatten(StrapSlots.make_slot(Vector2(0.0, 18.0), 22.0, 3.5))]
	out.append(TestResult.new("a strap slot near the edge is not read as a bolt hole",
		_edge_warning(slotted) == null, _ids(slotted)))
	# An oblong 3.2 × 1.5 mm cut-out spans an M3 hole's diameter corner to corner, so only the
	# roundness rule keeps it from being read as one.
	var oblong := _plate_doc(40.0)
	(oblong.plates[0] as Dictionary)["holes"] = [AirframeDocument.flatten(
		StrapSlots.make_slot(Vector2(0.0, 18.5), 3.2, 1.5))]
	out.append(TestResult.new("an oblong cut-out near the edge is not read as a bolt hole",
		_edge_warning(oblong) == null, _ids(oblong)))
	# A 10 mm round lightening hole whose centre sits 5.5 mm from the edge: round, but no screw's
	# clearance, so not a bolt hole — the diameter rule, not the roundness rule, keeps it quiet. (Read
	# as the largest thread, M4, it would need 6 mm and warn.)
	var lightened := _plate_doc(40.0)
	FrameEdits.add_hole(lightened, 0, Vector2(0.0, 14.5), 10.0)
	out.append(TestResult.new("a round 10 mm lightening hole near the edge is not read as a bolt hole",
		_edge_warning(lightened) == null, _ids(lightened)))
	return out


# ---------------------------------------------------------------------------
# The workbench
# ---------------------------------------------------------------------------

static func _the_workbench_adds_one_undo_step_per_mount() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	var workbench := FrameWorkbench.new(catalog)
	workbench.start_from(_fixture_frame(catalog))

	# Nothing selected: refused, and no undo step.
	workbench._on_selection_changed(-1)
	var depth0 := workbench.editor.history.depth()
	var unselected := workbench.add_stack_mount("30.5x30.5")
	out.append(TestResult.new("+ Stack mount with no plate selected changes nothing",
		not unselected and workbench.editor.history.depth() == depth0,
		"returned %s, depth %d -> %d" % [unselected, depth0, workbench.editor.history.depth()]))

	# A fresh 40 mm plate (selected by "+ Plate"), then the BUTTON, with the picker on 20×20.
	workbench._on_add_plate()
	var index := workbench.editor.document.plates.size() - 1
	var depth1 := workbench.editor.history.depth()
	workbench.stack_picker.select(AirframeDocument.STACK_MOUNT_PATTERNS.find("20x20"))
	var button := _find_button(workbench, "+ Stack mount")
	if button != null:
		button.pressed.emit()
	var holes := AirframeDocument.plate_holes(workbench.editor.document.plates[index])
	var hole_d := 0.0
	if not holes.is_empty():
		var c := PolygonProps.centroid(holes[0])
		hole_d = 2.0 * (holes[0] as PackedVector2Array)[0].distance_to(c)
	out.append(TestResult.new("\"+ Stack mount\" cuts the picked 20×20 pattern as ONE undo step",
		button != null and holes.size() == 4 and absf(hole_d - 2.2) < 1.0e-4
			and workbench.editor.history.depth() == depth1 + 1,
		"button %s, %d holes of %.3f mm, depth %d -> %d" % [button != null, holes.size(), hole_d,
			depth1, workbench.editor.history.depth()]))
	workbench.editor.undo()
	# The plate must SURVIVE the undo: an add that recorded no step makes this Undo take back the
	# "+ Plate" before it instead, and the plate itself is gone.
	var plates := workbench.editor.document.plates
	var undone := AirframeDocument.plate_holes(plates[index]).size() if index < plates.size() else -1
	out.append(TestResult.new("one Undo removes all four holes and nothing else",
		undone == 0 and workbench.editor.history.depth() == depth1,
		"%d holes after undo (-1: the plate went too), depth %d" % [undone,
			workbench.editor.history.depth()]))
	if index >= plates.size():
		workbench.free()
		return out

	# A plate too small for the pattern: refused, and the undo stack is untouched.
	workbench._on_selection_changed(index)
	FrameEdits.scale_plate(workbench.editor.document, index, 0.5)
	var depth2 := workbench.editor.history.depth()
	var refused := workbench.add_stack_mount("30.5x30.5")
	out.append(TestResult.new("a stack mount that does not fit adds no undo step",
		not refused and workbench.editor.history.depth() == depth2
			and AirframeDocument.plate_holes(workbench.editor.document.plates[index]).is_empty(),
		"returned %s, depth %d -> %d" % [refused, depth2, workbench.editor.history.depth()]))
	workbench.free()
	return out


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

static func _plate_doc(side_mm: float) -> AirframeDocument:
	var document := FrameEdits.new_frame("stack")
	FrameEdits.add_rectangle(document, Vector2.ZERO, side_mm, side_mm, 2.0, 0.0,
		AirframeDocument.ROLE_BOTTOM)
	return document


static func _edge_warning(document: AirframeDocument) -> BuildWarning:
	var props := AirframeProperties.compute(document, FrameMaterials.load_default())
	for warning in FrameWarnings.of(document, props):
		if warning.id == &"hole_to_edge":
			return warning
	return null


static func _ids(document: AirframeDocument) -> String:
	var props := AirframeProperties.compute(document, FrameMaterials.load_default())
	var ids: Array = []
	for warning in FrameWarnings.of(document, props):
		ids.append(str(warning.id))
	return "warnings: %s" % ", ".join(ids)


static func _mass_g(document: AirframeDocument) -> float:
	return AirframeProperties.compute(document, FrameMaterials.load_default()).total_mass_g()


static func _plate_mass_g(area_mm2: float, thickness_mm: float) -> float:
	var density := FrameMaterials.load_default().density("carbon_3k_twill_0_90")
	return area_mm2 * thickness_mm * 1.0e-9 * density * 1000.0


static func _fixture_frame(catalog: PartsCatalog) -> Dictionary:
	for frame in catalog.list_category("frame"):
		if str(frame.get("name", "")) == FIXTURE_FRAME:
			return frame
	return {}


static func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


# MUTATIONS (G2, 2026-10-03) — each applied alone in src/, this suite run, then reverted:
#   holes cut at the origin, not `centre`         -> 4 centre tests + the near-edge warning fail
#   every stack read as M3 (no M2 default)        -> 20x20/25.5 diameters, mass, M2-passes, button fail
#   stack holes wound like an outline (add mass)  -> all 4 mass tests fail
#   preset keeps its old fixed 1.6 mm radius      -> 20x20 and 25.5 preset-parity tests fail
#   no fit check in add_stack_mount               -> both refusal tests fail
#   edge check not appended in FrameWarnings.of   -> both "warns" tests fail
#   thread not read off the hole (all M3)         -> "M2 stack passes at 3.5 mm" fails
#   diameter range dropped (any round hole bolts) -> the lightening-hole test fails
#   roundness rule dropped                        -> the oblong cut-out test fails
#   history recorded before the fit check         -> one-undo-step, undo, and refused-no-step fail
#   no history record at all                      -> one-undo-step and undo fail
#   picker ignored (always 30.5)                  -> the 20x20 button test fails
