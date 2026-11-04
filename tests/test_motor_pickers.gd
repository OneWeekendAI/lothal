class_name TestMotorPickers
extends RefCounted
## Motor Designer M6b: the Pack and Prop dropdowns on the bench, the "Limited by" line, the
## monochrome palette, and the Design-a-pack round trip.
##
## Each check was shown to fail under a mutation:
## - swap reruns: drop the _rederive() call in set_pack / set_prop (figures and result stay put).
## - weaker pack lowers rpm: ignore bench_parts.battery in MotorBench.make_build.
## - limited-by follows the inputs: hard-code the key in MotorBench.limited_from, or read only one ratio.
## - lists: leave designed packs / generator props out of _fill_pickers, or drop the last item.
## - round trip: do not call select_pack from DesignSpace._design_pack_for_motor.
## - view follows prop: pass the class-typical prop (not prop_pick_id()) to show_motor.
## - compare: drop y2 from the sweep charts, run the compare on the default pack, or draw one legend item.
## - palette: take mono_theme() out of MotorDesigner._init, or colour chart lines ACCENT.

const SCRATCH := "user://test_motor_pickers_scratch.json"
const CHARGE := "user://test_motor_pickers_charge.json"


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _items(o: OptionButton) -> Array:
	var out: Array = []
	for i in o.item_count:
		out.append(o.get_item_text(i))
	return out


static func _index_of(o: OptionButton, id: String) -> int:
	for i in o.item_count:
		if String(o.get_item_metadata(i)) == id:
			return i
	return -1


static func _selected_id(o: OptionButton) -> String:
	return String(o.get_item_metadata(o.selected))


static func run() -> Array:
	var out: Array = []
	var cfg := MotorConfigs.load_default()
	var shipped := PartsCatalog.load_default()

	# A catalog with one designed pack (3x the resistance of the reference pack) and one designed prop.
	var catalog := PartsCatalog.new()
	catalog.by_id = shipped.by_id.duplicate()
	catalog.by_category = shipped.by_category.duplicate()
	var weak := shipped.get_part(ReferenceBuild.BATTERY_ID).duplicate(true)
	weak["part_id"] = "custom_weak_pack"
	weak["name"] = "Weak pack"
	weak["specs"]["internal_r_ohm"] = float(weak["specs"]["internal_r_ohm"]) * 3.0
	catalog.by_id["custom_weak_pack"] = weak
	catalog.by_category["battery"] = (catalog.by_category["battery"] as Array).duplicate()
	catalog.by_category["battery"].append(weak)
	var blade := shipped.get_part(ReferenceBuild.PROPELLER_ID).duplicate(true)
	blade["part_id"] = "custom_blade_prop"
	blade["name"] = "Blade generator prop"
	catalog.by_id["custom_blade_prop"] = blade
	catalog.by_category["propeller"] = (catalog.by_category["propeller"] as Array).duplicate()
	catalog.by_category["propeller"].append(blade)

	var d := MotorDesigner.new(cfg, catalog)
	d.size = Vector2(1280, 720)
	d.set_bench_build(null)

	# The row: two plain dropdowns at the top of the bench.
	var pickers := d.find_child("Pickers", true, false)
	var packs := _items(d.pack_option)
	var props := _items(d.prop_option)
	out.append(_t("the bench opens with one row of two dropdowns, Pack and Prop",
		pickers != null and pickers.get_parent() == d.bench_box.get_child(0)
		and pickers.get_index() == 0 and pickers is HBoxContainer
		and d.pack_option.get_parent().get_parent() == pickers
		and d.prop_option.get_parent().get_parent() == pickers, ""))
	out.append(_t("Pack lists this drone's pack first, shelf packs, then designed packs, and ends with Design a pack…",
		packs[0] == "This drone's pack" and packs[packs.size() - 1] == "Design a pack…"
		and packs.has("Weak pack") and packs.find("Weak pack") > packs.find("1S 300mAh 30C")
		and packs.find("Weak pack") < packs.size() - 1, str(packs)))
	out.append(_t("Prop lists shelf props and blade-generator props",
		props.has("Blade generator prop") and props.size() > 5 and props.find("Blade generator prop") == props.size() - 1,
		str(props)))

	# Swap -> rerun at once.
	d.set_bench("punch")
	var base := d.bench_result()
	var n0 := d.derive_count
	var before_text := d.bench_result_label.text
	d.set_pack("custom_weak_pack")
	out.append(_t("choosing a pack reruns the bench and figures at once (result line, run and derive count change)",
		d.derive_count > n0 and d.bench_result_label.text != before_text
		and d.bench_result_label.text == String(d.bench_result().result)
		and _selected_id(d.pack_option) == "custom_weak_pack", before_text + " -> " + d.bench_result_label.text))
	out.append(_t("a weaker (3x resistance) pack lowers punch-out rpm and pack voltage",
		float(d.bench_result().end_rpm) < float(base.end_rpm) - 100.0
		and float(d.bench_result().low_v) < float(base.low_v),
		"rpm %.0f vs %.0f" % [d.bench_result().end_rpm, base.end_rpm]))
	var n1 := d.derive_count
	var prop_before := String(d.bench_result_label.text)
	var seen := d.bench_result()
	d.set_prop("prop_6x4x2")
	out.append(_t("choosing a prop reruns the bench and figures at once and loads the motor differently",
		d.derive_count > n1 and _selected_id(d.prop_option) == "prop_6x4x2"
		and d.bench_result_label.text != prop_before and float(d.bench_result().end_rpm) != float(seen.end_rpm),
		prop_before + " -> " + d.bench_result_label.text))
	# The middle 3D view and its caption follow the Prop picker.
	d.set_prop("prop_7x4x3")
	var r7 := d.motor_view.prop.radius_m
	var cap7 := (d.find_child("PropNote", true, false) as Label).text
	var blades7 := d.motor_view.prop.blade_count
	d.set_prop("prop_6x4x2")
	var r6 := d.motor_view.prop.radius_m
	var cap6 := (d.find_child("PropNote", true, false) as Label).text
	out.append(_t("the middle view draws the picked prop (7x4x3 vs 6x4x2: radius, blades) and the caption names it",
		absf(r7 - 3.5 * 0.0254) < 1e-3 and absf(r6 - 3.0 * 0.0254) < 1e-3 and blades7 == 3
		and d.motor_view.prop.blade_count == 2 and d.prop_id == "prop_6x4x2"
		and cap7.contains(String(d.catalog.get_part("prop_7x4x3").name)) and cap6.contains(String(d.catalog.get_part("prop_6x4x2").name)) and cap7 != cap6,
		"%s | %s | %.4f %.4f" % [cap7, cap6, r7, r6]))

	# Compare with…: a second line on the throttle sweep, a two-item legend, nothing else.
	d.set_pack(MotorDesigner.DRONE_PACK)
	d.set_prop(ReferenceBuild.PROPELLER_ID)
	d.set_bench("sweep")
	var cmp_items := _items(d.compare_option)
	var plain: Dictionary = d.charts.charts[0]
	out.append(_t("Compare with… lists None first, then the shelf motors, with no line yet drawn",
		cmp_items[0] == "None" and cmp_items.size() > 10 and not plain.has("y2") and not plain.has("legend")
		and d.compare_result().is_empty(), str(cmp_items.slice(0, 3))))
	var other_id := ""
	for i in d.compare_option.item_count:
		if String(d.compare_option.get_item_text(i)).contains("2306"):
			other_id = String(d.compare_option.get_item_metadata(i))
			break
	d.compare_option.item_selected.emit(_index_of(d.compare_option, other_id))
	var two: Dictionary = d.charts.charts[0]
	var leg: Array = two.get("legend", [])
	out.append(_t("choosing a motor draws two lines on the sweep (this one and the other, same pack and prop) with a two-item legend",
		other_id != "" and d.compare_id == other_id and two.has("y2") and (two.y2 as PackedFloat64Array).size() == (two.y as PackedFloat64Array).size()
		and leg.size() == 2 and leg[0].name == d.design.display_name() and leg[1].name == d.compare_name()
		and d.charts.charts.size() == 3 and leg[0].color != leg[1].color, str(leg)))
	var other_run := MotorBench.run("sweep", MotorDesign.from_record(d.catalog.get_part(other_id), cfg), cfg, d.bench_parts, {}, d.catalog)
	out.append(_t("the other line is that motor's own sweep on the same pack and prop, and it differs from this motor's",
		(two.y2 as PackedFloat64Array) == (other_run.thrust_g as PackedFloat64Array)
		and absf(float((two.y2 as PackedFloat64Array)[40]) - float((two.y as PackedFloat64Array)[40])) > 50.0, ""))
	d.set_pack("custom_weak_pack")
	var weak_two: Dictionary = d.charts.charts[0]
	out.append(_t("swapping the pack reruns both lines on the new pack",
		float((weak_two.y2 as PackedFloat64Array)[40]) < float((two.y2 as PackedFloat64Array)[40]) - 20.0
		and float((weak_two.y as PackedFloat64Array)[40]) < float((two.y as PackedFloat64Array)[40]) - 20.0, ""))
	d.set_pack(MotorDesigner.DRONE_PACK)
	d.set_bench("punch")
	out.append(_t("the other tabs stay single-line and hide the compare row (compare is the sweep's)",
		not d.charts.charts[0].has("y2") and d.charts.charts.size() == 2 and not d.compare_row.visible, ""))
	d.set_bench("sweep")
	d.set_compare("")
	out.append(_t("the compare dropdown sits in its own row, shown on the sweep tab only",
		d.compare_row.visible and d.compare_option.get_parent().get_parent() == d.compare_row
		and d.compare_row.get_parent() == d.bench_box.get_child(0), ""))
	out.append(_t("choosing None puts the single line back",
		not d.charts.charts[0].has("y2") and not d.charts.charts[0].has("legend") and d.compare_result().is_empty(), ""))
	d.set_bench("punch")

	d.set_pack(MotorDesigner.DRONE_PACK)
	d.set_prop(ReferenceBuild.PROPELLER_ID)
	out.append(_t("This drone's pack goes back to the drone's own (the first run's result returns)",
		d.bench_result_label.text == before_text and _selected_id(d.pack_option) == MotorDesigner.DRONE_PACK, ""))

	# Limited by: computed from the inputs, one short sentence, three different answers. Since the
	# thermal refit (2026-11-04) the 2207 on the drone's own pack is heat-limited (130 C punch), so
	# the pack answer is read on a small 4S 650.
	var default_key := d.limited_by_key()
	var text0 := d.limited_by_text()
	d.set_pack("battery_4s_650")
	var key_small := d.limited_by_key()
	var text_over := d.limited_by_text()
	var ratio_over: Dictionary = d._limited.ratios
	d.set_pack(MotorDesigner.DRONE_PACK)
	d.set_stator("3115")
	var key_big := d.limited_by_key()
	out.append(_t("Limited by: names motor heat on the drone's pack, pack current on a small pack, prop load with a big stator",
		default_key == "motor" and key_small == "pack" and key_big == "prop", "%s %s %s" % [default_key, key_small, key_big]))
	out.append(_t("the line is one short sentence beginning 'Limited by:' and shows on screen under the chart",
		text0.begins_with("Limited by: motor heat") and text0.count(". ") == 0 and text0.ends_with(".")
		and text0.split(" ", false).size() <= 9 and d.limited_label.text == d.limited_by_text(), text0))
	d.set_stator("2207")
	out.append(_t("a pack that is over its rating says so with the numbers",
		float(ratio_over.pack) > 1.0 and text_over.begins_with("Limited by: pack current, ") and text_over.contains(" A of "), text_over))

	# Design a pack round trip.
	var asked := [0]
	d.design_pack_requested.connect(func(): asked[0] += 1)
	d.pack_option.item_selected.emit(d.pack_option.item_count - 1)
	out.append(_t("choosing Design a pack… asks the host to open the pack designer (once) and keeps the old pack shown",
		asked[0] == 1 and _selected_id(d.pack_option) == MotorDesigner.DRONE_PACK, str(asked)))
	d.select_pack("custom_weak_pack")
	out.append(_t("select_pack puts a returning pack on the bench",
		d.pack_id() == "custom_weak_pack" and _selected_id(d.pack_option) == "custom_weak_pack", d.pack_id()))

	# Palette.
	out.append_array(_palette(d))
	d.free()

	out.append_array(_round_trip(shipped))
	return out


static func _palette(d: MotorDesigner) -> Array:
	var out: Array = []
	var accent := LothalTheme.ACCENT
	var bad := ""
	var t := d.theme
	for cls in t.get_type_list():
		for n in t.get_stylebox_list(cls):
			var sb := t.get_stylebox(n, cls)
			if sb is StyleBoxFlat:
				for c in [(sb as StyleBoxFlat).bg_color, (sb as StyleBoxFlat).border_color]:
					if absf(c.r - accent.r) < 0.02 and absf(c.g - accent.g) < 0.02 and absf(c.b - accent.b) < 0.02:
						bad += " %s/%s" % [cls, n]
		for n in t.get_color_list(cls):
			var c2 := t.get_color(n, cls)
			if absf(c2.r - accent.r) < 0.02 and absf(c2.g - accent.g) < 0.02 and absf(c2.b - accent.b) < 0.02:
				bad += " %s/%s" % [cls, n]
	out.append(_t("the designer's theme has no blue left (selected tab, chips, focus, menu highlight)", bad == "", bad))
	var pressed := t.get_color("font_pressed_color", "Button")
	out.append(_t("a selected tab reads as ink, not a hue", is_equal_approx(pressed.r, pressed.g) and is_equal_approx(pressed.g, pressed.b), str(pressed)))
	var coloured := ""
	for kind in MotorBench.KINDS:
		d.set_bench(kind)
		for c in d.charts.charts:
			var col: Color = c.color
			if not is_equal_approx(col.r, col.g) or not is_equal_approx(col.g, col.b):
				if col != LothalTheme.WARNING:
					coloured += " %s:%s" % [kind, col]
	out.append(_t("chart lines are ink; the only colour any of them takes is the warning amber", coloured == "", coloured))
	d.set_stator("0802")
	d.set_bench("punch")
	var amber := false
	for c in d.charts.charts:
		amber = amber or c.color == LothalTheme.WARNING
	out.append(_t("a line a warning is about turns amber (0802 punch-out heat)", amber and not d.bench_warnings().is_empty(), str(d.bench_warnings())))
	d.set_stator("2207")
	return out


## DesignSpace -> motor designer -> Design a pack… -> pack designer -> save -> back selected.
static func _round_trip(shipped: PartsCatalog) -> Array:
	var out: Array = []
	_wipe(SCRATCH)
	_wipe(CHARGE)
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), shipped)
	ds.size = Vector2(1280, 720)
	ds.custom_parts_path = SCRATCH
	ds.pack_charge_path = CHARGE
	ds.open_motor_designer()
	var md := ds.motor_designer
	var before_ids := _items(md.pack_option)
	md.pack_option.item_selected.emit(md.pack_option.item_count - 1)
	out.append(_t("Design a pack… opens the pack designer over the Design Space", ds.pack_designer != null and ds.pack_designer.get_parent() == ds, ""))
	if ds.pack_designer != null:
		ds.pack_designer.name_field.text = "Round trip pack"
		var id := ds.pack_designer.save()
		out.append(_t("the pack saves", id != "", id))
		out.append(_t("back on the motor designer the new pack is in the list, selected, and the bench runs on it",
			md.pack_id() == id and _selected_id(md.pack_option) == id
			and _items(md.pack_option).size() == before_ids.size() + 1 and _items(md.pack_option).has("Round trip pack")
			and md.bench_result_label.text == String(md.bench_result().result), md.pack_id()))
		out.append(_t("the motor designer's own catalog knows the new pack (the bench really ran on it)",
			md.catalog.get_part(id).size() > 0 and md.bench_parts.battery == id, ""))
		ds.pack_designer.close()
	ds.free()
	_wipe(SCRATCH)
	_wipe(CHARGE)
	return out
