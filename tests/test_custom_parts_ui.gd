class_name TestCustomPartsUi
extends RefCounted
## The authoring surfaces themselves: the rails a builder actually reaches the custom-parts feature
## through, and the dialogs behind them (the pack dialog went with the pack designer).
##
## This suite exists because of a specific way the feature failed. CustomPropellers, the old custom-pack store
## and their plausibility warnings were all written, tested and merged into the catalog by
## PartsCatalog.load_with_custom — and none of it was reachable. The propeller DIALOG was finished
## too; nothing constructed it. Every model-level test passed the whole time, because a model test
## calls make_record directly and never asks whether a builder could have got there.
##
## So the assertions here are deliberately about REACHABILITY rather than about records:
##
##   Each authoring rail offers a way in, and a way back out for a part the builder owns.
##   Each rail's change signal exists, so LabScreen has something to rebuild from.
##   The prop rail's delete refuses a prop a custom motor is measured on — the one delete in the
##   feature that can break a NEIGHBOURING document.
##
## A test that only checked "make_record produces a good record" would have gone on passing through
## the entire period the buttons did not exist. These are the checks that would not have.

const CATALOG_PROP_ID := "prop_5x43x3"


static func run() -> Array:
	var results: Array = []
	# THE HOLD ON THE BUILDER'S OWN FILES. Taken here and released below, because a section that
	# aborts mid-way never reaches its own restore — measured, and it is what left a 3500 m
	# elevation and an invented weather row on this developer's disk. `run()` is the only frame
	# GDScript guarantees will resume after an abort inside a section, so the hold lives here and
	# `run()` does nothing else but call sections and append results. See tests/real_files.gd.
	var held := RealFiles.hold([CustomParts.SAVE_PATH])
	results.append(_test_every_authoring_rail_offers_a_way_in())
	results.append(_test_every_authoring_rail_has_a_change_signal())
	results.append(_test_delete_is_disabled_on_a_catalog_part_and_enabled_on_your_own())
	results.append(_test_the_save_button_does_not_close_a_dialog_on_a_refusal())
	results.append(_test_prop_rail_refuses_to_delete_a_prop_a_motor_is_measured_on())
	results.append(_test_prop_rail_deletes_an_independent_prop())
	results.append(_test_esc_dialog_saves_a_record_the_model_accepts())
	results.append(_test_fc_dialog_derives_noise_and_labels_the_bias_illustrative())
	# C7 — the payload rails.
	results.append(_test_payload_rail_reloads_the_catalog("Electronics"))
	results.append(_test_payload_rail_reloads_the_catalog("Link"))
	results.append(_test_payload_rail_delete("Electronics", "Video", "camera", "cam_micro_analog",
		CustomCameras.make_record("Shed cam", 6.0, 19.0, 19.0, 20.0, "analog", "micro", "CMOS",
			"measured on my scale")))
	results.append(_test_payload_rail_delete("Link", "Control", "gps", "gps_micro_flat",
		CustomGps.make_record("Shed gps", 9.0, 25.0, 25.0, 8.0, 40.0, "GPS", true, "UBX",
			"measured on my scale")))
	results.append(_test_link_rail_new_opens_the_chosen_category())
	results.append(_test_component_dialog_saves("camera",
		{"signal": "digital", "size_class": "nano", "sensor": "CMOS"},
		func(r: Dictionary) -> bool: return r["catalog"]["size_class"] == "nano"))
	results.append(_test_component_dialog_saves("vtx",
		{"signal": "digital", "power_class": "1 W", "band": "5.8 GHz"},
		func(r: Dictionary) -> bool: return r["catalog"]["power_class"] == "1 W"))
	results.append(_test_component_dialog_saves("antenna",
		{"polarisation": "LHCP", "connector": "u.FL", "gain_class": "3 dBi"},
		func(r: Dictionary) -> bool: return r["catalog"]["connector"] == "u.FL"))
	results.append(_test_component_dialog_saves("receiver",
		{"protocol": "ExpressLRS", "band": "900 MHz", "antenna_type": "T"},
		func(r: Dictionary) -> bool: return r["catalog"]["band"] == "900 MHz"))
	results.append(_test_component_dialog_saves("gps",
		{"mast_height_mm": 55.0, "constellations": "GPS", "protocol": "UBX", "compass": true},
		func(r: Dictionary) -> bool: return is_equal_approx(float(r["specs"]["mast_height_mm"]), 55.0) \
			and r["catalog"]["compass"] == true))
	results.append(_test_component_dialog_saves("buzzer",
		{"self_powered": false, "loudness_db": 85.0},
		func(r: Dictionary) -> bool: return r["specs"]["self_powered"] is bool \
			and r["specs"]["self_powered"] == false))
	held.restore()
	results.append(TestResult.new(
		"the builder's own files are back the way they were found, whatever the sections did",
		held.intact(), held.report()))
	return results


# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------

static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _write_raw(path: String, text: String) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()


static func _restore(path: String, previous: String) -> void:
	if previous == "":
		_wipe(path)
	else:
		_write_raw(path, previous)


## Same dance as tests/test_custom_propellers.gd — see its copy for why every test that touches the
## real save path must restore it.
static func _with_scratch_savepath(body: Callable) -> Variant:
	var previous := ""
	if FileAccess.file_exists(CustomParts.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomParts.SAVE_PATH)
	_wipe(CustomParts.SAVE_PATH)
	var result = body.call()
	_restore(CustomParts.SAVE_PATH, previous)
	return result


## The four rails that author parts, built against the merged catalog the way LabScreen builds
## them. ESC and FC are deliberately absent: they have no custom-parts document, so a "New custom…"
## button on them would be a button that could not work.
static func _authoring_rails(catalog: PartsCatalog) -> Dictionary:
	return {
		"frame": FramePicker.new(catalog),
		"motor": MotorPicker.new(catalog),
		"propeller": PropellerPicker.new(catalog),
		"esc": EscPicker.new(catalog),
		"flight_controller": FcPicker.new(catalog),
		# C7: both payload rails, built the way LabScreen builds them — from Build's system table, not
		# from a hand-written three names — so a category moved between rails is still covered.
		"electronics": ElectronicsPicker.new(catalog, Build.components_for_system("Video"), "Electronics"),
		"link": ElectronicsPicker.new(catalog, Build.components_for_system("Control"), "Link"),
	}


## Every Button anywhere under a rail, by text. The rails put their controls in an HBoxContainer
## handed to PartPicker.add_custom_buttons, and this walks rather than reaching for a known path so
## the test does not break the moment a rail rearranges its own row.
static func _button_texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	if node is Button:
		found.append((node as Button).text)
	for child in node.get_children():
		found.append_array(_button_texts(child))
	return found


static func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var hit := _find_button(child, text)
		if hit != null:
			return hit
	return null


static func _free_rails(rails: Dictionary) -> void:
	for rail in rails.values():
		(rail as Node).free()


# ---------------------------------------------------------------------------
# 1. Reachability: the check that would have caught the whole gap
# ---------------------------------------------------------------------------

## The regression test for this slice. Each of the four categories with a CustomParts document
## behind it must offer a builder a way to author one, on the rail where that category is browsed.
##
## Asserted per-rail with the category named in the failure detail, rather than as one boolean over
## all four, because "some rail is missing its button" is not an actionable failure message and the
## whole point of this test is to name the rail that was forgotten.
static func _test_every_authoring_rail_offers_a_way_in() -> TestResult:
	var catalog := PartsCatalog.load_with_custom()
	var rails := _authoring_rails(catalog)

	var missing: Array[String] = []
	for category in rails:
		var texts := _button_texts(rails[category])
		var has_new := false
		for text in texts:
			if text.begins_with("New custom"):
				has_new = true
		if not has_new or not texts.has("Delete"):
			missing.append("%s (new=%s, delete=%s)" % [category, has_new, texts.has("Delete")])

	_free_rails(rails)
	return TestResult.new(
		"every rail with a custom-parts document offers New and Delete",
		missing.is_empty(),
		"all %d reachable" % rails.size() if missing.is_empty() else "unreachable: %s" % ", ".join(missing))


## The signal LabScreen rebuilds from. A rail that had the button but no signal would save the part
## and leave the screen showing the build from before it existed.
static func _test_every_authoring_rail_has_a_change_signal() -> TestResult:
	var catalog := PartsCatalog.load_with_custom()
	var rails := _authoring_rails(catalog)
	var expected := {
		"frame": "custom_frames_changed",
		"motor": "custom_motors_changed",
		"propeller": "custom_propellers_changed",
		"esc": "custom_escs_changed",
		"flight_controller": "custom_flight_controllers_changed",
		"electronics": "custom_components_changed",
		"link": "custom_components_changed",
	}

	var missing: Array[String] = []
	for category in rails:
		if not (rails[category] as Object).has_signal(expected[category]):
			missing.append("%s.%s" % [category, expected[category]])

	_free_rails(rails)
	return TestResult.new(
		"every authoring rail carries the change signal LabScreen reloads on",
		missing.is_empty(),
		"all seven present" if missing.is_empty() else "missing: %s" % ", ".join(missing))


## A signal nobody listens to is the button-with-no-rebuild failure one layer up: the part is saved
## and the dropdown it was entered from does not show it until a restart. So the WIRING is asked of a
## real LabScreen, per payload rail — one row each, because wiring one rail and forgetting the other
## is the specific way this goes wrong when there are two instances of one class.
##
## FAILS IF: LabScreen._build_rails does not connect that rail's custom_components_changed to
## reload_catalog.
static func _test_payload_rail_reloads_the_catalog(rail_name: String) -> TestResult:
	var lab := LabScreen.new(PartsCatalog.load_default(), AssemblyTweaks.new(), PackCharge.new())
	var rail: ElectronicsPicker = null
	for candidate in lab.component_rails():
		if String(candidate.name) == rail_name:
			rail = candidate
	# Both read BEFORE the free: a freed rail compares equal to null, so a detail computed afterwards
	# reports "rail found=false" on a rail that was found — which is what the first mutation run printed.
	var found := rail != null
	var wired := found and rail.custom_components_changed.is_connected(lab.reload_catalog)
	lab.free()
	return TestResult.new(
		"LabScreen reloads the catalog when a custom part is saved or deleted on the %s rail" % rail_name,
		wired,
		"rail found=%s, connected=%s" % [found, wired])


## Delete on a payload rail: dead on a shipped part, live on the builder's own, and — through the
## real button — removes the record and asks Lab to reload. One row per rail, each on a category
## that rail carries.
##
## FAILS IF: `_refresh_delete_button` stops consulting PartsCatalog.is_custom (enabled on a catalog
## part, or never enabled), if Delete acts on a category other than the one shown, or if the button
## is wired to nothing (the record survives and no reload is emitted).
static func _test_payload_rail_delete(rail_name: String, system: String, category: String,
		catalog_id: String, record: Dictionary) -> TestResult:
	var check := func() -> Dictionary:
		var document := CustomComponentDialog.document_for(category)
		var added := document.add(record)
		document.save()
		var catalog := PartsCatalog.load_with_custom()
		var rail := ElectronicsPicker.new(catalog, Build.components_for_system(system), rail_name)
		var seen := {"reloaded": false}
		rail.custom_components_changed.connect(func() -> void: seen["reloaded"] = true)
		var delete := _find_button(rail, "Delete")

		rail.set_authoring_category(category)
		rail.select_component(category, catalog_id)
		var off_on_catalog := delete.disabled
		var custom_id := str(record["part_id"])
		var selectable := rail.select_component(category, custom_id)
		var on_on_custom := not delete.disabled
		delete.pressed.emit()
		var gone := CustomComponentDialog.document_for(category).get_record(custom_id).is_empty()
		rail.free()
		return {"added": added, "off": off_on_catalog, "selectable": selectable,
			"on": on_on_custom, "gone": gone, "reloaded": seen["reloaded"]}

	var out: Dictionary = _with_scratch_savepath(check)
	return TestResult.new(
		"%s rail: Delete is disabled on a catalog %s, enabled on the builder's own, and removes it" % [
			rail_name, category],
		(out["added"] as Array).is_empty() and out["off"] and out["selectable"] and out["on"]
			and out["gone"] and out["reloaded"],
		"added problems=%s, disabled on catalog=%s, custom selectable=%s, enabled on custom=%s, removed=%s, reload emitted=%s" % [
			out["added"], out["off"], out["selectable"], out["on"], out["gone"], out["reloaded"]])


## New on a payload rail opens the dialog for the category SHOWN, not for the first one the rail
## carries. FAILS IF: the dialog is built from anything but authoring_category(), e.g. categories[0].
static func _test_link_rail_new_opens_the_chosen_category() -> TestResult:
	var rail := ElectronicsPicker.new(PartsCatalog.load_default(),
		Build.components_for_system("Control"), "Link")
	rail.set_authoring_category("buzzer")
	var dialog := rail.open_dialog()
	var opened := dialog.category
	rail.free()
	return TestResult.new("the Link rail's New opens the dialog for the category the builder chose",
		opened == "buzzer", "chose buzzer, dialog opened for \"%s\"" % opened)


## The component dialog's wiring, per category: fields in, a record the category's own store accepts
## on disk, each dimension where it belongs and the category's own extra stored. Six rows, not a loop,
## because the failure this catches is ONE category's make_record call with its arguments shifted.
##
## FAILS IF: submit() passes length/width/height in the wrong order for that category, calls the
## wrong store, or drops that category's extra (the mast, the power answer, a metadata string).
static func _test_component_dialog_saves(category: String, meta: Dictionary,
		extra_check: Callable) -> TestResult:
	var check := func() -> Dictionary:
		var dialog := CustomComponentDialog.new(category)
		var seen := {"id": ""}
		dialog.component_saved.connect(func(part_id: String) -> void: seen["id"] = part_id)
		dialog.set_fields("Shed %s" % category, 7.5, 31.0, 21.0, 11.0, meta, "measured on my scale")
		var refusals := dialog.submit()
		# Guarded, not dereferenced: a category the store table lost returns null, and calling through
		# it would abort the whole runner instead of failing THIS row by name (the M15 mutation did).
		var store := CustomComponentDialog.document_for(category)
		var stored: Dictionary = store.get_record(seen["id"]) if store != null else {}
		dialog.free()
		return {"problems": refusals, "id": seen["id"], "stored": stored}

	var out: Dictionary = _with_scratch_savepath(check)
	var saved: Dictionary = out["stored"]
	var specs: Dictionary = saved.get("specs", {})
	var dims_ok := is_equal_approx(float(saved.get("mass_g", 0.0)), 7.5) \
		and is_equal_approx(float(specs.get("length_mm", 0.0)), 31.0) \
		and is_equal_approx(float(specs.get("width_mm", 0.0)), 21.0) \
		and is_equal_approx(float(specs.get("height_mm", 0.0)), 11.0) \
		and str(saved.get("category", "")) == category
	var extra_ok: bool = not saved.is_empty() and extra_check.call(saved)
	return TestResult.new(
		"the component dialog saves a %s its store accepts, dimensions and extras in place" % category,
		(out["problems"] as Array).is_empty() and out["id"] != "" and dims_ok and extra_ok,
		"problems=%s, id=%s, dims ok=%s, extra ok=%s, stored=%s" % [out["problems"], out["id"],
			dims_ok, extra_ok, JSON.stringify(saved)])


## Delete must be dead on a shipped part and live on the builder's own — on the two rails this
## slice added, checked against a catalog that actually holds one of each.
static func _test_delete_is_disabled_on_a_catalog_part_and_enabled_on_your_own() -> TestResult:
	var check := func() -> Dictionary:
		var props := CustomPropellers.new()
		props.add(CustomPropellers.make_record("Shed 5x4.3x3", 4.5, 5.0, 4.3, 3, "polycarbonate",
			"measured on my scale"))
		props.save(CustomParts.SAVE_PATH)

		var catalog := PartsCatalog.load_with_custom()
		var prop_rail := PropellerPicker.new(catalog)

		prop_rail.select_id(CATALOG_PROP_ID)
		var prop_catalog_disabled := _find_button(prop_rail, "Delete").disabled
		prop_rail.select_id("custom_shed_5x4_3x3")
		var prop_custom_enabled := not _find_button(prop_rail, "Delete").disabled

		prop_rail.free()
		return {"prop_off": prop_catalog_disabled, "prop_on": prop_custom_enabled}

	var out: Dictionary = _with_scratch_savepath(check)
	return TestResult.new(
		"Delete is disabled on a catalog prop, enabled on the builder's own",
		out["prop_off"] and out["prop_on"],
		"prop: catalog disabled=%s custom enabled=%s" % [out["prop_off"], out["prop_on"]])


# ---------------------------------------------------------------------------
# 2. Dialogs that must not close on a refusal
# ---------------------------------------------------------------------------

## The refusal a builder actually meets, at the BUTTON rather than at submit().
##
## Every one of these dialogs is an AcceptDialog, and AcceptDialog hides itself the moment OK is
## pressed or Enter is hit — before any handler runs, and with no hook that stops it. So a refused
## record showed its problems on a window that was already gone: the form vanished exactly as it
## does on success, nothing was written, and the builder found out only when they reopened Lothal
## and the part was missing. Every one of the four dialogs did this.
##
## `_test_pack_dialog_refuses_and_stays_open_without_a_source` could not catch it, because it calls
## submit() directly and never touches the button. This one presses the button, and asserts on
## `visible` — which is the thing the builder is actually looking at — in both directions: a refused
## record leaves the form up, and an accepted one takes it away.
static func _test_the_save_button_does_not_close_a_dialog_on_a_refusal() -> TestResult:
	# One refused record per category and one good one, differing only in the field that is wrong:
	# the frame has no arm (the SpinBox's own starting value), the others no source.
	var bad := {
		"frame": func() -> AcceptDialog:
			var d := CustomFrameDialog.new()
			d.set_fields("Bad Frame", 118.0, 0.0, 5.0, "16x16", "30.5x30.5", "carbon fibre", "scale")
			return d,
		"motor": func() -> AcceptDialog:
			var d := CustomMotorDialog.new()
			d.set_fields("Bad Motor", 30.9, 22.0, 6.0, 2400.0, 1650.0, 40.0, 14, "16x16",
				CATALOG_PROP_ID, 14.0, "")
			return d,
		"propeller": func() -> AcceptDialog:
			var d := CustomPropellerDialog.new()
			d.set_fields("Bad Prop", 4.5, 5.0, 4.3, 3, "polycarbonate", "")
			return d,
		# C7. The six component categories refused for no source — and the two refusals the component
		# dialog exists to make: a GPS whose mast was left EMPTY, and a buzzer whose power question
		# was left UNANSWERED, each with a source, so the refusal can only be the field itself.
		"camera": func() -> AcceptDialog: return _component_dialog("camera", {}, ""),
		"vtx": func() -> AcceptDialog: return _component_dialog("vtx", {}, ""),
		"antenna": func() -> AcceptDialog: return _component_dialog("antenna", {}, ""),
		"receiver": func() -> AcceptDialog: return _component_dialog("receiver", {}, ""),
		"gps (no source)": func() -> AcceptDialog: return _component_dialog("gps", {"mast_height_mm": 0.0}, ""),
		"gps (mast left empty)": func() -> AcceptDialog: return _component_dialog("gps", {}, "scale"),
		"buzzer (no source)": func() -> AcceptDialog: return _component_dialog("buzzer", {"self_powered": true}, ""),
		"buzzer (power unanswered)": func() -> AcceptDialog: return _component_dialog("buzzer", {}, "scale"),
	}
	var good := {
		"frame": func() -> AcceptDialog:
			var d := CustomFrameDialog.new()
			d.set_fields("Good Frame", 118.0, 105.0, 5.0, "16x16", "30.5x30.5", "carbon fibre", "scale")
			return d,
		"motor": func() -> AcceptDialog:
			var d := CustomMotorDialog.new()
			d.set_fields("Good Motor", 30.9, 22.0, 6.0, 2400.0, 1650.0, 40.0, 14, "16x16",
				CATALOG_PROP_ID, 14.0, "spec sheet")
			return d,
		"propeller": func() -> AcceptDialog:
			var d := CustomPropellerDialog.new()
			d.set_fields("Good Prop", 4.5, 5.0, 4.3, 3, "polycarbonate", "product page")
			return d,
		"camera": func() -> AcceptDialog: return _component_dialog("camera", {}, "scale"),
		"vtx": func() -> AcceptDialog: return _component_dialog("vtx", {}, "scale"),
		"antenna": func() -> AcceptDialog: return _component_dialog("antenna", {}, "scale"),
		"receiver": func() -> AcceptDialog: return _component_dialog("receiver", {}, "scale"),
		# Mast 0 on the good GPS on purpose: the flat module is the answer an over-eager refusal
		# would wrongly bounce, so the "accepted closes" half watches that edge too.
		"gps (no source)": func() -> AcceptDialog: return _component_dialog("gps", {"mast_height_mm": 0.0}, "scale"),
		"gps (mast left empty)": func() -> AcceptDialog: return _component_dialog("gps", {"mast_height_mm": 0.0}, "scale"),
		"buzzer (no source)": func() -> AcceptDialog: return _component_dialog("buzzer", {"self_powered": false}, "scale"),
		"buzzer (power unanswered)": func() -> AcceptDialog: return _component_dialog("buzzer", {"self_powered": false}, "scale"),
	}

	var check := func() -> Array:
		var faults: Array[String] = []
		for category in bad:
			var refused_dialog: AcceptDialog = (bad[category] as Callable).call()
			refused_dialog.get_ok_button().pressed.emit()
			var refused: bool = not refused_dialog.call("problems").is_empty()
			var stayed_open: bool = refused_dialog.visible
			refused_dialog.free()

			var saved_dialog: AcceptDialog = (good[category] as Callable).call()
			saved_dialog.get_ok_button().pressed.emit()
			var accepted: bool = saved_dialog.call("problems").is_empty()
			var closed: bool = not saved_dialog.visible
			saved_dialog.free()

			# A fixture that stopped being a refusal (or stopped being acceptable) proves nothing,
			# and passing quietly on it is how this test would rot into one that cannot fail.
			if not refused or not accepted:
				faults.append("%s (fixtures no longer refused/accepted: refused=%s accepted=%s)" % [
					category, refused, accepted])
				continue
			if not stayed_open:
				faults.append("%s (closed on a refusal)" % category)
			if not closed:
				faults.append("%s (stayed open after saving)" % category)
		return faults

	var wrong: Array = _with_scratch_savepath(check)
	return TestResult.new(
		"Save leaves a refused dialog open and closes an accepted one",
		wrong.is_empty(),
		"all %d, both ways" % bad.size() if wrong.is_empty() else "; ".join(wrong))


## A component dialog filled with a plausible part and the given extras. Each good fixture gets a
## name unique to its key's category AND extras, so two accepted dialogs of one category in the same
## scratch file do not collide on part_id and turn a pass into a refusal.
static func _component_dialog(category: String, meta: Dictionary, source: String) -> AcceptDialog:
	var d := CustomComponentDialog.new(category)
	d.set_fields("Shed %s %d" % [category, randi()], 6.0, 20.0, 20.0, 10.0, meta, source)
	return d


# ---------------------------------------------------------------------------
# 3. The delete that can break the document next door
# ---------------------------------------------------------------------------

## tests/test_custom_propellers.gd proves CustomPropellers.remove_or_refuse refuses. This proves the
## RAIL asks it — the button is where a builder meets that rule, and a rail that called plain
## remove() would satisfy every existing test while deleting the motor's thrust reference.
##
## Checked through the button's own pressed signal rather than by calling _delete_selected, so a
## rail that wired Delete to nothing at all fails here.
static func _test_prop_rail_refuses_to_delete_a_prop_a_motor_is_measured_on() -> TestResult:
	var check := func() -> Dictionary:
		var props := CustomPropellers.new()
		props.add(CustomPropellers.make_record("Shed 5x4.3x3", 4.5, 5.0, 4.3, 3, "polycarbonate",
			"measured on my scale"))
		props.save(CustomParts.SAVE_PATH)

		var motors := CustomMotors.load_from()
		var motor_rejections := motors.add(CustomMotors.make_record("Shed Motor", 32.0, 22.0, 7.0,
			1960.0, 1450.0, 32.0, 14, "16x16", "custom_shed_5x4_3x3", 14.8,
			"manufacturer table on a prop I entered myself"))
		motors.save(CustomParts.SAVE_PATH)

		var catalog := PartsCatalog.load_with_custom()
		var rail := PropellerPicker.new(catalog)
		var seen := {"reloaded": false, "refusal": ""}
		rail.custom_propellers_changed.connect(func() -> void: seen["reloaded"] = true)
		rail.delete_refused.connect(func(message: String) -> void: seen["refusal"] = message)
		rail.select_id("custom_shed_5x4_3x3")
		_find_button(rail, "Delete").pressed.emit()

		var survived: bool = not CustomPropellers.load_from().get_propeller(
			"custom_shed_5x4_3x3").is_empty()
		# And the motor is still loadable — the actual damage a cascade would have done.
		var motor_survived: bool = not CustomMotors.load_from().get_motor(
			"custom_shed_motor").is_empty()
		# The refusal must have been ANNOUNCED, not merely decided. A rail that returned early
		# without telling the builder anything would otherwise pass every assertion here — the
		# prop survives and the motor survives whether or not anyone was told why.
		var explained: bool = str(seen["refusal"]).contains("Shed Motor")
		rail.free()

		return {"motor_ok": motor_rejections.is_empty(), "survived": survived,
			"motor_survived": motor_survived, "reloaded": seen["reloaded"],
			"explained": explained}

	var out: Dictionary = _with_scratch_savepath(check)
	var passed: bool = out["motor_ok"] and out["survived"] and out["motor_survived"] \
		and not out["reloaded"] and out["explained"]
	return TestResult.new(
		"the prop rail's Delete refuses a prop a custom motor is measured on, names it, and the motor survives",
		passed,
		"motor accepted=%s, prop survived=%s, motor survived=%s, reload emitted=%s (want false), refusal shown naming the motor=%s" % [
			out["motor_ok"], out["survived"], out["motor_survived"], out["reloaded"],
			out["explained"]])


## The other side of the refusal. Without this, a rail whose Delete did nothing whatsoever would
## pass the test above — the failure mode that test alone cannot distinguish from working.
static func _test_prop_rail_deletes_an_independent_prop() -> TestResult:
	var check := func() -> Dictionary:
		var props := CustomPropellers.new()
		props.add(CustomPropellers.make_record("Shed 7x4x3", 9.0, 7.0, 4.0, 3,
			"glass-filled nylon", "off the product page"))
		props.save(CustomParts.SAVE_PATH)

		var catalog := PartsCatalog.load_with_custom()
		var rail := PropellerPicker.new(catalog)
		var seen := {"reloaded": false}
		rail.custom_propellers_changed.connect(func() -> void: seen["reloaded"] = true)
		rail.select_id("custom_shed_7x4x3")
		_find_button(rail, "Delete").pressed.emit()

		var gone: bool = CustomPropellers.load_from().get_propeller("custom_shed_7x4x3").is_empty()
		rail.free()
		return {"gone": gone, "reloaded": seen["reloaded"]}

	var out: Dictionary = _with_scratch_savepath(check)
	return TestResult.new(
		"the prop rail's Delete removes a prop nothing depends on, and asks Lab to reload",
		out["gone"] and out["reloaded"],
		"prop removed=%s, catalog reload emitted=%s" % [out["gone"], out["reloaded"]])


# ---------------------------------------------------------------------------
# 4. The two stack dialogs (LTHL-25)
# ---------------------------------------------------------------------------

## The ESC form's whole job, checked through submit() rather than make_record for the reason the
## retired pack dialog's copy gave: what is untested is the WIRING, and a form that read the burst box into
## the continuous argument would pass every model test in the suite next door — while quadrupling
## the board a builder flies on.
static func _test_esc_dialog_saves_a_record_the_model_accepts() -> TestResult:
	var check := func() -> Dictionary:
		var dialog := CustomEscDialog.new()
		var seen := {"id": ""}
		dialog.esc_saved.connect(func(part_id: String) -> void: seen["id"] = part_id)
		dialog.set_fields("Shed 60A 4in1", 60.0, 70.0, 4, 13.0, "30.5x30.5", "3-6S", "DShot600",
			"off the product page")

		var refusals := dialog.submit()
		var stored := CustomEscs.load_from().get_esc("custom_shed_60a_4in1")
		var specs: Dictionary = stored.get("specs", {})
		dialog.free()

		return {
			"problems": refusals,
			"announced": seen["id"],
			"stored": not stored.is_empty(),
			"continuous": float(specs.get("continuous_a", 0.0)),
			"burst": float(specs.get("burst_a", 0.0)),
			"channels": int(specs.get("channels", 0)),
			"mass_g": float(stored.get("mass_g", 0.0)),
			"pattern": str(stored.get("mounting", {}).get("pattern", "")),
		}

	var out: Dictionary = _with_scratch_savepath(check)
	# Continuous and burst asserted separately and in the right order, because the failure this
	# catches is precisely the two being swapped.
	var fields_ok: bool = is_equal_approx(out["continuous"], 60.0) \
		and is_equal_approx(out["burst"], 70.0) and out["channels"] == 4 \
		and is_equal_approx(out["mass_g"], 13.0) and out["pattern"] == "30.5x30.5"
	var passed: bool = (out["problems"] as Array).is_empty() and out["stored"] \
		and out["announced"] == "custom_shed_60a_4in1" and fields_ok
	return TestResult.new(
		"the ESC dialog saves a record CustomEscs accepts, with continuous and burst the right way round",
		passed,
		"problems=%s, announced=%s, stored=%s, %.0f A continuous / %.0f A burst x%d, %.0f g, %s" % [
			out["problems"], out["announced"], out["stored"], out["continuous"], out["burst"],
			out["channels"], out["mass_g"], out["pattern"]])


## The FC form's one job that no other dialog has: showing the builder the noise floor it derived
## for them, naming the datasheet it came from, and saying in the same breath that the bias beside
## it is nothing of the kind. A form that printed both as plain numbers would be the whole failure
## this category is built to avoid.
static func _test_fc_dialog_derives_noise_and_labels_the_bias_illustrative() -> TestResult:
	var dialog := CustomFcDialog.new()
	dialog.set_fields("Shed H743 Board", "ICM-42688-P", 8000.0, 12.0, "30.5x30.5", "H743", 8000,
		"off the product page")
	var text := dialog.derived_text()
	var expected_noise := CustomFlightControllers.derived_noise_rad_s(
		CustomFlightControllers.density_for("ICM-42688-P"), 8000.0)
	dialog.free()

	var shows_noise := text.contains("%.4f" % expected_noise)
	var names_datasheet := text.contains("DS-000347")
	var says_illustrative := text.to_lower().contains("illustrative")
	var says_derived := text.to_lower().contains("derived")

	return TestResult.new(
		"the FC dialog shows the derived noise floor, names its datasheet, and calls the bias illustrative",
		shows_noise and names_datasheet and says_illustrative and says_derived,
		"noise %.4f shown=%s, datasheet named=%s, bias called illustrative=%s, says derived=%s" % [
			expected_noise, shows_noise, names_datasheet, says_illustrative, says_derived])
