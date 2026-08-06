class_name TestCustomFrames
extends RefCounted
## Builder-entered frames (LTHL-21). Two things this suite exists to prevent, above everything
## else it checks: a custom frame silently becoming the reference build, and a half-written
## user:// document stopping Lab from opening.

const EPS := 0.05


static func run() -> Array:
	var results: Array = []
	results.append(_test_shipped_catalog_carries_no_custom_ids())
	results.append(_test_loader_refuses_a_custom_prefixed_entry())
	results.append(_test_reference_build_is_out_of_reach())
	return results


## Catalog hygiene, not a loader test: this only shows that nothing in data/parts/ currently
## HAPPENS to use the reserved prefix, which is true whether or not the loader would refuse one.
## The loader's actual refusal is exercised by _test_loader_refuses_a_custom_prefixed_entry below,
## against a fixture built to contain the collision this file cannot.
static func _test_shipped_catalog_carries_no_custom_ids() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var offenders: Array[String] = []
	for part_id in catalog.by_id:
		if PartsCatalog.is_custom(part_id):
			offenders.append(str(part_id))
	return TestResult.new(
		"no shipped part claims the reserved custom_ prefix",
		offenders.is_empty() and catalog.is_valid(),
		"%d parts loaded, %d reserved-prefix offenders %s" % [
			catalog.by_id.size(), offenders.size(), offenders])


## Drives _load_category directly against a fixture holding one ordinary frame and one
## custom_-prefixed impostor, because CATEGORY_FILES has no such collision to offer. Checks all
## three of: the impostor is refused (absent from by_id), the refusal is surgical rather than a
## file-level abort (the ordinary entry beside it still loads), and the refusal is reported
## (load_errors names the offending id) rather than merely silent.
static func _test_loader_refuses_a_custom_prefixed_entry() -> TestResult:
	var catalog := PartsCatalog.new()
	catalog._load_category("frame", "res://tests/fixtures/frames_with_custom_id.json")
	var impostor_rejected := not catalog.by_id.has("custom_impostor")
	var ordinary_loaded := catalog.by_id.has("frame_fixture_ordinary")
	var error_named := false
	for error in catalog.load_errors:
		if error.contains("custom_impostor"):
			error_named = true
	return TestResult.new(
		"_load_category refuses a custom_-prefixed entry without dropping its neighbours",
		impostor_rejected and ordinary_loaded and error_named,
		"impostor rejected: %s, ordinary loaded: %s, error named it: %s (load_errors: %s)" % [
			impostor_rejected, ordinary_loaded, error_named, catalog.load_errors])


## The 496 g / 11.69 / 29.6% oracle, asserted here as well as in the day-2 tests, because THIS is
## the suite that would notice it moving for a custom-frames reason.
static func _test_reference_build_is_out_of_reach() -> TestResult:
	var build := ReferenceBuild.build()
	var auw := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()
	var ok := absf(auw - 496.0) < EPS and absf(twr - 11.69) < 0.01 and absf(hover - 0.296) < 0.001
	return TestResult.new(
		"the reference build is 496 g / 11.69 : 1 / 29.6% hover",
		ok, "AUW %.2f g, TWR %.2f, hover %.1f%%" % [auw, twr, hover * 100.0])
