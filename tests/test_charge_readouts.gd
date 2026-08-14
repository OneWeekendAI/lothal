class_name TestChargeReadouts
extends RefCounted
## What the two rooms say about the pack: the garage's charger and the field's HUD.
##
## Both were silent about things the model already knew. PackCharge.seconds_to_full() existed and
## nothing displayed it, so there was no way to tell how long a recharge would take; the HUD
## reported volts and amps, which say what the pack is doing now and nothing about how much longer
## you have.
##
## ---------------------------------------------------------------------------
## THE ASSERTIONS ARE THAT THE UI AGREES WITH THE MODEL, NOT THAT IT SAYS SOMETHING
## ---------------------------------------------------------------------------
##
## A readout test that only checked for non-empty text would pass on a panel showing plausible
## nonsense. So every figure here is checked against the class that OWNS it — PackCharge for
## charge and both clocks, BatteryModel for the voltages, Build for the minutes — which is also
## the check that the UI has not quietly grown its own arithmetic. That is the failure mode worth
## defending against: two places in this project computing a pack's voltage is exactly how the
## garage and the field come to disagree about one battery.
##
## Every Control built here is freed, or the runner emits leaked-RID ERROR lines that read like
## failures.

const HALF := 0.5


static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_the_charger_states_the_pack(catalog))
	results.append_array(_test_the_charger_shows_both_clocks(catalog))
	results.append_array(_test_the_countdown_counts_down(catalog))
	results.append_array(_test_the_charger_runs_unattended(catalog))
	results.append_array(_test_the_shelf_separates_flat_from_charged(catalog))
	results.append_array(_test_the_hud_shows_charge_and_time_left(catalog))

	return results


## A charger panel pointed at the reference pack, with that pack part-used.
static func _panel(catalog: PartsCatalog, used_fraction: float) -> PackChargePanel:
	var charge := PackCharge.new()
	var build := ReferenceBuild.build()
	charge.set_used_mah(ReferenceBuild.BATTERY_ID,
		float(build.battery["specs"]["mah"]) * used_fraction)
	var panel := PackChargePanel.new(charge, catalog)
	panel.render(build)
	return panel


# ---------------------------------------------------------------------------
# State of charge, capacity, and the voltages
# ---------------------------------------------------------------------------

static func _test_the_charger_states_the_pack(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var panel := _panel(catalog, HALF)
	var text := panel.readout_text()

	var build := ReferenceBuild.build()
	var capacity: float = float(build.battery["specs"]["mah"])

	results.append(TestResult.new(
		"the charger says the state of charge as a percentage AND in mAh",
		text["summary"].contains("50 %") and text["summary"].contains("%.0f" % (capacity * HALF))
			and text["summary"].contains("%.0f" % capacity),
		"summary reads \"%s\"" % text["summary"]
	))

	# The voltages have to be the model's, to the digit shown. A panel that derived its own would
	# pass a "looks like a voltage" check and drift from the aircraft the first time the curve
	# changed — which is precisely what just happened to the curve.
	var pack := build.battery_model()
	pack.used_mah = pack.capacity_mah * (1.0 - HALF)
	results.append(TestResult.new(
		"resting voltage and per-cell voltage are BatteryModel's, shown to the digit",
		text["volts"].contains("%.2f V resting" % pack.resting_voltage_v())
			and text["volts"].contains("%.2f V per cell" % pack.resting_cell_v()),
		"panel reads \"%s\"; model says %.2f V / %.2f V per cell" % [
			text["volts"], pack.resting_voltage_v(), pack.resting_cell_v()]
	))

	# ...and the per-cell figure is the one a builder judges by, so it must be a real cell voltage
	# rather than the pack's. A 4S at half charge is a 3.79 V cell, not a 15.16 V one.
	results.append(TestResult.new(
		"the per-cell figure is a cell voltage, not the pack's divided by nothing",
		pack.resting_cell_v() > 3.0 and pack.resting_cell_v() < 4.3
			and is_equal_approx(pack.resting_cell_v() * 4.0, pack.resting_voltage_v()),
		"%.2f V per cell across %d cells = %.2f V" % [
			pack.resting_cell_v(), pack.cells, pack.resting_voltage_v()]
	))

	panel.free()
	return results


# ---------------------------------------------------------------------------
# Both clocks, and the compression between them
# ---------------------------------------------------------------------------

## The compressed wait and the real one, together. Either alone is a half-truth: "4:30" hides what
## is being compressed, and "45:00" is not the wait the user is going to have.
static func _test_the_charger_shows_both_clocks(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var panel := _panel(catalog, HALF)
	var text := panel.readout_text()

	var capacity: float = float(ReferenceBuild.build().battery["specs"]["mah"])
	var compressed := panel.charge.seconds_to_full(ReferenceBuild.BATTERY_ID, capacity)
	var real := panel.charge.real_seconds_to_full(ReferenceBuild.BATTERY_ID, capacity)

	results.append(TestResult.new(
		"the charger shows the compressed wait AND the real one it stands for",
		text["clock"].contains(Duration.spoken(compressed))
			and text["clock"].contains(Duration.spoken(real))
			and text["clock"].contains("10:1"),
		"clock reads \"%s\" (compressed %.0f s, real %.0f s)" % [
			text["clock"], compressed, real]
	))

	# The real figure has to be the compression factor times the compressed one, or the two
	# numbers on screen are not two views of one wait.
	results.append(TestResult.new(
		"the real wait is the compressed wait times the compression factor",
		is_equal_approx(real, compressed * panel.charge.charge_compression),
		"%.0f s = %.0f s x %.0f" % [real, compressed, panel.charge.charge_compression]
	))

	# At 1:1 there is nothing to compress, and claiming a compression would be noise.
	panel.charge.set_compression(1.0)
	panel._refresh()
	var real_time: String = panel.readout_text()["clock"]
	results.append(TestResult.new(
		"at 1:1 the charger says so plainly instead of quoting a compression of one",
		real_time.contains("real time") and not real_time.contains(":1,"),
		"clock reads \"%s\"" % real_time
	))

	panel.free()
	return results


## ---------------------------------------------------------------------------
## A CHARGER YOU HAVE TO STAND IN FRONT OF IS NOT A CHARGER
## ---------------------------------------------------------------------------
##
## The charger used to be stopped by `render()`, which Lab calls on EVERY selection change —
## so picking a different frame, motor or propeller, none of which is the pack on the charger,
## silently took the pack off it. The user found this by leaving a pack charging and clicking
## around: 45 compressed minutes of charge quietly never happened, and nothing said so.
##
## The rule these three checks pin down: what is ON the charger is what was put on it. What is
## SELECTED only decides what the panel is showing you. The two are allowed to differ, and the
## charger keeps running while they do — which is the entire point of a charger on a bench.
static func _test_the_charger_runs_unattended(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var panel := _panel(catalog, HALF)
	var capacity: float = float(ReferenceBuild.build().battery["specs"]["mah"])

	panel.set_charging(true)
	for _i in 30:
		panel.tick(1.0)
	var before := panel.charge.used_mah(ReferenceBuild.BATTERY_ID)

	# Look at a different FRAME. Same pack, and it is still the pack on the charger — nothing
	# about this click went anywhere near the battery rail.
	var other_frame := Build.from_ids(catalog, "frame_7in_long_range", ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID)
	panel.render(other_frame)

	results.append(TestResult.new(
		"changing a part that is not the pack leaves the charger running",
		panel.charging,
		"charger reports charging = %s after the frame changed" % panel.charging
	))

	for _i in 30:
		panel.tick(1.0)
	var after := panel.charge.used_mah(ReferenceBuild.BATTERY_ID)
	results.append(TestResult.new(
		"...and it is still actually putting charge in, not merely claiming to be on",
		after < before - 1.0,
		"%.1f mAh used -> %.1f mAh used over 30 s after the change" % [before, after]
	))

	# Now walk over to a DIFFERENT PACK. The charger does not follow the eye: the pack that was
	# put on it stays on it and keeps filling while a second one is being read about.
	var other_pack := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, "battery_6s_1300", ReferenceBuild.ESC_ID)
	panel.render(other_pack)
	var before_away := panel.charge.used_mah(ReferenceBuild.BATTERY_ID)
	for _i in 30:
		panel.tick(1.0)
	var after_away := panel.charge.used_mah(ReferenceBuild.BATTERY_ID)

	results.append(TestResult.new(
		"a pack left on the charger keeps charging while a different pack is on screen",
		after_away < before_away - 1.0
			and panel.charge.used_mah("battery_6s_1300") == 0.0,
		"%.1f -> %.1f mAh used on the charged pack; the pack being looked at moved %.1f mAh" % [
			before_away, after_away, panel.charge.used_mah("battery_6s_1300")]
	))

	# The countdown is now describing a pack you cannot see, so it has to say WHICH pack, or it
	# is a number with no subject.
	results.append(TestResult.new(
		"and the panel names the pack that is on the charger when it is not the one shown",
		panel.readout_text()["clock"].contains(ReferenceBuild.build().battery["name"]),
		"clock reads \"%s\"" % panel.readout_text()["clock"]
	))

	# Capacity comes from the pack ON the charger, not the one on screen — a 1500 mAh pack must
	# not fill at a 1300 mAh pack's rate because the eye wandered. Checked as the mAh actually
	# delivered over those 30 s, against both rates: the wrong one is a distinguishable number,
	# which is the only reason this assertion can fail.
	var delivered := before_away - after_away
	var charged_rate := panel.charge.charge_rate_mah_per_s(capacity) * 30.0
	var displayed_rate := panel.charge.charge_rate_mah_per_s(
		float(catalog.get_part("battery_6s_1300")["specs"]["mah"])) * 30.0
	results.append(TestResult.new(
		"the charge rate is the charged pack's, not the displayed pack's",
		is_equal_approx(delivered, charged_rate) and not is_equal_approx(charged_rate, displayed_rate),
		"delivered %.2f mAh in 30 s; the %.0f mAh pack's rate gives %.2f, the 1300 mAh pack's %.2f" % [
			delivered, capacity, charged_rate, displayed_rate]
	))

	# Leaving with the pack unplugs it — and only that pack. A room that flies or benches a pack
	# snapshots it on entry and writes it back on exit, so a charger still running into one has
	# its whole contribution overwritten on the way back: you would return with LESS than you
	# left. Charging a pack you are not taking with you is exactly the case worth keeping.
	results.append(TestResult.new(
		"taking a DIFFERENT pack out of the garage leaves the charger alone",
		not panel.release("battery_6s_1300") and panel.charging,
		"released the 6S; charger reports charging = %s" % panel.charging
	))
	results.append(TestResult.new(
		"taking the CHARGED pack out unplugs it, rather than letting the room overwrite it",
		panel.release(ReferenceBuild.BATTERY_ID) and not panel.charging,
		"released the charged pack; charger reports charging = %s" % panel.charging
	))

	panel.free()
	return results


## A countdown that does not count down is a figure quoted once. Charging for a while has to move
## the number the user is watching.
static func _test_the_countdown_counts_down(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var panel := _panel(catalog, HALF)

	var capacity: float = float(ReferenceBuild.build().battery["specs"]["mah"])
	var before := panel.charge.seconds_to_full(ReferenceBuild.BATTERY_ID, capacity)
	var before_text: String = panel.readout_text()["clock"]

	panel.set_charging(true)
	for _i in 60:
		panel.tick(1.0)
	var after := panel.charge.seconds_to_full(ReferenceBuild.BATTERY_ID, capacity)
	var after_text: String = panel.readout_text()["clock"]

	results.append(TestResult.new(
		"a minute on the charger puts charge in and takes it off the countdown",
		after < before - 1.0 and after_text != before_text,
		"%s -> %s" % [Duration.spoken(before), Duration.spoken(after)]
	))

	# ...and it stops at full rather than running against a pack that cannot take any more.
	for _i in 600:
		panel.tick(1.0)
	results.append(TestResult.new(
		"the charger stops itself at full and says so",
		panel.charge.is_full(ReferenceBuild.BATTERY_ID) and not panel.charging
			and panel.readout_text()["clock"].contains("Full"),
		"\"%s\" / button \"%s\"" % [panel.readout_text()["clock"], panel.readout_text()["button"]]
	))

	panel.free()
	return results


# ---------------------------------------------------------------------------
# The shelf
# ---------------------------------------------------------------------------

## Owning two packs only means something if both are visible at once (labs-and-sim.md §5). The
## shelf has to separate the one worth fitting from the one that needs charging, by name.
static func _test_the_shelf_separates_flat_from_charged(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var charge := PackCharge.new()
	var flat_pack := catalog.get_part("battery_4s_1300")
	var used_pack := catalog.get_part(ReferenceBuild.BATTERY_ID)
	charge.set_used_mah("battery_4s_1300", float(flat_pack["specs"]["mah"]) * 0.95)
	charge.set_used_mah(ReferenceBuild.BATTERY_ID, float(used_pack["specs"]["mah"]) * 0.4)

	var panel := PackChargePanel.new(charge, catalog)
	panel.render(ReferenceBuild.build())
	var shelf: String = panel.readout_text()["shelf"]

	results.append(TestResult.new(
		"the shelf names the flat pack as flat and the part-used one as part-used",
		shelf.contains("flat") and shelf.contains(str(flat_pack["name"]))
			and shelf.contains("part-used") and shelf.contains(str(used_pack["name"])),
		"shelf reads \"%s\"" % shelf
	))

	# A pack never flown is a full pack, and listing every full pack would turn the shelf into a
	# copy of the catalog rather than a thing you can read at a glance.
	results.append(TestResult.new(
		"packs that have never been flown are not listed, because a full pack needs no decision",
		not shelf.contains("6S 1100") and shelf.contains("full"),
		"shelf reads \"%s\"" % shelf
	))

	panel.free()

	var untouched := PackChargePanel.new(PackCharge.new(), catalog)
	untouched.render(ReferenceBuild.build())
	results.append(TestResult.new(
		"a shelf of untouched packs says so in one line rather than listing them all",
		untouched.readout_text()["shelf"] == "Shelf: every pack full.",
		"reads \"%s\"" % untouched.readout_text()["shelf"]
	))
	untouched.free()

	return results


# ---------------------------------------------------------------------------
# The HUD
# ---------------------------------------------------------------------------

## Remaining charge and remaining flying, alongside the volts and amps that were already there,
## and both moving while the aircraft flies.
static func _test_the_hud_shows_charge_and_time_left(_catalog: PartsCatalog) -> Array:
	var results: Array = []

	var build := ReferenceBuild.build()
	var core := build.build_drone_core()
	var course := GateCourse.new()
	var timer := LapTimer.new(course.fingerprint())
	var hud := Hud.new()

	var throttle := build.hover_throttle_for(core.powertrain.battery)
	core.prime_motors(throttle)
	hud.render(core, build, course, timer, true)
	var at_spawn: String = hud._pack_label.text

	results.append(TestResult.new(
		"the HUD reports a full pack as full, with flying time left on it",
		at_spawn.contains("100 %") and at_spawn.contains("left")
			and build.remaining_flight_time_min(core.powertrain.battery) > 1.0,
		"HUD reads \"%s\"" % at_spawn
	))

	# Fly for a while. Both figures have to move, and the minutes have to move DOWN — a flight
	# time that stood still would be the stats panel's constant wearing a countdown's clothes.
	#
	# 90 s rather than the 60 s this was written with. There is no flight controller in this
	# fixture, so what it actually does is spin up at hover throttle and then tumble, and since the
	# forward-flight prop model landed (2026-08-14) a tumbling aircraft spends much of its time with
	# a large axial inflow, where the prop unloads and draws less. The pack therefore drains more
	# slowly than it used to and 60 s no longer clears the 0.5 min threshold below.
	#
	# The THRESHOLD is untouched: what a reader of this test is owed is that the countdown moves
	# down by an amount a pilot would notice, and 0.5 min is that claim. Widening it to fit the new
	# model would have been describing the model rather than checking it. Flying longer is not.
	var commands: Dictionary = {}
	for name in MotorLayout.MOTOR_NAMES:
		commands[name] = throttle
	var minutes_at_spawn := build.remaining_flight_time_min(core.powertrain.battery)
	for _i in 45000:
		core.step(commands, 1.0 / 500.0)
	hud.render(core, build, course, timer, true)
	var after: String = hud._pack_label.text
	var minutes_after := build.remaining_flight_time_min(core.powertrain.battery)

	results.append(TestResult.new(
		"a minute of flying moves both the charge and the time remaining, downward",
		after != at_spawn and minutes_after < minutes_at_spawn - 0.5
			and core.observables.capacity_used_fraction > 0.0,
		"\"%s\" -> \"%s\" (%.2f min -> %.2f min, %.1f%% used)" % [
			at_spawn, after, minutes_at_spawn, minutes_after,
			core.observables.capacity_used_fraction * 100.0]
	))

	# The percentage on screen is the powertrain's own drain figure rather than a second count.
	var remaining := 1.0 - core.observables.capacity_used_fraction
	results.append(TestResult.new(
		"the charge on the HUD is the fraction the powertrain published, not a second count",
		after.contains("%.0f %%" % (remaining * 100.0)),
		"HUD reads \"%s\"; observables say %.0f%% remaining" % [after, remaining * 100.0]
	))

	# ...and the volts and amps it sat beside are still there.
	results.append(TestResult.new(
		"voltage and current are still on the HUD beside the new pack line",
		hud._voltage_label.text.contains("V") and hud._voltage_label.text.contains("A"),
		"reads \"%s\"" % hud._voltage_label.text
	))

	hud.free()
	return results
