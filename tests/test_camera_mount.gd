class_name TestCameraMount
extends RefCounted
## The camera mount — printed-room slice PR2 (plans/2026-09-14-printed-room-plan.md, PR2 checks).
##
## One TPU cheek, printed twice: the camera's own side silhouette at the current tilt, with a screw
## hole at the pivot, filling the gap between the camera and the frame's side plate.
##
## Where each check could pass while proving nothing, and what stops it:
##   - "manifold" on an empty list: the count is asserted, and the volume is held to the closed form
##     (box side minus a regular N-gon), so a cheek with no hole fails as surely as no cheek.
##   - "tilt applies" at 25° could agree with a hard-coded 25°; it is checked at 40°, against the
##     tipped box's height written out by hand (l·sin θ + h·cos θ), not against Build's own helper.
##   - "clearance applies" at the default could not see it ignored; 0.10 vs 0.35 mm.
##   - "refuses a camera wider than the gap" needs a fixture it ACCEPTS (the micro camera) beside the
##     one it refuses (the full-size camera), or a refusal stuck at "no" stays green.
##   - "the gap is per drone" is only visible with two drones holding DIFFERENT values (A/B/A).
##   - "adds no mass" is checked on a build whose printing block names a camera mount, so a mutation
##     that weighs it has something to weigh.

const EPS := 1e-6


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var micro := catalog.get_part("cam_micro_analog")
	var nano := catalog.get_part("cam_nano_analog")
	var full := catalog.get_part("cam_fullsize_analog")

	results.append_array(_the_solid_is_a_holed_cheek(micro))
	results.append(_tilt_is_the_tipped_box_at_40(micro))
	results.append(_clearance_thins_the_cheek_and_opens_the_hole(micro))
	results.append(_the_mount_follows_the_camera(micro, nano))
	results.append_array(_a_camera_wider_than_the_gap_is_refused(micro, full))
	results.append_array(_the_gap_is_a_labelled_guess_per_drone())
	results.append(_it_weighs_nothing_of_its_own())
	results.append(_no_camera_no_row())
	return results


static func _the_solid_is_a_holed_cheek(camera: Dictionary) -> Array:
	var dims := CameraMount.dimensions(camera, {}, 40.0)
	var triangles := CameraMount.triangles_mm(dims)
	var report := StlWriter.check_manifold(triangles)
	var n := int(dims.get("hole_segments", 0))
	var r := float(dims.get("hole_radius_mm", 0.0))
	# Written out here rather than read from CameraMount.volume_mm3, so the oracle is not the code.
	var expected := (19.0 * 21.0 - n * 0.5 * r * r * sin(TAU / maxf(n, 1))) * float(dims.get("cheek_thickness_mm", 0.0))
	var volume := float(report["volume_mm3"])
	return [
		TestResult.new("the micro camera's cheek has triangles to check",
			triangles.size() > 0, "%d triangles" % triangles.size()),
		TestResult.new("and they close into an outward solid whose volume is the camera's side minus the screw hole",
			bool(report["ok"]) and n >= 12 and r > 0.0 and absf(volume - expected) < 1e-4 * expected,
			"ok %s, %.4f mm³ vs %.4f mm³ (N %d, r %.3f), reasons %s" % [report["ok"], volume, expected, n, r,
				report["reasons"]]),
	]


static func _tilt_is_the_tipped_box_at_40(camera: Dictionary) -> TestResult:
	var at_40 := CameraMount.triangles_mm(CameraMount.dimensions(camera, {}, 40.0))
	var at_0 := CameraMount.triangles_mm(CameraMount.dimensions(camera, {}, 0.0))
	var theta := deg_to_rad(40.0)
	var tipped := 19.0 * sin(theta) + 21.0 * cos(theta)
	var span_40 := _span(at_40, 1)
	var span_0 := _span(at_0, 1)
	return TestResult.new(
		"printed at 40°, the cheek stands as tall as the tipped camera (l·sin θ + h·cos θ), and level it is h",
		absf(span_40 - tipped) < 1e-3 and absf(span_0 - 21.0) < 1e-3,
		"40°: %.4f vs %.4f mm; 0°: %.4f vs 21 mm" % [span_40, tipped, span_0])


static func _clearance_thins_the_cheek_and_opens_the_hole(camera: Dictionary) -> TestResult:
	var tight := {}
	PrintSettings.set_clearance_mm(tight, 0.10)
	var loose := {}
	PrintSettings.set_clearance_mm(loose, 0.35)
	var t := CameraMount.dimensions(camera, tight, 40.0)
	var l := CameraMount.dimensions(camera, loose, 40.0)
	var thinner := _span(CameraMount.triangles_mm(t), 2) - _span(CameraMount.triangles_mm(l), 2)
	var wider := float(l.get("hole_radius_mm", 0.0)) - float(t.get("hole_radius_mm", 0.0))
	return TestResult.new(
		"0.25 mm more clearance takes 0.25 mm off the cheek, in the solid, and opens the screw hole's radius by 0.25 mm",
		absf(thinner - 0.25) < 1e-3 and absf(wider - 0.25) < 1e-6,
		"cheek −%.4f mm, hole radius +%.4f mm" % [thinner, wider])


static func _the_mount_follows_the_camera(micro: Dictionary, nano: Dictionary) -> TestResult:
	var m := CameraMount.triangles_mm(CameraMount.dimensions(micro, {}, 0.0))
	var n := CameraMount.triangles_mm(CameraMount.dimensions(nano, {}, 0.0))
	var dm := CameraMount.dimensions(micro, {}, 0.0)
	var dn := CameraMount.dimensions(nano, {}, 0.0)
	# A 5 mm narrower camera in the same 24 mm gap leaves 2.5 mm more for each cheek.
	return TestResult.new(
		"swapping the micro camera for the nano changes the cheek: 19 → 14 mm long, and 2.5 mm thicker each side",
		absf(_span(m, 0) - 19.0) < 1e-3 and absf(_span(n, 0) - 14.0) < 1e-3
			and absf((float(dn.get("cheek_thickness_mm", 0.0)) - float(dm.get("cheek_thickness_mm", 0.0))) - 2.5) < 1e-6,
		"lengths %.3f / %.3f mm, cheeks %.3f / %.3f mm" % [_span(m, 0), _span(n, 0),
			dm.get("cheek_thickness_mm", 0.0), dn.get("cheek_thickness_mm", 0.0)])


static func _a_camera_wider_than_the_gap_is_refused(micro: Dictionary, full: Dictionary) -> Array:
	var refused := CameraMount.dimensions(full, {}, 25.0)
	var accepted := CameraMount.dimensions(micro, {}, 25.0)
	var widened := {}
	CameraMount.set_value(widened, CameraMount.PLATE_SPACING, 34.0)
	var accepted_wide := CameraMount.dimensions(full, widened, 25.0)
	var path := "user://exports/_fullsize_camera_mount.stl"
	# Cleared first: a broken refusal writes this file, and a leftover would fail every later run.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var written := StlWriter.write("camera_mount", CameraMount.triangles_mm(refused), path)
	return [
		TestResult.new("a 26 mm camera in the 24 mm guessed gap is refused, naming the part, the camera and both widths",
			not bool(refused["ok"]) and String(refused["reason"]).begins_with("camera_mount:")
				and String(refused["reason"]).contains("cam_fullsize_analog")
				and String(refused["reason"]).contains("26.0") and String(refused["reason"]).contains("24.0"),
			String(refused.get("reason", ""))),
		TestResult.new("its export writes nothing; the 19 mm camera is accepted, and so is the 26 mm one in a 34 mm gap",
			not bool(written["ok"]) and not FileAccess.file_exists(path) and bool(accepted["ok"])
				and bool(accepted_wide["ok"]),
			"write ok %s; micro ok %s; full in 34 mm ok %s" % [written["ok"], accepted["ok"], accepted_wide["ok"]]),
	]


## A at 30 mm, B untouched, A again — through the panel the builder sees, and an edit through the
## panel's own signal reaching the project file.
static func _the_gap_is_a_labelled_guess_per_drone() -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	# A new project fits no camera, and no camera means no mount row; each drone here fits the micro.
	var a := _with_camera("Drone A")
	CameraMount.set_value(a.printing, CameraMount.PLATE_SPACING, 30.0)
	var b := _with_camera("Drone B")
	shell.apply_project(a)
	var first := shell.lab.print_panel.row_note(CameraMount.PART_ID)
	shell.apply_project(b)
	var second := shell.lab.print_panel.row_note(CameraMount.PART_ID)
	shell.apply_project(a)
	var third := shell.lab.print_panel.row_note(CameraMount.PART_ID)
	results.append(TestResult.new(
		"the plate gap is per drone: A 30 mm, B the 24 mm guess (said so on the row), A 30 mm again",
		first.contains("gap 30.0 mm") and not first.contains("gap 30.0 mm (guess)")
			and second.contains("gap 24.0 mm (guess)") and third.contains("gap 30.0 mm"),
		"A \"%s\" | B \"%s\" | A \"%s\"" % [first, second, third]))

	shell.apply_project(_with_camera("Edited"))
	shell.lab.print_panel.camera_mount_edited.emit(CameraMount.PLATE_SPACING, 27.5)
	var note := shell.lab.print_panel.row_note(CameraMount.PART_ID)
	shell._sync_project()
	var reloaded := Project.from_dict(shell.container.project.to_dict()) if shell.container != null else null
	var stored := float(CameraMount.settings(reloaded.printing).get(CameraMount.PLATE_SPACING, 0.0)) \
		if reloaded != null else 0.0
	shell.free()
	results.append(TestResult.new(
		"a gap edited on the panel shows on the row, reaches the project and survives a round trip",
		note.contains("gap 27.5 mm") and is_equal_approx(stored, 27.5),
		"note \"%s\", reloaded %.2f" % [note, stored]))
	return results


static func _it_weighs_nothing_of_its_own() -> TestResult:
	var base := ReferenceBuild.build()
	var with_mount := ReferenceBuild.build()
	var printing := {}
	CameraMount.set_value(printing, CameraMount.PLATE_SPACING, 26.0)
	ArmGuard.set_value(printing, ArmGuard.WALL, 2.0)
	with_mount.set_printing(printing)
	return TestResult.new(
		"a camera mount adds no mass: the camera's 8 g is the camera as mounted, so the build is still 507.48 g",
		absf(base.mass_properties.total_mass_kg * 1000.0 - TestHarness.REFERENCE_AUW_G) < 0.01
			and absf(with_mount.mass_properties.total_mass_kg - base.mass_properties.total_mass_kg) < 1e-12
			and bool(CameraMount.dimensions(with_mount.components.get("camera", {}), printing, 25.0).get("ok", false)),
		"%.3f g with a camera mount set, %.3f g without" % [with_mount.mass_properties.total_mass_kg * 1000.0,
			base.mass_properties.total_mass_kg * 1000.0])


static func _no_camera_no_row() -> TestResult:
	var build := ReferenceBuild.build()
	var with_camera := _ids(PrintedParts.for_build(build))
	build.components.erase("camera")
	var without := _ids(PrintedParts.for_build(build))
	return TestResult.new(
		"a build with a camera lists the camera mount; with no camera it lists none, and no error",
		with_camera.has(CameraMount.PART_ID) and not without.has(CameraMount.PART_ID),
		"with %s, without %s" % [with_camera, without])


static func _with_camera(project_name: String) -> Project:
	var project := Project.create(project_name)
	project.parts["camera"] = "cam_micro_analog"
	return project


static func _ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row["id"]))
	return out


static func _span(triangles: Array, axis: int) -> float:
	var lo := INF
	var hi := -INF
	for t in triangles:
		for p in t:
			lo = minf(lo, p[axis])
			hi = maxf(hi, p[axis])
	return hi - lo if hi >= lo else 0.0
