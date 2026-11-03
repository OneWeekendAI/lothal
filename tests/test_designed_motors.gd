class_name TestDesignedMotors
extends RefCounted
## M7: saving designed motors to custom_parts.json (schema 3), the lossless migration of the
## hand-typed motors already in a real file, the shelf showing a saved motor, and the drone flying it.
##
## The fixture is a copy of a real schema-2 custom_parts.json (one designed pack, two hand-typed
## motors, an empty frames block), with only the owner's name changed.
## Every save goes through the Design Space and the designer's own buttons, so a missing
## refresh_catalog wiring fails "appears on the shelf".

const FIXTURE := "res://tests/fixtures/custom_parts_v2_current.json"
const SCRATCH := "user://test_designed_motors_scratch.json"
const TYPED_IDS := ["custom_5_freestyle_shed", "custom_beast_2207"]


static func _t(name: String, ok: bool, detail: String = "") -> TestResult:
	return TestResult.new(name, ok, detail)


static func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _stage() -> void:
	_wipe(SCRATCH)
	var h := FileAccess.open(SCRATCH, FileAccess.WRITE)
	h.store_string(FileAccess.get_file_as_string(FIXTURE))
	h.close()


static func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


static func _written() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SCRATCH))


static func _same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)


## Figures equal to ~12 significant digits (JSON text keeps ~14).
static func _figs_close(a: Dictionary, b: Dictionary) -> String:
	var bad := ""
	if a.size() != b.size():
		bad += " size %d/%d" % [a.size(), b.size()]
	for k in a:
		if not b.has(k):
			bad += " missing " + String(k)
		elif a[k] is float or a[k] is int:
			var x := float(a[k])
			var y := float(b[k])
			if absf(x - y) > 1e-9 * maxf(absf(x), 1.0):
				bad += " %s %s/%s" % [k, x, y]
		elif str(a[k]) != str(b[k]):
			bad += " %s %s/%s" % [k, a[k], b[k]]
	return bad


static func _build(catalog: PartsCatalog, motor_id: String) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, motor_id, ReferenceBuild.PROPELLER_ID,
		ReferenceBuild.BATTERY_ID)


static func run() -> Array:
	var results: Array = []
	results.append_array(_migration())
	results.append_array(_save_reload_shelf_drone())
	_wipe(SCRATCH)
	return results


static func _migration() -> Array:
	var out: Array = []
	_stage()
	var raw := _raw()
	var before := FileAccess.get_file_as_string(SCRATCH)
	var catalog := PartsCatalog.load_with_custom(SCRATCH)
	var motors := CustomMotors.load_from(SCRATCH)
	var bad := ""
	for want in raw.motors:
		var got := motors.get_record(String(want.part_id))
		if got.is_empty():
			bad += " missing " + String(want.part_id)
			continue
		for k in want:
			if not _same(got[k], want[k]):
				bad += " %s.%s" % [want.part_id, k]
		var block: Dictionary = got.get("design", {})
		if not bool(block.get("legacy", false)) or String(block.get("basis", "")) != CustomMotors.LEGACY_BASIS:
			bad += " %s not legacy" % want.part_id
	out.append(_t("schema-2 file: every hand-typed motor loads with every field identical, marked legacy",
		bad == "" and motors.rejections().is_empty() and motors.records().size() == 2, bad + str(motors.rejections())))
	out.append(_t("and the merged catalog still flies them (typed thrust and specs, not redesigned)",
		_same(catalog.get_part(TYPED_IDS[1]).specs, raw.motors[1].specs)
		and _build(catalog, TYPED_IDS[1]) != null, ""))
	var packs := DesignedPacks.load_from(SCRATCH)
	out.append(_t("the designed pack in the same file loads unchanged",
		packs.records().size() == 1 and _same(packs.records()[0], raw.batteries[0]), ""))
	out.append(_t("loading does not rewrite the file; CustomParts is at schema 3",
		FileAccess.get_file_as_string(SCRATCH) == before and CustomParts.SCHEMA_VERSION == 3, ""))
	return out


static func _save_reload_shelf_drone() -> Array:
	var out: Array = []
	_stage()
	var raw := _raw()
	var cfg := MotorConfigs.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), PartsCatalog.load_default())
	ds.size = Vector2(1280, 720)
	ds.custom_parts_path = SCRATCH
	ds.shelf.set_open(true)
	ds.shelf.toggle_category("motor")
	ds.open_motor_designer()
	var d := ds.motor_designer
	var save_btn := d.find_child("Save", true, false) as Button
	out.append(_t("the Save button is enabled", save_btn != null and not save_btn.disabled))

	# Hill climber: 2207, 2400 KV, 9N12P, N52H, 5 mm shaft. Saved with the Save button.
	d.set_kv(2400.0)
	d.set_poles(12)
	d.set_magnet("N52H")
	d.set_shaft(5.0)
	d.name_field.text = "Hill climber"
	var figs_before := d.design.derive(cfg)
	save_btn.pressed.emit()
	var id := d.part_id
	var w := _written()
	var rec: Dictionary = {}
	for r in w.motors:
		if String(r.part_id) == id:
			rec = r
	out.append(_t("Save stores a designer record: choices, derived figures, a thrust test, at schema 3",
		id == "custom_hill_climber" and int(w.schema) == 3 and not rec.is_empty()
		and String(rec.design.size) == "2207" and float(rec.design.kv) == 2400.0
		and int(rec.design.poles) == 12 and String(rec.design.magnet) == "N52H"
		and float(rec.design.shaft_mm) == 5.0 and String(rec.mount_pattern) == "16x16"
		and rec.has("figures") and rec.has("thrust_test") and float(rec.specs.max_thrust_g) > 0.0,
		"%s %s" % [id, str(rec.get("design", {}))]))

	var kept := ""
	for want in raw.motors:
		var got: Dictionary = {}
		for r in w.motors:
			if String(r.part_id) == String(want.part_id):
				got = r
		for k in want:
			if got.is_empty() or not _same(got.get(k), want[k]):
				kept += " %s.%s" % [want.part_id, k]
	out.append(_t("saving keeps everything else: both typed motors, the pack, the frames block",
		kept == "" and _same(w.get("batteries"), raw.batteries) and w.has("frames") and w.motors.size() == 3,
		kept))

	# Reload from disk: identical figures and choices.
	var reloaded := CustomMotors.load_from(SCRATCH).get_record(id)
	var again := MotorDesign.from_record(reloaded, cfg)
	var bad := _figs_close(figs_before, again.derive(cfg)) + _figs_close(figs_before, reloaded.figures as Dictionary)
	out.append(_t("save -> reload -> identical figures (derived again and as stored) and choices",
		bad == "" and again.name == "Hill climber" and again.poles == 12 and again.magnet == "N52H"
		and again.shaft_mm == 5.0 and again.kv == 2400.0, bad))

	# The shelf shows it: its name and one key spec.
	var row := ds.shelf.row_of(id)
	var card: Control = row.get("button") if not row.is_empty() else null
	var name_l := card.find_child("Name", true, false) as Label if card != null else null
	var spec_l := card.find_child("Spec", true, false) as Label if card != null else null
	out.append(_t("the motor shelf shows it at once: its name and one key spec",
		name_l != null and name_l.text == "Hill climber" and spec_l != null and spec_l.text == "2207 2400KV",
		"%s / %s" % [name_l.text if name_l else "-", spec_l.text if spec_l else "-"]))

	# The drone flies it like a preset.
	var flies := PartsCatalog.load_with_custom(SCRATCH)
	var part := flies.get_part(id)
	var ref := MotorDesign.reference_preset(flies, 22.0, 7.0, 2400.0)
	var prop := flies.get_part(String(part.thrust_test.prop_id))
	var k_ref := float(Build.fit_rated_point(ref, prop).k_t)
	var k_own := float(Build.fit_rated_point(part, prop).k_t)
	out.append(_t("the drone's thrust fit lands on the reference prop's k_t (thrust from this motor's Kv/Rm/Io)",
		ref.part_id == "motor_2207_2400kv" and absf(k_own - k_ref) < 1e-6 * k_ref,
		"%s %s vs %s" % [ref.part_id, k_own, k_ref]))

	var b_ref := _build(flies, ReferenceBuild.MOTOR_ID)
	var b_new := _build(flies, id)
	var dm := float(part.mass_g) - float(flies.get_part(ReferenceBuild.MOTOR_ID).mass_g)
	var auw_d := b_new.all_up_weight_g() - b_ref.all_up_weight_g()
	out.append(_t("fitted on the reference drone: AUW moves by 4x its mass difference, and T:W, hover, flight time and top speed all change",
		absf(auw_d - 4.0 * dm) < 0.01 and b_new.thrust_to_weight() > 1.0
		and b_new.thrust_to_weight() != b_ref.thrust_to_weight()
		and b_new.hover_throttle() != b_ref.hover_throttle()
		and b_new.flight_time_min() > 0.0 and b_new.flight_time_min() != b_ref.flight_time_min()
		and b_new.top_speed_kmh() != b_ref.top_speed_kmh(),
		"auw %+.2f vs 4x%+.2f; tw %.2f/%.2f hover %.3f/%.3f ft %.2f/%.2f top %.1f/%.1f" % [auw_d, dm,
			b_ref.thrust_to_weight(), b_new.thrust_to_weight(), b_ref.hover_throttle(), b_new.hover_throttle(),
			b_ref.flight_time_min(), b_new.flight_time_min(), b_ref.top_speed_kmh(), b_new.top_speed_kmh()]))

	# Reopen to edit: Save keeps the id; Save as new makes a copy.
	d.close()
	ds.open_motor_designer(id)
	d = ds.motor_designer
	var opened_ok := d.part_id == id and d.design.kv == 2400.0 and d.design.poles == 12 \
		and (d.find_child("SaveAs", true, false) as Button).visible
	d.set_kv(2650.0)
	d.save()
	var edited := CustomMotors.load_from(SCRATCH).get_record(id)
	var copy_id := d.save_as()
	var n := CustomMotors.load_from(SCRATCH).records().size()
	out.append(_t("reopened from the shelf it edits in place (same id), and Save as new adds a copy",
		opened_ok and float(edited.design.kv) == 2650.0 and copy_id == "custom_hill_climber_copy"
		and n == 4 and String(CustomMotors.load_from(SCRATCH).get_record(id).name) == "Hill climber",
		"%s kv %s copy %s n %d" % [opened_ok, edited.design.kv, copy_id, n]))
	d.close()

	# A typed motor opens on the grid as a NEW design: saving never overwrites what was typed.
	ds.open_motor_designer(TYPED_IDS[0])
	d = ds.motor_designer
	out.append(_t("a typed motor opens on the nearest grid point as a new design",
		d.part_id == "" and d.design.size == "2207" and d.design.name == "5\" Freestyle Shed",
		"%s %s" % [d.part_id, d.design.size]))
	d.close()

	# Delete: the first request only arms it; the second removes it from the file and the shelf.
	var swapped := ds.choose("motor", copy_id)
	var armed := not ds.delete_saved_motor(copy_id) and not CustomMotors.load_from(SCRATCH).get_record(copy_id).is_empty()
	var gone := ds.delete_saved_motor(copy_id)
	out.append(_t("delete asks twice, then the motor leaves the file and the shelf; a fitted one is swapped back",
		bool(swapped.get("ok", false)) and armed and gone and CustomMotors.load_from(SCRATCH).get_record(copy_id).is_empty()
		and ds.shelf.row_of(copy_id).is_empty()
		and String(ds.session.selection.get("motor", "")) == String(DroneClass.parts_for("five_inch").motor)
		and not ds.session.readouts(ds._catalog).is_empty(),
		"swap %s armed %s gone %s" % [swapped.get("ok"), armed, gone]))
	ds.free()
	return out
