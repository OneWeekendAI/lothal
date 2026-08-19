class_name TestFrameMaterials
extends RefCounted
## The material table is a set of constants that every mass, stiffness and stress number in the
## airframe multiplies by, so the failure mode it has is not "crashes" — it is "quietly wrong and
## nobody can tell where the number came from". These tests are aimed at exactly that: every entry
## must cite a source, every density must be in a range that catches a units slip, and the
## anisotropy must actually be direction-dependent for a weave and actually be flat for a
## quasi-isotropic layup, because a table where E(θ) is constant everywhere would pass any test
## that only ever asks one material one question.

static func run() -> Array:
	var results: Array = []
	var table := FrameMaterials.load_default()

	results.append(_test_loads_clean(table))
	results.append(_test_every_entry_cites_a_source(table))
	results.append(_test_densities_are_physically_sane(table))
	results.append(_test_all_eight_materials_present(table))
	results.append(_test_twill_is_direction_dependent(table))
	results.append(_test_quasi_isotropic_is_not(table))
	results.append(_test_schema_names_the_two_tiers())

	return results


static func _test_loads_clean(table: FrameMaterials) -> TestResult:
	var passed := table.is_valid()
	return TestResult.new(
		"data/materials.json loads with no errors",
		passed,
		"%d materials, errors: %s" % [table.ordered.size(), str(table.load_errors)]
	)


## A material figure with no citation is a recalled number, and §6.1's own note is that these were
## checked rather than recalled. The loader refuses a sourceless record outright, so this asserts on
## the loaded table AND on the raw file — otherwise "every loaded entry has a source" would be
## tautologically true and would pass a file where half the entries had been dropped.
static func _test_every_entry_cites_a_source(table: FrameMaterials) -> TestResult:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(FrameMaterials.MATERIALS_PATH))
	var bad: Array[String] = []
	var raw_count := 0
	if raw is Dictionary and raw.has("materials"):
		for entry in raw["materials"]:
			raw_count += 1
			var source := str(entry.get("source", "")).strip_edges()
			if source.is_empty():
				bad.append(str(entry.get("material_id", "<no id>")))
			# A shop link is banned from part data and is banned here: the source names a datasheet
			# or a published measurement, in words, and a bare URL is how vendor links get in.
			elif source.to_lower().contains("http"):
				bad.append("%s: source is a link rather than a citation" % entry.get("material_id", ""))

	var passed := bad.is_empty() and raw_count == table.ordered.size() and raw_count > 0
	return TestResult.new(
		"every material entry carries a non-empty source",
		passed,
		"%d entries in file, %d loaded, problems: %s" % [raw_count, table.ordered.size(), str(bad)]
	)


static func _test_densities_are_physically_sane(table: FrameMaterials) -> TestResult:
	var bad: Array[String] = []
	for material_id in table.ids():
		var rho := table.density(material_id)
		if rho < FrameMaterials.DENSITY_MIN_KG_M3 or rho > FrameMaterials.DENSITY_MAX_KG_M3:
			bad.append("%s=%.1f" % [material_id, rho])

	# Ordering facts the range check alone cannot see: steel must outweigh titanium must outweigh
	# aluminium must outweigh carbon. A table where every density had been multiplied by the same
	# wrong factor would clear the range and fail this.
	var ordering_ok := table.density("steel_fastener") > table.density("titanium_ti6al4v") \
		and table.density("titanium_ti6al4v") > table.density("aluminium_7075") \
		and table.density("aluminium_7075") > table.density("aluminium_6061") \
		and table.density("aluminium_6061") > table.density("carbon_quasi_isotropic") \
		and table.density("carbon_quasi_isotropic") > table.density("pa12_sls")

	var passed := bad.is_empty() and ordering_ok
	return TestResult.new(
		"densities are in a physically sane range and in the right order",
		passed,
		"out of range: %s; steel>Ti>7075>6061>carbon>PA12 holds: %s" % [str(bad), ordering_ok]
	)


static func _test_all_eight_materials_present(table: FrameMaterials) -> TestResult:
	var required := ["carbon_3k_twill_0_90", "carbon_quasi_isotropic", "pa12_sls", "tpu_95a",
		"aluminium_6061", "aluminium_7075", "steel_fastener", "titanium_ti6al4v"]
	var missing: Array[String] = []
	for material_id in required:
		if table.get_material(material_id).is_empty():
			missing.append(material_id)
	return TestResult.new(
		"all eight materials of airframe.md §6.1 are in the table",
		missing.is_empty(),
		"missing: %s (have %s)" % [str(missing), str(table.ids())]
	)


## The twill's whole point: an arm cut at 45° to the weave is a different arm. Asserted as a
## RELATIONSHIP between three angles rather than against a stored value, so a table that carried a
## 45° field and then ignored it in E(θ) would fail here.
static func _test_twill_is_direction_dependent(table: FrameMaterials) -> TestResult:
	var twill := "carbon_3k_twill_0_90"
	var e0 := table.modulus_at_angle_gpa(twill, 0.0)
	var e45 := table.modulus_at_angle_gpa(twill, 45.0)
	var e90 := table.modulus_at_angle_gpa(twill, 90.0)
	var stiff := table.modulus_gpa(twill)

	var knockdown := 1.0 - e45 / e0
	var passed := table.is_anisotropic(twill) \
		and absf(e0 - stiff) < 0.01 \
		and absf(e90 - stiff) < 0.01 \
		and knockdown > 0.20 and knockdown < 0.40 \
		and str(table.get_material(twill)["catalog"]["modulus_tier"]) == "characteristic"

	return TestResult.new(
		"3K twill E(θ) drops ~30% at 45° and is labelled characteristic",
		passed,
		"E(0)=%.1f E(45)=%.1f E(90)=%.1f GPa, knockdown %.1f%% (want 20-40%%), tier=%s" % [
			e0, e45, e90, knockdown * 100.0,
			table.get_material(twill).get("catalog", {}).get("modulus_tier", "<none>")]
	)


## The other half of the same claim, and the one a builder pays extra for: a quasi-isotropic layup
## really is the same stiffness whichever way the arm is cut.
static func _test_quasi_isotropic_is_not(table: FrameMaterials) -> TestResult:
	var quasi := "carbon_quasi_isotropic"
	var spread := 0.0
	var base := table.modulus_at_angle_gpa(quasi, 0.0)
	for angle in [0.0, 15.0, 30.0, 45.0, 60.0, 90.0]:
		spread = maxf(spread, absf(table.modulus_at_angle_gpa(quasi, angle) - base))

	var passed := not table.is_anisotropic(quasi) and spread < 1e-6 and base > 0.0 \
		and base < table.modulus_gpa("carbon_3k_twill_0_90")

	return TestResult.new(
		"quasi-isotropic carbon has no direction dependence and is softer on-axis than twill",
		passed,
		"E=%.1f GPa flat to %.8f across 0-90°, twill stiff axis %.1f GPa" % [
			base, spread, table.modulus_gpa("carbon_3k_twill_0_90")]
	)


## The `_schema` prose is the only documentation a contributor gets, so it is held to what it
## claims — the same reason the parts files' schemas are tested.
static func _test_schema_names_the_two_tiers() -> TestResult:
	var schema := FrameMaterials.schema().to_lower()
	var required := ["specs", "catalog", "density_kg_m3", "characteristic", "price"]
	var missing: Array[String] = []
	for word in required:
		if not schema.contains(word):
			missing.append(word)
	return TestResult.new(
		"materials.json _schema explains the specs/catalog split and the banned fields",
		missing.is_empty() and schema.length() > 200,
		"%d chars, missing terms: %s" % [schema.length(), str(missing)]
	)
