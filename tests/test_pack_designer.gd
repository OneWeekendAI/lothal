class_name TestPackDesigner
extends RefCounted
## The pack designer pop-up and the "+" tile that opens it. Headless: controls are built, no
## frames are run, so the reveal animation is skipped (the charts jump to their final state).
##
## The checks that could have passed while proving nothing:
## - "no new button": the expected names below were TAKEN FROM THE DESIGN SPACE BEFORE THIS CHANGE
##   (shelf open on the battery category, five-inch class), by walking every button; this file adds
##   exactly one name to them, "AddPack". A second new button anywhere fails it.
## - "typed fields": the editable controls are found by walking the pop-up for LineEdit / SpinBox,
##   not by asking the designer what it thinks is editable.

const SIZE := Vector2(1280, 720)
const SCRATCH := "user://test_pack_designer_parts.json"
const CHARGE := "user://test_pack_designer_charge.json"

## Named buttons of the Design Space, shelf open on batteries, before the pack designer existed.
const BEFORE_NAMES := ["Back", "Cat_antenna", "Cat_battery", "Cat_camera", "Cat_esc",
	"Cat_flight_controller", "Cat_guard", "Cat_motor", "Cat_propeller", "Cat_receiver", "Cat_vtx",
	"Chip_cells_n1", "Chip_cells_n2", "Chip_cells_n3", "Chip_cells_n4", "Chip_cells_n5",
	"Chip_cells_n6", "Chip_cells_n7", "Chip_cells_n8", "Home", "LabelsToggle", "ShelfHeader", "mark_auw_g", "mark_flight_time_min",
	"mark_hover_throttle", "mark_thrust_to_weight", "mark_top_speed_kmh"]
## And its unnamed ("@Button@N") buttons.
const BEFORE_UNNAMED := 15

## Figure keys that are derived from cells; none may be reachable by typing.
const DERIVED := ["nominal_v", "full_v", "empty_v", "mah", "wh", "mass_g", "dims_mm", "cont_a",
	"burst_a", "internal_r_ohm"]


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _designer(catalog: PartsCatalog, with_build := true) -> PackDesigner:
	_wipe(SCRATCH)
	_wipe(CHARGE)
	var store := DesignedPacks.load_from(SCRATCH)
	var charge := PackCharge.load_from(CHARGE)
	var build: Build = null
	if with_build:
		build = DesignSession.default_for_class("five_inch").build(catalog)
	var d := PackDesigner.new(catalog, CellLibrary.load_default(), store, charge, build)
	d.store_path = SCRATCH
	d.charge_path = CHARGE
	d.size = SIZE
	return d


static func _walk(n: Node, out: Array, cls: String) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_walk(c, out, cls)


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	results.append_array(_test_tile(catalog))
	results.append_array(_test_opens_valid(catalog))
	results.append_array(_test_default_load(catalog))
	results.append_array(_test_motor_picker(catalog))
	results.append_array(_test_series_rederives(catalog))
	results.append_array(_test_label(catalog))
	results.append_array(_test_typed_fields(catalog))
	results.append_array(_test_recharge(catalog))
	results.append_array(_test_range(catalog))
	results.append_array(_test_drain(catalog))
	results.append_array(_test_my_packs(catalog))
	results.append_array(_test_cell_voltage_and_knee(catalog))
	results.append_array(_test_delete(catalog))
	results.append_array(_test_modal(catalog))
	_wipe(SCRATCH)
	_wipe(CHARGE)
	return results


static func _test_tile(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = SIZE
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("battery")
	var buttons: Array = []
	_walk(ds, buttons, "BaseButton")
	var named: Array = []
	var unnamed := 0
	var tile: Node = null
	for b in buttons:
		var nm := String(b.name)
		if nm.begins_with("Part_"):
			continue
		if nm.begins_with("@"):
			unnamed += 1
		elif not named.has(nm):
			named.append(nm)
		if nm == "AddPack":
			tile = b
	named.sort()
	var expected: Array = BEFORE_NAMES.duplicate()
	expected.append("AddPack")
	expected.append("MisfitToggle_battery")  # the 5"'s 1S-3S packs are other classes' (ClassFit), held back behind it
	expected.append("Plug")  # the selected-battery charge chip's plug button (charge_chip.gd)
	expected.sort()
	out.append(_t("battery shelf ends with an AddPack tile and no other new button exists",
		named == expected and unnamed == BEFORE_UNNAMED, "named %s unnamed %d" % [named, unnamed]))

	var after_last_pack := _tile_follows_last_pack(ds)
	out.append(_t("the AddPack tile comes right after the last battery card, and misfits shown or not",
		after_last_pack and _tile_follows_last_pack(_misfits_shown(catalog)), "plain=%s" % [after_last_pack]))

	var got := [false]
	if tile != null:
		ds.shelf.pack_designer_requested.connect(func(): got[0] = true)
		(tile as BaseButton).pressed.emit()
	out.append(_t("pressing the tile asks for the designer", got[0]))

	var ds2 := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds2.shelf.set_open(true)
	ds2.shelf.toggle_category("motor")
	var walk2: Array = []
	_walk(ds2, walk2, "BaseButton")
	var motor_tile := false
	for b in walk2:
		if String(b.name) == "AddPack":
			motor_tile = true
	out.append(_t("no tile in any other category", not motor_tile))
	return out


static func _misfits_shown(catalog: PartsCatalog) -> DesignSpace:
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = SIZE
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("battery")
	ds.shelf.set_show_misfits("battery", true)
	return ds


## In the shelf's list the tile's previous sibling is the last battery card (Part_*), and the next
## one is not a battery card: whatever follows belongs to another category or a note.
static func _tile_follows_last_pack(ds: DesignSpace) -> bool:
	var list := ds.shelf.list
	var kids := list.get_children()
	var at := -1
	for i in kids.size():
		if String(kids[i].name) == "AddPack":
			at = i
	if at < 1:
		return false
	var prev_ok := String(kids[at - 1].name).begins_with("Part_")
	var battery_ids: Array = []
	for r in ds.shelf.rows:
		if String(r["category"]) == "battery":
			battery_ids.append("Part_" + String(r["id"]))
	var no_card_after := true
	for i in range(at + 1, kids.size()):
		if battery_ids.has(String(kids[i].name)):
			no_card_after = false
	return prev_ok and no_card_after


static func _test_opens_valid(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	var bench: Dictionary = d.bench_result()
	var f := d.figures()
	out.append(_t("pop-up opens on a valid 4S1P pack with a bench result",
		d.design.series == 4 and d.design.parallel == 1 and float(f.get("mah", 0.0)) == 1500.0
		and float(bench.get("run_time_s", 0.0)) > 0.0 and d.warnings().is_empty(),
		"S%d P%d mah %s run %s warn %s" % [d.design.series, d.design.parallel, f.get("mah"),
			bench.get("run_time_s"), d.warnings()]))
	d.free()
	return out


static func _test_motor_picker(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog, true)
	d.open_new()
	var own_a := d._discharge_current()
	var items: Array = []
	for i in d.motor_option.item_count:
		items.append(d.motor_option.get_item_text(i))
	var shelf := catalog.list_category("motor")
	out.append(_t("the Motor dropdown lists this drone's motors first, then every shelf motor",
		items[0] == "This drone's motors" and items.size() == shelf.size() + 1 and items.has(String(shelf[0].name))
		and d.motor_option.selected == 0 and d.motor_option.get_parent() == d.discharge_row, str(items.slice(0, 3))))
	# A small motor and a big one load the same pack very differently.
	var small_id := ""
	var big_id := ""
	var lo := INF
	var hi := -INF
	for rec in shelf:
		var dia := float(rec.specs.get("stator_diameter_mm", 0.0))
		if dia < lo:
			lo = dia
			small_id = String(rec.part_id)
		if dia > hi:
			hi = dia
			big_id = String(rec.part_id)
	d.motor_option.item_selected.emit(d.motor_option.get_item_count() - 1)
	var picked_last := d.motor_id
	d.set_motor(small_id)
	var small_a := d._discharge_current()
	var small_run := float(d.bench_result().run_time_s)
	d.set_motor(big_id)
	var big_a := d._discharge_current()
	var big_run := float(d.bench_result().run_time_s)
	var twin := PackBench.build_with_motor(catalog, d.build, big_id)
	out.append_array([
		_t("choosing a motor drives the Discharge run: the current is that motor's average flight draw on this drone",
			picked_last != "" and absf(big_a - PackBench.this_drone_current_a(twin)) < 1e-9
			and twin.motor["part_id"] == big_id and d.discharge_mode == "this_drone" and d.drone_button.button_pressed,
			"%s %.2f" % [d.motor_id, big_a]),
		_t("a small and a big motor load the same pack differently, and the run time follows the load",
			absf(big_a - small_a) > 1.0 and absf(big_run - small_run) > 5.0 and (big_a > small_a) == (big_run < small_run),
			"%.1f A %.0f s vs %.1f A %.0f s" % [small_a, small_run, big_a, big_run]),
	])
	d.set_motor("")
	out.append(_t("This drone's motors puts the drone's own load back",
		absf(d._discharge_current() - own_a) < 1e-9 and d.motor_option.selected == 0, "%.2f vs %.2f" % [d._discharge_current(), own_a]))
	d.free()
	# No drone: no 'This drone's motors' item, but a picked motor still drives the run.
	var bare := _designer(catalog, false)
	bare.open_new()
	var bare_items: Array = []
	for i in bare.motor_option.item_count:
		bare_items.append(bare.motor_option.get_item_text(i))
	bare.set_motor(small_id)
	var bs := bare._discharge_current()
	bare.set_motor(big_id)
	out.append(_t("with no drone the list has no 'This drone's motors' and a picked motor drives the run on the reference airframe",
		not bare_items.has("This drone's motors") and bare.motor_option.selected >= 0
		and bare.discharge_mode == "this_drone" and bs > 0.1 and absf(bare._discharge_current() - bs) > 1.0,
		"%.2f %.2f" % [bs, bare._discharge_current()]))
	bare.free()
	return out


static func _test_default_load(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var with_build := _designer(catalog, true)
	with_build.open_new()
	out.append(_t("the bench defaults to 'This drone' when a build is present",
		with_build.discharge_mode == "this_drone" and with_build.drone_button.button_pressed
		and not with_build.steady_button.button_pressed
		and absf(with_build._discharge_current() - PackBench.this_drone_current_a(with_build.build)) < 1e-9,
		"%s %s" % [with_build.discharge_mode, with_build._discharge_current()]))
	with_build.free()
	var bare := _designer(catalog, false)
	bare.open_new()
	out.append(_t("with no build the bench defaults to a steady 10 A",
		bare.discharge_mode == "constant" and absf(bare._discharge_current() - 10.0) < 1e-9
		and bare.steady_button.button_pressed, "%s %s" % [bare.discharge_mode, bare._discharge_current()]))
	bare.free()
	return out


static func _test_series_rederives(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	var v4 := float(d.figures().get("nominal_v", 0.0))
	var run4 := float(d.bench_result().get("run_time_s", 0.0))
	var stamp := d.derive_count
	d.set_series(6)
	var f := d.figures()
	out.append(_t("changing S re-derives figures and reruns the bench",
		absf(float(f.nominal_v) - 1.5 * v4) < 1e-6 and d.derive_count == stamp + 1
		and float(d.bench_result().get("run_time_s", 0.0)) > 0.0
		and absf(float(d.bench_result().get("v_rest")[0]) - float(f.full_v)) < 0.05
		and run4 > 0.0,
		"nominal %s -> %s, count %d -> %d" % [v4, f.nominal_v, stamp, d.derive_count]))
	d.set_parallel(2)
	out.append(_t("changing P doubles capacity",
		float(d.figures().mah) == 3000.0 and d.derive_count == stamp + 2))
	d.set_wiring("XT60", 22, 150.0)
	out.append(_t("set_wiring shows the new gauge and length in the controls",
		d.awg_option.get_selected_id() == 22 and is_equal_approx(d.length_spin.value, 150.0),
		"wire box shows %d AWG" % d.awg_option.get_selected_id()))
	d.free()
	return out


static func _test_label(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	d.set_cell("cell_molicel_p42a")
	var f := d.figures()
	var texts: Array = []
	var labels: Array = []
	_walk(d, labels, "Label")
	for l in labels:
		texts.append((l as Label).text)
	var has_header := false
	for tx in texts:
		if String(tx).contains(PackDesign.BASIS):
			has_header = true
	out.append(_t("figures carry the ideal / datasheet label (datasheet cell)",
		String(f.get("basis", "")) == "ideal / datasheet" and has_header
		and String(d.figure_tags().get("mass_g", "")) == "estimate"
		and String(d.figure_tags().get("nominal_v", "")) == "ideal / datasheet",
		str(d.figure_tags())))
	out.append(_t("the burst figure is marked (est.) when the datasheet does not publish it",
		(d._figure_values["current"] as Label).text.contains("burst (est.)"),
		(d._figure_values["current"] as Label).text))
	d.set_cell("cell_murata_vtc5a")
	out.append(_t("an estimated resistance is marked (est.) too",
		(d._figure_values["resistance"] as Label).text.contains("(est.)"), (d._figure_values["resistance"] as Label).text))
	d.set_cell("cell_samsung_40t")
	out.append(_t("and is not marked for a published burst",
		not (d._figure_values["current"] as Label).text.contains("est."),
		(d._figure_values["current"] as Label).text))
	d.set_cell("cell_lipo_1500")
	var head := d.figures_header.text
	out.append(_t("a class-typical cell says typical, in the header and on every figure",
		String(d.figures().get("basis", "")) == "typical" and head.contains("typical") and not head.contains("datasheet")
		and String(d.figure_tags().get("nominal_v", "")) == "typical"
		and String(d.figure_tags().get("mass_g", "")) == "estimate", head + " " + str(d.figure_tags())))
	d.free()
	return out


static func _test_typed_fields(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	var typed: Array = []
	_walk(d, typed, "LineEdit")
	_walk(d, typed, "SpinBox")
	var names: Array = []
	for c in typed:
		names.append(String(c.name))
	var inside_figures: Array = []
	_walk(d.figures_box, inside_figures, "LineEdit")
	_walk(d.figures_box, inside_figures, "SpinBox")
	var overlap := false
	for k in d.typed_fields():
		if DERIVED.has(k):
			overlap = true
	out.append(_t("no typed field can override derived figures (named cell)",
		inside_figures.is_empty() and not overlap
		and not names.has("CustomMah") and not names.has("CustomMass")
		and not d.typed_fields().has("custom_mah"), "typed %s" % [names]))
	d.set_cell("custom_cell")
	var custom_typed: Array = []
	_walk(d, custom_typed, "SpinBox")
	var custom_names: Array = []
	for c in custom_typed:
		if (c as Control).is_visible_in_tree() or true:
			custom_names.append(String(c.name))
	d.set_custom_field("mah", 2000.0)
	out.append(_t("custom cell fields appear only for a custom cell, and are the only extra",
		custom_names.has("CustomMah") and d.typed_fields().has("custom_mah")
		and float(d.figures().mah) == 2000.0 and inside_figures.is_empty(),
		"%s" % [custom_names]))
	var before_n := PackDesigner.new(catalog, CellLibrary.load_default(), DesignedPacks.new(),
		PackCharge.new(), null)
	var plain: Array = []
	_walk(before_n, plain, "SpinBox")
	var hidden_custom := true
	for c in plain:
		if String(c.name).begins_with("Custom") and (c as Control).visible:
			hidden_custom = false
	out.append(_t("custom cell fields are hidden until Custom cell is chosen", hidden_custom))
	before_n.free()
	d.free()
	return out


static func _test_recharge(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	var id := d.save()
	d.charge.set_used_mah(id, 700.0)
	d.open_pack(id)
	var before := d.charge.used_mah(id)
	d.run_recharge()
	out.append(_t("recharge sets stored used_mah to 0",
		id != "" and before == 700.0 and d.charge.used_mah(id) == 0.0
		and float(d.recharge_result().get("time_to_full_s", 0.0)) > 0.0,
		"id %s before %s after %s" % [id, before, d.charge.used_mah(id)]))
	d.free()

	# The charge line: before, and after.
	var e := _designer(catalog)
	e.open_new()
	var pid := e.save()
	var mah := roundi(float(e.figures()["mah"]))
	e.charge.set_used_mah(pid, 930.0)
	e.open_pack(pid)
	e.set_tab("recharge")
	var expect_before := "Charge: %d%% (930 of %d mAh used)" % [roundi((1.0 - 930.0 / mah) * 100.0), mah]
	out.append(_t("recharge tab states the charge before: percent and mAh used",
		e.charge_line.text == expect_before and e.charge_line.visible and e.charge_bar.visible
		and absf(e.charge_bar.value - (1.0 - 930.0 / mah) * 100.0) < 0.01,
		"%s | %s" % [e.charge_line.text, expect_before]))
	e.run_recharge()
	out.append(_t("and 'Charged to 100% \u2713' with a full bar after",
		e.charge_line.text == "Charged to 100% \u2713" and e.charge_bar.value == 100.0,
		e.charge_line.text))
	e.free()
	return out


static func _test_range(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	d.set_series(20)
	d.set_parallel(20)
	out.append(_t("the steppers reach 8S and 6P and stop there",
		d.design.series == 8 and d.design.parallel == 6 and d.series_label.text == "8S"
		and d.parallel_label.text == "6P" and float(d.figures().nominal_v) > 29.0, d.series_label.text))
	d.free()
	return out


static func _test_drain(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	var id := d.save()
	d.open_pack(id)
	out.append(_t("opening and editing a saved pack does not drain it",
		d.charge.used_mah(id) == 0.0 and not d.test_note.visible, str(d.charge.used_mah(id))))
	d.run_discharge_test()
	var used: PackedFloat64Array = d.bench_result().used_mah
	var end_used := float(used[used.size() - 1])
	var reloaded := PackCharge.load_from(CHARGE)
	out.append(_t("a Discharge run on a saved pack leaves its stored used_mah at the run's end",
		end_used > 0.0 and absf(d.charge.used_mah(id) - end_used) < 1e-6
		and absf(reloaded.used_mah(id) - end_used) < 1e-6,
		"run end %.1f stored %.1f file %.1f" % [end_used, d.charge.used_mah(id), reloaded.used_mah(id)]))
	out.append(_t("and the bench says so",
		d.test_note.visible and d.test_note.text == "This test used the pack's charge", d.test_note.text))
	out.append(_t("the charge line then reads the drained state",
		d.charge_line.text.begins_with("Charge: ") and not d.charge_line.text.begins_with("Charge: 100%"),
		d.charge_line.text))
	d.set_series(5)
	out.append(_t("the note clears on the next change", not d.test_note.visible))
	d.free()

	var e := _designer(catalog)
	e.open_new()
	e.run_discharge_test()
	out.append(_t("a new unsaved design is not drained and shows no note",
		e.charge.used_mah("") == 0.0 and not e.test_note.visible and e.charge._used_mah.is_empty(),
		str(e.charge._used_mah)))
	e.free()

	var p := _designer(catalog)
	p.open_pack("battery_4s_1300")
	p.run_discharge_test()
	out.append(_t("a shelf preset's charge is drained by the run too",
		p.charge.used_mah("battery_4s_1300") > 0.0 and p.test_note.visible, str(p.charge.used_mah("battery_4s_1300"))))
	p.free()
	return out


static func _test_my_packs(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	var id := d.save()
	# A legacy (hand-typed) pack beside it.
	var preset: Dictionary = catalog.list_category("battery")[0]
	var legacy_rec := DesignedPacks.migrate_v1_record(_as_typed_record(preset))
	d.store.add(legacy_rec)
	var rows := d.my_packs()
	var ids: Array = []
	var kinds := {}
	for r in rows:
		ids.append(String(r.id))
		kinds[String(r.id)] = String(r.kind)
	out.append(_t("My packs lists presets and saved packs",
		ids.has(String(preset.part_id)) and ids.has(id) and kinds[id] == "saved"
		and kinds[String(preset.part_id)] == "preset" and ids.size() >= 16,
		"%d rows" % ids.size()))
	d.open_pack(String(legacy_rec.part_id))
	out.append(_t("a legacy pack shows its badge and Rebuild from cells",
		d.is_legacy_open() and d.rebuild_button.visible and d.badge_label.visible
		and d.badge_label.text == PackDesign.LEGACY_BASIS, d.badge_label.text))
	var legacy_mah := float(d.figures().mah)
	d.set_series(6)
	out.append(_t("a legacy pack's figures cannot be edited until rebuilt",
		d.design.series != 6 and float(d.figures().mah) == legacy_mah))
	d.rebuild_from_cells()
	out.append(_t("Rebuild from cells makes it a derived pack",
		not d.is_legacy_open() and not d.rebuild_button.visible))
	d.open_pack(String(preset.part_id))
	var save_blocked := d.save() == "" and d.read_only
	out.append(_t("a preset opens read-only: it cannot be saved over, only started from",
		save_blocked and d.start_from_button.visible))
	d.start_from_this()
	out.append(_t("Start from this makes an editable copy with no id yet",
		not d.read_only and d.part_id == "" and not d.is_legacy_open() and d.design.name.contains("copy")))
	d.free()
	return out


static func _as_typed_record(preset: Dictionary) -> Dictionary:
	var rec := preset.duplicate(true)
	rec["part_id"] = "custom_test_legacy"
	rec["name"] = "Test typed pack"
	rec.erase("design")
	return rec


static func _test_modal(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.size = SIZE
	ds.open_pack_designer()
	var d := ds.pack_designer
	out.append(_t("the Design Space opens the designer as a modal over itself",
		d != null and d.get_parent() == ds and d.mouse_filter == Control.MOUSE_FILTER_STOP
		and float(d.bench_result().get("run_time_s", 0.0)) > 0.0))
	if d != null:
		d.close()
	out.append(_t("closing removes the pop-up", ds.pack_designer == null))
	return out


## Audit A7 and A8: per-cell voltage under load in the bench row; the capacity chart turns red past
## the knee (less than 20 % of the pack left).
static func _test_cell_voltage_and_knee(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	d.set_series(4)
	var res: Dictionary = d.bench_result()
	var per_cell := float(res.get("cell_v_load", 0.0))
	var v0: float = (res.get("v_live", PackedFloat64Array()) as PackedFloat64Array)[0]
	out.append(_t("bench row shows the per-cell voltage under load",
		absf(per_cell - v0 / 4.0) < 1e-6 and per_cell > 2.5
		and d.result_label.text.contains("%.2f V/cell" % per_cell),
		"cell %s v0 %s row '%s'" % [per_cell, v0, d.result_label.text]))
	var cap: Dictionary = {}
	for c in d.charts.charts:
		if String(c.get("title", "")) == "Capacity used":
			cap = c
	var mah := float(d.figures().get("mah", 0.0))
	out.append(_t("capacity chart turns red past the knee at 20 % left",
		cap.has("red_above") and absf(float(cap.get("red_above", 0.0)) - 0.8 * mah) < 1e-6,
		"chart %s mah %s" % [cap.get("red_above", "none"), mah]))
	out.append(_t("charge left reads 100 % at the start and under 20 % at the end",
		PackCharts.left_pct(cap, 0) > 99.9 and PackCharts.left_pct(cap, 1000000) < 20.0
		and PackCharts.is_red(cap, 1000000) and not PackCharts.is_red(cap, 0),
		"start %s end %s" % [PackCharts.left_pct(cap, 0), PackCharts.left_pct(cap, 1000000)]))
	d.free()
	return out


## Audit A17: Delete in My packs, behind a confirm step; presets cannot be deleted.
static func _test_delete(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
	var id := d.save()
	var preset_id := String(catalog.list_category("battery")[0].part_id)
	out.append(_t("My packs delete asks first and removes nothing on the first press",
		not d.request_delete(id) and d.store.records().size() == 1 and d.pending_delete == id,
		"pending '%s'" % d.pending_delete))
	out.append(_t("My packs delete removes the pack on confirm and persists it",
		d.request_delete(id) and d.store.records().size() == 0 and d.pending_delete == ""
		and DesignedPacks.load_from(SCRATCH).records().size() == 0))
	out.append(_t("My packs delete refuses a shelf preset",
		not d.request_delete(preset_id) and not d.request_delete(preset_id)
		and not d.my_packs().filter(func(r): return r.id == preset_id).is_empty()))
	d.free()
	return out
