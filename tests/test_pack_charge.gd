class_name TestPackCharge
extends RefCounted
## Persistent pack charge — the one thing in Lothal that crosses the Lab/Sim boundary backwards
## (labs-and-sim.md §4), and the consequence that makes owning two packs mean something (§5).
##
## Two of the checks in this file could pass while proving nothing, and both are written
## specifically so they cannot.
##
## ---------------------------------------------------------------------------
## 1. PERSISTENCE, WITHOUT EVER TOUCHING DISK
## ---------------------------------------------------------------------------
##
## The natural test is a round trip: set a value, save, load, assert. It passes on a save() that
## writes nothing and a load() that hands back the object already in memory — and that is not a
## hypothetical, it is precisely how the first PackCharge in this branch was written, as a
## deliberately wrong stub that returned defaults without opening the file.
##
## So every persistence assertion here goes through a FRESH loader that has never seen the object
## that wrote the file, and the awkward cases are exercised with real malformed files on disk
## rather than with hand-built dictionaries.
##
## ---------------------------------------------------------------------------
## 2. DRAIN RATE, WHERE "IT WENT DOWN" TELLS YOU NOTHING
## ---------------------------------------------------------------------------
##
## Asserting that capacity decreases passes for any positive number. It passes for a drain sixty
## times too fast, which is the classic seconds-versus-minutes slip and is the single most likely
## bug in this whole area — and it is invisible, because a pack that empties in four seconds and a
## pack that empties in four minutes both look like a pack emptying.
##
## The check is therefore two independent routes to one figure, the way the thrust stand's slice
## checked itself. Build predicts flight time ANALYTICALLY from hover current and capacity;
## Powertrain reaches empty DYNAMICALLY by integrating drain at hover over simulated time. A 60x
## error converges either way and disagrees loudly here.
##
## Files are written under a test-only path so the suite never depends on, or overwrites, the
## configuration of whoever is running it.

const TEST_PATH := "user://test_pack_charge.json"
const DT := 0.002

const PACK_A := "battery_4s_1500"
const PACK_B := "battery_4s_1300"

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_it_actually_reaches_disk())
	results.append_array(_test_a_file_from_the_future_survives())
	results.append_array(_test_a_broken_file_loads_as_defaults())
	results.append_array(_test_charge_is_per_pack())
	results.append_array(_test_drain_runs_at_one_to_one(catalog))
	results.append_array(_test_charging_is_compressed(catalog))
	results.append_array(_test_a_bench_run_costs_charge_that_survives_the_app(catalog))
	results.append_array(_test_every_room_shares_one_shelf())

	return results


# ---------------------------------------------------------------------------
# One shelf, and only written when something happened
# ---------------------------------------------------------------------------

## Two claims about the shell. First, that every room is looking at ONE set of packs — a bench
## holding its own copy would drain a battery that the field then flew as though it were full.
## Second, that walking through a room without doing anything writes nothing, which matters more
## than it sounds: AppShell saves on every room change to the real user:// file, and without the
## check this suite would overwrite the packs of whoever is running it with an empty shelf.
static func _test_every_room_shares_one_shelf() -> Array:
	var results: Array = []
	var shell := AppShell.new()

	shell.show_battery_bench()
	var bench_store := shell.battery_bench.pack_charge
	shell.show_lab()
	shell.show_bench()
	var stand_store := shell.bench.pack_charge
	shell.show_lab()
	shell.show_sim()
	var sim_store = shell.sim.pack_charge
	shell.show_lab()

	results.append(TestResult.new(
		"the two benches, the field and Lab all read and write ONE set of packs",
		bench_store == shell.pack_charge and stand_store == shell.pack_charge
			and sim_store == shell.pack_charge and shell.lab.pack_charge == shell.pack_charge,
		"one PackCharge instance across Lab, both benches and Sim"
	))

	results.append(TestResult.new(
		"walking through every room without running anything leaves nothing to save",
		not shell.pack_charge.has_unsaved_changes(),
		"has_unsaved_changes = %s after four room changes" % shell.pack_charge.has_unsaved_changes()
	))

	shell.free()
	return results


static func _clean() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


static func _write_raw(text: String) -> void:
	var handle := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()


static func _read_raw() -> String:
	return FileAccess.get_file_as_string(TEST_PATH)


# ---------------------------------------------------------------------------
# It reaches disk, and comes back to something that has never seen it
# ---------------------------------------------------------------------------

static func _test_it_actually_reaches_disk() -> Array:
	var results: Array = []
	_clean()

	var written := PackCharge.new()
	written.set_used_mah(PACK_A, 412.5)
	written.set_compression(1.0)
	var saved := written.save(TEST_PATH)

	results.append(TestResult.new(
		"saving pack charge produces an actual file with the value in its text",
		saved and FileAccess.file_exists(TEST_PATH) and _read_raw().contains("412.5"),
		"%d bytes on disk" % _read_raw().length()
	))

	# The load-bearing line: a loader constructed from the PATH, with no reference of any kind to
	# the object that wrote it. An in-memory round trip cannot pass this.
	var fresh := PackCharge.load_from(TEST_PATH)
	results.append(TestResult.new(
		"a fresh loader that has never seen the writer reads the charge back off disk",
		is_equal_approx(fresh.used_mah(PACK_A), 412.5),
		"read %.1f mAh where 412.5 was written" % fresh.used_mah(PACK_A)
	))

	results.append(TestResult.new(
		"the charging compression setting survives the round trip too",
		is_equal_approx(fresh.charge_compression, 1.0),
		"read %.1f:1 where 1.0:1 was written" % fresh.charge_compression
	))

	# A pack nobody has used is absent from the file, not stored as a zero — an absent pack is a
	# full one, which is the right default for a battery that has never been flown.
	results.append(TestResult.new(
		"a pack that has never been used is absent from the file and reads as full",
		not _read_raw().contains(PACK_B) and fresh.is_full(PACK_B)
			and is_equal_approx(fresh.remaining_fraction(PACK_B, 1300.0), 1.0),
		"%s is not in the file and reads as %.0f%% charged" % [
			PACK_B, fresh.remaining_fraction(PACK_B, 1300.0) * 100.0]
	))

	_clean()
	return results


## A file written by a later version of Lothal holds fields this one has never heard of — a cycle
## count, a storage-charge date, a pack it does not have in its catalog. Opening an older build
## must not silently destroy them. Checked against the file's TEXT after a save, because that is
## the only place the loss would show.
static func _test_a_file_from_the_future_survives() -> Array:
	var results: Array = []
	_clean()

	_write_raw("""{
		"schema": 1,
		"charge_compression": 4.0,
		"packs": {
			"battery_4s_1500": { "used_mah": 300.0, "cycles": 42, "last_storage_charge": "2027-01-04" },
			"battery_9s_9000_unobtainium": { "used_mah": 12.0 }
		},
		"charger_profile": { "amps": 3.0 }
	}""")

	var loaded := PackCharge.load_from(TEST_PATH)
	results.append(TestResult.new(
		"a file from the future still yields the charge this version does understand",
		is_equal_approx(loaded.used_mah(PACK_A), 300.0)
			and is_equal_approx(loaded.charge_compression, 4.0),
		"%.0f mAh used at %.1f:1" % [loaded.used_mah(PACK_A), loaded.charge_compression]
	))

	loaded.set_used_mah(PACK_A, 500.0)
	loaded.save(TEST_PATH)
	var text := _read_raw()

	results.append(TestResult.new(
		"saving over it keeps every unknown field — top level, inside a pack, and a whole pack",
		text.contains("cycles") and text.contains("last_storage_charge")
			and text.contains("charger_profile")
			and text.contains("battery_9s_9000_unobtainium")
			and text.contains("500"),
		"the rewritten file still carries all four unknowns alongside the updated 500 mAh"
			if text.contains("cycles") and text.contains("charger_profile")
			else "lost fields — file is now: %s" % text
	))

	# ...and the unknowns come back through a fresh loader too, rather than only surviving as text.
	var again := PackCharge.load_from(TEST_PATH)
	again.save(TEST_PATH)
	results.append(TestResult.new(
		"the unknowns survive a SECOND round trip, so they are held rather than merely copied once",
		_read_raw().contains("cycles") and _read_raw().contains("charger_profile"),
		"still present after two saves through two separate loaders"
	))

	_clean()
	return results


## Missing, truncated, not JSON at all, valid JSON of the wrong shape, and a value of the wrong
## type. Every one of them has to load as defaults rather than stop the app, and every one is
## exercised with a real file on disk rather than a hand-built dictionary — the point is the
## parsing, and a dictionary skips exactly the step under test.
static func _test_a_broken_file_loads_as_defaults() -> Array:
	var results: Array = []

	var cases := {
		"a file that is not there": null,
		"an empty file": "",
		"truncated mid-write": "{\"schema\": 1, \"packs\": {\"battery_4s_1500\": {\"used_",
		"not JSON at all": "this is not a save file",
		"JSON, but an array": "[1, 2, 3]",
		"the right shape with a packs block of the wrong type": "{\"schema\": 1, \"packs\": 7}",
		"a pack block that is not a block": "{\"packs\": {\"battery_4s_1500\": \"lots\"}}",
		"a used_mah that is not a number": "{\"packs\": {\"battery_4s_1500\": {\"used_mah\": \"half\"}}}",
		"a compression that is not a number": "{\"charge_compression\": \"fast\", \"packs\": {}}",
	}

	var survivors: Array = []
	var all_defaulted := true
	for name in cases:
		_clean()
		if cases[name] != null:
			_write_raw(cases[name])
		var loaded := PackCharge.load_from(TEST_PATH)
		# Defaults means: a full pack, and the default compression. Not a crash, and not a
		# half-populated configuration either.
		if not loaded.is_full(PACK_A) or loaded.charge_compression <= 0.0:
			all_defaulted = false
			survivors.append("%s -> %.1f mAh at %.1f:1" % [
				name, loaded.used_mah(PACK_A), loaded.charge_compression])

	results.append(TestResult.new(
		"every way a save file can be broken loads as defaults instead of stopping the app",
		all_defaulted,
		"%d malformed files on disk, all loaded as a full pack" % cases.size()
			if all_defaulted else "; ".join(survivors)
	))

	# A wrong-typed value must be treated as ABSENT rather than coerced. float("half") is 0.0, and
	# a silent zero here is a pack reported as full when the file said something unreadable.
	_clean()
	_write_raw("{\"packs\": {\"battery_4s_1500\": {\"used_mah\": \"half\"}}}")
	var coerced := PackCharge.load_from(TEST_PATH)
	results.append(TestResult.new(
		"a value of the wrong type is treated as absent rather than coerced to zero",
		coerced.is_full(PACK_A),
		"%s reads as %.0f%% charged" % [PACK_A, coerced.remaining_fraction(PACK_A, 1500.0) * 100.0]
	))

	_clean()
	return results


## §5's whole argument for why more than one pack is worth owning. Two packs, one flown flat and
## one untouched, have to be two different states — and they have to still be two different states
## after a trip through the file.
static func _test_charge_is_per_pack() -> Array:
	var results: Array = []
	_clean()

	var charge := PackCharge.new()
	charge.set_used_mah(PACK_A, 1400.0)
	charge.save(TEST_PATH)

	var fresh := PackCharge.load_from(TEST_PATH)
	results.append(TestResult.new(
		"flying one 4S pack flat leaves the other one full, across a save and a reload",
		fresh.remaining_fraction(PACK_A, 1500.0) < 0.1
			and is_equal_approx(fresh.remaining_fraction(PACK_B, 1300.0), 1.0),
		"%s at %.0f%%, %s at %.0f%%" % [
			PACK_A, fresh.remaining_fraction(PACK_A, 1500.0) * 100.0,
			PACK_B, fresh.remaining_fraction(PACK_B, 1300.0) * 100.0]
	))

	_clean()
	return results


# ---------------------------------------------------------------------------
# 1:1, cross-checked by two independent routes
# ---------------------------------------------------------------------------

## The check the header is about. Neither route knows the other exists: Build solves flight time
## from hover current and capacity with arithmetic, and Powertrain gets there by integrating
## BatteryModel.drain over simulated time at 1 kHz.
static func _test_drain_runs_at_one_to_one(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var build := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, PACK_A)

	# Solved at the voltage a FULL pack rests at, because that is the pack the run below starts
	# with. Since nominal voltage became an operating point rather than full charge
	# (physics.md §5), Build's default figures are quoted a couple of volts below where a fresh
	# battery actually sits, and the two routes have to be asked the same question to be evidence.
	var full_rest_v := build.battery_model().resting_voltage_v()
	var hover := build.hover_throttle(full_rest_v)
	var hover_current_a := build.hover_current_a(hover, full_rest_v)

	# --- The tight one, at full charge, where nothing else is moving ---
	#
	# Thirty seconds at hover. Short enough that the pack's resting voltage has barely fallen, so
	# the current is essentially the one Build predicted and the ONLY thing being compared is the
	# unit conversion inside drain(). This is where a 60x slip is caught to the digit rather than
	# to the order of magnitude.
	var pt := _powertrain_for(build)
	pt.prime(hover)
	var seconds := 30.0
	for _i in int(seconds / DT):
		pt.step({"M1": hover, "M2": hover, "M3": hover, "M4": hover}, DT)

	var expected_mah := hover_current_a * (seconds / 3600.0) * 1000.0
	var actual_mah := pt.battery.used_mah
	results.append(TestResult.new(
		"30 s of integrated drain matches the charge Build's hover current says it should cost",
		absf(actual_mah - expected_mah) / expected_mah < 0.02,
		"%.2f mAh integrated vs %.2f mAh predicted (%.1f A for 30 s) — a 60x slip would read %.0f" % [
			actual_mah, expected_mah, hover_current_a, expected_mah * 60.0]
	))

	# --- The whole-pack one, run to empty ---
	#
	# Build.flight_time_min() is quoted on 80% of the pack at 1.6x hover current, because real
	# flying averages above hover and packs are landed with reserve. Undoing both factors gives
	# the time to empty AT hover current, which is what the dynamic run below actually does.
	var analytic_s := build.flight_time_min() * 60.0 \
		* (1.0 / Build.USABLE_CAPACITY_FRACTION) * Build.FLIGHT_CURRENT_TO_HOVER_RATIO

	var runner := _powertrain_for(build)
	runner.prime(hover)
	var elapsed := 0.0
	var step := 0.05
	var guard := 0
	while runner.battery.remaining_fraction() > 0.0 and guard < 200000:
		runner.step({"M1": hover, "M2": hover, "M3": hover, "M4": hover}, step)
		elapsed += step
		guard += 1

	# The two do not agree exactly, and the reason is physics rather than slack: at a FIXED
	# throttle the motors slow down as the pack's resting voltage falls, so they draw less current
	# and the pack lasts longer than a constant-current prediction says. That is worth a fifth of
	# the run. It is nowhere near a factor of sixty.
	var ratio := elapsed / analytic_s
	results.append(TestResult.new(
		"integrating drain to empty agrees with Build's analytic flight time, which knows nothing of it",
		ratio > 0.85 and ratio < 1.35,
		"%.0f s integrated vs %.0f s analytic (%.2fx) — a 60x drain error would read %.2fx" % [
			elapsed, analytic_s, ratio, ratio / 60.0]
	))

	# And the sanity floor the two-route check exists to replace: this is a four-minute pack, so
	# it has to take minutes rather than seconds or hours. Stated in absolute terms because both
	# routes above would still agree with each other if both were wrong by the same factor.
	results.append(TestResult.new(
		"a four-minute pack takes minutes to flatten in real time, not seconds and not an hour",
		elapsed > 120.0 and elapsed < 900.0,
		"%.0f s (%.1f min) at hover on a %.0f mAh pack drawing %.1f A" % [
			elapsed, elapsed / 60.0, build.battery["specs"]["mah"], hover_current_a]
	))

	return results


static func _powertrain_for(build: Build) -> Powertrain:
	var geometry := build.prop_geometry()
	return Powertrain.new(
		build.motor_model(), build.k_t, build.k_q, build.battery_model(),
		build.effective_max_amps, build.rated_rpm(),
		build.pole_pairs(), geometry.blades, geometry.diameter_m * 0.5)


# ---------------------------------------------------------------------------
# Charging: compressed, and a setting
# ---------------------------------------------------------------------------

static func _test_charging_is_compressed(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var capacity := float(catalog.get_part(PACK_A)["specs"]["mah"])

	var charge := PackCharge.new()
	charge.set_used_mah(PACK_A, capacity)
	var compressed_s := charge.seconds_to_full(PACK_A, capacity)

	charge.set_compression(1.0)
	var real_time_s := charge.seconds_to_full(PACK_A, capacity)

	results.append(TestResult.new(
		"a full charge takes about 45 minutes at 1:1, and a tenth of that at the default 10:1",
		absf(real_time_s - PackCharge.FULL_CHARGE_S) < 1.0
			and absf(compressed_s - PackCharge.FULL_CHARGE_S / PackCharge.DEFAULT_COMPRESSION) < 1.0,
		"%.0f s at 1:1 against %.0f s at %.0f:1" % [
			real_time_s, compressed_s, PackCharge.DEFAULT_COMPRESSION]
	))

	# Charging actually puts charge back, at the rate it claims, and stops at full rather than
	# running past it into a negative used_mah.
	var topping_up := PackCharge.new()
	topping_up.set_used_mah(PACK_A, capacity)
	topping_up.charge(PACK_A, PackCharge.FULL_CHARGE_S / PackCharge.DEFAULT_COMPRESSION * 0.5, capacity)
	var halfway := topping_up.remaining_fraction(PACK_A, capacity)

	topping_up.charge(PACK_A, PackCharge.FULL_CHARGE_S, capacity)
	results.append(TestResult.new(
		"charging restores at the rate it claims and stops at full rather than overfilling",
		absf(halfway - 0.5) < 0.02 and topping_up.is_full(PACK_A)
			and topping_up.used_mah(PACK_A) == 0.0,
		"half a charge left it at %.0f%%; a long charge finished at %.0f mAh used" % [
			halfway * 100.0, topping_up.used_mah(PACK_A)]
	))

	# Charging is a Lab activity, and the compression is a setting rather than a constant.
	var slow := PackCharge.new()
	slow.set_compression(1.0)
	slow.set_used_mah(PACK_A, capacity)
	var fast := PackCharge.new()
	fast.set_used_mah(PACK_A, capacity)
	slow.charge(PACK_A, 60.0, capacity)
	fast.charge(PACK_A, 60.0, capacity)
	results.append(TestResult.new(
		"the compression is a setting: a minute on the charger puts back 10x as much at 10:1",
		fast.used_mah(PACK_A) < slow.used_mah(PACK_A),
		"after 60 s: %.0f mAh still missing at 1:1, %.0f mAh at %.0f:1" % [
			slow.used_mah(PACK_A), fast.used_mah(PACK_A), PackCharge.DEFAULT_COMPRESSION]
	))

	return results


# ---------------------------------------------------------------------------
# The acceptance criterion, end to end
# ---------------------------------------------------------------------------

## "A bench run leaves the pack partly empty; that charge is still gone after quitting and
## reopening the app; charging in the garage restores it." Run as one sequence, through the real
## bench and a real file, because the interesting failures are all at the joins — a bench that
## drains a copy, a save that happens before the run finishes, a Lab that reads a different file.
static func _test_a_bench_run_costs_charge_that_survives_the_app(catalog: PartsCatalog) -> Array:
	var results: Array = []
	_clean()

	var charge := PackCharge.new()
	var bench := BatteryBenchScreen.new(catalog, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, PACK_A, charge)

	bench.set_load_mode(BatteryBenchScreen.Load.PUNCH)
	bench.set_running(true)
	for _i in 80:
		bench.advance(0.25)
	var used_on_the_bench := bench.powertrain.battery.used_mah
	bench.persist_pack_charge()
	charge.save(TEST_PATH)
	bench.free()

	results.append(TestResult.new(
		"a bench run costs real charge, because a motor on a stand is drawing current",
		used_on_the_bench > 100.0,
		"%.0f mAh gone after 20 s of full-throttle bench time" % used_on_the_bench
	))

	# The app closing and opening again, as far as this file is concerned.
	var after_restart := PackCharge.load_from(TEST_PATH)
	results.append(TestResult.new(
		"that charge is still gone after the app has been closed and reopened",
		absf(after_restart.used_mah(PACK_A) - used_on_the_bench) < 1.0,
		"%.0f mAh still missing where %.0f was used" % [
			after_restart.used_mah(PACK_A), used_on_the_bench]
	))

	# ...and a bench opened on that pack starts where the last run left off rather than on a
	# freshly charged one. This is the assertion that a seeded-from-disk bench passes and a bench
	# that always builds a full pack does not.
	var second_bench := BatteryBenchScreen.new(catalog, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, PACK_A, after_restart)
	results.append(TestResult.new(
		"the bench opens on the pack as it actually is, not on a freshly charged one",
		absf(second_bench.powertrain.battery.used_mah - used_on_the_bench) < 1.0,
		"bench opened at %.0f%% charge" % (
			second_bench.powertrain.battery.remaining_fraction() * 100.0)
	))
	second_bench.free()

	# Charging in the garage puts it back.
	var capacity := float(catalog.get_part(PACK_A)["specs"]["mah"])
	after_restart.charge(PACK_A, after_restart.seconds_to_full(PACK_A, capacity), capacity)
	after_restart.save(TEST_PATH)
	var charged := PackCharge.load_from(TEST_PATH)
	results.append(TestResult.new(
		"charging in the garage restores it, and that survives a restart too",
		charged.is_full(PACK_A),
		"%s back to %.0f%%" % [PACK_A, charged.remaining_fraction(PACK_A, capacity) * 100.0]
	))

	_clean()
	return results
