class_name FramePlausibility
extends RefCounted
## What a build says about a frame whose numbers came from a builder rather than from the catalog,
## and one thing it says about ANY build that the custom-frames slice is the first to make visible.
##
## Everything here is CHARACTERISTIC. Not one of these is an error, and none of them blocks
## anything: labs-and-sim.md §2 warns and never blocks, and the only refusals in this slice are the
## two in CustomFrames where there is no geometry to draw at all. A builder who enters a 900 mm arm
## gets a 900 mm aircraft and a sentence saying nobody has built one.
##
## ---------------------------------------------------------------------------
## WHERE EACH BOUND IS, AND WHY IT IS THERE
## ---------------------------------------------------------------------------
##
## Fixed before any of them was run against anything, in thrust_validation.gd's spirit: a bound
## moved to fit the data it is measuring is not a bound. Each cites something real.
##
## ARM_MIN_MM / ARM_MAX_MM — 25 mm and 400 mm.
##   The bottom is set by the smallest thing anyone sells. A 65 mm whoop — the smallest class in
##   production, and the smallest frame in this catalog — is 32 mm centre-to-motor. At 25 mm the
##   arm is shorter than a 1103 motor is wide, so the "arms" are no longer arms; the motors are
##   touching the centre plate. The top is set by where the four-motor X stops describing the
##   aircraft: 400 mm centre-to-motor is 1.13 m motor to motor, past every quad in this catalog
##   (the 10" is 215 mm) and into the class that is built as an X8 or a hex because a single
##   400 mm carbon arm is not stiff enough to hold a motor still. Lothal models a four-motor X and
##   nothing else, so beyond here it is answering a question about an aircraft it is not modelling.
##
## MASS_PER_ARM_SQ_MIN / MAX — 4.0 and 30.0 g per 1000 mm².
##   A frame is mostly flat carbon plate, so its mass goes roughly as a length squared, and arm
##   length is the length there is. Measured across THIS CATALOG, the ratio spans 5.7 (the 10"
##   long range) to 21.5 (the 65 mm whoop, which is an injection moulding with a duct rather than
##   a plate). The bounds sit outside that observed span with room either side, which is the
##   honest thing to do with a ratio derived from fourteen points: they are wide enough that
##   everything anyone has actually built passes, and tight enough to catch a number that is off
##   by more than a factor of two — a gram/ounce slip, or a mass typed in kilograms. This is a
##   REGULARITY, not a law, and the warning says so.
##
## PROP OVERLAP — arm_mm * sqrt(2) is the geometric ceiling, no constant of my own.
##   On a symmetric X, adjacent motors are arm * sqrt(2) apart. Two props of diameter D on
##   adjacent arms intersect when D exceeds that spacing. There is nothing to tune here: it is the
##   diagonal of a square. Every frame in the shipped catalog clears it (the 5" freestyle claims
##   5.1" against a 6.12" ceiling), which is the check that the rule is describing reality rather
##   than inventing it.
##
## ELECTRONICS_LUMP_FRACTION — 0.25.
##
##   **PW4 REWROTE THIS WARNING'S SENTENCE, AND THE REASON IS THE POINT OF THE ROW.** It used to
##   tell the builder "the wiring share of that is a flat figure on every build regardless of size,
##   so at this weight you are partly reading a constant rather than your own parts." That has been
##   FALSE since PW2: `Harness` weighs a connector, a capacitor and four gauged wire runs off the
##   parts and lengths this build actually specifies, and `HarnessChecks` warns about them by name.
##   The cost of leaving it was not abstract — a whoop got that sentence sitting in the same warning
##   list as an ampacity warning naming its actual 26 AWG lead, so Lothal was telling the builder
##   their wiring was a constant one line under a warning derived from it. A warning that
##   contradicts its neighbour teaches a builder to trust neither.
##
##   What survives of the caveat is `Harness.REMAINDER_MASS_G`: 5 g of straps, tape, solder and
##   heat-shrink at the origin, flat because harness sundries scale with something Lothal has
##   measured on zero aircraft. It is quoted by name and by size so the reader can see it is far
##   too small to be the explanation, which is the honest shape of a caveat that has shrunk.
##
##   The BOUND itself is unchanged and so is why it exists.
##   Build.ELECTRONICS_BUDGET_G is a FLAT 55 g — the allowance camera, VTX, antenna, receiver and
##   wiring were budgeted against, no longer the mass of any of them — and it is wrong at both ends
##   of the catalog's own span:
##
##       frame_65mm_whoop      AUW   79.9 g | TWR  1.40 | hover 80.2%
##       frame_5in_freestyle   AUW  496.0 g | TWR 11.69 | hover 29.6%   <- exact
##       frame_10in_long_range AUW 1251.2 g | TWR  7.02 | hover 29.7%
##
##   A real 65 mm whoop is 20-25 g all-up and hovers near 35%. Lothal is about 3.5x heavy there
##   because the lump alone outweighs the aircraft. It is wrong the other way at the top: a
##   kg-class build carries MORE than 55 g of electronics, not less.
##
##   The threshold is where the lump stops being a rounding error and starts being the answer. On
##   the reference build it is 11% of all-up weight, which is small enough that an error of ±50%
##   in it moves AUW by 5%. At 25% the same ±50% error moves AUW by 12%, which is larger than the
##   entire spread of frame masses in the 5" class — at that point the builder is reading Lothal's
##   constant rather than their own frame, and has to be told.
##
##   Custom frames do NOT cause this and this file does NOT try to fix it. The wiring half of
##   LTHL-11 is closed — PW2 scaled it — and what is left is the four fixed component masses at the
##   small end, where a 65 mm whoop is quoted the same camera and VTX as a 5". That is a catalog
##   question rather than a scaling law, so the warning still names the ticket and no longer
##   promises that a term is about to start moving.
##
##   Emitted for EVERY build, not only custom ones. It is a true statement about the aircraft
##   whichever shelf the frame came off, and gating an honest warning on the provenance of a
##   number it does not depend on would be a lie of omission with extra machinery.

const ARM_MIN_MM := 25.0
const ARM_MAX_MM := 400.0
const MASS_PER_ARM_SQ_MIN := 4.0
const MASS_PER_ARM_SQ_MAX := 30.0
const ELECTRONICS_LUMP_FRACTION := 0.25
const INCH_MM := 25.4


## Everything this file has to say about one build, in one list, so Build.warnings() appends it
## unconditionally and has no opinion about which of these apply.
static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	out.append_array(_custom_provenance(build))
	if PartsCatalog.is_custom(str(build.frame.get("part_id", ""))):
		out.append_array(_bounds(build))
	out.append_array(_electronics_lump(build))
	return out


## That these numbers have not been through anything.
##
## CHARACTERISTIC, and it is the definitional case: it is not a fault in the build, it is a
## description of what the build IS — an aircraft assembled from a measurement nobody else has
## checked. It quotes the builder's own `source` because the sentence is worthless without it. A
## badge that only exists in the UI would not do: warnings are where this project says what it
## knows about an aircraft, and "we know nothing about where this frame's numbers came from except
## what you told us" is the most important thing it knows.
static func _custom_provenance(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var part_id := str(build.frame.get("part_id", ""))
	if not PartsCatalog.is_custom(part_id):
		return out
	var source := str(build.frame.get("source", "")).strip_edges()
	out.append(BuildWarning.characteristic(&"custom_frame",
		"The %s is a frame you entered yourself (%s). Nothing about it has been through the catalog's checks, so every figure on this build is exactly as good as those measurements are." % [
			build.frame.get("name", part_id), source],
		{"part_id": part_id, "source": source}))
	return out


## The three things that can be surprising about an entered frame. Separate ids rather than one
## combined sentence, because a build can be surprising in more than one way at once and a test or
## a panel has to be able to ask about each alone — the same reasoning as the two resonance ids.
static func _bounds(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var specs: Dictionary = build.frame.get("specs", {})
	var arm_mm := float(specs.get("arm_mm", 0.0))
	var mass_g := float(build.frame.get("mass_g", 0.0))

	if arm_mm < ARM_MIN_MM or arm_mm > ARM_MAX_MM:
		var where := "shorter than the %.0f mm arms of the smallest whoop anyone sells" % ARM_MIN_MM \
			if arm_mm < ARM_MIN_MM \
			else "longer than the %.0f mm at which a single carbon arm stops holding a motor still, which is why aircraft that size are built as X8s and hexes" % ARM_MAX_MM
		out.append(BuildWarning.characteristic(&"implausible_arm",
			"%.0f mm centre-to-motor is %s. Lothal will fly it as a four-motor X because that is the only thing it models — check the number is centre-to-MOTOR and not motor-to-motor." % [
				arm_mm, where],
			{"arm_mm": arm_mm, "min_mm": ARM_MIN_MM, "max_mm": ARM_MAX_MM}))

	# Guarded rather than assumed: arm_mm cannot be zero here (CustomFrames refuses that) but this
	# function must be safe to call on any frame dictionary, including one a future caller hands it.
	if arm_mm > 0.0:
		var per_sq := mass_g / (arm_mm * arm_mm) * 1000.0
		if per_sq < MASS_PER_ARM_SQ_MIN or per_sq > MASS_PER_ARM_SQ_MAX:
			out.append(BuildWarning.characteristic(&"implausible_frame_mass",
				"%.0f g on %.0f mm arms is %.1f g per 1000 mm², against %.0f-%.0f for every frame in the catalog. Frame mass goes roughly as arm length squared because a frame is mostly flat plate — that is a regularity rather than a law, so this is worth a second look at the scale rather than a correction." % [
					mass_g, arm_mm, per_sq, MASS_PER_ARM_SQ_MIN, MASS_PER_ARM_SQ_MAX],
				{"mass_g": mass_g, "arm_mm": arm_mm, "grams_per_1000mm2": per_sq}))

		# The diagonal of a square, and nothing else. Adjacent motors on a symmetric X sit
		# arm * sqrt(2) apart, so two props wider than that spacing occupy the same air.
		var spacing_in := arm_mm * sqrt(2.0) / INCH_MM
		var claimed_in := float(specs.get("max_prop_inches", 0.0))
		if claimed_in > spacing_in:
			out.append(BuildWarning.characteristic(&"prop_overlap",
				"Adjacent motors on %.0f mm arms are %.1f\" apart, so %.1f\" props would overlap each other. Lothal models each rotor on its own air and will not show you that — it is geometry, not a prediction." % [
					arm_mm, spacing_in, claimed_in],
				{"arm_mm": arm_mm, "spacing_inches": spacing_in, "max_prop_inches": claimed_in}))

	return out


## See ELECTRONICS_LUMP_FRACTION above for the whole of the reasoning.
static func _electronics_lump(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var auw := build.all_up_weight_g()
	if auw <= 0.0:
		return out
	# The build's ACTUAL electronics mass, not the flat budget. LTHL-11 unbundled the camera, VTX,
	# antenna and receiver into parts that can be omitted, so a build that omits them genuinely
	# carries less — and a warning still quoting 55 g would be overstating the problem it exists to
	# name. What it quotes now moves when the builder changes something, which is the difference
	# between a warning about the aircraft and a warning about Lothal.
	var electronics_g := build.electronics_mass_g()
	var fraction := electronics_g / auw
	if fraction < ELECTRONICS_LUMP_FRACTION:
		return out
	out.append(BuildWarning.characteristic(&"electronics_lump",
		"%.0f%% of this aircraft's %.0f g is its electronics: %.0f g of stack, camera, VTX, antenna, receiver and harness, against Lothal's %.0f g allowance for all of it. Every one of those is now weighed off the part you fitted — the harness included, down to the gauge and length of each lead — except a flat %.0f g of straps, tape, solder and heat-shrink, which is the only constant left in it. So this is your parts rather than a stand-in — but at this all-up weight the catalog is the thing to check next, because a camera, VTX, antenna and receiver chosen for a 5\" are most of a much smaller aircraft, and the ones that class actually flies are lighter or are on the board already. Tracked as LTHL-11." % [
			fraction * 100.0, auw, electronics_g, Build.ELECTRONICS_BUDGET_G,
			Harness.REMAINDER_MASS_G],
		# `remainder_g` is here because the message quotes it: the one constant left in this figure,
		# carried as a value so the shrinking of that caveat is checkable rather than prose.
		{"electronics_g": electronics_g, "all_up_g": auw, "fraction": fraction,
			"remainder_g": Harness.REMAINDER_MASS_G}))
	return out
