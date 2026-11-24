class_name TestSaveReopen
extends RefCounted
## "Save, quit, reopen through the real path gives identical figures and document." The path is the
## app's own: a DesignApp makes a project (new -> class picker -> choose), the builder edits in the
## Design Space (a part swap, a frame edit, an assembly tweak), the autosave tick writes it, the app is
## freed, and a FRESH DesignApp in the tree boots from the recent-projects list in app_settings.json
## (the resume path `_ready` takes) and opens the Design Space on what the file holds. ProjectLibrary.root
## and the held settings file keep it off the builder's own drones.
##
## MUTATION: dropping `tweaks` (or the frame document) from what the app writes at save fails the
## matching check, and the readout check with it.

const SCRATCH := "user://test_save_reopen"
const CLASS_ID := "five_inch"
const KEYS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]


static func _figures(session: DesignSession, catalog: PartsCatalog) -> String:
	var b := session.build(catalog)
	if b == null:
		return "no build"
	var r := DesignSession.readouts_of(b)
	var parts: Array = []
	for k in KEYS:
		parts.append(var_to_str(r[k]))
	parts.append(var_to_str(float(b.frame["mass_g"])))
	return "|".join(parts)


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	var held := RealFiles.hold([AppSettings.SAVE_PATH, AssemblyTweaks.SAVE_PATH])
	var saved_root := ProjectLibrary.root
	ProjectLibrary.root = SCRATCH
	_clean()
	ProjectLibrary.ensure_dir()
	var catalog := PartsCatalog.load_default()

	# --- session 1: make, edit, autosave, quit
	var shell := DesignApp.new()
	tree.root.add_child(shell)
	await tree.process_frame
	shell._on_project_action("new")
	shell.class_picker.show_class(CLASS_ID)
	shell.class_picker.choose()
	var s1 := shell.design_space.session
	var swapped := false
	for opt in catalog.list_category("motor"):
		var mid := String(opt["part_id"])
		if mid != String(s1.selection["motor"]) and s1.swap(catalog, "motor", mid)["ok"]:
			swapped = true
			break
	var thick: Dictionary = s1.set_plate_thickness(s1.plate_of_mesh("frame_plate_top"), 2.5)
	var tw := AssemblyTweaks.from_dict(s1.tweaks.to_dict())
	tw.set_mm(AssemblyTweaks.CAMERA_TILT, 40.0)
	s1.set_tweaks(tw)
	out.append(TestResult.new("the edits took (swap, frame, tweak)",
		swapped and thick.get("ok", false) and s1.tweaks.has_override(AssemblyTweaks.CAMERA_TILT), str(thick)))
	var path: String = shell.container.path
	var want_class := s1.drone_class
	var want_parts: Dictionary = s1.selection.duplicate(true)
	var want_doc := JSON.stringify(s1.frame_document().to_dictionary())
	var want_tweaks := JSON.stringify(s1.tweaks.to_dict())
	var want_figs := _figures(s1, catalog)
	var seed_figs := _figures(DesignSession.default_for_class(CLASS_ID), catalog)
	out.append(TestResult.new("the edited design's figures differ from the class seed", want_figs != seed_figs, want_figs))
	shell._on_autosave_tick()  # the real timer handler (and the "projects" action's save)
	shell.get_parent().remove_child(shell)
	shell.free()
	out.append(TestResult.new("the autosave wrote the project file", FileAccess.file_exists(path), path))

	# --- session 2: a fresh app resumes from disk
	var boot := DesignApp.new()
	tree.root.add_child(boot)
	await tree.process_frame
	out.append(TestResult.new("the fresh app resumed the saved project on its own",
		boot.container != null and boot.container.path == path, str(boot.container.path if boot.container != null else "none")))
	var ds := boot.show_design_space()
	var s2: DesignSession = ds.session if ds != null else DesignSession.default_for_class(CLASS_ID)
	out.append(TestResult.new("drone class identical", s2.drone_class == want_class, s2.drone_class))
	out.append(TestResult.new("parts identical", s2.selection == want_parts, str(s2.selection)))
	out.append(TestResult.new("frame document identical",
		s2.frame_document() != null and JSON.stringify(s2.frame_document().to_dictionary()) == want_doc, ""))
	out.append(TestResult.new("tweaks identical", JSON.stringify(s2.tweaks.to_dict()) == want_tweaks, JSON.stringify(s2.tweaks.to_dict())))
	var got_figs := _figures(s2, catalog)
	out.append(TestResult.new("readout figures bit-identical", got_figs == want_figs, got_figs + " vs " + want_figs))
	boot.get_parent().remove_child(boot)
	boot.free()

	held.restore()
	_clean()
	ProjectLibrary.root = saved_root
	return out


static func _clean() -> void:
	for sub in ["", "/trash"]:
		var dir := ProjectSettings.globalize_path(SCRATCH + sub)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH + "/trash"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
