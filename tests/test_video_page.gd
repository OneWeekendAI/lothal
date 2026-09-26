class_name TestVideoPage
extends RefCounted
## The Video item pages (lab dock design §3, §4): Camera and VTX & antenna, headless.
##
## What this suite guards: each row's line 3, its page's two numbers and its drawing come from ONE
## computation (`VideoFigures`) — the angle the Camera row quotes is the obstruction warning's own
## split of `AirframeModel.camera_clearances`, the height is VideoPlausibility's
## `Build.camera_standing_height_m`, and every position the VTX page draws or measures is the seat the
## mass model weighs the part at (`Build.component_centre_m`). No lens angle, no range and no
## temperature appear anywhere: none is published or modelled.
##
## One test per case.

const EPS := 1e-6


static func run() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var clearances := airframe.camera_clearances()
	var guarded := _guarded()
	var guarded_airframe := AirframeModel.new()
	guarded_airframe.rebuild(guarded)
	var guarded_clearances := guarded_airframe.camera_clearances()

	# --- the shared figures
	out.append(_component_centre_is_the_mass_models_seat(build))
	out.append(_component_centre_is_where_the_airframe_draws_it(build, airframe))
	out.append(_standing_heights_are_the_published_box_level_and_tipped(build))
	out.append(_clearances_frame_is_the_plates_nearest(clearances))
	out.append(_nearest_is_the_frame_with_no_guard(clearances))
	out.append(_nearest_is_the_guard_when_it_is_nearer(guarded_clearances))
	out.append(_nearest_of_nothing_is_empty())
	out.append(_nearest_text_carries_its_tilde(clearances))
	out.append(_antenna_lever_is_seat_minus_com(build))
	out.append(_antenna_lever_without_an_antenna_is_nan())
	out.append(_vtx_and_antenna_mass(build))

	# --- the rows
	out.append(_camera_row_names_the_tilt(build))
	out.append(_camera_row_reads_the_nearest_angle(build, clearances))
	out.append(_camera_row_without_the_airframe_is_empty(build))
	out.append(_camera_row_fits_the_line(build, clearances))
	out.append(_vtx_row_reads_its_grams_with_the_antenna(build))
	out.append(_vtx_row_without_an_antenna_says_so())
	out.append(_obstruction_short_names_the_part_and_angle(guarded_airframe))

	# --- the page numbers
	out.append(_camera_page_numbers(build, clearances))
	out.append(_camera_page_numbers_with_a_guard(guarded, guarded_clearances))
	out.append(_camera_page_numbers_with_no_camera())
	out.append(_vtx_page_numbers(build))

	# --- the drawings
	out.append(_page_definitions_name_their_drawings())
	out.append(_camera_drawing_draws_one_cone_to_the_frame(build, airframe, clearances))
	out.append(_camera_drawing_draws_both_cones_with_a_guard(guarded, guarded_airframe,
		guarded_clearances))
	out.append(_side_view_parts_are_the_drawn_parts(build, airframe))
	out.append(_side_view_eye_is_the_airframes_lens(build, airframe))
	out.append(_side_view_draws_one_disc_per_fore_aft_pair(build, airframe))
	out.append(_vtx_drawing_lever_is_the_figure(build, airframe))
	out.append(_forward_is_right_and_up_is_up(build, airframe))

	# --- the sheets
	out.append(_vtx_sheet_keeps_only_its_rows(build))
	out.append(_whole_sheet_keeps_every_row(build))
	out.append(_vtx_output_row_is_the_catalogues(build))
	out.append(_camera_sheet_rows(build))
	out.append(_camera_sheet_prose_and_warnings_go(build))

	airframe.free()
	guarded_airframe.free()
	return out


## The freestyle reference with the 5" bumper fitted: the guard comes nearer the lens axis than
## the frame (test_camera_view's pair).
static func _guarded() -> Build:
	var catalog := PartsCatalog.load_default()
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, {}, null, "guard_bumper_5in_abs")


static func _without(category: String) -> Build:
	var catalog := PartsCatalog.load_default()
	var ids := Build.DEFAULT_COMPONENT_IDS.duplicate()
	ids[category] = ""
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID, ids)


static func _row(rows: Array, id: StringName) -> Dictionary:
	for row in rows:
		if row["id"] == id:
			return row
	return {}


static func _diagram(build: Build, mode: String, airframe: AirframeModel,
		clearances: Dictionary) -> VideoDiagram:
	var d := VideoDiagram.new()
	d.size = Vector2(600, 500)
	d.show_build(build, mode, airframe, clearances)
	return d


# ---------------------------------------------------------------------------
# The shared figures
# ---------------------------------------------------------------------------

static func _component_centre_is_the_mass_models_seat(build: Build) -> TestResult:
	var antenna_name := str(build.components["antenna"]["name"])
	var weighed := Vector3.INF
	for part in build.mass_parts():
		if part.label == antenna_name:
			weighed = part.position_m
	var got := build.component_centre_m("antenna")
	return TestResult.new("video figures: the antenna's centre is where the mass model weighs it",
		got.is_equal_approx(weighed) and got != Vector3.ZERO, "%s vs %s" % [got, weighed])


static func _component_centre_is_where_the_airframe_draws_it(build: Build,
		airframe: AirframeModel) -> TestResult:
	var drawn: Vector3 = (airframe.component_meshes["vtx"] as Node3D).position
	var got := build.component_centre_m("vtx")
	return TestResult.new("video figures: the VTX's centre is where the airframe draws it",
		got.is_equal_approx(drawn), "%s vs %s" % [got, drawn])


static func _standing_heights_are_the_published_box_level_and_tipped(build: Build) -> TestResult:
	var got := VideoFigures.standing_mm(build)
	var camera: Dictionary = build.components["camera"]
	var tipped := Build.camera_standing_height_m(camera, 25.0) * 1000.0
	return TestResult.new("video figures: the camera stands its published 21 mm level and l·sinθ + h·cosθ at 25°",
		absf(float(got["level"]) - 21.0) < 1e-3 and absf(float(got["tipped"]) - tipped) < 1e-6
			and absf(tipped - (19.0 * sin(deg_to_rad(25.0)) + 21.0 * cos(deg_to_rad(25.0)))) < 1e-3,
		str(got))


static func _clearances_frame_is_the_plates_nearest(clearances: Dictionary) -> TestResult:
	var report: Dictionary = clearances["report"]
	var nearest := INF
	for name in report:
		if str(name).begins_with("Plate"):
			nearest = minf(nearest, float(report[name]))
	return TestResult.new("video figures: the frame's angle is the plates' nearest approach to the lens axis",
		is_finite(nearest) and absf(float(clearances["frame_deg"]) - nearest) < EPS
			and (clearances["fitted"] as Array).is_empty(),
		"%s vs %s" % [clearances["frame_deg"], nearest])


static func _nearest_is_the_frame_with_no_guard(clearances: Dictionary) -> TestResult:
	var got := VideoFigures.nearest_in_view(clearances)
	return TestResult.new("video figures: with no guard the nearest thing to the lens axis is the frame edge",
		got.get("name") == VideoFigures.FRAME_NAME and absf(float(got["deg"])
			- float(clearances["frame_deg"])) < EPS, str(got))


static func _nearest_is_the_guard_when_it_is_nearer(clearances: Dictionary) -> TestResult:
	var got := VideoFigures.nearest_in_view(clearances)
	var guard: Dictionary = (clearances["fitted"] as Array)[0]
	return TestResult.new("video figures: a guard nearer the lens axis than the frame is the nearest",
		got.get("name") == guard["name"] and str(got["name"]).begins_with("guard ")
			and float(got["deg"]) < float(clearances["frame_deg"]), str(got))


static func _nearest_of_nothing_is_empty() -> TestResult:
	return TestResult.new("video figures: nothing measured is nothing nearest, not an invented angle",
		VideoFigures.nearest_in_view({}).is_empty() and VideoFigures.nearest_text({}) == "", "")


static func _nearest_text_carries_its_tilde(clearances: Dictionary) -> TestResult:
	var got := VideoFigures.nearest_text(clearances)
	var want := "frame edge ~%d° off lens axis" % roundi(float(clearances["frame_deg"]))
	return TestResult.new("video figures: the nearest angle reads 'frame edge ~N° off lens axis'",
		got == want, "'%s' want '%s'" % [got, want])


static func _antenna_lever_is_seat_minus_com(build: Build) -> TestResult:
	var want := (build.component_centre_m("antenna").z - build.mass_properties.com_m.z) * 1000.0
	var got := VideoFigures.antenna_aft_of_com_mm(build)
	return TestResult.new("video figures: the antenna's lever is its seat behind the centre of mass",
		absf(got - want) < EPS and got > 20.0, "%.2f vs %.2f" % [got, want])


static func _antenna_lever_without_an_antenna_is_nan() -> TestResult:
	return TestResult.new("video figures: no antenna has no lever",
		is_nan(VideoFigures.antenna_aft_of_com_mm(_without("antenna"))), "")


static func _vtx_and_antenna_mass(build: Build) -> TestResult:
	var got := VideoFigures.vtx_antenna_mass_g(build)
	return TestResult.new("video figures: VTX and antenna weigh 6 + 5 g on the reference build",
		absf(got - 11.0) < EPS, "%.2f" % got)


# ---------------------------------------------------------------------------
# The rows
# ---------------------------------------------------------------------------

static func _camera_row_names_the_tilt(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Video", build), &"camera")
	return TestResult.new("video rows: Camera line 2 names the camera and its uptilt",
		row.get("choice") == "Micro analog (19 mm) · 25° up", "'%s'" % row.get("choice"))


static func _camera_row_reads_the_nearest_angle(build: Build, clearances: Dictionary) -> TestResult:
	var row := _row(SectionRows.rows("Video", build, [], {"camera_view": clearances}), &"camera")
	return TestResult.new("video rows: Camera line 3 is what comes nearest the lens axis",
		row.get("number") == VideoFigures.nearest_text(clearances) and row.get("line3") == row.get("number")
			and str(row.get("number")).begins_with("frame edge ~"), "'%s'" % row.get("number"))


## Without the drawn airframe there is no lens position to measure from: line 3 stays empty rather
## than falling back to the tilt setting (a copied value, not a computed one).
static func _camera_row_without_the_airframe_is_empty(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Video", build), &"camera")
	return TestResult.new("video rows: Camera line 3 is empty without the drawn airframe",
		row.get("number") == "", "'%s'" % row.get("number"))


static func _camera_row_fits_the_line(build: Build, clearances: Dictionary) -> TestResult:
	var row := _row(SectionRows.rows("Video", build, [], {"camera_view": clearances}), &"camera")
	var three := str(row.get("number"))
	var two := str(row.get("choice"))
	return TestResult.new("video rows: Camera's lines 2 and 3 fit a row",
		three.length() <= WarningRows.SHORT_MAX and two.length() <= WarningRows.SHORT_MAX,
		"'%s' %d, '%s' %d" % [two, two.length(), three, three.length()])


static func _vtx_row_reads_its_grams_with_the_antenna(build: Build) -> TestResult:
	var row := _row(SectionRows.rows("Video", build), &"vtx")
	return TestResult.new("video rows: VTX & antenna line 3 is the two parts' grams",
		row.get("number") == "11.0 g with antenna", "'%s'" % row.get("number"))


static func _vtx_row_without_an_antenna_says_so() -> TestResult:
	var build := _without("antenna")
	var row := _row(SectionRows.rows("Video", build, build.warnings()), &"vtx")
	var owned: Array = row.get("warnings", [])
	return TestResult.new("video rows: a VTX with no antenna reads its grams, 'no antenna', and owns the warning",
		row.get("number") == "6.0 g · no antenna" and owned.size() == 1
			and (owned[0] as BuildWarning).id == &"vtx_without_antenna",
		"'%s', %d owned" % [row.get("number"), owned.size()])


static func _obstruction_short_names_the_part_and_angle(airframe: AirframeModel) -> TestResult:
	var warnings := airframe.camera_view_warnings()
	var short := warnings[0].short if warnings.size() == 1 else ""
	var want := "%s ~%d° off lens axis" % [str(warnings[0].values["closest_name"]),
		roundi(float(warnings[0].values["closest_deg"]))] if warnings.size() == 1 else "?"
	return TestResult.new("video rows: the obstruction's short names the part and its angle",
		short == want and short.begins_with("guard ") and short.length() <= WarningRows.SHORT_MAX
			and warnings[0].item == &"camera", "'%s' want '%s'" % [short, want])


# ---------------------------------------------------------------------------
# The page numbers
# ---------------------------------------------------------------------------

static func _camera_page_numbers(build: Build, clearances: Dictionary) -> TestResult:
	var got := SectionRows.page_numbers(&"camera", build, {"camera_view": clearances})
	var stands := VideoFigures.standing_mm(build)
	var want := [["Nearest the lens axis", "frame edge ~%d°" % roundi(float(clearances["frame_deg"]))],
		["Stands at 25° (21.0 mm level)", "%.1f mm" % float(stands["tipped"])]]
	return TestResult.new("page numbers: Camera shows what is nearest the lens axis and how tall it stands tipped",
		got == want, "%s want %s" % [got, want])


static func _camera_page_numbers_with_a_guard(build: Build, clearances: Dictionary) -> TestResult:
	var got := SectionRows.page_numbers(&"camera", build, {"camera_view": clearances})
	var guard: Dictionary = (clearances["fitted"] as Array)[0]
	return TestResult.new("page numbers: with a guard nearer, Camera names the guard",
		str(got[0][1]) == "%s ~%d°" % [guard["name"], roundi(float(guard["deg"]))], str(got))


static func _camera_page_numbers_with_no_camera() -> TestResult:
	var got := SectionRows.page_numbers(&"camera", _without("camera"), {})
	return TestResult.new("page numbers: with no camera, Camera says so and invents no height",
		got == [["Nearest the lens axis", "no camera fitted"], ["Standing height", "—"]], str(got))


static func _vtx_page_numbers(build: Build) -> TestResult:
	var got := SectionRows.page_numbers(&"vtx", build)
	var want := [["VTX + antenna", "11.0 g"],
		["Antenna behind CoM", "~%d mm" % roundi(VideoFigures.antenna_aft_of_com_mm(build))]]
	return TestResult.new("page numbers: VTX & antenna shows the two parts' grams and the antenna's lever, marked ~",
		got == want, "%s want %s" % [got, want])


# ---------------------------------------------------------------------------
# The drawings
# ---------------------------------------------------------------------------

static func _page_definitions_name_their_drawings() -> TestResult:
	var pages := {}
	for definition in SectionRows.DEFINITIONS["Video"]:
		pages[definition["id"]] = definition["page"]
	var ok: bool = pages[&"camera"] == {"panels": ["Camera"], "column": "Electronics",
			"diagram": VideoDiagram.MODE_CAMERA} \
		and pages[&"vtx"] == {"panels": ["Electronics"], "column": "Electronics",
			"diagram": VideoDiagram.MODE_VTX, "sheet": "vtx"}
	return TestResult.new("video rows: Camera and VTX pages name their drawing, sheet and rail",
		ok, str(pages))


static func _camera_drawing_draws_one_cone_to_the_frame(build: Build, airframe: AirframeModel,
		clearances: Dictionary) -> TestResult:
	var d := _diagram(build, VideoDiagram.MODE_CAMERA, airframe, clearances)
	var ok := d.nearest == VideoFigures.nearest_in_view(clearances) and is_inf(d.frame_deg) \
		and absf(d.tilt_deg - 25.0) < EPS
	var shown := "%s, frame %s" % [d.nearest, d.frame_deg]
	d.free()
	return TestResult.new("video drawing: the camera's clear cone runs to the frame edge, one cone",
		ok, shown)


static func _camera_drawing_draws_both_cones_with_a_guard(build: Build, airframe: AirframeModel,
		clearances: Dictionary) -> TestResult:
	var d := _diagram(build, VideoDiagram.MODE_CAMERA, airframe, clearances)
	var ok := str(d.nearest.get("name", "")).begins_with("guard ") \
		and absf(d.frame_deg - float(clearances["frame_deg"])) < EPS
	var shown := "%s, frame %s" % [d.nearest, d.frame_deg]
	d.free()
	return TestResult.new("video drawing: with a guard nearer, the guard's cone and the frame's are both drawn",
		ok, shown)


static func _side_view_parts_are_the_drawn_parts(build: Build, airframe: AirframeModel) -> TestResult:
	var view := VideoFigures.side_view(airframe, build)
	var bad: Array = []
	for category in ["camera", "vtx", "antenna"]:
		var drawn: Vector3 = (airframe.component_meshes[category] as Node3D).position * 1000.0
		var part: Dictionary = view["parts"][category]
		if absf(float(part["f"]) + drawn.z) > 1e-3 or absf(float(part["y"]) - drawn.y) > 1e-3:
			bad.append(category)
	return TestResult.new("video drawing: the camera, VTX and antenna are drawn where the airframe draws them",
		bad.is_empty(), str(bad))


static func _side_view_eye_is_the_airframes_lens(build: Build, airframe: AirframeModel) -> TestResult:
	var view := VideoFigures.side_view(airframe, build)
	var eye: Vector3 = airframe.camera_eye_m() * 1000.0
	var bore := airframe.camera_boresight()
	var ok := bool(view["has_eye"]) and (view["eye"] as Vector2).is_equal_approx(Vector2(-eye.z, eye.y)) \
		and absf((view["bore"] as Vector2).angle() - deg_to_rad(25.0)) < 1e-4 \
		and absf(bore.y - sin(deg_to_rad(25.0))) < 1e-4
	return TestResult.new("video drawing: the lens and its axis are the airframe's, 25° above level",
		ok, "%s %s" % [view["eye"], view["bore"]])


static func _side_view_draws_one_disc_per_fore_aft_pair(build: Build, airframe: AirframeModel) -> TestResult:
	var view := VideoFigures.side_view(airframe, build)
	var discs: Array = view["discs"]
	var radius := (airframe.propeller_meshes["M1"] as PropellerMesh).radius_m * 1000.0
	var ok := discs.size() == 2 and absf(float(discs[0]["r"]) - radius) < EPS \
		and signf(float(discs[0]["f"])) != signf(float(discs[1]["f"]))
	return TestResult.new("video drawing: an X quad's four discs are two in side view, at the drawn radius",
		ok, str(discs))


static func _vtx_drawing_lever_is_the_figure(build: Build, airframe: AirframeModel) -> TestResult:
	var d := _diagram(build, VideoDiagram.MODE_VTX, airframe, {})
	var ok := absf(d.antenna_aft_mm - VideoFigures.antenna_aft_of_com_mm(build)) < EPS \
		and d.power_class == "400 mW"
	var shown := "%.2f, '%s'" % [d.antenna_aft_mm, d.power_class]
	d.free()
	return TestResult.new("video drawing: the VTX page's lever is the figure and its power is the catalogue's class",
		ok, shown)


static func _forward_is_right_and_up_is_up(build: Build, airframe: AirframeModel) -> TestResult:
	var d := _diagram(build, VideoDiagram.MODE_CAMERA, airframe, {})
	d._fit()
	var origin := d.to_px(Vector2.ZERO)
	var ahead := d.to_px(Vector2(10.0, 0.0))
	var above := d.to_px(Vector2(0.0, 10.0))
	d.free()
	return TestResult.new("video drawing: forward draws right and up draws up, one scale",
		ahead.x > origin.x and above.y < origin.y and absf((ahead.x - origin.x) - (origin.y - above.y)) < 1e-3,
		"%s %s %s" % [origin, ahead, above])


# ---------------------------------------------------------------------------
# The sheets
# ---------------------------------------------------------------------------

static func _vtx_sheet_keeps_only_its_rows(build: Build) -> TestResult:
	var panel := ElectronicsDetails.new()
	panel.render_components(build)
	panel.set_dock_sheet("vtx")
	var keys := panel.shown_keys()
	var title := panel.shown_title()
	panel.free()
	return TestResult.new("video sheet: the VTX page's sheet is the transmitter and the antenna only",
		keys == ElectronicsDetails.VTX_SHEET_ROWS and title == "VTX & ANTENNA", "%s '%s'" % [keys, title])


static func _whole_sheet_keeps_every_row(build: Build) -> TestResult:
	var panel := ElectronicsDetails.new()
	panel.render_components(build)
	panel.set_dock_sheet("vtx")
	panel.set_dock_sheet("")
	var keys := panel.shown_keys()
	panel.free()
	return TestResult.new("video sheet: the whole Electronics sheet shows every row again",
		keys.size() == ElectronicsDetails.SPEC_ROWS.size(), str(keys))


static func _vtx_output_row_is_the_catalogues(build: Build) -> TestResult:
	var panel := ElectronicsDetails.new()
	panel.render_components(build)
	var output := panel.row_text("vtx_output")
	var kind := panel.row_text("antenna_type")
	panel.free()
	return TestResult.new("video sheet: the VTX's output and the antenna's type are the catalogue's words",
		output == "400 mW · 5.8 GHz" and kind == "RHCP · u.FL · 2.0 dBi", "'%s' '%s'" % [output, kind])


static func _camera_sheet_rows(build: Build) -> TestResult:
	var panel := CameraPanel.new()
	panel.render(build, AssemblyTweaks.new())
	var part := panel.spec_text("part")
	var box := panel.spec_text("size")
	var sensor := panel.spec_text("sensor")
	panel.free()
	return TestResult.new("video sheet: the Camera sheet names the camera, its box L × W × H and sensor",
		part == "Micro analog (19 mm)   8.0 g" and box == "19 × 19 × 21 mm" and sensor == "CMOS 1/1.8\"",
		"'%s' '%s' '%s'" % [part, box, sensor])


## Rendered on a build that HAS a camera warning (a nano behind 28 mm standoffs, tipped 25° into
## the top plate — test_video_panel's fixture), or an empty list would be hidden anyway.
static func _camera_sheet_prose_and_warnings_go(_build: Build) -> TestResult:
	var catalog := PartsCatalog.load_default()
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, Build.DEFAULT_ESC_ID,
		Build.DEFAULT_FC_ID, {"camera": "cam_nano_analog"})
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.PLATE_GAP, 28.0)
	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, 25.0)
	build.set_assembly(tweaks.resolved_m(build))
	var panel := CameraPanel.new()
	panel.set_prose_visible(false)
	panel.set_warnings_visible(false)
	panel.render(build, tweaks)
	var ok := not panel.prose_visible() and not panel.warnings_visible() \
		and VideoPlausibility.warnings_for(build).size() == 1
	panel.free()
	return TestResult.new("video sheet: on the dock the Camera panel drops its sentences and its warning list, across a render",
		ok, "")
