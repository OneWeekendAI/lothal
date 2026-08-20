class_name TestPropellerDocument
extends RefCounted
## PropellerDocument is the §2 data model and the migration of the catalog props onto it. These
## tests are about the DOCUMENT — what it holds, what survives a save, and whether a preset lands
## its planform where the picture already draws it. What the geometry WEIGHS is BladeGeometry's
## subject (test_blade_geometry.gd), but the falsification that a preset's computed mass can be
## compared against its published figure lives here because it is the migration's contract.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var materials := FrameMaterials.load_default()

	results.append(_test_every_catalog_prop_becomes_a_document(catalog))
	results.append(_test_every_preset_is_chord_assumed(catalog))
	results.append(_test_round_trip_is_unchanged(catalog))
	results.append(_test_unknown_fields_survive_a_round_trip())
	results.append(_test_a_bad_file_loads_as_an_empty_propeller())
	results.append(_test_material_mapping_follows_the_catalog_string(catalog, materials))
	results.append(_test_no_authored_mass_field(catalog))
	results.append(_test_planform_matches_the_mesh_shape(catalog))
	results.append(_test_mass_falsification_is_reported_not_gated(catalog, materials))

	return results


static func _test_every_catalog_prop_becomes_a_document(catalog: PartsCatalog) -> TestResult:
	var presets := PropellerDocument.presets_from_catalog(catalog)
	var props := catalog.list_category("propeller")
	var problems: Array = []

	for prop in props:
		var id := str(prop["part_id"])
		if not presets.has(id):
			problems.append("%s: no preset" % id)
			continue
		var doc: PropellerDocument = presets[id]
		var specs: Dictionary = prop["specs"]
		var expected_diameter_mm: float = float(specs["diameter_inches"]) * PropellerDocument.INCH_TO_MM
		var expected_pitch_mm: float = float(specs["pitch_inches"]) * PropellerDocument.INCH_TO_MM
		if absf(doc.diameter_mm - expected_diameter_mm) > 1e-9:
			problems.append("%s: diameter %.3f vs %.3f" % [id, doc.diameter_mm, expected_diameter_mm])
		if absf(doc.pitch_mm - expected_pitch_mm) > 1e-9:
			problems.append("%s: pitch %.3f vs %.3f" % [id, doc.pitch_mm, expected_pitch_mm])
		if doc.blades != int(specs["blades"]):
			problems.append("%s: blades %d vs %d" % [id, doc.blades, int(specs["blades"])])
		if doc.chord.size() < 4:
			problems.append("%s: planform degenerate" % id)
		if doc.radius_mm() <= 0.0:
			problems.append("%s: no radius" % id)

	return TestResult.new(
		"every catalog prop migrates to a PropellerDocument with its published geometry",
		problems.is_empty(),
		"%d props migrated" % props.size() if problems.is_empty() else "; ".join(problems))


static func _test_every_preset_is_chord_assumed(catalog: PartsCatalog) -> TestResult:
	# §3.1's whole honesty contract: nobody publishes a chord distribution, so every generated
	# preset SAYS so. A preset that stopped carrying the flag would let every number derived from it
	# claim a measurement it is not — the exact laundering §9b forbids.
	var problems: Array = []
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		if not doc.chord_is_assumed:
			problems.append("%s: generated preset is not flagged chord_is_assumed" % prop["part_id"])
	return TestResult.new(
		"every catalog preset is flagged chord_is_assumed",
		problems.is_empty(),
		"%d presets flagged" % catalog.list_category("propeller").size()
			if problems.is_empty() else "; ".join(problems))


static func _test_round_trip_is_unchanged(catalog: PartsCatalog) -> TestResult:
	# Save, load, save. The two serialised forms must be byte-identical — not approximately equal.
	# That is why the planform is stored as doubles: a single-precision round trip would force the
	# assertion down to is_equal_approx, and the test would stop being about persistence.
	var problems: Array = []
	var checked := 0
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		var path := "user://test_propeller_%s.json" % prop["part_id"]
		if not doc.save_to(path):
			problems.append("%s: save failed" % prop["part_id"])
			continue
		var reloaded := PropellerDocument.load_from(path)
		var first := JSON.stringify(doc.to_dictionary(), "  ")
		var second := JSON.stringify(reloaded.to_dictionary(), "  ")
		if first != second:
			problems.append("%s: differs after a round trip" % prop["part_id"])
		elif reloaded.chord.size() != doc.chord.size():
			problems.append("%s: lost planform points" % prop["part_id"])
		else:
			checked += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return TestResult.new(
		"a preset round-trips through save/load byte-identically",
		problems.is_empty(),
		"%d documents identical after save/load/save" % checked
			if problems.is_empty() else "; ".join(problems))


static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	# json_store.gd's fourth rule. A file written by a later Lothal must come back out of an older
	# one intact — a camber distribution, a section table, an owner field, whatever ships next.
	var authored := {
		"schema": PropellerDocument.SCHEMA_VERSION,
		"id": "future", "name": "Future prop", "author": "", "revision": "",
		"diameter_mm": 127.0, "pitch_mm": 109.22, "blades": 3,
		"chord": [0.5, 10.0, 1.0, 3.0],
		"twist_mode": "geometric", "twist": [],
		"material_id": "polycarbonate", "thickness_ratio": 0.1,
		"camber_percent": 5.0,                  # unknown, top level
	}
	var path := "user://test_propeller_unknown.json"
	JsonStore.write_document(path, authored)
	var doc := PropellerDocument.load_from(path)
	var out := doc.to_dictionary()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var problems: Array = []
	if float(out.get("camber_percent", 0.0)) != 5.0:
		problems.append("unknown camber_percent lost")
	if absf(doc.diameter_mm - 127.0) > 1e-9:
		problems.append("known diameter was not parsed")
	return TestResult.new(
		"unknown fields survive a load/save at the top level",
		problems.is_empty(),
		"camber_percent returned" if problems.is_empty() else "; ".join(problems))


static func _test_a_bad_file_loads_as_an_empty_propeller() -> TestResult:
	# json_store.gd's first rule. An unopenable prop must not be an unopenable prop editor.
	var path := "user://test_propeller_broken.json"
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string("{\"chord\": [ not json at all")
	handle.close()
	var doc := PropellerDocument.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var missing := PropellerDocument.load_from("user://test_propeller_does_not_exist.json")
	var ok := doc.chord.is_empty() and doc.id == "" and missing.chord.is_empty()
	return TestResult.new(
		"a truncated or missing prop file loads as an empty document, not a crash",
		ok,
		"malformed: %d chord points; missing: %d chord points" % [doc.chord.size(), missing.chord.size()])


static func _test_material_mapping_follows_the_catalog_string(
	catalog: PartsCatalog, materials: FrameMaterials
) -> TestResult:
	var problems: Array = []
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		if materials.density(doc.material_id) <= 0.0:
			problems.append("%s: '%s' has no density in the table" % [prop["part_id"], doc.material_id])
	# And the explicit mapping, so a prose drift in the catalog is caught rather than silently
	# defaulting every prop to polycarbonate.
	if PropellerDocument.material_id_for_catalog("carbon-filled nylon") != "carbon_filled_nylon":
		problems.append("carbon-filled nylon mapped wrong")
	if PropellerDocument.material_id_for_catalog("glass-filled nylon") != "glass_filled_nylon":
		problems.append("glass-filled nylon mapped wrong")
	if PropellerDocument.material_id_for_catalog("polycarbonate") != "polycarbonate":
		problems.append("polycarbonate mapped wrong")
	return TestResult.new(
		"catalog material prose maps to a material table id that has a density",
		problems.is_empty(),
		"%d preset materials resolved, all with densities" % catalog.list_category("propeller").size()
			if problems.is_empty() else "; ".join(problems))


static func _test_no_authored_mass_field(catalog: PartsCatalog) -> TestResult:
	# §2's ban, asserted rather than assumed: the field that would appear here is the one that makes
	# every downstream number a lie. A preset carries published_mass_g (a third party's claim, never
	# read into physics) and nothing else.
	var problems: Array = []
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		var out := doc.to_dictionary()
		if out.has("mass_g") or out.has("mass_kg"):
			problems.append("%s: carries an authored mass" % prop["part_id"])
		# The carried figure IS the catalog's, so the falsification below has a target.
		if doc.published_mass_g <= 0.0:
			problems.append("%s: published_mass_g missing" % prop["part_id"])
	return TestResult.new(
		"presets carry no authored mass, only the published figure for falsification",
		problems.is_empty(),
		"%d presets checked" % catalog.list_category("propeller").size()
			if problems.is_empty() else "; ".join(problems))


## THE PLANFORM IS THE SHAPE THE MESH DRAWS. §7.2 says the mesh's chord constants become the
## document's c(r); until that rewiring ships, this pins the two copies together so they cannot
## drift. The mesh's `_chord_at(span, chord_max)` is rebuilt here from its PUBLIC constants and
## compared against the document's planform AT THE DOCUMENT'S OWN STATIONS — the same technique
## test_rust_constants uses (derive the other side from behaviour, not from an accessor).
##
## The comparison must be at the document's own points, not between them: §2 says a planform IS
## piecewise-linear c(r), so the stored chord equals the exact sine-arch at each station and is a
## linear interpolation between them. Asking for the exact arch value at an off-station radius would
## measure the interpolation sagitta, not a drift — a real failure of this pin must be a station
## value, not an interpolated one.
##
## The tolerance is RELATIVE (1e-9) and the points are read from the flat PackedFloat64Array, not
## from `chord_points()`: that accessor returns Vector2, which is SINGLE precision, and §3.1
## measures what that costs — about 4e-7 relative on a chord near 13 mm, which would fail any
## absolute pin that a real drift (a changed exponent, a missing 0.5) misses by a factor of ten
## thousand. The stored doubles are the document; they are what the pin must test.
static func _test_planform_matches_the_mesh_shape(catalog: PartsCatalog) -> TestResult:
	var problems: Array = []
	for prop_id in ["prop_5x43x3", "prop_7x35x2", "prop_16x12x4", "prop_10x5x2"]:
		var prop: Dictionary = catalog.get_part(prop_id)
		var specs: Dictionary = prop["specs"]
		var diameter_mm: float = float(specs["diameter_inches"]) * PropellerDocument.INCH_TO_MM
		var blades := int(specs["blades"])
		var doc := PropellerDocument.from_catalog_prop(prop)

		# The mesh's own chord law, from its own constants:
		var radius_mm := diameter_mm * 0.5
		var chord_max_mm := diameter_mm * PropellerMesh.CHORD_TO_DIAMETER_AT_3_BLADE \
			* pow(3.0 / float(blades), PropellerMesh.CHORD_BLADE_COUNT_EXPONENT)
		var hub_mm := radius_mm * PropellerMesh.HUB_RADIUS_TO_RADIUS

		var stations := int(doc.chord.size() / 2.0)
		var i := 0
		while i + 1 < doc.chord.size():
			var r_frac := doc.chord[i]
			var doc_chord_mm := doc.chord[i + 1]
			var span := (r_frac * radius_mm - hub_mm) / (radius_mm - hub_mm)
			var arch := PropellerMesh.CHORD_ROOT_FRACTION \
				+ (PropellerMesh.CHORD_TIP_FRACTION - PropellerMesh.CHORD_ROOT_FRACTION) * span
			var mesh_chord_mm := chord_max_mm * pow(sin(PI * arch), PropellerMesh.CHORD_FULLNESS)
			var rel := absf(doc_chord_mm - mesh_chord_mm) / maxf(absf(mesh_chord_mm), 1e-9)
			if rel > 1e-9:
				problems.append("%s: at r/R %.3f mesh %.4f mm vs doc %.4f mm (rel %.1e)" % [
					prop_id, r_frac, mesh_chord_mm, doc_chord_mm, rel])
			i += 2

		if stations != PropellerDocument.PLANFORM_STATIONS:
			problems.append("%s: %d stations, want %d" % [
				prop_id, stations, PropellerDocument.PLANFORM_STATIONS])
	return TestResult.new(
		"the document's planform matches the mesh's sine-arch at every document station",
		problems.is_empty(),
		"4 props x %d stations agree" % PropellerDocument.PLANFORM_STATIONS
			if problems.is_empty() else "; ".join(problems))


## §3.2's FALSIFIABLE CLAIM — the migration's contract — run as a falsification. The preset generator
## reads diameter, pitch and blade count, and never reads mass_g, so this comparison is against a
## number the pipeline has not seen. Unlike the frame's ±10%, this is REPORTED rather than asserted:
## the blade-only mass cannot reproduce the whole-prop figure (no hub), and the planform is assumed
## (chord_is_assumed), so the honest shape of the result is a band, printed — not a pass/fail that
## would silently "fix" itself by tuning the planform (the exact bound-moved-to-fit-its-data that
## §9a forbids).
static func _test_mass_falsification_is_reported_not_gated(
	catalog: PartsCatalog, materials: FrameMaterials
) -> TestResult:
	var rows: Array = []
	var band_min := INF
	var band_max := -INF
	for prop in catalog.list_category("propeller"):
		var doc := PropellerDocument.from_catalog_prop(prop)
		var computed := BladeGeometry.blade_mass_g(doc, materials)
		var published := doc.published_mass_g
		if published <= 0.0:
			continue
		var ratio := computed / published
		band_min = minf(band_min, ratio)
		band_max = maxf(band_max, ratio)
		rows.append("%s %+.0f%% (%.2fg vs %.2fg)" % [
			str(prop["part_id"]).replace("prop_", ""), (ratio - 1.0) * 100.0, computed, published])

	var finding := "band %0.2f..%0.2f x published — blade-only, no hub; reported per §3.1" % [band_min, band_max]
	return TestResult.new(
		"FINDING (not a gate): preset blade mass vs published, reported as a band",
		band_min > 0.0 and is_finite(band_min) and band_max > band_min,
		"%s | %s" % [finding, "; ".join(rows)])
