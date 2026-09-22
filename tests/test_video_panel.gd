class_name TestVideoPanel
extends RefCounted
## Video's Camera panel — video slice V5 (plans/2026-09-13-video-room-design.md §4).
##
## The claim is that a builder who picked Video can see and set the uptilt without going to
## Airframe's Fit tab, and that doing so is the SAME edit the Fit tab makes. So every check here runs
## on a real GlassShell with Video selected, drives the Camera panel's own signal, and reads back what
## the tweaks, the Fit row and the drawn camera say.
##
## THESE CHECKS WRITE THE REAL `user://assembly_tweaks.json`: a tweak edit ends in `tweaks.save()`.
## The file is captured and removed before the shell is built — a developer's saved tilt would
## otherwise make "(as built)" false for a reason that is not the code — and put back afterwards,
## exactly as test_assembly_tweaks.gd does.

const EPS := 1e-4


static func run() -> Array:
	var results: Array = []
	# THE HOLD ON THE BUILDER'S OWN FILES. A net beneath the hand-rolled stash/restore below, taken
	# here and released just before `return results` because a section that aborts mid-way never
	# reaches its own restore — measured, and it is what left a 3500 m elevation and an invented
	# weather row on this developer's disk. `run()` is the only frame GDScript guarantees will
	# resume after an abort inside a section. See tests/real_files.gd.
	var held := RealFiles.hold([AssemblyTweaks.SAVE_PATH])
	var previous: Variant = _stash_saved_tweaks()

	var shell := GlassShell.new()
	shell.select_system_by_name("Video")
	var panel: CameraPanel = shell.lab.camera_panel
	var fit := shell.lab.assembly_panel

	var shown := _shown_titles(shell.lab.panels)
	results.append(TestResult.new(
		"selecting Video shows the Camera and Electronics panels, Camera in front, and no others",
		shown == ["Camera", "Electronics"], "showing %s" % [shown]))

	var range_deg := panel.slider_range()
	var limits: Dictionary = AssemblyTweaks.limits(shell.lab.current_build())[AssemblyTweaks.CAMERA_TILT]
	results.append(TestResult.new(
		"the Camera slider spans the tweak's own limits",
		is_equal_approx(range_deg.x, limits["min"]) and is_equal_approx(range_deg.y, limits["max"]),
		"slider %s, limits %s..%s" % [range_deg, limits["min"], limits["max"]]))

	# The small lie V1 left on the Fit panel, fixed beside it: the imbalance is grams and its row
	# used to print "mm" because an absent `unit` means millimetres.
	var imbalance := fit.tweak_row_text(AssemblyTweaks.PROP_IMBALANCE)
	results.append(TestResult.new(
		"the Fit panel's prop-imbalance row reads grams, not millimetres",
		imbalance.contains(" g") and not imbalance.contains("mm"), "reads \"%s\"" % imbalance))

	var before_panel := panel.tilt_row_text()
	var before_fit := fit.tweak_row_text(AssemblyTweaks.CAMERA_TILT)
	results.append(TestResult.new(
		"untouched, the Camera row and the Fit row read the same string, and it says (as built)",
		before_panel == before_fit and before_panel.contains("25.0") and before_panel.contains("(as built)"),
		"camera \"%s\", fit \"%s\"" % [before_panel, before_fit]))

	# The slider under the mouse emits this; Range does not emit for a value set from code.
	panel.tilt_edited.emit(40.0)

	var stored := shell.lab.tweaks.value_mm(AssemblyTweaks.CAMERA_TILT, shell.lab.current_build())
	var after_panel := panel.tilt_row_text()
	var after_fit := fit.tweak_row_text(AssemblyTweaks.CAMERA_TILT)
	results.append(TestResult.new(
		"moving the Camera slider to 40 stores 40 through the Fit panel's path, and both rows say so",
		absf(stored - 40.0) < EPS and after_panel == after_fit and after_panel.contains("40.0")
			and not after_panel.contains("(as built)"),
		"stored %.2f, camera \"%s\", fit \"%s\"" % [stored, after_panel, after_fit]))

	var boresight := shell.lab.airframe.camera_boresight()
	results.append(TestResult.new(
		"and the drawn camera looks up by the new tilt",
		absf(boresight.y - sin(deg_to_rad(40.0))) < EPS,
		"boresight %s, sin 40 = %.4f" % [boresight, sin(deg_to_rad(40.0))]))

	shell.free()
	_restore_saved_tweaks(previous)

	results.append(_the_panel_shows_the_warning_the_tilt_causes())
	held.restore()
	results.append(TestResult.new(
		"the builder's own files are back the way they were found, whatever the sections did",
		held.intact(), held.report()))
	return results


## The VideoPlausibility warning is on the panel the slider is on. A nano camera behind 28 mm
## standoffs fits level and not at 25° — test_video_warnings.gd's fixture — and at 0° the same
## panel is silent, so the text is there because of the tilt and not because of the build.
static func _the_panel_shows_the_warning_the_tilt_causes() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var texts := {}
	for tilt in [0.0, 25.0]:
		var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, Build.DEFAULT_ESC_ID,
			Build.DEFAULT_FC_ID, {"camera": "cam_nano_analog"})
		var tweaks := AssemblyTweaks.new()
		tweaks.set_mm(AssemblyTweaks.PLATE_GAP, 28.0)
		tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, tilt)
		build.set_assembly(tweaks.resolved_m(build))
		var panel := CameraPanel.new()
		panel.render(build, tweaks)
		texts[tilt] = panel.warning_text()
		panel.free()
	return TestResult.new(
		"the Camera panel says the tipped camera strikes the top plate at 25°, and nothing at 0°",
		str(texts[25.0]).contains("top plate") and not str(texts[0.0]).contains("top plate"),
		"0°: \"%s\" | 25°: \"%s\"" % [texts[0.0], texts[25.0]])


static func _shown_titles(tabs: TabContainer) -> Array:
	var out: Array = []
	for i in tabs.get_tab_count():
		if not tabs.is_tab_hidden(i):
			out.append(tabs.get_tab_title(i))
	return out


## Null when there was no file, so the restore can put back ABSENCE rather than an empty file.
static func _stash_saved_tweaks() -> Variant:
	var previous = null
	if FileAccess.file_exists(AssemblyTweaks.SAVE_PATH):
		previous = FileAccess.get_file_as_string(AssemblyTweaks.SAVE_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AssemblyTweaks.SAVE_PATH))
	return previous


static func _restore_saved_tweaks(previous: Variant) -> void:
	if FileAccess.file_exists(AssemblyTweaks.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AssemblyTweaks.SAVE_PATH))
	if previous != null:
		var handle := FileAccess.open(AssemblyTweaks.SAVE_PATH, FileAccess.WRITE)
		handle.store_string(String(previous))
		handle.close()
