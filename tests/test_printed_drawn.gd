class_name TestPrintedDrawn
extends RefCounted
## Printed parts drawn in the Lab (printed-room PR16–PR18, plans/2026-09-14-printed-room-plan.md).
##
## Each fitted part is drawn from its own `triangles_mm` — the list the export writes — and seated
## where it is weighed or where the part it holds is drawn. Not fitted draws nothing.

const MASTED := "gps_masted_compact"


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_the_mast_is_drawn_on_its_bay_where_it_is_weighed(catalog))
	results.append_array(_the_pad_is_drawn_under_the_pack_where_it_is_weighed())
	results.append(_under_the_bottom_plate_the_pad_is_turned_over())
	results.append(_nothing_is_drawn_until_fitted(catalog))
	results.append_array(_the_cheeks_are_drawn_either_side_of_the_tipped_camera())
	results.append_array(_the_cheeks_move_no_camera_check())
	results.append(_the_cheeks_are_fitted_from_the_panel())
	return results


## Tolerances are 1e-6 m (1 µm) and 1e-5 of a volume: drawn vertices are single-precision mesh data. Every
## mutation these checks exist for moves a part by a millimetre or more.

## Signed volume by the divergence theorem, m³. Positive for an outward shell; a reflected drawing flips it.
static func signed_volume_m3(vertices: PackedVector3Array) -> float:
	var sum := 0.0
	for i in range(0, vertices.size() - 2, 3):
		sum += vertices[i].dot(vertices[i + 1].cross(vertices[i + 2]))
	return sum / 6.0


## A triangle list (Array of PackedVector3Array) as one flat vertex list.
static func flatten(triangles: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for t in triangles:
		out.append_array(t)
	return out


static func bounds(vertices: PackedVector3Array) -> AABB:
	if vertices.is_empty():
		return AABB()
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		box = box.expand(v)
	return box


static func _masted_build(catalog: PartsCatalog, printing: Dictionary) -> Build:
	var build := ReferenceBuild.build()
	build.components["gps"] = catalog.get_part(MASTED)
	build.set_printing(printing)
	return build


static func _the_mast_is_drawn_on_its_bay_where_it_is_weighed(catalog: PartsCatalog) -> Array:
	var printing := {}
	GpsMast.set_value(printing, GpsMast.FITTED, true)
	GpsMast.set_value(printing, GpsMast.PAD, 3.0)
	var build := _masted_build(catalog, printing)
	# Off the module's own 45 mm, so a drawing that read the catalog height instead of Build's is caught.
	build.set_assembly({"mast_height_m": 0.030})
	var dims := GpsMast.dimensions(build, printing)
	var triangles := GpsMast.triangles_mm(dims)
	var printed_volume := signed_volume_m3(flatten(triangles)) * 1e-9

	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var mesh: PrintedPartMesh = airframe.printed_part_meshes.get(GpsMast.PART_ID, null)
	var local := mesh.drawn_vertices_m() if mesh != null else PackedVector3Array()
	var seated := mesh.seated_vertices_m() if mesh != null else PackedVector3Array()
	var bay := airframe.mount_point("gps_mount")
	var bay_y := bay.position.y if bay != null else INF
	airframe.free()

	var weighed := Vector3.INF
	for pm in build.mass_parts():
		if (pm as PartMass).label == "GPS mast":
			weighed = (pm as PartMass).position_m
	var box := bounds(seated)
	var drawn_volume := signed_volume_m3(local)
	# Written out: a 27 mm post under a 3 mm pad standing on the bay's face (PR16); weighed half the 30 mm mast up.
	return [
		TestResult.new("the fitted mast is drawn from the exported triangles, wound as printed",
			triangles.size() > 0 and local.size() == triangles.size() * 3
				and printed_volume > 0.0 and absf(drawn_volume - printed_volume) < 1e-5 * printed_volume,
			"%d vertices for %d triangles; drawn %.4f mm³ vs printed %.4f mm³" % [local.size(), triangles.size(),
				drawn_volume * 1e9, printed_volume * 1e9]),
		TestResult.new("its flange stands on the GPS bay, 30 mm tall pad included, centred over the weighed point half the mast up",
			not seated.is_empty() and absf(box.position.y - bay_y) < 1e-6
				and absf(box.size.y - 0.030) < 1e-6
				and absf(bay_y + 0.015 - weighed.y) < 1e-6
				and Vector2(box.get_center().x - weighed.x, box.get_center().z - weighed.z).length() < 1e-6,
			"foot %.6f vs bay %.6f; height %.6f m; centre %s vs weighed %s" % [box.position.y, bay_y, box.size.y,
				box.get_center(), weighed]),
	]


static func _the_pad_is_drawn_under_the_pack_where_it_is_weighed() -> Array:
	var printing := {}
	BatteryPad.set_value(printing, BatteryPad.FITTED, true)
	BatteryPad.set_value(printing, BatteryPad.THICKNESS, 3.0)
	var build := ReferenceBuild.build()
	build.set_printing(printing)
	# Slid 9 mm aft, so a pad drawn at the default seat is caught.
	build.set_assembly({"battery_offset_m": -0.009})
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.BATTERY_OFFSET, -9.0)
	var dims := BatteryPad.dimensions(build.battery, printing)
	var triangles := BatteryPad.triangles_mm(dims)
	var printed_volume := signed_volume_m3(flatten(triangles)) * 1e-9

	var airframe := AirframeModel.new()
	airframe.rebuild(build, tweaks)
	var mesh: PrintedPartMesh = airframe.printed_part_meshes.get(BatteryPad.PART_ID, null)
	var local := mesh.drawn_vertices_m() if mesh != null else PackedVector3Array()
	var seated := mesh.seated_vertices_m() if mesh != null else PackedVector3Array()
	var pack_bottom := airframe.battery_mesh.position.y - airframe.battery_mesh.size_m.y * 0.5
	var pack_z := airframe.battery_mesh.position.z
	airframe.free()

	var weighed := Vector3.INF
	for pm in build.mass_parts():
		if (pm as PartMass).label == "Battery pad":
			weighed = (pm as PartMass).position_m
	var box := bounds(seated)
	var drawn_volume := signed_volume_m3(local)
	return [
		TestResult.new("the fitted pad is drawn from the exported triangles, wound as printed",
			triangles.size() > 0 and local.size() == triangles.size() * 3
				and printed_volume > 0.0 and absf(drawn_volume - printed_volume) < 1e-5 * printed_volume,
			"%d vertices for %d triangles; drawn %.4f mm³ vs printed %.4f mm³" % [local.size(), triangles.size(),
				drawn_volume * 1e9, printed_volume * 1e9]),
		TestResult.new("it is the pad's width × length × 3 mm, its top on the slid pack's underside, centred on the weighed point",
			not seated.is_empty()
				and absf(box.size.x - float(dims["pad_width_mm"]) * 0.001) < 1e-6
				and absf(box.size.z - float(dims["pad_length_mm"]) * 0.001) < 1e-6
				and absf(box.size.y - 0.003) < 1e-6
				and absf(box.end.y - pack_bottom) < 1e-6
				and absf(box.get_center().z - pack_z) < 1e-6
				and box.get_center().distance_to(weighed) < 1e-6,
			"box %s; top %.6f vs pack underside %.6f; centre %s vs weighed %s" % [box, box.end.y, pack_bottom,
				box.get_center(), weighed]),
	]


## A pack strapped under the bottom plate hangs from it, so the pad is between the plate's underside and the
## pack's top: turned over, still wound outward.
static func _under_the_bottom_plate_the_pad_is_turned_over() -> TestResult:
	var printing := {}
	BatteryPad.set_value(printing, BatteryPad.FITTED, true)
	BatteryPad.set_value(printing, BatteryPad.THICKNESS, 3.0)
	var build := ReferenceBuild.build()
	build.set_printing(printing)
	build.set_assembly({"battery_mount": "strap_bottom"})
	var tweaks := AssemblyTweaks.new()
	tweaks.set_choice(AssemblyTweaks.BATTERY_MOUNT, "strap_bottom")
	var airframe := AirframeModel.new()
	airframe.rebuild(build, tweaks)
	var on_bottom := airframe.battery_mount != null and airframe.battery_mount.id == "strap_bottom"
	var face := airframe.battery_mount.position.y if airframe.battery_mount != null else INF
	var pack_top := airframe.battery_mesh.position.y + airframe.battery_mesh.size_m.y * 0.5
	var mesh: PrintedPartMesh = airframe.printed_part_meshes.get(BatteryPad.PART_ID, null)
	var seated := mesh.seated_vertices_m() if mesh != null else PackedVector3Array()
	airframe.free()
	var box := bounds(seated)
	return TestResult.new("under the bottom plate the 3 mm pad spans from the pack's top to the plate's underside, wound outward",
		on_bottom and not seated.is_empty() and absf(box.position.y - pack_top) < 1e-6 and absf(box.end.y - face) < 1e-6
			and signed_volume_m3(seated) > 0.0,
		"on bottom %s; pad %.6f..%.6f, pack top %.6f, plate %.6f; volume %.4f mm³" % [on_bottom, box.position.y, box.end.y,
			pack_top, face, signed_volume_m3(seated) * 1e9])


static func _nothing_is_drawn_until_fitted(catalog: PartsCatalog) -> TestResult:
	var build := _masted_build(catalog, {})
	var airframe := AirframeModel.new()
	airframe.rebuild(build)
	var count := airframe.printed_part_meshes.size()
	var children := 0
	for child in airframe.frame_model.get_children():
		if child is PrintedPartMesh:
			children += 1
	airframe.free()
	return TestResult.new("a build that fits a GPS and a pack but ticks nothing draws no printed part",
		count == 0 and children == 0, "%d meshes, %d nodes" % [count, children])


## A reference build (micro camera, 19 × 19 × 21 mm) at a 40° tilt from the tweaks, a 26 mm gap and 0.35 mm
## of clearance, all off their defaults so a drawing that ignored any of them is caught.
static func _cheek_airframe(fitted: bool, gap_mm: float = 26.0) -> AirframeModel:
	var printing := {}
	CameraMount.set_value(printing, CameraMount.FITTED, fitted)
	CameraMount.set_value(printing, CameraMount.PLATE_SPACING, gap_mm)
	PrintSettings.set_clearance_mm(printing, 0.35)
	var build := ReferenceBuild.build()
	build.set_printing(printing)
	var tweaks := AssemblyTweaks.new()
	tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, 40.0)
	var airframe := AirframeModel.new()
	airframe.rebuild(build, tweaks)
	return airframe


static func _the_cheeks_are_drawn_either_side_of_the_tipped_camera() -> Array:
	var airframe := _cheek_airframe(true)
	var camera_at: Vector3 = (airframe.component_meshes["camera"] as Node3D).position \
		if airframe.component_meshes.has("camera") else Vector3.INF
	var sides := {}
	for side in ["left", "right"]:
		var mesh: PrintedPartMesh = airframe.printed_part_meshes.get("%s_%s" % [CameraMount.PART_ID, side], null)
		sides[side] = {"local": mesh.drawn_vertices_m() if mesh != null else PackedVector3Array(),
			"seated": mesh.seated_vertices_m() if mesh != null else PackedVector3Array()}
	airframe.free()
	var refused := _cheek_airframe(true, 18.0)
	var refused_count := refused.printed_part_meshes.size()
	refused.free()

	var fixture := {}
	CameraMount.set_value(fixture, CameraMount.PLATE_SPACING, 26.0)
	PrintSettings.set_clearance_mm(fixture, 0.35)
	var dims := CameraMount.dimensions(ReferenceBuild.build().components["camera"], fixture, 40.0)
	var triangles := CameraMount.triangles_mm(dims)
	var printed_volume := signed_volume_m3(flatten(triangles)) * 1e-9
	# Written out: 19 mm wide, so the inner face is 9.5 + 0.35 mm off the camera's centre and the outer face
	# half the 26 mm gap; standing height at 40° is 19 sin 40° + 21 cos 40°.
	var inner := (9.5 + 0.35) / 1000.0
	var outer := 13.0 / 1000.0
	var standing := (19.0 * sin(deg_to_rad(40.0)) + 21.0 * cos(deg_to_rad(40.0))) / 1000.0
	var shape_ok := true
	var detail := ""
	for side in ["left", "right"]:
		var local: PackedVector3Array = sides[side]["local"]
		var seated: PackedVector3Array = sides[side]["seated"]
		var side_sign := -1.0 if side == "left" else 1.0
		var near := INF
		var far := -INF
		for v in seated:
			near = minf(near, (v.x - camera_at.x) * side_sign)
			far = maxf(far, (v.x - camera_at.x) * side_sign)
		var box := bounds(seated)
		var ok := (local.size() == triangles.size() * 3 and triangles.size() > 0
			and absf(signed_volume_m3(local) - printed_volume) < 1e-6 * printed_volume
			and absf(near - inner) < 1e-6 and absf(far - outer) < 1e-6
			and absf(box.size.y - standing) < 1e-6
			and absf(box.get_center().y - camera_at.y) < 1e-6)
		shape_ok = shape_ok and ok
		detail += "%s: %d verts for %d triangles, volume %.4f vs %.4f mm³, near off %.9f far off %.9f, tall off %.9f, centre y off %.9f; " % [
			side, local.size(), triangles.size(), signed_volume_m3(local) * 1e9, printed_volume * 1e9,
			near - inner, far - outer, box.size.y - standing, box.get_center().y - camera_at.y]
	return [
		TestResult.new("two fitted cheeks are drawn from the exported triangles, from clearance off the camera's side to half the gap, as tall as the camera tipped to 40°",
			shape_ok and printed_volume > 0.0, detail),
		TestResult.new("a 19 mm camera in an 18 mm gap is refused, so nothing is drawn beside it",
			refused_count == 0, "%d meshes" % refused_count),
	]


## The Wave V numbers do not move: the camera-view report, its warnings and the component fit warnings are
## identical with the cheeks drawn, and every drawn cheek point is behind the lens — over 90° off the boresight.
static func _the_cheeks_move_no_camera_check() -> Array:
	var reports := []
	var worst := INF
	for fitted in [false, true]:
		var airframe := _cheek_airframe(fitted)
		var eye: Vector3 = airframe.camera_eye_m()
		var boresight := airframe.camera_boresight()
		var view := CameraView.off_axis_report(eye, boresight, airframe.camera_obstruction_points_m())
		var words := []
		for w in airframe.camera_view_warnings():
			words.append((w as BuildWarning).message)
		for w in airframe.component_fit_warnings():
			words.append((w as BuildWarning).message)
		reports.append([view, words])
		if fitted:
			for id in airframe.printed_part_meshes:
				for v in (airframe.printed_part_meshes[id] as PrintedPartMesh).seated_vertices_m():
					worst = minf(worst, rad_to_deg(boresight.angle_to(v - eye)))
		airframe.free()
	return [
		TestResult.new("fitting the cheeks changes no camera-view angle, view warning or fit warning",
			str(reports[0]) == str(reports[1]) and not str(reports[0][0]).is_empty(),
			"unfitted %s / fitted %s" % [reports[0], reports[1]]),
		TestResult.new("every drawn cheek point is more than 90° off the boresight, so a cheek can never be in the picture",
			worst > 90.0 and worst < INF, "nearest %.3f°" % worst),
	]


static func _the_cheeks_are_fitted_from_the_panel() -> TestResult:
	var shell := GlassShell.new()
	var project := Project.create("Cheeks")
	project.parts["camera"] = "cam_micro_analog"
	shell.apply_project(project)
	var before := shell.lab.airframe.printed_part_meshes.size()
	var mass_before := shell.lab.current_build().mass_properties.total_mass_kg
	# The checkbox itself is pressed, so a toggle that emits nothing is caught.
	var toggle := shell.lab.print_panel.fit_toggle(CameraMount.PART_ID)
	if toggle != null:
		toggle.button_pressed = true
	var after := shell.lab.airframe.printed_part_meshes.keys()
	var mass_after := shell.lab.current_build().mass_properties.total_mass_kg
	var refreshed := shell.lab.print_panel.fit_toggle(CameraMount.PART_ID)
	var pressed := refreshed != null and refreshed.button_pressed
	shell.free()
	return TestResult.new("the camera mount's Fitted toggle draws both cheeks and adds no weight",
		before == 0 and after.has("camera_mount_left") and after.has("camera_mount_right") and pressed
			and mass_after == mass_before,
		"before %d, after %s, pressed %s, %+.6f g" % [before, after, pressed, (mass_after - mass_before) * 1000.0])
