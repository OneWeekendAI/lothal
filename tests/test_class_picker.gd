class_name TestClassPicker
extends RefCounted
## The "Choose your drone class" screen: New lands on it, the arrows walk the classes in size
## order, choosing writes the class and its parts into the project, the Design Space opens on that
## class's drone, and the models are drawn at one true scale.
##
## ## The checks that could have passed while proving nothing
##
## - **"New shows the picker"** would pass against a picker built at boot and never shown. So the
##   shell is checked to have NO picker before New and one after, through both New entries.
## - **"Choosing writes the class"** would pass against a project that already held those parts:
##   the starting project IS the 5" reference. So the choice is a 7", every check compares against
##   the 7" ids, and the file is reopened from disk rather than read back from memory.
## - **"Sizes are monotonic"** would pass non-strictly against a picker that scales every model to
##   fit its frame (all equal). So the order is STRICT, every model's own scale must be one, and the
##   camera's metres-per-pixel must be the same whichever class is on show.
##   (Superseded 2026-10-31: every class is now FRAMED LARGE, and size lives in the size row.)
##
## One result per class and per adjacent pair, so a break says how many cases it took.

## Size order, smallest first. Written out rather than read from DroneClass, so a reordered table
## is a failure here rather than a new truth.
const SIZE_ORDER := ["tiny_whoop", "toothpick", "sub250_35", "cinewhoop_3", "four_inch", "five_inch",
	"six_inch", "seven_lr", "cinelifter", "x_class"]


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_test_new_lands_on_the_picker())
	results.append_array(_test_arrows_walk_in_size_order(catalog))
	results.append_array(_test_choosing_writes_the_project(catalog))
	results.append_array(_test_design_space_default_matches_the_class(catalog))
	results.append_array(_test_sizes_are_true_and_monotonic(catalog))
	results.append_array(_test_packs_match_the_catalogue(catalog))
	results.append_array(_test_seed_label_and_model_agree(catalog))
	return results


## The shipped GLB's motor meshes (top-level nodes named motor_*), counted.
static func model_motor_count(id: String) -> int:
	var scene := load("res://assets/models/classes/%s.glb" % id) as PackedScene
	if scene == null:
		return 0
	var root := scene.instantiate() as Node3D
	var re := RegEx.create_from_string("^motor_(FL|FR|BL|BR)(_lo)?$")
	var names := {}
	for child in root.find_children("motor_*", "", true, false):
		if re.search(String(child.name)) != null:
			names[String(child.name)] = true
	root.free()
	return names.size()


## Classes whose seed pack is knowingly outside the typical cell range, and why.
const KNOWN_CELL_GAPS := {"x_class": "the catalog has no 8S+ pack; the seed is the 6S 4000 Li-ion placeholder"}


## Low and high cell counts of a typical-battery string like "6–8S" or "1S".
static func typical_cells(text: String) -> Vector2i:
	var t := text.replace("S", "").replace("–", "-")
	var parts := t.split("-")
	return Vector2i(int(parts[0]), int(parts[parts.size() - 1]))


## 2026-10-31: the Cinelifter seeded a 6S Li-ion while its model printed "6S 10C" (read as 5S) on a
## pack its typical line called 6–8S LiPo, weighed 1233 g against a typical 2–4 kg, and flew four
## motors on a coaxial X8 model. Every class: the model's pack names the SAME catalogue part the class
## seeds and the seed's cells sit inside the class's typical range; every model's motor meshes number
## what Build flies. Cinelifter: a 6S LiPo, eight motors, AUW inside the typical 2–4 kg.
static func _test_seed_label_and_model_agree(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var script := FileAccess.get_file_as_string("res://tools/blender/build_drone.py")
	for id in SIZE_ORDER:
		var seed_id := String(DroneClass.parts_for(id).get("battery", ""))
		var cfg_start := script.find('    "%s": dict(' % id)
		var cfg := script.substr(cfg_start, script.find("zmin=", cfg_start) - cfg_start)
		results.append(TestResult.new("%s: the model's pack is the seed's own catalogue part (%s)" % [id, seed_id],
			cfg.contains('seed="%s"' % seed_id), cfg.get_slice("seed=", 1).get_slice(",", 0)))
		var cells := int(catalog.get_part(seed_id)["specs"]["cells"])
		var band := typical_cells(String(DroneClass.by_id(id)["battery"]))
		var inside := cells >= band.x and cells <= band.y
		if KNOWN_CELL_GAPS.has(id):
			# A known, labelled gap: the check asserts it is STILL a gap, so closing it fails here
			# and the entry has to be deleted rather than silently outliving the fix.
			results.append(TestResult.new("%s: the seed's %dS is still outside the typical %s (known gap: %s)" % [
				id, cells, DroneClass.by_id(id)["battery"], KNOWN_CELL_GAPS[id]], not inside, ""))
		else:
			results.append(TestResult.new("%s: the seed's %dS sits inside the typical %s" % [id, cells, DroneClass.by_id(id)["battery"]],
				inside, ""))
		var b := DesignSession.default_for_class(id).build(catalog)
		var drawn := model_motor_count(id)
		results.append(TestResult.new("%s: the model draws as many motors as Build flies (%d)" % [id, b.motor_count()],
			drawn == b.motor_count(), "model %d, build %d" % [drawn, b.motor_count()]))
	var lifter := DesignSession.default_for_class("cinelifter").build(catalog)
	var sp: Dictionary = lifter.battery["specs"]
	results.append(TestResult.new("the Cinelifter seeds a 6S LiPo (not a Li-ion)",
		int(sp["cells"]) == 6 and String(sp["chemistry"]) == "LiPo", "%s" % lifter.battery["name"]))
	results.append(TestResult.new("the Cinelifter flies eight motors (coaxial X8)",
		lifter.motor_count() == 8, "%d" % lifter.motor_count()))
	results.append(TestResult.new("the Cinelifter weighs inside its typical 2–4 kg",
		lifter.all_up_weight_g() >= 2000.0 and lifter.all_up_weight_g() <= 4000.0,
		"%.0f g" % lifter.all_up_weight_g()))
	return results


## The shipped GLB's pack body (surfaces wearing the printed wrap or the end-cap shrink; leads, plug,
## strap and pad are not the cell) as extents in mm: x across, y up, z front-to-back.
static func pack_extents_mm(id: String) -> Vector3:
	var scene := load("res://assets/models/classes/%s.glb" % id) as PackedScene
	if scene == null:
		return Vector3.ZERO
	var root := scene.instantiate() as Node3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not String(mi.name).begins_with("battery"):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for surf in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(surf)
			var mname := mat.resource_name if mat != null else ""
			if not (mname.begins_with("lipo_wrap") or mname.begins_with("lipo_end_shrink")):
				continue
			for v in (mi.mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var w := xf * v
				lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
				hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
	root.free()
	if lo.x == INF:
		return Vector3.ZERO
	return (hi - lo) * 1000.0


static func _cleanup(shell: GlassShell) -> void:
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()


static func _test_new_lands_on_the_picker() -> Array:
	var results: Array = []
	for entry in ["chip", "projects screen"]:
		var shell := GlassShell.new()
		var before := shell.class_picker
		var path_before := shell.container.path
		if entry == "chip":
			shell._on_project_action("new")
		else:
			shell.projects_screen.new_requested.emit()
		var picker := shell.class_picker
		results.append(TestResult.new(
			"New from the %s lands on the class picker, showing 5\" first" % entry,
			before == null and picker != null and picker.current_id == DroneClass.DEFAULT_ID
				and picker.get_parent() is CanvasLayer,
			"before=%s picker=%s showing=%s" % [before, picker,
				picker.current_id if picker != null else "-"]))
		results.append(TestResult.new(
			"and the new drone is already on disk under it (%s)" % entry,
			shell.container.path != "" and shell.container.path != path_before
				and FileAccess.file_exists(shell.container.path)
				and shell.container.project.drone_class == "",
			"path=%s class='%s'" % [shell.container.path, shell.container.project.drone_class]))
		_cleanup(shell)
	return results


static func _test_arrows_walk_in_size_order(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var picker := ClassPicker.new(catalog)
	results.append(TestResult.new("the carousel opens on 5\"",
		picker.current_id == "five_inch", picker.current_id))

	var start := SIZE_ORDER.find("five_inch")
	var walked: Array = []
	for i in SIZE_ORDER.size():                       # bounded: a wrapping step must fail, not hang
		if not picker.step(1):
			break
		walked.append(picker.current_id)
	results.append(TestResult.new("→ walks up through every bigger class in order, then stops",
		walked == SIZE_ORDER.slice(start + 1) and picker.current_id == "x_class",
		str(walked)))

	picker.show_class("five_inch")
	walked = []
	for i in SIZE_ORDER.size():
		if not picker.step(-1):
			break
		walked.append(picker.current_id)
	var down := SIZE_ORDER.slice(0, start)
	down.reverse()
	results.append(TestResult.new("← walks down through every smaller class in order, then stops",
		walked == down and picker.current_id == "tiny_whoop", str(walked)))

	# The keyboard, through the input handler the window delivers to.
	picker.show_class("five_inch")
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	picker._unhandled_input(right)
	var after_right := picker.current_id
	var left := InputEventAction.new()
	left.action = &"ui_left"
	left.pressed = true
	picker._unhandled_input(left)
	picker._unhandled_input(left)
	results.append(TestResult.new("the → and ← keys step the same way",
		after_right == "six_inch" and picker.current_id == "four_inch",
		"after → %s, after ←← %s" % [after_right, picker.current_id]))

	var chosen: Array = []
	picker.class_chosen.connect(func(id: String) -> void: chosen.append(id))
	var all_choosable := true
	for id in SIZE_ORDER:
		picker.show_class(id)
		all_choosable = all_choosable and not picker.choose_button.disabled and picker.choose()
	results.append(TestResult.new("all ten classes are selectable, none is 'coming soon'",
		all_choosable and chosen == SIZE_ORDER, str(chosen)))
	picker.free()
	return results


static func _test_choosing_writes_the_project(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var shell := GlassShell.new(catalog)
	shell._on_project_action("new")
	var picker := shell.class_picker
	for i in SIZE_ORDER.size():
		if picker.current_id == "seven_lr" or not picker.step(1):
			break
	picker.choose()
	var expected := DroneClass.parts_for("seven_lr")

	var project := shell.container.project
	results.append(TestResult.new("choosing 7\" writes the class into the project",
		project.drone_class == "seven_lr", "class='%s'" % project.drone_class))
	var wrong: Array = []
	for category in ProjectSchema.all_categories():
		if String(project.parts.get(category, "")) != String(expected[category]):
			wrong.append("%s=%s" % [category, project.parts.get(category, "")])
	results.append(TestResult.new("and the 7\" parts, every category",
		wrong.is_empty(), str(wrong)))

	var reopened := ProjectContainer.open(shell.container.path)
	results.append(TestResult.new("and saves both: the file reopens as a 7\"",
		reopened != null and reopened.project.drone_class == "seven_lr"
			and String(reopened.project.parts["frame"]) == String(expected["frame"]),
		"reopened=%s" % (reopened.project.drone_class if reopened != null else "null")))

	var flown := shell.lab.current_build()
	results.append(TestResult.new("the drone on the rails is the 7\" one",
		String(flown.frame["part_id"]) == String(expected["frame"])
			and String(flown.propeller["part_id"]) == String(expected["propeller"]),
		"frame=%s prop=%s" % [flown.frame["part_id"], flown.propeller["part_id"]]))
	results.append(TestResult.new("and the picker has closed", shell.class_picker == null,
		str(shell.class_picker)))
	_cleanup(shell)
	return results


static func _test_design_space_default_matches_the_class(catalog: PartsCatalog) -> Array:
	var results: Array = []
	for id in SIZE_ORDER:
		var session := DesignSession.default_for_class(id)
		if not DroneClass.is_available(id):
			results.append(TestResult.new("%s is coming soon and has no default drone" % id,
				session == null and DroneClass.parts_for(id).is_empty(), str(session)))
			continue
		var build := session.build(catalog) if session != null else null
		var expected := DroneClass.parts_for(id)
		var ok: bool = build != null and session.drone_class == id
		var got := ""
		if build != null:
			got = "%s %s %s %s guard=%s" % [build.frame["part_id"], build.motor["part_id"],
				build.propeller["part_id"], build.battery["part_id"],
				build.guard.get("part_id", "")]
			ok = ok and String(build.frame["part_id"]) == String(expected["frame"]) \
				and String(build.motor["part_id"]) == String(expected["motor"]) \
				and String(build.propeller["part_id"]) == String(expected["propeller"]) \
				and String(build.battery["part_id"]) == String(expected["battery"]) \
				and String(build.guard.get("part_id", "")) == String(expected["guard"])
			for warning in build.warnings():
				if warning.severity == BuildWarning.Severity.IMPOSSIBLE:
					ok = false
					got += " IMPOSSIBLE: %s" % warning.message
		results.append(TestResult.new(
			"the Design Space opens a %s project on that class's drone, and it is buildable" % id,
			ok, got))

	var five := DesignSession.default_for_class("five_inch").build(catalog)
	results.append(TestResult.new("the 5\" default is the reference build (507.5 g)",
		absf(five.all_up_weight_g() - ReferenceBuild.build().all_up_weight_g()) < 1e-6
			and absf(five.all_up_weight_g() - 507.5) < 0.1,
		"%.2f g" % five.all_up_weight_g()))
	var sub := DesignSession.default_for_class("sub250_35").build(catalog)
	results.append(TestResult.new("the Sub-250 default weighs under 250 g",
		sub.all_up_weight_g() < 250.0, "%.1f g" % sub.all_up_weight_g()))

	# The session a CHOSEN project opens into, not only the class default.
	var project := ProjectLibrary.starting_project("Session check")
	DroneClass.apply_to(project, "six_inch")
	var chosen := DesignSession.from_project(project).build(catalog)
	results.append(TestResult.new("a project switched to 6\" opens the Design Space on the 6\"",
		chosen != null and String(chosen.frame["part_id"]) == "frame_6in_long_range"
			and absf(chosen.all_up_weight_g()
				- DesignSession.default_for_class("six_inch").build(catalog).all_up_weight_g()) < 1e-6,
		"frame=%s" % (chosen.frame["part_id"] if chosen != null else "null")))
	return results


static func _test_sizes_are_true_and_monotonic(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var picker := ClassPicker.new(catalog)
	picker.load_all()
	var missing: Array = []
	for id in SIZE_ORDER:
		if not picker.models.has(id) or picker.radius_m(id) <= 0.0:
			missing.append(id)
	results.append(TestResult.new("every class draws its Blender model (assets/models/classes/<id>.glb)",
		missing.is_empty(), str(missing)))

	var unscaled: Array = []
	for id in SIZE_ORDER:
		var model: Node3D = picker.models[id]
		if not model.scale.is_equal_approx(Vector3.ONE) or model.get_parent() != picker.slot:
			unscaled.append(id)
	results.append(TestResult.new("no model is scaled to fit: all hang off one slot at scale 1",
		unscaled.is_empty() and picker.slot.scale.is_equal_approx(Vector3.ONE), str(unscaled)))

	for i in range(1, SIZE_ORDER.size()):
		var r_small := picker.radius_m(SIZE_ORDER[i - 1])
		var r_big := picker.radius_m(SIZE_ORDER[i])
		results.append(TestResult.new(
			"%s is drawn bigger than %s" % [SIZE_ORDER[i], SIZE_ORDER[i - 1]],
			r_big > r_small + 0.002,
			"%.1f mm vs %.1f mm" % [r_big * 1000.0, r_small * 1000.0]))

	# Every class is framed large: its turntable circle fills 50-70% of the viewport width, at
	# several window shapes. One result per class and shape so a break says how many cases it took.
	for vp in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1100, 800)]:
		for id in SIZE_ORDER:
			picker.show_class(id)
			var frac := picker.fitted_width_fraction(vp)
			results.append(TestResult.new(
				"%s is framed large at %dx%d (50-70%% of the width)" % [id, int(vp.x), int(vp.y)],
				frac >= 0.50 and frac <= 0.70, "%.1f%%" % (frac * 100.0)))

	# Size is carried by the size row: true relative wheelbase, the current class lit.
	picker.show_class("five_inch")
	var row := picker.size_row()
	var lit: Array = []
	var row_ok := row.size() == SIZE_ORDER.size()
	for i in row.size():
		if bool(row[i]["current"]):
			lit.append(row[i]["id"])
		if i > 0 and not (float(row[i]["diameter_px"]) > float(row[i - 1]["diameter_px"])):
			row_ok = false
	results.append(TestResult.new("the size row has ten discs, strictly growing, one lit (the shown class)",
		row_ok and lit == ["five_inch"], "%s" % [lit]))
	var ratio_ok := true
	for entry in row:
		var wb := float(DroneClass.by_id(String(entry["id"]))["wheelbase_mm"])
		if absf(float(entry["diameter_px"]) / (wb / 700.0) - ClassPicker.SIZE_ROW_MAX_PX) > 0.01:
			ratio_ok = false
	results.append(TestResult.new("the size row is at true relative wheelbase (X-Class 700 mm is the widest)",
		ratio_ok, ""))

	# The picker's default build and the model agree about the pack: the label baked into each
	# GLB is generated from tools/blender/build_drone.py, which must name the seed battery's cells and mAh.
	var script := FileAccess.get_file_as_string("res://tools/blender/build_drone.py")
	for id in SIZE_ORDER:
		var seed_battery := catalog.get_part(String(DroneClass.parts_for(id).get("battery", "")))
		var cells := int(seed_battery["specs"]["cells"])
		var mah := int(seed_battery["specs"]["mah"])
		var cfg_start := script.find('    "%s": dict(' % id)
		var cfg_end := script.find("zmin=", cfg_start)
		var cfg := script.substr(cfg_start, cfg_end - cfg_start)
		var liion := String(seed_battery["specs"].get("chemistry", "")) == "Li-ion"
		var label_mah := "LI-ION" if liion else str(mah)
		results.append(TestResult.new(
			"%s: the model's pack label matches its seed battery (%dS %s)" % [id, cells, label_mah],
			cfg.contains('cells="%dS", mah="%s"' % [cells, label_mah]), seed_battery["name"]))

	# Render-quality settings are part of the contract.
	results.append(TestResult.new("3D renders with 4x MSAA and screen-space AA",
		picker.viewport.msaa_3d == Viewport.MSAA_4X
			and picker.viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED,
		"msaa=%d ssaa=%d" % [picker.viewport.msaa_3d, picker.viewport.screen_space_aa]))
	picker.free()

	# Defaults the class screen promises.
	var whoop := DesignSession.default_for_class("tiny_whoop").build(catalog)
	results.append(TestResult.new("the Tiny Whoop default no longer seeds at 71 g",
		whoop.all_up_weight_g() < 60.0, "%.1f g" % whoop.all_up_weight_g()))
	var lifter := DesignSession.default_for_class("cinelifter").build(catalog)
	var prop_d := float(lifter.propeller["specs"]["diameter_inches"]) if lifter.propeller.has("specs") else 0.0
	results.append(TestResult.new("the Cinelifter flies 8-10\" props",
		prop_d >= 8.0 and prop_d <= 10.0, "%.1f in" % prop_d))
	return results


## Every class's pack in the shipped GLB is the seed battery's real size (within 2 mm) and lies flat:
## height under width, long axis front-to-back. One result per class and per property.
static func _test_packs_match_the_catalogue(catalog: PartsCatalog) -> Array:
	var results: Array = []
	for id in SIZE_ORDER:
		var seed_battery := catalog.get_part(String(DroneClass.parts_for(id).get("battery", "")))
		var sp: Dictionary = seed_battery["specs"]
		var want_l := float(sp["length_mm"])
		var want_hi := maxf(float(sp["width_mm"]), float(sp["height_mm"]))
		var want_lo := minf(float(sp["width_mm"]), float(sp["height_mm"]))
		var e := pack_extents_mm(id)
		var detail := "pack across %.1f up %.1f long %.1f mm; catalogue %s %.1f x %.1f x %.1f" % [
			e.x, e.y, e.z, seed_battery["part_id"], want_hi, want_lo, want_l]
		results.append(TestResult.new("%s: pack length, width and height are within 2 mm of the seed battery" % id,
			e != Vector3.ZERO and absf(e.z - want_l) <= 2.0 and absf(e.x - want_hi) <= 2.0
				and absf(e.y - want_lo) <= 2.0, detail))
		results.append(TestResult.new("%s: the pack lies flat, long axis front-to-back (height < width < length)" % id,
			e != Vector3.ZERO and e.y < e.x and e.x <= e.z, detail))
	return results
