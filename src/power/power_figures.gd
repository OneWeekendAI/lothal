class_name PowerFigures
extends RefCounted
## The numbers the Power rows, their page numbers and their charts all read (lab dock design §3):
## one computation per figure, so the list, the page and the drawing cannot disagree. The
## `FrameHardware` / `PropulsionFigures` pattern, for Power.
##
## Every figure is a composition of `Build` and `HarnessChecks` calls that already exist — nothing
## here is a second model. Currents come from `Build.hover_current_a` (the Fitting expression the
## powertrain agrees with to 1e-5 A), voltages from the pack's own `R` (`BatteryModel.voltage_live`
## is `rest - I*R` and nothing else).
##
## THE WORST CASE IS A FRESH PACK AT THE THROTTLE CEILING. A full pack rests above nominal, so it
## drives the motors harder and draws more than the nominal datum the stats quote at: on the
## reference build 116 A against 92 A. That is the draw `HarnessChecks` checks the harness against,
## so the Battery, ESC and Harness pages all quote the same 116 A.


## Whole amps as every Power screen prints them, the SAME on every platform. "%.0f" is not: at an
## exact .5 — which the reference build hits, its pack-limited draw IS the 112.5 A rating — macOS/
## Linux printf rounds half to even ("112") and the Windows build rounds half away ("113"), and an
## x86 ULP either side of .5 flips it again. Half to even, with a 1e-9 A band counted as the tie.
static func amps_text(a: float) -> String:
	var below := floorf(a)
	if absf(a - below - 0.5) < 1.0e-9:
		return "%d" % (int(below) if int(below) % 2 == 0 else int(below) + 1)
	return "%d" % roundi(a)


## Where a fresh (full) pack rests, volts.
static func fresh_rest_v(build: Build) -> float:
	return build.battery_model().resting_voltage_v()


## The pack's nominal voltage — the datum hover, flight time and peak thrust are quoted at.
static func nominal_v(build: Build) -> float:
	return float(build.battery["specs"]["nominal_v"])


static func internal_r_ohm(build: Build) -> float:
	return float(build.battery["specs"]["internal_r_ohm"])


## The pack's rated continuous current, amps (mAh × C) — `Build.pack_max_amps`.
static func pack_limit_a(build: Build) -> float:
	return build.pack_max_amps()


## Total draw at the throttle ceiling on a fresh pack, amps: the worst the pack, the board and the
## harness see. Equal to `HarnessChecks.draw().peak_a`.
static func worst_draw_a(build: Build) -> float:
	# The very draw the pack and ESC ceilings are solved on (`Build.supply_limit_for`), so at a
	# binding supply limit this reads the rating — "112 A of 112 A", not 116.
	return build.fresh_draw_at_a(build.max_throttle_fraction())


## Total draw at the throttle ceiling at the nominal datum, amps.
static func nominal_full_throttle_a(build: Build) -> float:
	return build.hover_current_a(build.max_throttle_fraction())


## The pack's own sag at the worst draw, volts (I × R).
static func worst_sag_v(build: Build) -> float:
	return worst_draw_a(build) * internal_r_ohm(build)


## Hover draw at the nominal datum, amps. 0 for a build that cannot hover.
static func hover_draw_a(build: Build) -> float:
	if not build.can_hover():
		return 0.0
	return build.hover_current_a(build.hover_throttle())


## The flight-profile average draw — the current flight time is computed from. 0 if it cannot hover.
static func flight_draw_a(build: Build) -> float:
	if not build.can_hover():
		return 0.0
	return build.average_flight_current_a()


## Pack voltage against current from `rest_v`: `samples + 1` points `Vector2(amps, volts)`, 0 to
## `max_a` — the pack's load line, `rest - I*R`.
static func load_line(build: Build, rest_v: float, max_a: float, samples: int = 2) -> Array:
	var out: Array = []
	var r := internal_r_ohm(build)
	for i in samples + 1:
		var amps := max_a * float(i) / float(samples)
		out.append(Vector2(amps, rest_v - amps * r))
	return out


## One ESC channel (= one motor), amps: `{rating, burst, motor_max, drawn, headroom}`. `motor_max`
## is what the motors can ask at their own limit (`Build.motor_demand_per_channel_a`, the figure
## headroom is quoted against); `drawn` is a quarter of the worst draw on this pack.
static func esc_channel(build: Build) -> Dictionary:
	return {"rating": build.esc_continuous_a(), "burst": build.esc_burst_a(),
		"motor_max": build.motor_demand_per_channel_a(),
		"drawn": worst_draw_a(build) * HarnessChecks.MOTOR_LEAD_CURRENT_SHARE,
		"headroom": build.esc_channel_headroom_a()}


## Volts lost in the main lead and its plug at the worst draw — `HarnessChecks`' trunk drop.
static func harness_drop_v(build: Build) -> float:
	if build.harness == null:
		return 0.0
	return worst_draw_a(build) * HarnessChecks.trunk_resistance_ohm(build)


static func harness_mass_g(build: Build) -> float:
	return build.harness.total_mass_g(build) if build.harness != null else 0.0
