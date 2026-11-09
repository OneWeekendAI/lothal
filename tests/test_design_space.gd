class_name TestDesignSpace
extends RefCounted
## The Design Space stage (PLAN Section 1): Choose lands on it showing the chosen class's model; the
## side panel reads the session's Build; the free camera keeps its limits and Home restores it.
##
## ## The checks that could have passed while proving nothing
##
## - "Choose shows the chosen class's model" is run through the shell's real path (New, picker,
##   Choose) for TWO classes, so a stage that always loads the 5" fails one of them.
## - "Readouts equal the engine" compares the panel's TEXT with the text of values taken from a Build
##   made independently by `Build.from_ids`, on a battery that is not the reference one, so a panel
##   showing the 5" defaults or a cached first build fails.
## - Limits are asserted on the goals after hundreds of inputs, not after one.
## - Home is asserted after the eased motion has been stepped to rest, not on the goal alone.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_test_choose_lands_on_the_model())
	results.append_array(_test_readouts_equal_the_engine(catalog))
	results.append_array(_test_build_change_updates_readouts(catalog))
	results.append_array(_test_gauge_fractions())
	results.append_array(_test_ring_shape())
	results.append_array(_test_camera_limits())
	results.append_array(_test_home_restores())
	results.append_array(_test_back_to_picker())
	results.append_array(_test_panel_fades())
	results.append_array(_test_charge_chip(catalog))
	results.append_array(_test_hidden_does_no_3d_work())
	results.append_array(_test_redraws_only_on_change())
	results.append_array(_test_fly_it_and_back())
	return results


static func _cleanup(shell: GlassShell) -> void:
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()


static func _test_choose_lands_on_the_model() -> Array:
	var results: Array = []
	for id in ["five_inch", "tiny_whoop"]:
		var shell := GlassShell.new()
		shell._on_project_action("new")
		var before := shell.design_space
		shell.class_picker.show_class(id)
		shell.class_picker.choose()
		var ds := shell.design_space
		var meshes := ds.mesh_boxes().size() if ds != null else 0
		results.append(TestResult.new("Choose %s lands on the Design Space" % id,
			before == null and ds != null and shell.class_picker == null and ds.session.drone_class == id,
			"before=%s ds=%s" % [before, ds]))
		results.append(TestResult.new("and it draws assets/models/classes/%s.glb" % id,
			ds != null and ds.model_path() == "res://assets/models/classes/%s.glb" % id and meshes > 10,
			"%s meshes=%d" % [ds.model_path() if ds != null else "-", meshes]))
		_cleanup(shell)
	return results


static func _expected_text(build: Build) -> Dictionary:
	var r := {
		"auw_g": build.all_up_weight_g(), "thrust_to_weight": build.thrust_to_weight(),
		"hover_throttle": build.hover_throttle(), "flight_time_min": build.flight_time_min(),
		"top_speed_kmh": build.top_speed_kmh()}
	return {
		"auw_g": "%.1f g" % r["auw_g"], "thrust_to_weight": "%.2f : 1" % r["thrust_to_weight"],
		"hover_throttle": "%.1f %%" % (r["hover_throttle"] * 100.0),
		"flight_time_min": "%.1f min" % r["flight_time_min"],
		"top_speed_kmh": "%.0f km/h" % r["top_speed_kmh"]}


static func _panel_matches(ds: DesignSpace, build: Build) -> String:
	var want := _expected_text(build)
	var bad := ""
	for key in want:
		var got := (ds.value_labels[key] as Label).text
		if got != want[key]:
			bad += " %s '%s' != '%s';" % [key, got, want[key]]
	return bad


static func _test_readouts_equal_the_engine(catalog: PartsCatalog) -> Array:
	var results: Array = []
	for id in ["five_inch", "seven_lr"]:
		var session := DesignSession.default_for_class(id)
		var ds := DesignSpace.new(session, catalog)
		var parts := DroneClass.parts_for(id)
		var direct := Build.from_ids(catalog, parts["frame"], parts["motor"], parts["propeller"], parts["battery"],
			parts["esc"], parts["flight_controller"], {}, null, parts.get("guard", ""))
		var bad := _panel_matches(ds, session.build(catalog))
		results.append(TestResult.new("%s: the panel shows the session Build's five figures" % id, bad == "", bad))
		var r := session.readouts(catalog)
		results.append(TestResult.new("%s: session readouts are the Build's own methods, unrounded" % id,
			absf(float(r["auw_g"]) - session.build(catalog).all_up_weight_g()) == 0.0
				and absf(float(r["hover_throttle"]) - session.build(catalog).hover_throttle()) == 0.0
				and direct != null and (id != "five_inch" or absf(float(r["auw_g"]) - direct.all_up_weight_g()) < 0.05
				and absf(float(r["thrust_to_weight"]) - direct.thrust_to_weight()) < 0.005), str(r)))
		ds.free()
	var ref := DesignSession.default_for_class("five_inch")
	var rr := ref.readouts(catalog)
	results.append(TestResult.new("the 5\" seed reads the oracle: 507.5 g, 8.13:1, 33.0 %",
		absf(float(rr["auw_g"]) - 507.5) < 0.05 and absf(float(rr["thrust_to_weight"]) - 8.131) < 0.005
			and absf(float(rr["hover_throttle"]) * 100.0 - 33.03) < 0.05, str(rr)))
	return results


static func _test_build_change_updates_readouts(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var session := DesignSession.default_for_class("five_inch")
	var ds := DesignSpace.new(session, catalog)
	var before: Dictionary = {}
	for key in ds.value_labels:
		before[key] = (ds.value_labels[key] as Label).text
	var fill_before: Dictionary = {}
	for key in ds.gauges:
		fill_before[key] = (ds.gauges[key] as ReadoutGauge).fill
	var changed := ds.set_part("battery", "battery_6s_1300")
	var build := session.build(catalog)
	var bad := _panel_matches(ds, build)
	results.append(TestResult.new("changing the battery in data moves the panel to the new Build's figures",
		changed and bad == "" and build.battery["part_id"] == "battery_6s_1300", bad))
	var moved := 0
	for key in ds.value_labels:
		if (ds.value_labels[key] as Label).text != before[key]:
			moved += 1
	results.append(TestResult.new("and every one of the five figures moved (4S 1500 -> 6S 1300)",
		moved == 5, "moved=%d" % moved))
	var gauges_moved := 0
	var gauges_right := 0
	for key in ds.gauges:
		var g := ds.gauges[key] as ReadoutGauge
		if absf(g.fill - float(fill_before[key])) > 1e-6:
			gauges_moved += 1
		if absf(g.fill - ReadoutGauge.fraction(key, session.readouts(catalog)[key])) < 1e-9:
			gauges_right += 1
	results.append(TestResult.new("and every one of the five gauges moved, to the fraction of the new figure",
		gauges_moved == 5 and gauges_right == 5, "moved=%d right=%d" % [gauges_moved, gauges_right]))
	results.append(TestResult.new("an unknown category changes nothing",
		not ds.set_part("flux_capacitor", "x") and _panel_matches(ds, build) == "", ""))
	ds.free()
	return results


static func _test_gauge_fractions() -> Array:
	var results: Array = []
	for key in ReadoutGauge.RANGES:
		var lo := float(ReadoutGauge.RANGES[key][0])
		var hi := float(ReadoutGauge.RANGES[key][1])
		var mid := ReadoutGauge.fraction(key, (lo + hi) * 0.5)
		var q := ReadoutGauge.fraction(key, lo + (hi - lo) * 0.25)
		results.append(TestResult.new("%s gauge: low end 0, high end 1, midpoint 0.5, quarter 0.25" % key,
			ReadoutGauge.fraction(key, lo) == 0.0 and ReadoutGauge.fraction(key, hi) == 1.0
				and absf(mid - 0.5) < 1e-9 and absf(q - 0.25) < 1e-9, "mid=%f q=%f" % [mid, q]))
		results.append(TestResult.new("%s gauge: clamped outside the range, empty when absent" % key,
			ReadoutGauge.fraction(key, hi * 10.0 + 5.0) == 1.0 and ReadoutGauge.fraction(key, lo - 99.0) == 0.0
				and ReadoutGauge.fraction(key, null) == 0.0 and ReadoutGauge.fraction(key, NAN) == 0.0, ""))
	results.append(TestResult.new("an unknown readout key has an empty gauge",
		ReadoutGauge.fraction("flux", 5.0) == 0.0, ""))
	results.append(TestResult.new("the 5\" seed: 507.5 g is half-ish of 1000 g, 11.43:1 is 0.762 of 15",
		absf(ReadoutGauge.fraction("auw_g", 507.5) - 0.5075) < 1e-9
			and absf(ReadoutGauge.fraction("thrust_to_weight", 11.43) - 0.762) < 1e-9, ""))
	return results


## The ring: the arc sweeps fraction x a full turn, the number sits inside it, icon then label below.
static func _test_ring_shape() -> Array:
	var results: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), PartsCatalog.load_default())
	var bad_sweep: Array = []
	for key in ReadoutGauge.RANGES:
		var lo := float(ReadoutGauge.RANGES[key][0])
		var hi := float(ReadoutGauge.RANGES[key][1])
		var g := ReadoutGauge.new(key)
		for f in [0.0, 0.25, 0.762, 1.0]:
			g.set_value(lo + (hi - lo) * f)
			if absf(g.arc_sweep() - f * TAU) > 1e-6:
				bad_sweep.append("%s@%s" % [key, f])
		g.free()
	results.append(TestResult.new("the ring's arc sweeps the fraction of a full turn, for every readout",
		bad_sweep.is_empty(), str(bad_sweep)))
	var bad_stack: Array = []
	for key in ds.gauges:
		var g := ds.gauges[key] as ReadoutGauge
		var val := ds.value_labels[key] as Label
		var cell := g.get_parent()
		var icon_at := g.get_index() + 1
		if val.get_parent() != g or not (cell.get_child(icon_at) is ReadoutGauge.Icon) \
				or not (cell.get_child(icon_at + 1) is Label) or (cell.get_child(icon_at + 1) as Label).text == "":
			bad_stack.append(key)
	results.append(TestResult.new("each readout stacks ring (number inside), then icon, then a label",
		bad_stack.is_empty() and ds.gauges.size() == 5, str(bad_stack)))
	var small := true
	for key in ds.value_labels:
		small = small and (ds.value_labels[key] as Label).get_theme_font_size("font_size") <= LothalTheme.FONT_SIZE_SMALL
	results.append(TestResult.new("the readout text is small (the old 22 px numbers are gone)", small, ""))
	ds.free()
	return results


static func _test_camera_limits() -> Array:
	var results: Array = []
	var rig := CameraRig.new(0.15, 0.06)
	for i in 400:
		rig.zoom_toward(0.8, Vector2(0.3, -0.2))
	results.append(TestResult.new("zooming in 400 times stops at the minimum distance",
		is_equal_approx(rig.goal_distance, CameraRig.MIN_DISTANCE), str(rig.goal_distance)))
	for i in 400:
		rig.zoom_toward(1.25, Vector2(-0.4, 0.1))
	results.append(TestResult.new("zooming out 400 times stops at the maximum distance",
		is_equal_approx(rig.goal_distance, rig.max_distance()), str(rig.goal_distance)))
	for i in 400:
		rig.orbit(0.3, 0.2)
	results.append(TestResult.new("orbiting down for ever stops short of straight down",
		rig.goal_pitch <= CameraRig.MAX_PITCH + 1e-9, str(rig.goal_pitch)))
	for i in 400:
		rig.orbit(-0.3, -0.2)
	results.append(TestResult.new("orbiting up for ever stops above the floor",
		rig.goal_pitch >= CameraRig.MIN_PITCH - 1e-9, str(rig.goal_pitch)))
	for i in 400:
		rig.pan(0.5, 0.5)
	var far_ok: bool = absf(rig.goal_target.x) <= rig.radius * 1.5 + 1e-9 and absf(rig.goal_target.z) <= rig.radius * 1.5 + 1e-9 \
		and rig.goal_target.y >= 0.0
	results.append(TestResult.new("panning for ever keeps the target near the drone and off the floor",
		far_ok, str(rig.goal_target)))
	# Zoom toward the cursor: the world point under the cursor stays under it.
	var r2 := CameraRig.new(0.15, 0.06)
	var ndc := Vector2(0.4, -0.3)
	var ray := r2.ray(ndc)
	var plane_hit: Variant = Plane(-r2.basis().z, r2.target).intersects_ray(ray["origin"], ray["dir"])
	r2.zoom_toward(0.5, ndc)
	r2.snap()
	var after := r2.project(plane_hit as Vector3)
	results.append(TestResult.new("zoom goes toward the cursor: the point under it stays under it",
		plane_hit != null and after.distance_to(ndc) < 1e-4, str(after)))
	# Double-click framing: the part ends up centred and filling the view.
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"))
	var box: AABB = ds.mesh_boxes()[0]["box"]
	ds.rig.frame(box)
	ds.rig.snap()
	var centre := ds.rig.project(box.get_center())
	results.append(TestResult.new("framing a part puts its centre on screen centre",
		centre.length() < 1e-4, str(centre)))
	ds.free()
	return results


static func _test_home_restores() -> Array:
	var results: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"))
	var rig := ds.rig
	var home_pos := rig.position()
	rig.orbit(1.1, 0.4)
	rig.pan(0.2, -0.1)
	rig.zoom_toward(0.3, Vector2(0.5, 0.5))
	for i in 120:
		rig.step(1.0 / 60.0)
	results.append(TestResult.new("after orbit, pan and zoom the camera is not at home",
		rig.position().distance_to(home_pos) > 0.01, str(rig.position())))
	var key := InputEventKey.new()
	key.keycode = KEY_H
	key.pressed = true
	ds._unhandled_key_input(key)
	for i in 240:
		rig.step(1.0 / 60.0)
	results.append(TestResult.new("pressing H eases the camera back to the isometric home view",
		rig.position().distance_to(home_pos) < 1e-4 and is_equal_approx(rig.pitch, CameraRig.HOME_PITCH)
			and is_equal_approx(rig.yaw, CameraRig.HOME_YAW), str(rig.position())))
	rig.orbit(0.7, 0.2)
	ds.home_button.pressed.emit()
	for i in 240:
		rig.step(1.0 / 60.0)
	results.append(TestResult.new("the Home button does the same",
		rig.position().distance_to(home_pos) < 1e-4, str(rig.position())))
	var eased := CameraRig.new()
	eased.orbit(1.0, 0.0)
	eased.step(1.0 / 60.0)
	results.append(TestResult.new("motion is eased: one frame moves part of the way, not all of it",
		eased.yaw != eased.goal_yaw and absf(eased.yaw - CameraRig.HOME_YAW) > 0.0, str(eased.yaw)))
	ds.free()
	return results


static func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


static func _open(id: String) -> GlassShell:
	var shell := GlassShell.new()
	shell._on_project_action("new")
	shell.class_picker.show_class(id)
	shell.class_picker.choose()
	return shell


static func _test_back_to_picker() -> Array:
	var results: Array = []
	var shell := _open("tiny_whoop")
	shell.design_space.back_button.pressed.emit()
	results.append(TestResult.new("Back opens the picker with the current class selected",
		shell.class_picker != null and shell.class_picker.current_id == "tiny_whoop"
			and not shell.design_space.visible, str(shell.class_picker)))
	# Esc on the picker: Design Space returns, same instance, build unchanged. Every dereference is
	# guarded, so a mutant that frees or replaces the Design Space fails THIS line, not a crash later.
	var ds := shell.design_space
	var frame_before: String = str(shell.container.project.parts)
	var ids_before := DroneClass.parts_for("tiny_whoop")
	if shell.class_picker != null:
		shell.class_picker.dismissed.emit()
	var alive := is_instance_valid(ds)
	var bad := _panel_matches(ds, ds.session.build(PartsCatalog.load_default())) if alive else "freed"
	results.append(TestResult.new("Esc on the picker restores the same Design Space, build unchanged",
		alive and shell.class_picker == null and shell.design_space == ds and ds.visible
			and ds.session.drone_class == "tiny_whoop" and bad == ""
			and ds.session.build(PartsCatalog.load_default()).frame["part_id"] == ids_before["frame"]
			and frame_before == (str(shell.container.project.parts)),
		bad))
	# Backspace does the same as the button.
	if alive:
		ds._unhandled_key_input(_key(KEY_BACKSPACE))
	var back_ok := shell.class_picker != null and shell.class_picker.current_id == "tiny_whoop"
	results.append(TestResult.new("Backspace also goes back", back_ok, str(shell.class_picker)))
	if not back_ok:
		shell.back_to_class_picker()
	if shell.class_picker == null:
		results.append(TestResult.new("choosing another class re-seeds the build and the model", false,
			"no picker to choose from"))
		_cleanup(shell)
		return results
	# Choose a different class: re-seeds build and model.
	shell.class_picker.show_class("seven_lr")
	shell.class_picker.choose()
	var ds2 := shell.design_space
	var want := DroneClass.parts_for("seven_lr")
	results.append(TestResult.new("choosing another class re-seeds the build and the model",
		ds2 != null and ds2 != ds and ds2.session.drone_class == "seven_lr" and shell.class_picker == null
			and ds2.session.build(PartsCatalog.load_default()).frame["part_id"] == want["frame"]
			and ds2.model_path() == "res://assets/models/classes/seven_lr.glb"
			and shell.container.project.drone_class == "seven_lr" and shell.container.project.parts["frame"] == want["frame"],
		str(ds2)))
	_cleanup(shell)
	return results


static func _test_panel_fades() -> Array:
	var results: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"))
	for i in 30:
		ds.step_panel(1.0 / 60.0)
	results.append(TestResult.new("the panel is visible at home",
		is_equal_approx(ds.panel.modulate.a, 1.0), str(ds.panel.modulate.a)))
	for i in 30:
		ds.rig.zoom_toward(0.7, Vector2.ZERO)
	ds.step_panel(1.0 / 60.0)
	results.append(TestResult.new("it is mid-fade after one frame, not a cut",
		ds.panel.modulate.a > 0.0 and ds.panel.modulate.a < 1.0, str(ds.panel.modulate.a)))
	for i in 30:
		ds.step_panel(1.0 / 60.0)
	results.append(TestResult.new("the panel is hidden when zoomed in",
		is_equal_approx(ds.panel.modulate.a, 0.0), str(ds.panel.modulate.a)))
	ds.go_home()
	for i in 30:
		ds.step_panel(1.0 / 60.0)
	results.append(TestResult.new("and back at home",
		is_equal_approx(ds.panel.modulate.a, 1.0), str(ds.panel.modulate.a)))
	ds.rig.snap()
	var pack := ds.picks.box_of("part/battery").get_center()
	ds.frame_at(ds.rig.project(pack))
	var framed := ds.rig.framing
	for i in 30:
		ds.step_panel(1.0 / 60.0)
	results.append(TestResult.new("framing a part hides it too",
		framed and is_equal_approx(ds.panel.modulate.a, 0.0), str(ds.panel.modulate.a)))
	ds.free()
	return results


const CHIP_CHARGE := "user://test_ds_chip_charge.json"


static func _chip_ds(catalog: PartsCatalog) -> DesignSpace:
	if FileAccess.file_exists(CHIP_CHARGE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHIP_CHARGE))
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.pack_charge_path = CHIP_CHARGE
	ds.refresh_charge_chip()
	return ds


## The selected-battery charge chip. Each check names a way the chip could be wrong: shown with no
## battery, a percentage not read from used_mah, a plug that does not store full, an enabled plug at 100%.
static func _test_charge_chip(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bare := DesignSession.default_for_class("five_inch")
	bare.selection.erase("battery")
	var ds0 := DesignSpace.new(bare, catalog)
	ds0.pack_charge_path = CHIP_CHARGE
	ds0.refresh_charge_chip()
	results.append(TestResult.new("charge chip is hidden when no battery is selected",
		ds0.charge_chip != null and not ds0.charge_chip.visible, ""))

	var ds := _chip_ds(catalog)
	var id := ds.selected_battery()
	var mah := float(catalog.get_part(id)["specs"]["mah"])
	results.append(TestResult.new("a full fitted battery shows its pack and 100%",
		ds.charge_chip.visible and ds.charge_chip.label.text == "4S %dmAh \u00b7 100%%" % int(mah),
		ds.charge_chip.label.text))
	var c := PackCharge.load_from(CHIP_CHARGE)
	c.set_used_mah(id, mah * 0.38)
	c.save(CHIP_CHARGE)
	ds.refresh_charge_chip()
	results.append(TestResult.new("the percentage is read from used_mah (38% used shows 62%)",
		ds.charge_chip.label.text.ends_with("\u00b7 62%") and not ds.charge_chip.plug.disabled,
		ds.charge_chip.label.text))
	ds.charge_chip.plug.pressed.emit()
	var stored := PackCharge.load_from(CHIP_CHARGE)
	results.append(TestResult.new("pressing the plug ends at 100% and stores used_mah 0",
		ds.charge_chip.label.text.ends_with("\u00b7 100%") and stored.used_mah(id) == 0.0,
		"%s stored %s" % [ds.charge_chip.label.text, stored.used_mah(id)]))
	results.append(TestResult.new("at 100% the plug is disabled",
		ds.charge_chip.plug.disabled, ""))

	# The animation, stepped by hand: the count rises monotonically and the text says Charging.
	var chip := ChargeChip.new()
	chip.set_pack("x", "4S 1500mAh", 1500.0, 930.0)
	chip._charging = true
	chip._from_frac = chip.fraction()
	var last := chip.percent()
	var rose := true
	var said := false
	for i in 31:
		chip.step(0.1)
		if chip.is_charging():
			said = said or chip.label.text.begins_with("Charging ")
			rose = rose and chip.percent() >= last
			last = chip.percent()
	results.append(TestResult.new("over 3 s the charge counts up, says Charging, then lands on 100%",
		rose and said and not chip.is_charging() and chip.label.text.ends_with("100%"),
		"%s rose=%s said=%s" % [chip.label.text, rose, said]))
	chip.free()
	ds.free()
	ds0.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHIP_CHARGE))
	return results


# ---------------------------------------------------------------------------
# Fly it / Field / Back to the drone (TRACKER section 9)
# ---------------------------------------------------------------------------

## A scratch ProjectLibrary root, so no test here touches the builder's own builds.
static func _scratch_open(id: String) -> GlassShell:
	ProjectLibrary.root = "user://scratch_flyit_%d" % OS.get_process_id()
	return _open(id)


static func _scratch_done(shell: GlassShell) -> void:
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR


static func _test_fly_it_and_back() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var shell := _scratch_open("five_inch")
	var ds := shell.design_space
	# Change a part in the Design Space only, so the old Lab's rails (still the class default) differ.
	var other := ""
	for opt in catalog.list_category("battery"):
		if String(opt.get("id", opt.get("part_id", ""))) != String(ds.session.selection["battery"]):
			other = String(opt.get("id", opt.get("part_id", "")))
			break
	ds.set_part("battery", other)
	var want := ds.session.build(catalog)
	ds.rig.goal_yaw += 0.7
	ds.rig.goal_distance *= 0.8
	var cam_before := Vector3(ds.rig.goal_yaw, ds.rig.goal_pitch, ds.rig.goal_distance)
	var sel_pick := ""
	for k in ds.pick_registry_addresses() if ds.has_method("pick_registry_addresses") else []:
		sel_pick = String(k)
		break
	ds.select(sel_pick if sel_pick != "" else "motor")
	var sel_before: String = ds.selected

	ds.file_bar.fly_button.pressed.emit()
	var sim = shell.rooms.sim
	var flown_ids: Dictionary = sim.initial_selection if sim != null else {}
	var parts := {}
	for c in ["frame", "motor", "propeller", "battery", "esc", "flight_controller"]:
		parts[c] = flown_ids.get(c, "")
	var project := Project.from_dict(shell.container.project.to_dict())
	project.parts.merge(flown_ids, true)
	var flown := project.to_build(catalog) if sim != null else null
	results.append(TestResult.new("Fly it shows the sim (Design Space hidden)",
		sim != null and not ds.visible and shell.away_from_design(), str(sim)))
	results.append(TestResult.new("Fly it flies the build being edited: same battery and same mass",
		flown != null and String(flown_ids.get("battery", "")) == other
			and is_equal_approx(flown.all_up_weight_g(), want.all_up_weight_g()),
		"flown=%s want=%s" % [flown.all_up_weight_g() if flown != null else -1.0, want.all_up_weight_g()]))
	results.append(TestResult.new("Fly it flies the same motor count",
		flown != null and flown.motor_count() == want.motor_count(),
		"%s vs %s" % [flown.motor_count() if flown != null else -1, want.motor_count()]))

	shell.back_to_drone_from_room()
	results.append(TestResult.new("Back returns to the same Design Space, project intact",
		shell.design_space == ds and ds.visible and shell.rooms.sim == null and not shell.away_from_design()
			and ds.session.selection["battery"] == other and ds.selected == sel_before
			and Vector3(ds.rig.goal_yaw, ds.rig.goal_pitch, ds.rig.goal_distance).is_equal_approx(cam_before)
			and String(shell.container.project.parts["battery"]) == other,
		"visible=%s sel=%s/%s" % [ds.visible, ds.selected, sel_before]))

	# Field: the world picker is on screen and Back returns the same way.
	shell.design_space.field_requested.emit()
	results.append(TestResult.new("Field opens the Field room (world picker present), Design Space hidden",
		not ds.visible and shell.away_from_design() and shell._field != null and shell._field.world_picker != null
			and shell._field.visible, "ds=%s away=%s field=%s picker=%s vis=%s" % [ds.visible, shell.away_from_design(), shell._field, shell._field.world_picker, shell._field.visible]))
	ds._unhandled_key_input(_key(KEY_F))
	shell.back_to_drone_from_room()
	results.append(TestResult.new("F on the Design Space flies it too, and Esc-path Back restores it",
		ds.visible and shell.rooms.sim == null, ""))
	ds._unhandled_key_input(_key(KEY_F))
	var esc := _key(KEY_ESCAPE)
	shell._unhandled_key_input(esc)
	results.append(TestResult.new("Esc in the sim goes back to the Design Space",
		ds.visible and shell.rooms.sim == null and not shell.away_from_design(), ""))

	# The old shell's own Lab/Sim toggle still works with no Design Space involved.
	shell.rooms.show_sim()
	var sim_on: bool = shell.rooms.sim != null
	shell._lab_button.pressed.emit()
	results.append(TestResult.new("The old Lab/Sim toggle still switches rooms",
		sim_on and shell.rooms.sim == null and shell.rooms.showing_lab(), ""))
	_scratch_done(shell)
	return results


## SR_PERF_FINDINGS #1: a hidden Design Space must not keep rendering a second 3D world.
static func _test_hidden_does_no_3d_work() -> Array:
	var results: Array = []
	var shell := _scratch_open("five_inch")
	var ds := shell.design_space
	results.append(TestResult.new("shown: the stage renders and the frame loop runs",
		ds.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and ds.can_process()
			or not ds.is_inside_tree(), str(ds.viewport.render_target_update_mode)))
	ds.file_bar.fly_button.pressed.emit()
	results.append(TestResult.new("flying: the hidden Design Space stage is UPDATE_DISABLED",
		ds.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		str(ds.viewport.render_target_update_mode)))
	results.append(TestResult.new("flying: the hidden Design Space frame loop is off",
		ds.process_mode == Node.PROCESS_MODE_DISABLED, str(ds.process_mode)))
	shell.back_to_drone_from_room()
	results.append(TestResult.new("back: the stage renders and the loop runs again",
		ds.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
			and ds.process_mode != Node.PROCESS_MODE_DISABLED, str(ds.viewport.render_target_update_mode)))
	shell.back_to_class_picker()
	results.append(TestResult.new("picker over it: the Design Space stage is off too",
		ds.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, ""))
	_scratch_done(shell)
	return results


## SR_PERF_FINDINGS minor: idle widgets request no redraw.
static func _test_redraws_only_on_change() -> Array:
	var results: Array = []
	var chip := ChargeChip.new()
	chip.set_pack("x", "4S 1500mAh", 1500.0, 930.0)
	var before := chip.redraw_requests
	for i in 60:
		chip._process(0.016)
	results.append(TestResult.new("charge chip: 60 idle frames request no plug redraw",
		chip.redraw_requests == before, str(chip.redraw_requests - before)))
	chip.free()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), PartsCatalog.load_default())
	ds.step_labels(0.0)
	var base := ds.redraw_requests
	for i in 60:
		ds.step_labels(0.016)
	results.append(TestResult.new("design space: steady label alpha requests no eye redraw",
		ds.redraw_requests == base, str(ds.redraw_requests - base)))
	ds.set_labels_hidden(true)
	results.append(TestResult.new("design space: hiding the labels does request one",
		ds.redraw_requests > base, str(ds.redraw_requests - base)))
	ds.free()
	return results
