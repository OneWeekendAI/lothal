class_name TestHoverAtCharge
extends RefCounted
## Can the reference build still hold altitude on a half-empty pack? (physics.md §5)
##
## This is the user-facing shape of the discharge-datum bug, and it is asserted here as a FLIGHT
## rather than as a voltage, because a voltage assertion is the kind a reader has to be told how
## to interpret. "It sinks at half pack" needs no interpretation.
##
## ---------------------------------------------------------------------------
## TWO DIFFERENT COMMANDS, AND BOTH HAVE TO WORK
## ---------------------------------------------------------------------------
##
## THE QUOTED FIGURE. Build.hover_throttle() is solved at the nominal voltage datum: it is the 29%
## on the stats panel, the number two builders compare, and it does not move. The first group below
## commands exactly that and asks whether the aircraft stays up on a half-empty pack.
##
## That is the reported bug, and it is the group with teeth. Before the datum was fixed this sank
## nearly nine metres in three seconds, because a half-empty 4S was modelled two volts below where
## a real one rests. It passes now for a reason worth stating plainly: nominal voltage IS an
## operating point down the middle of the discharge, so the throttle quoted there is a usable
## command across the middle of the pack rather than one that only works on a fresh battery. If
## that stops being true, the datum has drifted again.
##
## THE FLYING FIGURE. Build.hover_throttle_for(pack) solves for the pack in the state it is
## actually in, and scenes/main.gd rests the throttle stick there at spawn. The second group
## commands that instead, which is what a pilot's centred stick really does.
##
## Keeping both is the point. The flying figure alone could never fail — it commands whatever it
## takes, so it would assert that thrust is a continuous function of throttle and nothing about the
## battery. The quoted figure alone would not cover what the field actually flies.
##
## ---------------------------------------------------------------------------
## NO FLIGHT CONTROLLER, ON PURPOSE
## ---------------------------------------------------------------------------
##
## The four motors are commanded directly rather than through MotorMixer and the FC. A controller
## between the command and the motors would be a second thing that could hold the aircraft up or
## fail to, and this file is about the pack. Level, stationary, four equal commands: what is left
## is thrust against weight against a sagging pack, which is the whole claim.

const DT := 1.0 / 500.0
const FLIGHT_S := 3.0
## The pack state under test. Half is where the report says the descent starts, and it is also the
## deepest part of the curve's plateau — the place a wrongly-anchored datum is most wrong.
const HALF := 0.5
## How far the aircraft may drift down across the flight and still count as holding altitude.
## Generous deliberately: the failure this catches is a sink of several metres, not centimetres,
## and a tight bound here would turn into a flaky test about integrator detail.
const ALTITUDE_TOLERANCE_M := 0.5


static func run() -> Array:
	var results: Array = []

	results.append_array(_test_it_holds_altitude_on_a_full_pack())
	results.append_array(_test_it_holds_altitude_at_half_charge())
	results.append_array(_test_a_half_pack_still_rests_above_nominal())
	results.append_array(_test_the_stick_the_field_actually_rests_at())

	return results


## The control. If this ever fails the fixture is broken rather than the battery, and the
## half-charge assertion below means nothing until this one passes.
static func _test_it_holds_altitude_on_a_full_pack() -> Array:
	var drop := _altitude_change_m(1.0)
	return [TestResult.new(
		"the reference build holds altitude at the neutral stick on a FULL pack",
		drop > -ALTITUDE_TOLERANCE_M,
		"altitude moved %+.2f m over %.0f s" % [drop, FLIGHT_S]
	)]


## The reported bug. Before the datum was fixed this sank about two metres in three seconds, at
## roughly a fifth of a g, on a pack with 7.6:1 of thrust still nominally available — because the
## discharge curve was anchored at full charge and put a half-empty 4S two volts below where a
## real one rests.
static func _test_it_holds_altitude_at_half_charge() -> Array:
	var drop := _altitude_change_m(HALF)
	return [TestResult.new(
		"the reference build holds altitude at the neutral stick on a HALF-EMPTY pack",
		drop > -ALTITUDE_TOLERANCE_M,
		"altitude moved %+.2f m over %.0f s at %.0f%% charge" % [drop, FLIGHT_S, HALF * 100.0]
	)]


## The same claim stated electrically, which is what makes the flight result diagnosable rather
## than merely red. A 4S LiPo at half charge rests ABOVE its 14.8 V nominal, not below it: nominal
## is an operating point somewhere down the plateau, not the voltage the pack leaves the charger at.
static func _test_a_half_pack_still_rests_above_nominal() -> Array:
	var build := ReferenceBuild.build()
	var pack := build.battery_model()
	pack.used_mah = pack.capacity_mah * (1.0 - HALF)
	var nominal: float = float(build.battery["specs"]["nominal_v"])

	return [TestResult.new(
		"a 4S pack at half charge rests above its nominal voltage, which is why it can still hover",
		pack.resting_voltage_v() > nominal,
		"%.2f V resting against %.2f V nominal" % [pack.resting_voltage_v(), nominal]
	)]


## What scenes/main.gd actually does: seed the pack from the shelf, then solve the stick position
## for THAT pack. Centring the stick has to hover whatever came out of the bag, across the whole
## usable range of the discharge — a fresh pack, which rests above nominal and needs less than the
## quoted figure, and a nearly-flat one, which needs considerably more.
static func _test_the_stick_the_field_actually_rests_at() -> Array:
	var results: Array = []

	var worst_drop := INF
	var worst_soc := 0.0
	var details: Array = []
	for soc in [1.0, 0.75, 0.5, 0.25]:
		var drop := _altitude_change_m(soc, true)
		if drop < worst_drop:
			worst_drop = drop
			worst_soc = soc
		details.append("%.0f%%: %+.2f m" % [soc * 100.0, drop])

	results.append(TestResult.new(
		"the stick position the field rests at hovers the pack it was solved for, at any charge",
		worst_drop > -ALTITUDE_TOLERANCE_M,
		"worst %+.2f m at %.0f%% charge (%s)" % [worst_drop, worst_soc * 100.0, ", ".join(details)]
	))

	return results


## Flies the reference build hands-off for FLIGHT_S with the pack at `soc`, and returns the change
## in altitude. Negative is a descent.
##
## `for_the_pack` picks which throttle is commanded: the flying figure solved for this pack's own
## state, as scenes/main.gd does at spawn, or the quoted nominal-datum figure off the stats panel.
static func _altitude_change_m(soc: float, for_the_pack: bool = false) -> float:
	var build := ReferenceBuild.build()
	var core := build.build_drone_core()

	# Seeded the way scenes/main.gd seeds it — through the pack the powertrain is already holding,
	# after the core is built, so Build's own figures stay figures at the nominal datum.
	core.powertrain.battery.used_mah = core.powertrain.battery.capacity_mah * (1.0 - soc)
	var throttle := build.hover_throttle_for(core.powertrain.battery) if for_the_pack \
		else build.hover_throttle()
	core.prime_motors(throttle)

	var commands: Dictionary = {}
	for name in MotorLayout.MOTOR_NAMES:
		commands[name] = throttle

	var start_m: float = core.rigid_body.position_m.y
	for _i in int(FLIGHT_S / DT):
		core.step(commands, DT)
	return core.rigid_body.position_m.y - start_m
