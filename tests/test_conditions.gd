class_name TestConditions
extends RefCounted
## The weather — wind, gustiness and temperature — and the air composed from it and the site.
##
## Four things could go wrong here, and every one of them goes wrong QUIETLY, which is why each
## gets a section rather than a line:
##
## **1. The oracle could move.** 507.48 g / 11.43:1 / 29.92% are asserted in half a dozen files,
## and all of them are quoted at standard air. If `compose(default site, Standard)` is anything but
## bit-identical to `AirDensity.standard()`, every one of those becomes a statement about this
## slice's rounding. §2 and §3 pin it at both ends: the density itself, and the three numbers.
##
## **2. `compose` could read the wrong half of the wrong object.** Elevation from the site,
## temperature from the conditions — swap them, or read the site's own parked slot instead of the
## weather's, and a fresh install still looks perfect because 0 m and 15 °C and a null slot all
## read as standard. §2 puts a 2000 m site against a 35 °C set with a DIFFERENT temperature parked
## on it, which is the only arrangement the three candidate implementations disagree about.
##
## **3. Switching the weather could edit the builder's files.** The whole point of a switchable set
## is asking "what does this do on a hot day" without authoring anything. §4 compares the BYTES of
## `sites.json` and `courses.json` across a select.
##
## **4. The hand-off could invent rows.** F1 parked a temperature on every site, from a v1 course
## or from the spinbox, and F2 drains it. A builder who never typed one must finish with exactly
## one set — `Standard` — and no "15 °C" row beside it saying the same thing twice. §5.

const CONDITIONS_PATH := "user://test_conditions.json"
const SITES_PATH := "user://test_conditions_sites.json"
const COURSES_PATH := "user://test_conditions_courses.json"

## The three fixed points, at standard air, to the tolerances `tests/test_air_density.gd` uses.
## Repeated here rather than imported because this section's job is to be a SECOND witness: a
## constant read off the file that also computes the build would move with it.
const INVARIANT_MASS_G := 507.48
const INVARIANT_TWR := 11.43
const INVARIANT_HOVER_PCT := 29.92


static func run() -> Array:
	var results: Array = []
	var sections := {
		"a fresh install": _a_fresh_install(),
		"composed air": _composed_air(),
		"the reference build": _the_reference_build(),
		"switching costs nothing": _switching_writes_nothing(),
		"the parked temperature": _the_parked_temperature(),
		"the file": _the_file(),
		"four authored fields": _four_authored_fields(),
		"the garage": _the_garage_quotes_the_selection(),
	}
	# A runtime error partway through a section aborts only that section and its append never runs,
	# so the suite would pass with its best checks silently deleted. Asserting each section
	# produced something is what makes the count trustworthy — and what makes a mutation run
	# evidence rather than an anecdote.
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


## Rewrites a JSON document with a tab indent — the same document, in bytes the app's own writer
## would never produce. See the use site: this is what makes "nothing wrote this file" detectable
## without depending on a second boundary.
static func _reindent(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var document := JsonStore.read_document(path)
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(JSON.stringify(document, "\t"))
	handle.close()


static func _forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------------------
# 1. A fresh install ships one weather, and every damaged file opens on it
# ---------------------------------------------------------------------------

static func _a_fresh_install() -> Array:
	var results: Array = []
	_forget(CONDITIONS_PATH)

	# CHECK 1.
	var fresh := ConditionsLibrary.load_from(CONDITIONS_PATH)
	var only: Conditions = fresh.selected() if fresh != null else null
	results.append(TestResult.new(
		"a fresh install has exactly one set of conditions: Standard, calm, at 15 C",
		fresh != null and fresh.ids().size() == 1
			and fresh.selected_id == Conditions.STANDARD_ID
			and only != null and only.conditions_name == Conditions.STANDARD_NAME
			and only.is_calm()
			and absf(only.temperature_c - AirDensity.STANDARD_TEMPERATURE_C) < 1.0e-9,
		"%d set(s): %s%s" % [
			0 if fresh == null else fresh.ids().size(),
			"none" if fresh == null else ", ".join(fresh.names()),
			"" if only == null else " at %.1f C, calm %s" % [only.temperature_c, only.is_calm()]]))

	# `is_calm()` has to be capable of saying no, or the check above is asserting a constant. A set
	# with no steady wind and a real gust amplitude is the case that catches the half-written
	# version: it is not calm, and a `wind_speed_mps`-only test would call it calm.
	var breezy := Conditions.new()
	breezy.wind_speed_mps = 4.0
	var gusty := Conditions.new()
	gusty.gustiness_mps = 3.0
	results.append(TestResult.new(
		"and is_calm() says no to a steady wind AND to a gust amplitude with no steady wind",
		not breezy.is_calm() and not gusty.is_calm(),
		"4 m/s steady calm=%s, 0 m/s steady with 3 m/s gusts calm=%s" % [
			breezy.is_calm(), gusty.is_calm()]))

	# Every file-level failure there is, each landing on Standard rather than on an error dialog.
	var damaged := {
		"a file that is not there": "",
		"a truncated document": "{\"schema\": 1, \"conditions\": [",
		"a document that is not an object": "[1, 2, 3]",
		"a document of the wrong shape": "{\"schema\": 1, \"conditions\": \"windy\"}",
		"an empty file": "",
	}
	for label in damaged:
		_forget(CONDITIONS_PATH)
		var contents: String = damaged[label]
		if label != "a file that is not there":
			var handle := FileAccess.open(CONDITIONS_PATH, FileAccess.WRITE)
			handle.store_string(contents)
			handle.close()
		var opened := ConditionsLibrary.load_from(CONDITIONS_PATH)
		results.append(TestResult.new(
			"%s opens on Standard rather than stopping the app" % label,
			opened != null and opened.selected() != null
				and opened.selected().conditions_id == Conditions.STANDARD_ID,
			"nothing at all" if opened == null else "opened \"%s\"" % opened.selected_id))

	_forget(CONDITIONS_PATH)
	return results


# ---------------------------------------------------------------------------
# 2. compose(): which half comes from where
# ---------------------------------------------------------------------------

static func _composed_air() -> Array:
	var results: Array = []

	# CHECK 2. Bit-identical, not "close". Every headline number in this project is quoted at
	# standard air, and a tenth of a degree of drift in here moves all of them by a digit nobody
	# would look for.
	var default_site := Site.new()
	var composed := AirDensity.compose(default_site, Conditions.standard())
	var standard := AirDensity.standard()
	results.append(TestResult.new(
		"compose(default site, Standard) is bit-identical to AirDensity.standard()",
		composed.kgm3() == standard.kgm3()
			and composed.elevation_m == standard.elevation_m
			and composed.temperature_c == standard.temperature_c,
		# String.num to 17 places rather than a format string: GDScript does not implement %g, and
		# %f rounds away exactly the digits this check is about.
		"%s vs %s kg/m3" % [String.num(composed.kgm3(), 17), String.num(standard.kgm3(), 17)]))
	results.append(TestResult.new(
		"and it therefore reports itself as standard air, so nothing warns about a fresh install",
		composed.is_standard(),
		"is_standard() = %s" % composed.is_standard()))

	# CHECK 4. THE ONLY ARRANGEMENT THE THREE CANDIDATE IMPLEMENTATIONS DISAGREE ABOUT.
	#
	# A 2000 m site, a 35 C set, and a DIFFERENT temperature (5 C) parked on the site. Swap the two
	# arguments and you get 35 m at 2000 C, which the constructor clamps to 80 C — visibly wrong.
	# Read the site's parked slot instead of the weather's and you get 2000 m at 5 C, which is a
	# perfectly plausible density and wrong by 11%. Without the parked value being DIFFERENT, that
	# second mutation passes.
	var high := Site.new()
	high.site_id = "high"
	high.elevation_m = 2000.0
	high.parked_temperature_c = 5.0
	var hot := Conditions.new()
	hot.conditions_id = "hot"
	hot.temperature_c = 35.0
	var expected := AirDensity.new(2000.0, 35.0)
	var actual := AirDensity.compose(high, hot)
	results.append(TestResult.new(
		"compose reads elevation from the SITE and temperature from the CONDITIONS",
		actual.elevation_m == expected.elevation_m
			and actual.temperature_c == expected.temperature_c
			and actual.kgm3() == expected.kgm3(),
		"%.1f m / %.1f C / %.6f kg/m3 (expected %.1f m / %.1f C / %.6f)" % [
			actual.elevation_m, actual.temperature_c, actual.kgm3(),
			expected.elevation_m, expected.temperature_c, expected.kgm3()]))
	# And the site's own parked slot is genuinely a different answer, or the check above cannot
	# fail on an implementation that reads it.
	var from_parked := AirDensity.new(2000.0, 5.0)
	results.append(TestResult.new(
		"and the temperature parked on that site is a DIFFERENT density, so that check can fail",
		absf(from_parked.kgm3() - expected.kgm3()) > 0.05,
		"parked-slot reading %.6f vs conditions reading %.6f kg/m3" % [
			from_parked.kgm3(), expected.kgm3()]))

	# A missing half is the standard half rather than a crash — a world nobody has told about its
	# weather is the world every number here was quoted in.
	results.append(TestResult.new(
		"a null site or a null weather composes to the standard half rather than crashing",
		AirDensity.compose(null, hot).temperature_c == 35.0
			and AirDensity.compose(null, hot).elevation_m == 0.0
			and AirDensity.compose(high, null).elevation_m == 2000.0
			and AirDensity.compose(high, null).temperature_c
				== AirDensity.STANDARD_TEMPERATURE_C,
		"no site: %.1f m/%.1f C, no weather: %.1f m/%.1f C" % [
			AirDensity.compose(null, hot).elevation_m,
			AirDensity.compose(null, hot).temperature_c,
			AirDensity.compose(high, null).elevation_m,
			AirDensity.compose(high, null).temperature_c]))
	return results


# ---------------------------------------------------------------------------
# 3. The three fixed points, unmoved under the default site and Standard
# ---------------------------------------------------------------------------

## CHECK 3. The same three numbers `test_air_density.gd` pins, composed through the new path
## instead of defaulted through the constructor. If `compose` swapped its arguments, or offset the
## temperature by a tenth of a degree, this is where it shows up as a number a human would notice.
static func _the_reference_build() -> Array:
	var results: Array = []
	var air := AirDensity.compose(Site.new(), Conditions.standard())
	var build := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID,
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, {}, air)

	results.append(TestResult.new(
		"composed from the default site and Standard, all-up weight is still 507.5 g",
		absf(build.all_up_weight_g() - INVARIANT_MASS_G) < 0.05,
		"%.2f g" % build.all_up_weight_g()))
	results.append(TestResult.new(
		"and thrust-to-weight is still 11.43:1",
		absf(build.thrust_to_weight() - INVARIANT_TWR) < 0.01,
		"%.4f:1" % build.thrust_to_weight()))
	results.append(TestResult.new(
		"and hover throttle is still 29.9%",
		absf(build.hover_throttle() * 100.0 - INVARIANT_HOVER_PCT) < 0.05,
		"%.2f%%" % (build.hover_throttle() * 100.0)))

	# WITHOUT THIS, THE THREE ABOVE ARE WORTHLESS — test_air_density's own argument, and it applies
	# with more force here because `compose` is a brand new path. A build wired to ignore the
	# composed air entirely passes all three. So a hot day at altitude must give a DIFFERENT
	# thrust-to-weight through the same call.
	var hot := Conditions.new()
	hot.temperature_c = 35.0
	var where := Site.new()
	where.elevation_m = 2000.0
	var elsewhere := Build.from_ids(PartsCatalog.load_default(), ReferenceBuild.FRAME_ID,
		ReferenceBuild.MOTOR_ID, ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID,
		ReferenceBuild.ESC_ID, ReferenceBuild.FC_ID, {}, AirDensity.compose(where, hot))
	results.append(TestResult.new(
		"the same parts at 2000 m and 35 C give a DIFFERENT figure, so the three above can fail",
		absf(elsewhere.thrust_to_weight() - build.thrust_to_weight()) > 1.0,
		"2000 m / 35 C: %.2f:1 vs standard %.2f:1" % [
			elsewhere.thrust_to_weight(), build.thrust_to_weight()]))
	return results


# ---------------------------------------------------------------------------
# 4. Switching the weather writes nothing
# ---------------------------------------------------------------------------

## CHECK 5. The interaction this whole object exists for: ask what the build does on a hot day, and
## author nothing by asking. A version of `select()` that saved a site or a course would be editing
## the builder's own data to answer a question — and it would do it once per click, invisibly.
static func _switching_writes_nothing() -> Array:
	var results: Array = []
	for scratch in [CONDITIONS_PATH, SITES_PATH, COURSES_PATH]:
		_forget(scratch)

	var sites := SiteLibrary.with_default()
	var bando := sites.create("Bando")
	bando.elevation_m = 920.0
	sites.select(bando.site_id)
	sites.save(SITES_PATH)

	var courses := CourseLibrary.with_default()
	courses.selected().site_id = bando.site_id
	courses.save(COURSES_PATH)

	# THE REAL PATHS ARE WATCHED TOO, and that is not belt-and-braces. A library that wrote a site
	# on select() would not write this section's scratch file — it has no handle on it — it would
	# write `user://sites.json`, the one the app opens. Watching only the scratch pair gives a check
	# that cannot fail on the mutation it exists for, which is exactly what the first version of
	# this was. Both real files are recorded here and compared below; nothing in this section edits
	# them, so there is nothing to restore.
	var real_sites_existed := FileAccess.file_exists(SiteLibrary.SAVE_PATH)
	var real_courses_existed := FileAccess.file_exists(CourseLibrary.SAVE_PATH)
	# The builder's own bytes, captured BEFORE the re-indent below so that they are what goes back.
	var real_sites_original := FileAccess.get_file_as_string(SiteLibrary.SAVE_PATH) \
		if real_sites_existed else ""
	var real_courses_original := FileAccess.get_file_as_string(CourseLibrary.SAVE_PATH) \
		if real_courses_existed else ""
	# AND THEY ARE RE-INDENTED AND PUT BACK, exactly as the two scratch files below are, because
	# the mtime alone is not a reliable instrument: it has one-second resolution, and whether a
	# rewrite lands on a later second than the read depends on where in the second the section
	# started. Measured — the same mutant reddened this check when run alone and passed it when run
	# straight after another suite had touched the file. Flaky-green is the worse direction, so the
	# real files are put into a form the app's own writer does not emit for the length of this
	# section and restored byte-exactly at the end of it. Whitespace only; not one value moves.
	_reindent(SiteLibrary.SAVE_PATH)
	_reindent(CourseLibrary.SAVE_PATH)

	# AND THEIR MODIFICATION TIMES, because bytes alone cannot see this one. Both libraries
	# round-trip byte-identically by design, so a `select()` that loaded and re-saved the real
	# sites file would leave every byte where it was and still have rewritten a builder's file.
	# Measured: the mutation this check exists for passed all 43 checks until the mtimes were
	# added. A second's resolution is enough — the assertion is "not rewritten", and a rewrite
	# lands on a later second than the read that preceded the whole section often enough to catch
	# it; what makes it airtight is the pair, bytes for content and stamp for the act.
	var real_sites_before := FileAccess.get_file_as_string(SiteLibrary.SAVE_PATH) \
		if real_sites_existed else ""
	var real_courses_before := FileAccess.get_file_as_string(CourseLibrary.SAVE_PATH) \
		if real_courses_existed else ""
	var real_sites_stamp := FileAccess.get_modified_time(SiteLibrary.SAVE_PATH) \
		if real_sites_existed else 0
	var real_courses_stamp := FileAccess.get_modified_time(CourseLibrary.SAVE_PATH) \
		if real_courses_existed else 0

	# THE TWO SCRATCH FILES ARE RE-WRITTEN WITH A TAB INDENT, and that is the instrument rather
	# than untidiness. `FileAccess.get_modified_time()` has one-second resolution and these files
	# were written microseconds ago, so a mutant that loaded and re-saved them would land inside
	# the same second and leave the stamp alone — and the bytes alone cannot see it either, because
	# both libraries round-trip byte-identically by design. Flaky-green is the worse direction, so
	# the watched bytes are put into a form the writer does NOT emit: `JsonStore` indents with two
	# spaces, so any save at all normalises these and the byte comparison reddens without waiting
	# for a clock tick. The documents are unchanged; only their whitespace is.
	_reindent(SITES_PATH)
	_reindent(COURSES_PATH)

	var sites_before := FileAccess.get_file_as_string(SITES_PATH)
	var courses_before := FileAccess.get_file_as_string(COURSES_PATH)
	var sites_stamp := FileAccess.get_modified_time(SITES_PATH)
	var courses_stamp := FileAccess.get_modified_time(COURSES_PATH)

	var weather := ConditionsLibrary.with_default()
	var afternoon := weather.create("Hot afternoon")
	afternoon.temperature_c = 38.0
	var cold := AirDensity.compose(sites.selected(), weather.selected()).kgm3()
	var switched := weather.select(afternoon.conditions_id)
	var warm := AirDensity.compose(sites.selected(), weather.selected()).kgm3()

	results.append(TestResult.new(
		"selecting a different set of conditions changes the density",
		switched and absf(warm - cold) > 0.02,
		"%.6f kg/m3 at Standard, %.6f kg/m3 at 38 C" % [cold, warm]))
	var real_sites_same := (FileAccess.file_exists(SiteLibrary.SAVE_PATH) == real_sites_existed
		and FileAccess.get_file_as_string(SiteLibrary.SAVE_PATH) == real_sites_before
		and (not real_sites_existed
			or FileAccess.get_modified_time(SiteLibrary.SAVE_PATH) == real_sites_stamp))
	var real_courses_same := (FileAccess.file_exists(CourseLibrary.SAVE_PATH)
		== real_courses_existed
		and FileAccess.get_file_as_string(CourseLibrary.SAVE_PATH) == real_courses_before
		and (not real_courses_existed
			or FileAccess.get_modified_time(CourseLibrary.SAVE_PATH) == real_courses_stamp))
	results.append(TestResult.new(
		"and it writes nothing to sites.json or courses.json — same bytes, same mtime",
		FileAccess.get_file_as_string(SITES_PATH) == sites_before
			and FileAccess.get_file_as_string(COURSES_PATH) == courses_before
			and FileAccess.get_modified_time(SITES_PATH) == sites_stamp
			and FileAccess.get_modified_time(COURSES_PATH) == courses_stamp
			and real_sites_same and real_courses_same,
		"sites %s, courses %s, the app's own sites.json %s, courses.json %s" % [
			"untouched" if FileAccess.get_file_as_string(SITES_PATH) == sites_before
				else "REWRITTEN",
			"untouched" if FileAccess.get_file_as_string(COURSES_PATH) == courses_before
				else "REWRITTEN",
			"untouched" if real_sites_same else "REWRITTEN",
			"untouched" if real_courses_same else "REWRITTEN"]))
	# AND THE INSTRUMENT IS PROVED, not assumed. The check above can only catch a write if a write
	# would show — so a COPY of the watched file is loaded and re-saved here, and its bytes must
	# move. If `_reindent` ever stopped mattering, this goes red and says so, instead of the
	# check above going quietly blind.
	var probe := "user://test_conditions_probe_sites.json"
	_forget(probe)
	var probe_handle := FileAccess.open(probe, FileAccess.WRITE)
	probe_handle.store_string(sites_before)
	probe_handle.close()
	SiteLibrary.load_from(probe).save(probe)
	results.append(TestResult.new(
		"and a save really would change those bytes, so the check above is not blind to one",
		FileAccess.get_file_as_string(probe) != sites_before,
		"a load and re-save of the same document %s the bytes" % [
			"CHANGED" if FileAccess.get_file_as_string(probe) != sites_before else "left"]))
	_forget(probe)

	# And the elevation is still coming off the site through all of that, so the check above is
	# about the temperature rather than about nothing.
	results.append(TestResult.new(
		"and the elevation is still the site's 920 m on both sides of the switch",
		AirDensity.compose(sites.selected(), weather.selected()).elevation_m == 920.0,
		"%.1f m" % AirDensity.compose(sites.selected(), weather.selected()).elevation_m))

	# The builder's own two files go back exactly as they were found — whitespace included.
	_put_back(SiteLibrary.SAVE_PATH, real_sites_existed, real_sites_original)
	_put_back(CourseLibrary.SAVE_PATH, real_courses_existed, real_courses_original)
	results.append(TestResult.new(
		"and the builder's own sites.json and courses.json are put back byte for byte",
		(FileAccess.file_exists(SiteLibrary.SAVE_PATH) == real_sites_existed)
			and (not real_sites_existed
				or FileAccess.get_file_as_string(SiteLibrary.SAVE_PATH) == real_sites_original)
			and (FileAccess.file_exists(CourseLibrary.SAVE_PATH) == real_courses_existed)
			and (not real_courses_existed
				or FileAccess.get_file_as_string(CourseLibrary.SAVE_PATH)
					== real_courses_original),
		"sites %s, courses %s" % [
			"identical" if FileAccess.get_file_as_string(SiteLibrary.SAVE_PATH)
				== real_sites_original else "CHANGED",
			"identical" if FileAccess.get_file_as_string(CourseLibrary.SAVE_PATH)
				== real_courses_original else "CHANGED"]))

	for scratch in [CONDITIONS_PATH, SITES_PATH, COURSES_PATH]:
		_forget(scratch)
	return results


static func _put_back(path: String, had_file: bool, contents: String) -> void:
	if not had_file:
		_forget(path)
		return
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(contents)
	handle.close()


# ---------------------------------------------------------------------------
# 5. F1's parked temperature, moved rather than discarded — and not duplicated
# ---------------------------------------------------------------------------

## CHECK 6. A set per DISTINCT temperature. The failure this guards is not losing the number, it is
## inventing rows: a builder who never typed a temperature has 15 °C parked on every site they own
## once a v1 file migrates, and the naive hand-off gives them a "15 °C" row beside `Standard`
## saying exactly the same thing — one per site.
static func _the_parked_temperature() -> Array:
	var results: Array = []

	# Nobody typed anything: every site is standard, and the answer is one row and no more.
	var plain := SiteLibrary.with_default()
	plain.selected().parked_temperature_c = 15.0
	var quiet := ConditionsLibrary.with_default()
	var quiet_moved := quiet.absorb_parked_temperatures(plain)
	results.append(TestResult.new(
		"a 15 C parked temperature produces NO new set — it is Standard, and it is already here",
		quiet.ids().size() == 1 and quiet.selected_id == Conditions.STANDARD_ID
			and quiet_moved,
		"%d set(s): %s, selected \"%s\"" % [
			quiet.ids().size(), ", ".join(quiet.names()), quiet.selected_id]))
	results.append(TestResult.new(
		"and the slot is cleared back to null rather than to 15.0",
		plain.selected().parked_temperature_c == null,
		"slot holds %s" % str(plain.selected().parked_temperature_c)))

	# Two sites at one temperature and a third at another: two rows, not three, and not four.
	var several := SiteLibrary.with_default()
	several.selected().parked_temperature_c = 35.0
	var second := several.create("Second bando")
	second.parked_temperature_c = 35.0
	var third := several.create("Leh")
	third.elevation_m = 3500.0
	third.parked_temperature_c = 5.0
	var library := ConditionsLibrary.with_default()
	var moved := library.absorb_parked_temperatures(several)
	results.append(TestResult.new(
		"two sites parked at 35 C and one at 5 C produce exactly two new sets, named after them",
		moved and library.ids().size() == 3
			and library.names().has("35 °C") and library.names().has("5 °C"),
		"%d set(s): %s" % [library.ids().size(), ", ".join(library.names())]))
	# The SELECTED site's temperature is the one selected, so the app quotes the same density after
	# the hand-off as before it. The default site is the selected one here and it was parked at 35.
	results.append(TestResult.new(
		"the selected site's own temperature is the set left selected, so the density does not move",
		absf(library.selected().temperature_c - 35.0) < 1.0e-9,
		"selected \"%s\" at %.1f C" % [library.selected_id, library.selected().temperature_c]))
	var slots_cleared := true
	for id in several.ids():
		if several.site(id).parked_temperature_c != null:
			slots_cleared = false
	results.append(TestResult.new(
		"and every slot is cleared, so a second launch finds nothing left to move",
		slots_cleared and not library.absorb_parked_temperatures(several)
			and library.ids().size() == 3,
		"%d set(s) after a second pass, slots cleared %s" % [
			library.ids().size(), slots_cleared]))

	# The value really did survive. Moving a number and then losing it is the other half of the
	# failure, and a check that only counted rows would not see it.
	results.append(TestResult.new(
		"and 5 C really is on the set that was made for it",
		library.at_temperature(5.0).temperature_c == 5.0
			and library.at_temperature(5.0).is_calm(),
		"%s at %.1f C" % [library.at_temperature(5.0).conditions_name,
			library.at_temperature(5.0).temperature_c]))

	# THE PLACE IS AN ARGUMENT, NOT `sites.selected()`, and this is the check for it. The coverage
	# for this distinction lived entirely in `test_site.gd` §5 — a file this slice did not write —
	# and the section above only ever exercises the default. The case is the real one: on a first
	# launch against a v1 file the migration appends a site per course and leaves the library's own
	# selection on the DEFAULT field, while the place the builder is at is the site of the selected
	# course. Reading the library's selection absorbs the wrong site's temperature and the garage
	# quotes the right elevation at the wrong degree.
	var elsewhere := SiteLibrary.with_default()
	elsewhere.selected().parked_temperature_c = 15.0
	var away := elsewhere.create("Hill bando")
	away.elevation_m = 2500.0
	away.parked_temperature_c = 28.0
	var told := ConditionsLibrary.with_default()
	var told_moved := told.absorb_parked_temperatures(elsewhere, away)
	results.append(TestResult.new(
		"told which site the builder is at, it selects THAT site's temperature, not the library's",
		told_moved and absf(told.selected().temperature_c - 28.0) < 1.0e-9,
		"selected \"%s\" at %.1f C" % [told.selected_id, told.selected().temperature_c]))

	# And left to itself it follows the library's selection — so the argument is doing something,
	# rather than the two answers being the same and the check passing either way.
	var untold_sites := SiteLibrary.with_default()
	untold_sites.selected().parked_temperature_c = 15.0
	var untold_away := untold_sites.create("Hill bando")
	untold_away.elevation_m = 2500.0
	untold_away.parked_temperature_c = 28.0
	var untold := ConditionsLibrary.with_default()
	var untold_moved := untold.absorb_parked_temperatures(untold_sites)
	results.append(TestResult.new(
		"and left to itself it follows the library's own selection, so the argument is not inert",
		untold_moved
			and absf(untold.selected().temperature_c - AirDensity.STANDARD_TEMPERATURE_C) < 1.0e-9
			and untold.selected_id != told.selected_id,
		"untold selected \"%s\" at %.1f C, told selected \"%s\" at %.1f C" % [
			untold.selected_id, untold.selected().temperature_c,
			told.selected_id, told.selected().temperature_c]))

	# A WINDY SET AT THE SAME TEMPERATURE IS NOT A MATCH. Handing it back would add a wind nobody
	# asked for to a garage figure, silently.
	var windy := ConditionsLibrary.with_default()
	var breezy := windy.create("Breezy")
	breezy.temperature_c = 28.0
	breezy.wind_speed_mps = 6.0
	var found := windy.at_temperature(28.0)
	results.append(TestResult.new(
		"at_temperature() skips a set that is the right temperature in a wind, and makes a calm one",
		found.conditions_id != breezy.conditions_id and found.is_calm()
			and found.temperature_c == 28.0 and windy.ids().size() == 3,
		"found \"%s\" (calm %s), %d set(s)" % [
			found.conditions_name, found.is_calm(), windy.ids().size()]))
	return results


# ---------------------------------------------------------------------------
# 6. The file, and the promise that Lothal does not rewrite a builder's weather
# ---------------------------------------------------------------------------

## CHECK 7. The four `JsonStore` rules, the same way `test_site.gd` §2 asks them.
static func _the_file() -> Array:
	var results: Array = []
	_forget(CONDITIONS_PATH)

	# Written through JsonStore, the same writer the app uses, for the reason test_site records:
	# hand-rolling a fixture with JSON.stringify fails the byte comparison on the indent string
	# rather than on anything under test. Keys in the order the writer emits them, unknowns first
	# at both levels, because JSON preserves insertion order and this compares BYTES.
	var fixture := {
		"forecast": {"source": "met"},
		"schema": 1,
		"selected": "monsoon",
		"conditions": [{
			"humidity_pct": 90.0,
			"id": "monsoon",
			"name": "Monsoon",
			"wind_speed_mps": 6.5,
			"wind_from_deg": 225.0,
			"gustiness_mps": 3.25,
			"temperature_c": 27.5,
		}],
	}
	JsonStore.write_document(CONDITIONS_PATH, fixture)
	var before := FileAccess.get_file_as_string(CONDITIONS_PATH)

	var loaded := ConditionsLibrary.load_from(CONDITIONS_PATH)
	loaded.save(CONDITIONS_PATH)
	var after := FileAccess.get_file_as_string(CONDITIONS_PATH)

	results.append(TestResult.new(
		"a set of conditions round-trips to a byte-identical file",
		before == after,
		"%d bytes in, %d bytes out, %s" % [before.length(), after.length(),
			"identical" if before == after else "CHANGED"]))

	var raw := JsonStore.read_document(CONDITIONS_PATH)
	var kept: Dictionary = {}
	for entry in (raw.get("conditions", []) as Array):
		if (entry as Dictionary).get("id", "") == "monsoon":
			kept = entry
	results.append(TestResult.new(
		"fields a later version wrote survive a load and save, at the top level and inside a set",
		raw.has("forecast") and kept.has("humidity_pct"),
		"kept top-level %s, and the set's humidity_pct = %s" % [
			"forecast" if raw.has("forecast") else "NOTHING", kept.get("humidity_pct", "nothing")]))

	var monsoon := loaded.conditions("monsoon")
	results.append(TestResult.new(
		"and the four authored numbers come back exactly as they were written",
		monsoon != null and monsoon.wind_speed_mps == 6.5 and monsoon.wind_from_deg == 225.0
			and monsoon.gustiness_mps == 3.25 and monsoon.temperature_c == 27.5
			and not monsoon.is_calm(),
		"nothing" if monsoon == null else "%.2f m/s from %.0f deg, gusts %.2f, %.1f C" % [
			monsoon.wind_speed_mps, monsoon.wind_from_deg, monsoon.gustiness_mps,
			monsoon.temperature_c]))

	# A set with no id cannot be selected, so it is dropped rather than given a generated one —
	# and a document of nothing but such sets opens on Standard rather than on emptiness.
	_forget(CONDITIONS_PATH)
	JsonStore.write_document(CONDITIONS_PATH, {
		"schema": 1, "selected": "", "conditions": [{"name": "Nameless"}]})
	var idless := ConditionsLibrary.load_from(CONDITIONS_PATH)
	results.append(TestResult.new(
		"a set with no id is dropped, and a file of nothing else opens on Standard",
		idless.ids().size() == 1 and idless.selected_id == Conditions.STANDARD_ID,
		"%d set(s), selected \"%s\"" % [idless.ids().size(), idless.selected_id]))

	# A selection pointing at a set that is not in the file lands on one that is, rather than on
	# nothing — the same rule every other library here follows.
	_forget(CONDITIONS_PATH)
	JsonStore.write_document(CONDITIONS_PATH, {
		"schema": 1, "selected": "gone",
		"conditions": [{"id": "monsoon", "name": "Monsoon", "wind_speed_mps": 6.5,
			"wind_from_deg": 225.0, "gustiness_mps": 3.25, "temperature_c": 27.5}]})
	var dangling := ConditionsLibrary.load_from(CONDITIONS_PATH)
	results.append(TestResult.new(
		"a selection pointing at a set that is not there lands on one that is",
		dangling.selected() != null and dangling.selected_id == "monsoon",
		"selected \"%s\"" % dangling.selected_id))

	_forget(CONDITIONS_PATH)
	return results


# ---------------------------------------------------------------------------
# 7. Four authored fields, and a fifth is a design change
# ---------------------------------------------------------------------------

## CHECK 8. Enumerated against a literal list rather than counted, because a count passes when one
## field is swapped for another — and the thing being defended is not "how many", it is "which".
static func _four_authored_fields() -> Array:
	var results: Array = []
	var record := Conditions.standard().to_data()
	var keys: Array = record.keys()
	keys.sort()

	var expected := ["gustiness_mps", "id", "name", "temperature_c", "wind_from_deg",
		"wind_speed_mps"]
	results.append(TestResult.new(
		"a set writes exactly six keys: the two that identify it and the four it authors",
		keys == expected,
		"wrote %s" % str(keys)))

	var authored: Array = []
	for key in keys:
		if key != "id" and key != "name":
			authored.append(key)
	results.append(TestResult.new(
		"and the four authored ones are wind speed, wind bearing, gustiness and temperature",
		authored == ["gustiness_mps", "temperature_c", "wind_from_deg", "wind_speed_mps"],
		"authored %s" % str(authored)))

	# AND `AUTHORED_KEYS` SAYS THE SAME FOUR. It was asserted by its SIZE alone, which is the
	# cannot-fail class: swap a field inside it for another and a count of four still passes.
	# Nothing in src/ reads this constant, so the literal is the only thing that can hold it to
	# what the class claims about itself — and it is the SAME literal the check above uses, sorted,
	# rather than a second spelling free to drift from it.
	var named: Array = Conditions.AUTHORED_KEYS.duplicate()
	named.sort()
	results.append(TestResult.new(
		"and AUTHORED_KEYS names those same four, by content rather than by count",
		named == authored,
		"AUTHORED_KEYS = %s against the keys actually written %s" % [named, authored]))
	return results


# ---------------------------------------------------------------------------
# 8. The garage quotes the site it is at, in the weather it has chosen
# ---------------------------------------------------------------------------

## CHECK 9. `RoomHost` composes Lab's air from the SELECTED site and the SELECTED conditions. The
## mutation this exists for is the one a well-meaning change makes: composing from the default site
## or from `Conditions.standard()`, both of which read identically on a fresh install and are wrong
## for everybody who has typed an elevation or switched to a hot day.
##
## THE REAL PATHS ARE POISONED AND PUT BACK, for `test_air_density.gd` §4's measured reason: a
## version of this written against scratch files would read a fresh library at standard air and
## look innocent no matter what RoomHost did.
static func _the_garage_quotes_the_selection() -> Array:
	var results: Array = []
	var paths := [CourseLibrary.SAVE_PATH, SiteLibrary.SAVE_PATH, ConditionsLibrary.SAVE_PATH]
	var saved: Dictionary = {}
	var had: Dictionary = {}
	for path in paths:
		had[path] = FileAccess.file_exists(path)
		saved[path] = FileAccess.get_file_as_string(path) if had[path] else ""

	var sites := SiteLibrary.with_default()
	var bando := sites.create("Test bando")
	bando.elevation_m = 2000.0
	sites.select(bando.site_id)
	sites.save(SiteLibrary.SAVE_PATH)

	var courses := CourseLibrary.with_default()
	courses.selected().site_id = bando.site_id
	courses.save(CourseLibrary.SAVE_PATH)

	var weather := ConditionsLibrary.with_default()
	var hot := weather.create("Hot")
	hot.temperature_c = 35.0
	weather.select(hot.conditions_id)
	weather.save(ConditionsLibrary.SAVE_PATH)

	var rooms := RoomHost.new()
	var quoted := rooms.air_of_selected_course()
	var expected := AirDensity.new(2000.0, 35.0)
	results.append(TestResult.new(
		"RoomHost composes the garage's air from the selected site and the selected conditions",
		quoted.elevation_m == expected.elevation_m
			and quoted.temperature_c == expected.temperature_c,
		"%.1f m / %.1f C (expected %.1f m / %.1f C)" % [
			quoted.elevation_m, quoted.temperature_c,
			expected.elevation_m, expected.temperature_c]))
	results.append(TestResult.new(
		"and Lab is quoting that same air rather than a standard one, so the door hands it over",
		rooms.lab.air != null and rooms.lab.air.kgm3() == expected.kgm3()
			and absf(expected.kgm3() - AirDensity.standard_kgm3()) > 0.1,
		"lab %.6f kg/m3, expected %.6f, standard %.6f" % [
			-1.0 if rooms.lab.air == null else rooms.lab.air.kgm3(),
			expected.kgm3(), AirDensity.standard_kgm3()]))
	rooms.free()

	for path in paths:
		if not bool(had[path]):
			_forget(path)
			continue
		var handle := FileAccess.open(path, FileAccess.WRITE)
		handle.store_string(String(saved[path]))
		handle.close()
	return results
