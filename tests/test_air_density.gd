class_name TestAirDensity
extends RefCounted
## Air density, and the three things about it that could go wrong quietly.
##
## The FIRST is that the derivation might be plausible and wrong. A formula that produces numbers
## in the right neighbourhood, falling in the right direction, is indistinguishable from a correct
## one under any test written against itself — so §1 below checks it against the PUBLISHED
## standard-atmosphere table, an external authority this code does not contain. Round-tripping our
## own arithmetic would be a test that cannot fail.
##
## The SECOND is that the oracle might learn to see user state. ReferenceBuild's 496.0 g / 11.69:1
## / 29.6% are asserted in six other files, and every one of them would start reporting whatever
## field the developer happened to have selected. §4 is the guard, and it is written as the
## mutation a well-meaning future change would actually make.
##
## The THIRD is that old files might be rewritten. A course saved before air existed says nothing
## about where it is, and the correct reading of that silence is standard air — not because a
## default is convenient, but because 1.225 is exactly what that course was flown in. §5 pins that
## an untouched course round-trips to a byte-identical file, because the failure mode here is
## Lothal quietly editing every course a builder owns on first launch.

const LIBRARY_PATH := "user://test_air_courses.json"

## Agreement demanded against the published ISA table. The table quotes four significant figures
## and is itself computed with slightly different molar-mass and gas-constant roundings, so 0.2% is
## the level at which "the same atmosphere" is a meaningful claim — and it is fifty times tighter
## than the 10-16% effect this whole slice exists to model, so a real error cannot hide under it.
const PUBLISHED_ISA_TOL_FRACTION := 0.002

## The three fixed points, at standard air, to the tolerances the rest of the suite uses.
const INVARIANT_MASS_G := 507.48
const INVARIANT_TWR := 11.43
const INVARIANT_HOVER_PCT := 29.92

## The default circuit's fingerprint BEFORE air existed. Captured by running fingerprint() against
## the shipped code with this slice's changes stashed, not by pasting whatever the new code prints
## — a golden value taken from the implementation it is guarding is a test that cannot fail.
const PRE_AIR_DEFAULT_FINGERPRINT := "f106fd00d916b853"


static func run() -> Array:
	var results: Array = []
	var sections := {
		"published table": _published_isa_table(),
		"monotonicity": _monotonicity(),
		"invariants": _invariants_at_standard(),
		"oracle": _oracle_cannot_see_the_field(),
		"persistence": _persistence(),
		"library invariant": _library_always_has_a_selection(),
		"fingerprint": _fingerprint(),
	}
	# A runtime error partway through a section aborts only that section and its append never runs,
	# so the suite would pass with its best checks silently deleted. Measured, on this repo, on
	# 2026-08-12. Asserting each section produced something is what makes the count trustworthy.
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# 1. Against an external authority, not against ourselves
# ---------------------------------------------------------------------------

## The International Standard Atmosphere's own published densities, at its own temperatures. These
## numbers are from the standard, not from this code, and that is the entire point: they are what
## makes this a validation rather than a restatement.
##
## Every row is checked at the ISA temperature for that altitude, because the published density is
## quoted at that temperature. Feeding a fixed 15 C would compare our answer against a figure for
## a different atmosphere and would fail for a correct implementation.
static func _published_isa_table() -> Array:
	var results: Array = []
	# altitude m -> published density kg/m3
	var published := {
		0: 1.2250, 1000: 1.1117, 2000: 1.0066, 3000: 0.9093,
		5000: 0.7364, 8000: 0.5258, 11000: 0.3639,
	}
	for altitude in published:
		var elevation := float(altitude)
		# The ISA's own temperature profile at that altitude — the standard's lapse applied to the
		# standard's sea-level temperature.
		var isa_temperature_c: float = (AirDensity.SEA_LEVEL_TEMPERATURE_K
				- AirDensity.LAPSE_RATE_K_PER_M * elevation) - AirDensity.KELVIN_AT_ZERO_C
		var ours := AirDensity.new(elevation, isa_temperature_c).kgm3()
		var expected: float = published[altitude]
		var error := absf(ours / expected - 1.0)
		results.append(TestResult.new(
			"derived density matches the PUBLISHED standard atmosphere at %d m" % altitude,
			error < PUBLISHED_ISA_TOL_FRACTION,
			"ours %.5f, published %.4f, error %.3f%%" % [ours, expected, 100.0 * error]
		))
	return results


# ---------------------------------------------------------------------------
# 2. Monotonicity — and the derived stats that must follow it
# ---------------------------------------------------------------------------

## Checked as an ORDERING across a sweep rather than at a handful of points, so it cannot be
## satisfied by something that happens to hit the sampled values. A lookup table with the right
## corners passes a two-point check and fails this one.
static func _monotonicity() -> Array:
	var results: Array = []

	var previous := INF
	var elevation_falls := true
	for step in 45:
		var density := AirDensity.new(float(step) * 250.0, 15.0).kgm3()
		if density >= previous:
			elevation_falls = false
		previous = density
	results.append(TestResult.new(
		"density falls with elevation, at every step from 0 to 11000 m",
		elevation_falls,
		"0 m: %.4f, 11000 m: %.4f" % [
			AirDensity.new(0.0, 15.0).kgm3(), AirDensity.new(11000.0, 15.0).kgm3()]
	))

	previous = INF
	var temperature_falls := true
	for step in 60:
		var density := AirDensity.new(0.0, -20.0 + float(step)).kgm3()
		if density >= previous:
			temperature_falls = false
		previous = density
	results.append(TestResult.new(
		"density falls with temperature, at every step from -20 to 39 C",
		temperature_falls,
		"-20 C: %.4f, 39 C: %.4f" % [
			AirDensity.new(0.0, -20.0).kgm3(), AirDensity.new(0.0, 39.0).kgm3()]
	))

	# And the half that matters to a builder: the headline numbers have to follow the air. A
	# derivation that is perfectly monotonic and reaches nothing is the failure this slice's design
	# was rewritten to avoid — thrust_n has no rho in it, so without k_t scaling every figure below
	# is constant across the whole sweep.
	var catalog := PartsCatalog.load_default()
	var thinning := [0.0, 920.0, 1610.0, 2500.0, 3500.0]
	var previous_twr := INF
	var previous_hover := 0.0
	var twr_falls := true
	var hover_rises := true
	var readings := PackedStringArray()
	for elevation in thinning:
		var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			ReferenceBuild.FC_ID, {}, AirDensity.new(elevation, 20.0))
		var twr := build.thrust_to_weight()
		var hover := build.hover_throttle()
		if twr >= previous_twr:
			twr_falls = false
		if hover <= previous_hover:
			hover_rises = false
		previous_twr = twr
		previous_hover = hover
		readings.append("%.0fm %.2f:1/%.1f%%" % [elevation, twr, hover * 100.0])
	results.append(TestResult.new(
		"thrust-to-weight falls as the field gets higher",
		twr_falls, " ".join(readings)))
	results.append(TestResult.new(
		"hover throttle rises as the field gets higher",
		hover_rises, " ".join(readings)))
	return results


# ---------------------------------------------------------------------------
# 3. The three fixed points, unmoved at standard air
# ---------------------------------------------------------------------------

static func _invariants_at_standard() -> Array:
	var results: Array = []
	var standard := ReferenceBuild.build()
	results.append(TestResult.new(
		"all-up weight at standard air is still 507.5 g",
		absf(standard.all_up_weight_g() - INVARIANT_MASS_G) < 0.05,
		"%.2f g" % standard.all_up_weight_g()))
	results.append(TestResult.new(
		"thrust-to-weight at standard air is still 11.43:1",
		absf(standard.thrust_to_weight() - INVARIANT_TWR) < 0.01,
		"%.4f:1" % standard.thrust_to_weight()))
	results.append(TestResult.new(
		"hover throttle at standard air is still 29.9%",
		absf(standard.hover_throttle() * 100.0 - INVARIANT_HOVER_PCT) < 0.05,
		"%.2f%%" % (standard.hover_throttle() * 100.0)))

	# WITHOUT THIS, THE THREE ABOVE ARE WORTHLESS. "Unchanged" is only a claim if the thing was
	# capable of changing — a build wired to ignore air entirely passes every check above, which is
	# precisely the state this repo shipped for the air constant itself. So: the same parts at a
	# real field must give DIFFERENT numbers, and the mass must not be among them.
	var at_altitude := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID,
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, {}, AirDensity.new(3500.0, 20.0))
	results.append(TestResult.new(
		"the same parts at 3500 m give a DIFFERENT thrust-to-weight, so the checks above can fail",
		absf(at_altitude.thrust_to_weight() - standard.thrust_to_weight()) > 1.0,
		"3500 m: %.2f:1 vs standard %.2f:1" % [
			at_altitude.thrust_to_weight(), standard.thrust_to_weight()]))
	results.append(TestResult.new(
		"but the MASS does not move with air, because mass is a property of the aircraft",
		absf(at_altitude.all_up_weight_g() - standard.all_up_weight_g()) < 1.0e-9,
		"3500 m: %.4f g vs standard %.4f g" % [
			at_altitude.all_up_weight_g(), standard.all_up_weight_g()]))
	return results


# ---------------------------------------------------------------------------
# 4. The oracle cannot see the field
# ---------------------------------------------------------------------------

## ReferenceBuild is what six files assert 496.0 g / 11.69:1 / 29.6% against. If it ever learns to
## read the selected course, every one of those becomes a statement about the developer's own
## saved file, and the suite starts passing or failing on a number nobody typed into it.
##
## The defence is structural rather than vigilant: air is a constructor argument defaulting to
## standard, so the oracle gets standard air by OMITTING an argument. This asserts the structure
## holds even with a 3500 m field selected and saved on disk.
static func _oracle_cannot_see_the_field() -> Array:
	var results: Array = []

	# WRITTEN TO CourseLibrary.SAVE_PATH, NOT TO A SCRATCH FILE, and that is the whole test.
	#
	# The first version of this used LIBRARY_PATH like every other section here, and the mutation it
	# exists to catch — ReferenceBuild.build() calling CourseLibrary.load_from().selected().air —
	# PASSED ALL 1054 CHECKS. Of course it did: the oracle would read `user://courses.json`, which
	# no test had written, so it got a fresh library at standard air and looked innocent. The test
	# was measuring a file nothing under test reads.
	#
	# So it poisons the real path, and restores whatever was there afterwards. A test that guards
	# against reading user state has to CREATE the user state, or it is guarding nothing.
	# THE FIELD MOVED TO sites.json IN F1 — a course no longer carries air, the PLACE does — so both
	# real files are poisoned and both are put back. Poisoning only the courses file would leave
	# this section measuring a file nothing under test reads, which is the exact failure the
	# paragraph above records.
	var real_path := CourseLibrary.SAVE_PATH
	var real_sites := SiteLibrary.SAVE_PATH
	var had_file := FileAccess.file_exists(real_path)
	var had_sites := FileAccess.file_exists(real_sites)
	var saved_contents := FileAccess.get_file_as_string(real_path) if had_file else ""
	var saved_sites := FileAccess.get_file_as_string(real_sites) if had_sites else ""

	var high := Site.new()
	high.site_id = "test_oracle_high"
	high.elevation_m = 3500.0
	high.parked_temperature_c = 30.0
	var sites := SiteLibrary.with_default()
	sites.put(high)
	sites.select(high.site_id)
	sites.save(real_sites)

	var library := CourseLibrary.with_default()
	library.selected().site_id = high.site_id
	library.save(real_path)
	var reloaded := SiteLibrary.load_from(real_sites)

	var selected_rho := reloaded.selected().air().kgm3()
	var oracle := ReferenceBuild.build()
	results.append(TestResult.new(
		"a 3500 m field really is selected and saved, so this check has something to fail on",
		absf(selected_rho - AirDensity.standard_kgm3()) > 0.1,
		"selected field air %.4f kg/m3" % selected_rho))
	results.append(TestResult.new(
		"ReferenceBuild is standard air with a 3500 m field selected",
		absf(oracle.air.kgm3() - AirDensity.standard_kgm3()) < 1.0e-12,
		"oracle air %.6f, field air %.6f" % [oracle.air.kgm3(), selected_rho]))
	results.append(TestResult.new(
		"and therefore still reads 11.43:1 / 29.9% with that field selected",
		absf(oracle.thrust_to_weight() - INVARIANT_TWR) < 0.01
			and absf(oracle.hover_throttle() * 100.0 - INVARIANT_HOVER_PCT) < 0.05,
		"%.4f:1, %.2f%%" % [oracle.thrust_to_weight(), oracle.hover_throttle() * 100.0]))

	# Put the builder's own courses back. This suite runs inside a real user:// directory, and a
	# test that quietly replaced somebody's saved courses with a default circuit would be a worse
	# bug than the one it is checking for.
	if had_file:
		var restore := FileAccess.open(real_path, FileAccess.WRITE)
		restore.store_string(saved_contents)
		restore.close()
	else:
		DirAccess.remove_absolute(real_path)
	if had_sites:
		var restore_sites := FileAccess.open(real_sites, FileAccess.WRITE)
		restore_sites.store_string(saved_sites)
		restore_sites.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(real_sites))
	return results


# ---------------------------------------------------------------------------
# 5. The file
# ---------------------------------------------------------------------------

static func _persistence() -> Array:
	var results: Array = []

	# A course file with nothing to say about where it is. Since F1 that means a v2 record with no
	# `site_id`, which reads as the default field — at sea level, which is what this course was
	# always flown in. Reading it as anything else would change numbers a builder has already seen.
	var legacy := {
		"schema": 2,
		"selected": "default_circuit",
		"courses": [{
			"id": "default_circuit", "name": "Circuit",
			"gates": GateCourse.gates_to_data(GateCourse.build_gates()),
			"site_id": "default_site",
		}],
	}
	# Written through JsonStore, the same writer the app uses. Hand-rolling the fixture with
	# JSON.stringify was the first attempt and it made the byte-identity check below fail for a
	# reason that had nothing to do with air: a different indent string. A round-trip test has to
	# compare against the writer it is testing, or it is measuring the fixture.
	JsonStore.write_document(LIBRARY_PATH, legacy)
	var before := FileAccess.get_file_as_string(LIBRARY_PATH)

	var loaded := CourseLibrary.load_from(LIBRARY_PATH)
	var where := SiteLibrary.with_default().site(loaded.selected().site_id)
	results.append(TestResult.new(
		"a course that says nothing about where it is is flown in standard sea-level air",
		where != null and absf(where.air().kgm3() - AirDensity.standard_kgm3()) < 1.0e-12,
		"nowhere" if where == null else "%.6f kg/m3, elevation %.1f m, temperature %.1f C" % [
			where.air().kgm3(), where.air().elevation_m, where.air().temperature_c]))

	# And saving it back must not INVENT the block. A course nobody has told about its field has to
	# round-trip untouched, or this slice rewrites every course file on the planet on first launch
	# to say something none of their authors said.
	loaded.save(LIBRARY_PATH)
	var after := FileAccess.get_file_as_string(LIBRARY_PATH)
	results.append(TestResult.new(
		"and saving it back does not invent an air block",
		not after.contains("\"air\""),
		"file %s an air key after a round trip" % ("grew" if after.contains("\"air\"") else "kept no")))
	# BYTE-IDENTITY IS NOT THE CLAIM, and the reason is worth recording because byte-identity was
	# the first thing written here and it failed for a reason that has nothing to do with air.
	#
	# A gate's position is a Vector3, which is float32. Every save widens those to double and prints
	# them at full precision, and every load narrows them back — so a coordinate near zero sheds a
	# digit each trip: the default circuit's gate-1 normal goes 6.12e-17, then 6.0e-17, then
	# 1.09e-15 on the component beside it. It is not even idempotent, measured. All of this predates
	# this slice by months, and it is exactly why fingerprint() rounds to a millimetre — a record
	# that vanished because a save moved a gate by 1e-16 m is the bug that rounding exists to stop.
	#
	# So the claim is about the DOCUMENT and the TRACK rather than the bytes: no key appears or
	# disappears, no air block is invented, and the course is still the same course to fly. That is
	# what "we do not rewrite a builder's courses" means once the pre-existing float storage is
	# accounted for honestly, and it is a stronger statement than a byte comparison anyway — a
	# byte-identical file with a different fingerprint is impossible, but a fingerprint check would
	# catch a real geometry change that a lucky byte count would not.
	results.append(TestResult.new(
		"no key is added or dropped by a round trip (the air block is not invented)",
		_keys_of(before) == _keys_of(after),
		"keys in %s, keys out %s" % [_keys_of(before), _keys_of(after)]))

	# AND THE SAME FILE WITHOUT ITS `site_id`, which is the version of this check that can still
	# fail. The fixture above carries one, so "no key added" is satisfied by a writer that writes
	# site_id — it was already there. Dropping it asks the real question, and the answer is a
	# DELIBERATE one rather than the rule's default: a v2 record always names its site, so this
	# record gains exactly that one key and nothing else. `site_id` is not an invention in the sense
	# the rule forbids — it is the migration finishing, and its value is the default field, which is
	# precisely where a course that never said where it was has always been flown.
	var siteless := legacy.duplicate(true)
	(siteless["courses"] as Array)[0].erase("site_id")
	JsonStore.write_document(LIBRARY_PATH, siteless)
	var siteless_before := FileAccess.get_file_as_string(LIBRARY_PATH)
	CourseLibrary.load_from(LIBRARY_PATH).save(LIBRARY_PATH)
	var siteless_after := FileAccess.get_file_as_string(LIBRARY_PATH)
	var gained := PackedStringArray()
	for key in _keys_of(siteless_after):
		if not _keys_of(siteless_before).has(key):
			gained.append(key)
	results.append(TestResult.new(
		"a v2 course with no site_id gains exactly that key and no other, and no air block",
		Array(gained) == ["site_id"] and not siteless_after.contains("\"air\""),
		"gained %s%s" % [
			"nothing" if gained.is_empty() else str(gained),
			", and an air block" if siteless_after.contains("\"air\"") else ""]))
	# Restore the fixture the checks below read.
	JsonStore.write_document(LIBRARY_PATH, legacy)
	CourseLibrary.load_from(LIBRARY_PATH).save(LIBRARY_PATH)
	results.append(TestResult.new(
		"and it is still the same track, so a best lap set on it survives",
		CourseLibrary.load_from(LIBRARY_PATH).selected().fingerprint()
			== PRE_AIR_DEFAULT_FINGERPRINT,
		"%s" % CourseLibrary.load_from(LIBRARY_PATH).selected().fingerprint()))

	# AN AUTHORED FIELD MUST SURVIVE EXACTLY — and since F1 that means surviving the v1 -> v2
	# migration as well as a save and a load, because a builder who typed 920 m and 35 C typed it
	# into a v1 file. Both numbers land on the site the migration makes for the course: the
	# elevation because that is a fact about the place, the temperature parked for the conditions
	# (design §3.1) rather than discarded on its way past.
	var v1_path := "user://test_air_v1_courses.json"
	var v1_sites := SiteLibrary.path_beside(v1_path)
	for scratch in [v1_path, v1_sites]:
		if FileAccess.file_exists(scratch):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	JsonStore.write_document(v1_path, {
		"schema": 1,
		"selected": "default_circuit",
		"courses": [{
			"id": "default_circuit", "name": "Circuit",
			"air": {"elevation_m": 920.0, "temperature_c": 35.0},
			"gates": GateCourse.gates_to_data(GateCourse.build_gates()),
		}],
	})
	var migrated_sites := SiteLibrary.migrate_courses(v1_path, v1_sites)
	var authored := CourseLibrary.load_from(v1_path)
	var authored_site := migrated_sites.site(authored.selected().site_id)
	results.append(TestResult.new(
		"an authored field survives the migration, and a save and load after it",
		authored_site != null
			and absf(authored_site.air().elevation_m - 920.0) < 1.0e-9
			and absf(authored_site.air().temperature_c - 35.0) < 1.0e-9,
		"nowhere" if authored_site == null else "%.1f m, %.1f C, %.4f kg/m3" % [
			authored_site.air().elevation_m, authored_site.air().temperature_c,
			authored_site.air().kgm3()]))
	# And the course it was lifted off is still the same track, so the best lap set on it at 920 m
	# is still reachable after the file changed schema underneath it.
	results.append(TestResult.new(
		"and the migrated course is still the same track, so its best lap is not orphaned",
		authored.selected().fingerprint() == PRE_AIR_DEFAULT_FINGERPRINT,
		"%s (was %s)" % [authored.selected().fingerprint(), PRE_AIR_DEFAULT_FINGERPRINT]))
	for scratch in [v1_path, v1_sites]:
		if FileAccess.file_exists(scratch):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))

	# A damaged block is standard air rather than a crash or a NaN, on the same rule the rest of
	# this file follows: a bad document lands somewhere flyable and the app opens.
	for junk: Variant in [null, "somewhere warm", {"elevation_m": "high"}, {"temperature_c": []}, []]:
		var recovered := AirDensity.from_data(junk)
		results.append(TestResult.new(
			"a damaged air block reads as standard air rather than NaN (%s)" % JSON.stringify(junk),
			absf(recovered.kgm3() - AirDensity.standard_kgm3()) < 1.0e-12,
			"%.6f kg/m3" % recovered.kgm3()))

	# The formula has a fractional power of (1 - L*h/T0), which is NaN for a large enough
	# elevation. Clamping is what keeps "nan g" off the stats panel.
	for absurd in [1.0e9, -1.0e9, 44331.0]:
		var clamped := AirDensity.new(absurd, 15.0).kgm3()
		results.append(TestResult.new(
			"an absurd elevation (%.0f m) gives a real density, never NaN" % absurd,
			not is_nan(clamped) and clamped > 0.0,
			"%.6f kg/m3" % clamped))

	DirAccess.remove_absolute(LIBRARY_PATH)
	return results


## Every key name appearing anywhere in a document, sorted. Compared rather than the raw bytes so
## the check is about SHAPE — a key added, a key dropped — and not about float formatting.
static func _keys_of(document: String) -> PackedStringArray:
	var found: Dictionary = {}
	var regex := RegEx.create_from_string("\"([a-z_]+)\"\\s*:")
	for match_result in regex.search_all(document):
		found[match_result.get_string(1)] = true
	var keys: PackedStringArray = PackedStringArray(found.keys())
	keys.sort()
	return keys


# ---------------------------------------------------------------------------
# 6. The invariant Lab's readout rests on
# ---------------------------------------------------------------------------

## Lab reads the air of the SELECTED course's SITE, and the design's answer to "what happens when
## no field is selected" is that there is no such state. That answer is worth exactly as much as
## this test: every path into CourseLibrary must leave a selection that resolves, and the site it
## names must answer with air.
##
## Since F1 that is TWO libraries deep, which is one more place for the invariant to break: a
## course may resolve and still point at a site that is not there. So the site half is checked on
## a library that has never heard of the ids these courses carry, which is the shape a builder
## gets when they delete a field.
static func _library_always_has_a_selection() -> Array:
	var results: Array = []

	var checks := {
		"a fresh library": CourseLibrary.with_default(),
		"a library loaded from nothing at all": CourseLibrary.load_from("user://does_not_exist.json"),
	}

	var unknown_selection := CourseLibrary.with_default()
	unknown_selection.selected_id = "no_such_course"
	unknown_selection.save(LIBRARY_PATH)
	checks["a file naming a course that is not there"] = CourseLibrary.load_from(LIBRARY_PATH)

	var junk := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	junk.store_string("{ not json at all")
	junk.close()
	checks["a file that is not JSON"] = CourseLibrary.load_from(LIBRARY_PATH)

	var after_remove := CourseLibrary.with_default()
	after_remove.create("Second")
	after_remove.remove(after_remove.selected_id)
	checks["a library whose selected course was removed"] = after_remove

	var refused := CourseLibrary.with_default()
	refused.select("no_such_course")
	checks["a library after a refused select()"] = refused

	# A site library that knows only the default field — so every course below whose site_id is
	# anything else has to fall back rather than hand back nothing.
	var sites := SiteLibrary.with_default()
	for label in checks:
		var library: CourseLibrary = checks[label]
		var course := library.selected()
		var where: Site = null
		if course != null:
			where = sites.site(course.site_id)
			if where == null:
				where = sites.selected()
		results.append(TestResult.new(
			"%s still resolves to a course, and to a place with air" % label,
			course != null and where != null and where.air().kgm3() > 0.0,
			"selected \"%s\", air %s" % [library.selected_id,
				"nowhere" if where == null else "%.4f kg/m3" % where.air().kgm3()]))

	DirAccess.remove_absolute(LIBRARY_PATH)
	return results


# ---------------------------------------------------------------------------
# 7. Best laps, which are a fact about a track — and the air is part of the track
# ---------------------------------------------------------------------------

static func _fingerprint() -> Array:
	var results: Array = []

	# THE GOLDEN VALUE. Not "the same as itself", which would pass against any implementation: this
	# is the default circuit's fingerprint as it stood BEFORE air existed, pasted in. If air is
	# folded into the hash unconditionally this changes, and every best lap anyone has ever set
	# becomes unreachable — silently, because an orphaned record looks exactly like no record.
	var standard_course := GateCourse.new()
	results.append(TestResult.new(
		"the default circuit's fingerprint at standard air is unchanged by this slice",
		standard_course.fingerprint() == PRE_AIR_DEFAULT_FINGERPRINT,
		"%s (was %s)" % [standard_course.fingerprint(), PRE_AIR_DEFAULT_FINGERPRINT]))

	# But a lap flown in 36% thinner air is not comparable to a sea-level lap on the same rings, and
	# reporting one as the other is the stale record this whole mechanism exists to prevent.
	# The air is PASSED IN since F1 — a course no longer carries one, the site does — and an absent
	# argument means standard, which is what keeps the golden value above true.
	var thin := AirDensity.new(3500.0, 20.0)
	var high_course := GateCourse.new()
	results.append(TestResult.new(
		"the same rings at 3500 m are a different track, so records do not cross over",
		high_course.fingerprint(thin) != standard_course.fingerprint(),
		"3500 m: %s vs standard: %s" % [
			high_course.fingerprint(thin), standard_course.fingerprint()]))

	# And a thermometer read a tenth of a degree differently must NOT retire a record — the same
	# reason gate positions round to a millimetre.
	var jitter := AirDensity.new(3500.0, 20.001)
	var jittered := GateCourse.new()
	results.append(TestResult.new(
		"a hundredth of a degree does not retire a record",
		jittered.fingerprint(jitter) == high_course.fingerprint(thin),
		"%s vs %s" % [jittered.fingerprint(jitter), high_course.fingerprint(thin)]))
	return results
