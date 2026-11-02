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
	"Chip_cells_n6", "Home", "LabelsToggle", "ShelfHeader", "mark_auw_g", "mark_flight_time_min",
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
	results.append_array(_test_series_rederives(catalog))
	results.append_array(_test_label(catalog))
	results.append_array(_test_typed_fields(catalog))
	results.append_array(_test_recharge(catalog))
	results.append_array(_test_my_packs(catalog))
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
	d.free()
	return out


static func _test_label(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var d := _designer(catalog)
	d.open_new()
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
	out.append(_t("figures carry the ideal / datasheet label",
		String(f.get("basis", "")) == "ideal / datasheet" and has_header
		and String(d.figure_tags().get("mass_g", "")) == "estimate"
		and String(d.figure_tags().get("nominal_v", "")) == "ideal / datasheet",
		str(d.figure_tags())))
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
