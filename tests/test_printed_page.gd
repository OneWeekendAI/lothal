class_name TestPrintedPage
extends RefCounted
## The Printed section of the Lab dock (lab dock design §3, §4): one row per generated printed part,
## headless.
##
## What this suite guards: each part's row (line 2 the material, line 3 the print mass), its page's
## two numbers and its drawing read ONE computation (`PrintedFigures`) over the part's own exported
## triangles (`PrintedParts.solid_for`); a part that no longer matches its print record is amber on
## ITS row and no other; and no print time appears anywhere (no slicer is modelled).
##
## Where a check could pass while proving nothing, and what stops it:
##   - a mass equal to "the analytic volume × density" could be a copy of the analytic volume; the
##     mesh volume is asserted against it, and the antenna mount — which has NO analytic volume — is
##     asserted against the triangles directly.
##   - a fit read at the default clearance cannot tell the clearance from a constant 0.4 mm: every
##     fit is also checked at 0.35 mm.
##   - "(guess)" is checked absent once the clearance is set, not only present at the default.
##
## One test per case.

const EPS := 1e-6


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var loose := _loose(0.35)
	var guarded := _guarded()
	var rows := SectionRows.rows("Printed", build)

	# --- the shared figures
	out.append(_mesh_volume_is_the_arm_guards_own(build))
	out.append(_mesh_volume_is_the_camera_mounts_own(build))
	out.append(_battery_pad_print_mass_is_its_weighed_mass(build))
	out.append(_antenna_mount_mass_is_its_triangles(build))
	out.append(_guard_mass_is_its_ring_at_the_published_density(guarded))
	out.append(_arm_guard_fit(build))
	out.append(_arm_guard_fit_follows_the_clearance(loose))
	out.append(_camera_mount_fit_follows_the_clearance(loose))
	out.append(_antenna_mount_fit_follows_the_clearance(loose))
	out.append(_battery_pad_fit_follows_the_clearance(loose))
	out.append(_guard_has_no_fit(guarded))
	out.append(_a_bought_guard_prints_nothing(guarded))

	# --- the rows, one per part
	out.append(_row_names_its_part(rows, "arm_guard", "Arm guards"))
	out.append(_part_row(build, rows, "arm_guard", "~1.5 g each · print 4"))
	out.append(_part_row(build, rows, "camera_mount", "~1.1 g each · print 2"))
	out.append(_part_row(build, rows, "antenna_mount", "~3.3 g"))
	out.append(_part_row(build, rows, "battery_pad", "~7.2 g"))
	out.append(_guard_row(guarded))
	out.append(_rows_open_their_own_page(rows))
	out.append(_a_refused_part_is_red_with_its_reason())
	out.append(_divergence_is_amber_on_its_own_row(build))
	out.append(_divergence_leaves_the_other_rows_alone(build))
	out.append(_divergence_short_carries_the_print_date())
	out.append(_divergence_long_is_the_finding())
	out.append(_a_real_divergence_carries_its_date())

	# --- the page numbers
	out.append(_arm_guard_page_numbers(build))
	out.append(_page_numbers_drop_the_guess_once_set(loose))
	out.append(_guard_page_numbers(guarded))
	out.append(_no_print_time_anywhere(build))

	# --- the drawing
	out.append(_drawing_draws_the_exported_triangles(build))
	out.append(_drawing_dimensions_are_the_records_bbox(build))
	out.append(_drawing_fit_labels_follow_the_clearance(loose))
	out.append(_drawing_of_a_guard_has_no_fit(guarded))
	out.append(_drawing_of_a_refused_part_is_empty())
	out.append(_drawing_plan_is_x_right_y_up(build))

	# --- the sheet
	out.append(_sheet_cut_to_one_part(build))
	out.append(_sheet_cut_drops_the_prose(build))
	out.append(_sheet_whole_room_comes_back(build))
	out.append(_sheet_keeps_only_its_own_keep_and_reprint(build))
	return out


static func _diagram(build: Build, part: String) -> PrintedDiagram:
	var d := PrintedDiagram.new()
	d.size = Vector2(700, 500)
	d.show_part(build, part)
	return d


static func _drawing_draws_the_exported_triangles(build: Build) -> TestResult:
	var d := _diagram(build, "antenna_mount")
	var want: Array = PrintedParts.solid_for(build, "antenna_mount")["triangles"]
	var ok: bool = d.triangles.size() == want.size() and want.size() > 100 and d.triangles == want
	d.free()
	return TestResult.new("printed drawing: the antenna mount is drawn from the triangles its Export writes", ok,
		"%d triangles" % want.size())


static func _drawing_dimensions_are_the_records_bbox(build: Build) -> TestResult:
	var d := _diagram(build, "battery_pad")
	var box := PrintedExport.bbox_mm(PrintedParts.solid_for(build, "battery_pad")["triangles"])
	var labels := d.dimension_labels()
	d.free()
	return TestResult.new("printed drawing: the pad's three dimensions are its record's bounding box",
		labels.size() >= 3 and labels.slice(0, 3) == ["%.1f mm" % box[0], "%.1f mm" % box[1],
			"%.1f mm" % box[2]] and float(box[1]) > 70.0, str(labels))


static func _drawing_fit_labels_follow_the_clearance(loose: Build) -> TestResult:
	var d := _diagram(loose, "arm_guard")
	var labels := d.dimension_labels()
	d.free()
	return TestResult.new("printed drawing: at 0.35 mm the arm sleeve's section reads arm 5.0, hole 5.7, 0.35 each side",
		labels.slice(3) == ["Arm 5.0 mm", "hole 5.7 mm", "0.35 mm each side"], str(labels))


static func _drawing_of_a_guard_has_no_fit(guarded: Build) -> TestResult:
	var d := _diagram(guarded, "prop_guard")
	var labels := d.dimension_labels()
	var ok := labels.size() == 3 and d.fit.is_empty() and not d.triangles.is_empty()
	d.free()
	return TestResult.new("printed drawing: a guard ring draws plan and side, and no fit section", ok, str(labels))


static func _drawing_of_a_refused_part_is_empty() -> TestResult:
	var build := ReferenceBuild.build()
	var printing := {}
	CameraMount.set_value(printing, CameraMount.PLATE_SPACING, CameraMount.MIN_PLATE_SPACING_MM)
	build.set_printing(printing)
	var d := _diagram(build, "camera_mount")
	var ok := d.triangles.is_empty() and d.refused_reason != "" and d.dimension_labels().is_empty()
	d.free()
	return TestResult.new("printed drawing: a part the build refuses draws nothing and keeps its reason", ok, "")


static func _drawing_plan_is_x_right_y_up(build: Build) -> TestResult:
	var d := _diagram(build, "battery_pad")
	d._fit_views()
	var origin := d.plan_px(Vector3.ZERO)
	var ok := d.plan_px(Vector3(10, 0, 0)).x > origin.x and d.plan_px(Vector3(0, 10, 0)).y < origin.y \
		and d.side_px(Vector3(0, 0, 10)).y < d.side_px(Vector3.ZERO).y \
		and absf((d.plan_px(Vector3(10, 0, 0)) - origin).length() - (d.plan_px(Vector3(0, 10, 0)) - origin).length()) < 1e-3
	d.free()
	return TestResult.new("printed drawing: plan is X right and Y up the page, side Z up, one scale", ok, "")


static func _panel(build: Build, part: String) -> PrintPanel:
	var panel := PrintPanel.new()
	panel.render(build, build.printing)
	panel.set_dock_part(part)
	return panel


static func _sheet_cut_to_one_part(build: Build) -> TestResult:
	var panel := _panel(build, "camera_mount")
	var shown := panel.shown_parts()
	var ok: bool = shown == ["camera_mount"] and panel.export_button("camera_mount") != null \
		and panel.export_button("camera_mount").visible
	panel.free()
	return TestResult.new("printed sheet: the camera mount's page shows its own line and Export only", ok, str(shown))


static func _sheet_cut_drops_the_prose(build: Build) -> TestResult:
	var panel := _panel(build, "arm_guard")
	var ok := not panel.prose_visible()
	panel.free()
	return TestResult.new("printed sheet: on a part's page the room's sentences go", ok, "")


static func _sheet_whole_room_comes_back(build: Build) -> TestResult:
	var panel := _panel(build, "arm_guard")
	panel.set_dock_part("")
	var shown := panel.shown_parts()
	var ok := shown.size() == 4 and panel.prose_visible()
	panel.free()
	return TestResult.new("printed sheet: cut back to \"\" the whole room and its sentences return", ok, str(shown))


static func _sheet_keeps_only_its_own_keep_and_reprint(build: Build) -> TestResult:
	var panel := _panel(build, "arm_guard")
	panel.set_divergence([_finding("arm_guard", "differs"), _finding("camera_mount", "differs")])
	var own_keep := panel.divergence_button("arm_guard", "keep")
	var other := panel.divergence_button("camera_mount", "keep")
	var ok: bool = panel.before_visible() and own_keep != null and own_keep.visible \
		and other != null and not other.get_parent().visible
	panel.free()
	return TestResult.new("printed sheet: a part's page keeps its own Keep and Reprint, not another part's", ok, "")


static func _loose(mm: float) -> Build:
	var build := ReferenceBuild.build()
	var printing := {}
	PrintSettings.set_clearance_mm(printing, mm)
	build.set_printing(printing)
	return build


## The freestyle reference with the 5" ABS bumper fitted (a printed ring by the catalogue's silence).
static func _guarded() -> Build:
	var catalog := PartsCatalog.load_default()
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, "guard_bumper_5in_abs")


static func _row(rows: Array, part: String) -> Dictionary:
	for row in rows:
		if row["id"] == StringName("printed:%s" % part):
			return row
	return {}


static func _show(row: Dictionary) -> String:
	return "'%s' / '%s' / '%s' [%s]" % [row.get("name"), row.get("choice"), row.get("line3"),
		row.get("status")]


static func _finding(part: String, kind: String) -> Dictionary:
	return {"part": part, "kind": kind, "date": "2026-09-20",
		"message": "The %s you printed on 2026-09-20 differs (a test)." % part}


# ---------------------------------------------------------------------------
# The shared figures
# ---------------------------------------------------------------------------

static func _mesh_volume_is_the_arm_guards_own(build: Build) -> TestResult:
	var mesh := float(PrintedFigures.piece(build, "arm_guard")["volume_mm3"])
	var analytic := ArmGuard.volume_mm3(ArmGuard.dimensions(build.frame, build.printing))
	return TestResult.new("printed figures: the arm guard's volume off its triangles is ArmGuard's own",
		analytic > 100.0 and absf(mesh - analytic) < 1e-3 * analytic, "%.3f vs %.3f" % [mesh, analytic])


static func _mesh_volume_is_the_camera_mounts_own(build: Build) -> TestResult:
	var mesh := float(PrintedFigures.piece(build, "camera_mount")["volume_mm3"])
	var analytic := CameraMount.volume_mm3(CameraMount.dimensions(build.components["camera"],
		build.printing, float(build.assembly_value("camera_tilt_deg"))))
	return TestResult.new("printed figures: the camera cheek's volume off its triangles is CameraMount's own",
		analytic > 100.0 and absf(mesh - analytic) < 1e-3 * analytic, "%.3f vs %.3f" % [mesh, analytic])


## The pad is weighed when fitted; the page's print mass must be that same weight.
static func _battery_pad_print_mass_is_its_weighed_mass(build: Build) -> TestResult:
	var page := float(PrintedFigures.piece(build, "battery_pad")["mass_g"])
	var weighed := BatteryPad.mass_kg(BatteryPad.dimensions(build.battery, build.printing)) * 1000.0
	return TestResult.new("printed figures: the battery pad's print mass is the mass the build weighs it at",
		weighed > 1.0 and absf(page - weighed) < 1e-3 * weighed, "%.4f vs %.4f g" % [page, weighed])


## No analytic volume exists for the antenna mount; its mass is its triangles at TPU density.
static func _antenna_mount_mass_is_its_triangles(build: Build) -> TestResult:
	var solid := PrintedParts.solid_for(build, "antenna_mount")
	var by_hand := 0.0
	for t in solid["triangles"]:
		by_hand += (t[0] as Vector3).dot((t[1] as Vector3).cross(t[2] as Vector3)) / 6.0
	var want := by_hand * 1.0e-9 * PrintSettings.DENSITY_KG_M3 * PrintSettings.INFILL_FRACTION * 1000.0
	var got := float(PrintedFigures.piece(build, "antenna_mount")["mass_g"])
	return TestResult.new("printed figures: the antenna mount's print mass is its own triangles at TPU density",
		want > 1.0 and absf(got - want) < 1e-6, "%.5f vs %.5f g" % [got, want])


## The ring's own published density, not TPU's: ABS 1050 against TPU 1220 is a 16% difference.
static func _guard_mass_is_its_ring_at_the_published_density(guarded: Build) -> TestResult:
	var figures := PrintedFigures.piece(guarded, "prop_guard")
	var density := float(guarded.guard["specs"]["density_kg_m3"])
	var want := float(figures["volume_mm3"]) * 1.0e-9 * density * 1000.0
	var catalogue := float(guarded.guard["mass_g"])
	return TestResult.new("printed figures: a prop guard ring weighs its triangles at the catalogue's own density",
		absf(float(figures["mass_g"]) - want) < 1e-6 and absf(want - catalogue) < 0.02 * catalogue
			and density != PrintSettings.DENSITY_KG_M3,
		"%.3f g, want %.3f, catalogue %.2f" % [float(figures["mass_g"]), want, catalogue])


static func _arm_guard_fit(build: Build) -> TestResult:
	var fit := PrintedFigures.fit(build, "arm_guard")
	var arm := float(build.frame["specs"]["arm_thickness_mm"])
	return TestResult.new("printed figures: the arm guard closes on the frame's published arm with the clearance each side",
		str(fit.get("what")) == "Arm" and absf(float(fit.get("part_mm", 0.0)) - arm) < EPS
			and absf(float(fit.get("hole_mm", 0.0)) - (arm + 2.0 * PrintSettings.DEFAULT_CLEARANCE_MM)) < EPS,
		str(fit))


static func _arm_guard_fit_follows_the_clearance(loose: Build) -> TestResult:
	var fit := PrintedFigures.fit(loose, "arm_guard")
	return TestResult.new("printed figures: at 0.35 mm the arm sleeve opens 0.70 mm over the arm",
		absf(float(fit.get("hole_mm", 0.0)) - float(fit.get("part_mm", 0.0)) - 0.70) < 1e-6, str(fit))


static func _camera_mount_fit_follows_the_clearance(loose: Build) -> TestResult:
	var fit := PrintedFigures.fit(loose, "camera_mount")
	var width := float(Build.component_size_of(loose.components["camera"]).x * 1000.0)
	return TestResult.new("printed figures: at 0.35 mm the cheeks stand 0.70 mm wider than the published camera",
		absf(float(fit.get("part_mm", 0.0)) - width) < 1e-3
			and absf(float(fit.get("hole_mm", 0.0)) - width - 0.70) < 1e-6, str(fit))


static func _antenna_mount_fit_follows_the_clearance(loose: Build) -> TestResult:
	var fit := PrintedFigures.fit(loose, "antenna_mount")
	return TestResult.new("printed figures: at 0.35 mm the standoff ring bores 0.70 mm over the standoff",
		absf(float(fit.get("part_mm", 0.0)) - AntennaMount.DEFAULT_STANDOFF_DIAMETER_MM) < EPS
			and absf(float(fit.get("hole_mm", 0.0)) - float(fit.get("part_mm", 0.0)) - 0.70) < 1e-6, str(fit))


static func _battery_pad_fit_follows_the_clearance(loose: Build) -> TestResult:
	var fit := PrintedFigures.fit(loose, "battery_pad")
	return TestResult.new("printed figures: at 0.35 mm the strap slot opens 0.70 mm over the strap",
		absf(float(fit.get("part_mm", 0.0)) - BatteryPad.STRAP_THICKNESS_MM) < EPS
			and absf(float(fit.get("hole_mm", 0.0)) - float(fit.get("part_mm", 0.0)) - 0.70) < 1e-6, str(fit))


static func _guard_has_no_fit(guarded: Build) -> TestResult:
	return TestResult.new("printed figures: a prop guard ring closes on nothing bought, so it has no fit",
		PrintedFigures.fit(guarded, "prop_guard").is_empty(), "")


static func _a_bought_guard_prints_nothing(_unused: Build) -> TestResult:
	var guarded := _guarded()
	var bought := guarded.guard.duplicate(true)
	bought["fabrication"] = "bought"
	guarded.guard = bought
	var figures := PrintedFigures.piece(guarded, "prop_guard")
	var rows := SectionRows.rows("Printed", guarded)
	var row := _row(rows, "prop_guard")
	return TestResult.new("printed rows: a bought guard reads bought, weighs nothing to print, and is not a warning",
		not bool(figures["ok"]) and str(row.get("choice")) == "ABS · bought"
			and str(row.get("line3")) == "" and str(row.get("status")) == SectionRows.OK, _show(row))


# ---------------------------------------------------------------------------
# The rows
# ---------------------------------------------------------------------------

static func _row_names_its_part(rows: Array, part: String, name: String) -> TestResult:
	var row := _row(rows, part)
	return TestResult.new("printed rows: the %s row is named '%s'" % [part, name],
		str(row.get("name")) == name, _show(row))


## One per part: TPU 95A on line 2, the part's own print mass on line 3 (written out here, and equal
## to PrintedFigures'), green, and inside §3's ~40 characters.
static func _part_row(build: Build, rows: Array, part: String, want: String) -> TestResult:
	var row := _row(rows, part)
	var line3 := str(row.get("line3"))
	return TestResult.new("printed rows: %s reads TPU 95A and '%s'" % [part, want],
		str(row.get("choice")) == "TPU 95A" and line3 == want
			and line3 == PrintedFigures.mass_text(PrintedFigures.piece(build, part))
			and str(row.get("status")) == SectionRows.OK and line3.length() <= 40, _show(row))


static func _guard_row(guarded: Build) -> TestResult:
	var row := _row(SectionRows.rows("Printed", guarded), "prop_guard")
	return TestResult.new("printed rows: a fitted printed guard reads its catalogue material and its ring's grams, print four",
		str(row.get("choice")) == "ABS" and str(row.get("line3")).begins_with("~")
			and str(row.get("line3")).ends_with(" g each · print 4"), _show(row))


static func _rows_open_their_own_page(rows: Array) -> TestResult:
	var row := _row(rows, "camera_mount")
	return TestResult.new("printed rows: a part's page is the Print sheet cut to it, beside its drawing",
		row.get("page") == {"panels": ["Print"], "diagram": "printed", "sheet": "camera_mount"}, str(row.get("page")))


## Camera plate gap at its minimum: the cheeks cannot be cut. Red, with the refusal as its Why?.
static func _a_refused_part_is_red_with_its_reason() -> TestResult:
	var build := ReferenceBuild.build()
	var printing := {}
	CameraMount.set_value(printing, CameraMount.PLATE_SPACING, CameraMount.MIN_PLATE_SPACING_MM)
	build.set_printing(printing)
	var row := _row(SectionRows.rows("Printed", build), "camera_mount")
	var why: Array = row.get("why", [])
	var reason := str(PrintedParts.solid_for(build, "camera_mount")["reason"])
	return TestResult.new("printed rows: a part the build cannot generate is red, its reason behind Why?",
		str(row.get("status")) == SectionRows.BAD and str(row.get("line3")) == "⚠ cannot be generated"
			and why.size() == 1 and reason != "" and str(why[0]) == reason, _show(row) + " " + str(why))


static func _divergence_is_amber_on_its_own_row(build: Build) -> TestResult:
	var warnings := PrintedDivergence.warnings([_finding("camera_mount", "differs")])
	var row := _row(SectionRows.rows("Printed", build, warnings), "camera_mount")
	return TestResult.new("printed rows: a camera mount that differs from its print is amber and says so",
		str(row.get("status")) == SectionRows.WARN
			and str(row.get("line3")) == "⚠ differs from the 2026-09-20 print"
			and (row.get("warnings") as Array).size() == 1, _show(row))


static func _divergence_leaves_the_other_rows_alone(build: Build) -> TestResult:
	var warnings := PrintedDivergence.warnings([_finding("camera_mount", "differs")])
	var rows := SectionRows.rows("Printed", build, warnings)
	var arm := _row(rows, "arm_guard")
	return TestResult.new("printed rows: the camera mount's divergence is not on the arm guard's row",
		str(arm.get("status")) == SectionRows.OK and (arm.get("warnings") as Array).is_empty()
			and str(arm.get("line3")).ends_with("print 4"), _show(arm))


static func _divergence_short_carries_the_print_date() -> TestResult:
	var w := PrintedDivergence.warnings([_finding("battery_pad", "missing_file"),
		_finding("arm_guard", "differs")])
	return TestResult.new("printed warnings: each finding is owned by its part's row, with a short",
		w.size() == 2 and w[0].item == &"printed:battery_pad" and w[0].short == "printed file missing from drone"
			and w[1].item == &"printed:arm_guard" and w[1].short == "differs from the 2026-09-20 print"
			and w[1].severity == BuildWarning.Severity.LIMITING,
		str([w[0].item, w[0].short, w[1].item, w[1].short]) if w.size() == 2 else "%d warnings" % w.size())


static func _divergence_long_is_the_finding() -> TestResult:
	var finding := _finding("arm_guard", "differs")
	var w := PrintedDivergence.warnings([finding])
	return TestResult.new("printed warnings: Why? is the finding's own sentence",
		w.size() == 1 and w[0].long() == str(finding["message"]), "")


## Through the real check: exported at 0.20 mm, opened at 0.35 mm. The date is the record's.
static func _a_real_divergence_carries_its_date() -> TestResult:
	var dir := "user://exports/_test_printed_page"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	var build := ReferenceBuild.build()
	var project := Project.create("Printed page")
	var container := ProjectContainer.make(project)
	PrintedExport.export_all(build, dir, container)
	var records: Array = container.project.print_records
	var date := String((records[0] as Dictionary).get("printed_at", "")).substr(0, 10) \
		if not records.is_empty() else "?"
	var findings := PrintedDivergence.check(container.project, container, _loose(0.35))
	var warnings := PrintedDivergence.warnings(findings)
	var row := _row(SectionRows.rows("Printed", _loose(0.35), warnings), "arm_guard")
	return TestResult.new("printed rows: a real clearance change since export turns the arm guard amber with the print's date",
		date.length() == 10 and str(row.get("status")) == SectionRows.WARN
			and str(row.get("line3")) == "⚠ differs from the %s print" % date,
		"%d findings; %s" % [findings.size(), _show(row)])


# ---------------------------------------------------------------------------
# The page numbers
# ---------------------------------------------------------------------------

static func _arm_guard_page_numbers(build: Build) -> TestResult:
	var numbers := SectionRows.page_numbers(&"printed:arm_guard", build)
	return TestResult.new("printed page: the arm guard's two numbers are its print mass and the arm in its sleeve",
		numbers == [["Print mass", "~1.5 g each · print 4"], ["Arm in its print", "5.0 in 5.4 mm (guess)"]],
		str(numbers))


static func _page_numbers_drop_the_guess_once_set(loose: Build) -> TestResult:
	var numbers := SectionRows.page_numbers(&"printed:battery_pad", loose)
	return TestResult.new("printed page: with the clearance set the fit loses its (guess) and opens to it",
		numbers.size() == 2 and numbers[1] == ["Strap in its print", "2.0 in 2.7 mm"], str(numbers))


static func _guard_page_numbers(guarded: Build) -> TestResult:
	var numbers := SectionRows.page_numbers(&"printed:prop_guard", guarded)
	var box := PrintedExport.bbox_mm(PrintedParts.solid_for(guarded, "prop_guard")["triangles"])
	return TestResult.new("printed page: a guard ring, with no fit, gives its print size instead",
		numbers.size() == 2 and numbers[1] == ["Print size", "%.1f × %.1f × %.1f mm" % [box[0], box[1], box[2]]]
			and float(box[0]) > 100.0, str(numbers))


static func _no_print_time_anywhere(build: Build) -> TestResult:
	var text := str(SectionRows.rows("Printed", build))
	for part in ["arm_guard", "camera_mount", "antenna_mount", "battery_pad"]:
		text += str(SectionRows.page_numbers(StringName("printed:%s" % part), build))
	return TestResult.new("printed page: no print time is claimed — no slicer is modelled",
		not text.contains(" min") and not text.to_lower().contains("time") and not text.contains(" h "), "")
