class_name ControlFigures
extends RefCounted
## The numbers the Control rows, their page numbers and their drawings all read (lab dock design
## §3): one computation per figure, so the list, the page and the drawing cannot disagree. The
## `PowerFigures` / `PropulsionFigures` pattern, for Control.
##
## Nothing here is a second model. The port demand is `ControlPlausibility.serial_parts` (the list
## the serial-peripherals warning counts), the supply is `PortBudget.for_build` with its provenance,
## the D noise is `RateTune.d_noise_fraction` at the D gain actually installed, and the loop time
## constants are the tune's own.
##
## WHAT IS DELIBERATELY NOT HERE:
##   - a spare-port count. `ControlPlausibility`'s header refuses it: "four does not fit" survives a
##     class-typical range, "two spare" does not. The figures state use against the range, never
##     the difference.
##   - a link range. No receiver in `receivers.json` publishes an output power or a sensitivity, and
##     the control path takes stick positions from an input device rather than a modelled radio, so
##     any range figure would be invented.

## The bays the Link page describes, in the order the mass model weighs them (`LinkDetails.BAYS`).
const LINK_BAYS := ["receiver", "gps", "buzzer"]


## Every fitted part that wants a serial port: `{category, name, reason}`, in the warning's order.
static func serial_parts(build: Build) -> Array:
	return ControlPlausibility.serial_parts(build)


static func serial_demand(build: Build) -> int:
	return serial_parts(build).size()


## The board's port supply with its provenance — `PortBudget.for_build`, unchanged.
static func port_supply(build: Build) -> Dictionary:
	return PortBudget.for_build(build)


## The supply as a figure: "~4–5" (the catalogue's class-typical range, a guess, so `~`), "6" (the
## builder's typed count, a fact about their board), or "" when nothing is published.
static func ports_figure(build: Build) -> String:
	var supply := port_supply(build)
	var provenance := String(supply["provenance"])
	if provenance == PortBudget.UNPUBLISHED:
		return ""
	var low := int(supply["low"])
	var high := int(supply["high"])
	var figure := str(low) if low == high else "%d–%d" % [low, high]
	return figure if provenance == PortBudget.TYPED else "~" + figure


## "2 of ~4–5 UARTs used" — the FC row's line 3. Empty when the board publishes no count.
static func ports_used_text(build: Build) -> String:
	var figure := ports_figure(build)
	if figure == "":
		return ""
	return "%d of %s UARTs used" % [serial_demand(build), figure]


## The roll D gain in force: the tune's, or the hand tune when none has been derived — the same
## fallback `FcDetails` makes, so the page number and the sheet's row are one figure.
static func installed_kd(tune: RateTune) -> float:
	return tune.kd.x if tune != null else RateModeController.ROLL_PITCH_KD


## What fraction of full command, RMS, the installed D spends on the board's gyro noise with the
## aircraft still. An upper bound (Lothal models no D-term lowpass), so it is quoted with `~`.
static func d_noise_fraction(build: Build, tune: RateTune) -> float:
	return RateTune.d_noise_fraction(build, installed_kd(tune))


## The roll D in force as a share of the board's noise ceiling (`RateTune.kd_ceiling`, the D that
## spends `D_NOISE_BUDGET` on noise). 0 for a board with no noise, whose ceiling is INF.
static func d_ceiling_share(tune: RateTune) -> float:
	if tune == null or not is_finite(tune.kd_ceiling) or tune.kd_ceiling <= 0.0:
		return 0.0
	return tune.kd.x / tune.kd_ceiling


## The closed-loop time constant per axis, ms — the quantity the tuning law holds constant.
static func time_constants_ms(tune: RateTune) -> Vector3:
	return tune.time_constant_s() * 1000.0


## The link bays that are fitted, in `LINK_BAYS` order.
static func link_bays(build: Build) -> Array:
	var out: Array = []
	for category in LINK_BAYS:
		if build.components.has(category):
			out.append(category)
	return out


## The link bays' own masses, read off the build — the Link sheet's "Link total".
static func link_mass_g(build: Build) -> float:
	var total := 0.0
	for category in link_bays(build):
		total += float((build.components[category] as Dictionary).get("mass_g", 0.0))
	return total


## How many of the serial parts are link parts (the receiver, a GPS).
static func link_uarts(build: Build) -> int:
	var count := 0
	for part in serial_parts(build):
		if LINK_BAYS.has(str(part["category"])):
			count += 1
	return count


## A bolt pattern ("30.5x30.5") in millimetres, or ZERO when it cannot be read — never a guess.
static func pattern_mm(pattern: String) -> Vector2:
	var sides := pattern.to_lower().split("x")
	if sides.size() != 2 or not sides[0].is_valid_float() or not sides[1].is_valid_float():
		return Vector2.ZERO
	var out := Vector2(float(sides[0]), float(sides[1]))
	return out if out.x > 0.0 and out.y > 0.0 else Vector2.ZERO


## The three patterns on the stack: `{frame, fc, esc}`, as the build carries them. The same strings
## `Build._stack_fit_warning` compares.
static func stack_patterns(build: Build) -> Dictionary:
	return {"frame": str((build.frame.get("specs", {}) as Dictionary).get("stack_mount", "")),
		"fc": build.fc_mount_pattern(), "esc": build.esc_mount_pattern()}
