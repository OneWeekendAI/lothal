class_name CustomFlightControllers
extends CustomParts
## The flight controllers a builder entered themselves. Read CustomParts first for the id space, the
## shared document and the refusals that are not about boards, and CustomEscs for the other half of
## the same stack.
##
## The four gyro specs are the point of this file, and only ONE of them is typed.
##
## ---------------------------------------------------------------------------
## gyro_noise_rad_s IS DERIVED, AND THE DERIVATION IS DATASHEET-BACKED
## ---------------------------------------------------------------------------
##
## It is not a product-page number and nobody should be asked to type 0.0062. It is the IMU's
## published RATE NOISE DENSITY carried across the sample rate, and every shipped entry's `source`
## states the arithmetic so it is checkable rather than asserted:
##
##     noise_rad_s = density_deg_s_per_sqrtHz * sqrt(sample_rate_hz) * PI / 180
##
## Reproduced against all SIX shipped entries — not the four distinct IMUs — by
## tests/test_custom_flight_controllers.gd. The sixth matters: the MPU-6000 appears twice, at 1 kHz
## on the reference board and 8 kHz on the whoop, and their published floors differ 2.8x on
## IDENTICAL HARDWARE. A derivation keyed off the part rather than off the part AND the rate would
## reproduce five rows and miss the one that says what the formula is actually tracking.
##
## So a builder picks their IMU by name and enters the sample rate, and the noise floor follows.
##
## HOW THIS DIFFERS FROM THE BATTERY'S DERIVED RESISTANCE, and it is worth saying out loud because
## the two look alike: CustomBatteries derives internal resistance from a fit against the shipped
## catalog's own representative figures, so it reproduces an assumption and proves nothing about a
## real pack. THIS derivation runs on published datasheet densities. It is not a self-consistency
## relationship — it is the same arithmetic the datasheet invites — and it is correspondingly more
## trustworthy. Equally: it is still a noise DENSITY carried to a sample rate, not a measurement of
## the board on the builder's bench.
##
## ---------------------------------------------------------------------------
## gyro_bias_rad_s IS DERIVED AND IS NOT THE SAME KIND OF NUMBER
## ---------------------------------------------------------------------------
##
## flight_controllers.json is unambiguous: this is THE ONE ILLUSTRATIVE FIELD, and it must not be
## read as a measurement. No datasheet publishes calibration residue, because it is what one
## particular board's one particular bench calibration left behind, and it varies unit to unit.
##
## It is derived from SENSOR GRADE the way the catalog authored it — 0.0012 rad/s for a current
## part up to 0.0026 for a budget one — labelled illustrative everywhere a reader meets it, and
## overridable by anyone who has actually characterised their board. What it must never be is a
## plain number in a form with no explanation.
##
## ---------------------------------------------------------------------------
## gyro_cutoff_hz IS A CONFIGURATION, NOT A BOARD PROPERTY
## ---------------------------------------------------------------------------
##
## 150 on every shipped entry because that is Betaflight's default, not because any hardware
## imposes it. It arguably belongs with the tune rather than with the part, and it is NOT moved
## here: six catalog entries, Gyro.from_part and the reference build's oracle all read it where it
## is. The observation is recorded and left for a slice of its own.
##
## Custom boards therefore take Gyro.DEFAULT_CUTOFF_HZ, which is the same 150 — a builder is not
## asked for a firmware default they did not choose.

const FLIGHT_CONTROLLERS_KEY := "flight_controllers"

const BOLT_ATTACHMENT := "bolt"

## The IMU rate-noise densities, in deg/s/sqrt(Hz), with the document each came from.
##
## SEEDED WITH EXACTLY THE FOUR flight_controllers.json ALREADY CITES AND NO OTHERS. Every row
## carries a real datasheet reference, and a row without one would be the same fabrication
## motors.json's `validation` block forbids by name: an invented density produces a board whose
## noise floor is fiction, and RateTune.kd_ceiling_for computes the D-gain ceiling from it. The
## table is not padded from memory. A builder whose IMU is not here supplies the density themselves,
## with a source of their own — which is what keeps this table honest AND the feature unblocked.
##
## `grade` selects the illustrative bias below, and is the catalog's own reading of the part's
## generation rather than anything a datasheet states.
##
## ONE CAVEAT, carried rather than papered over: the ICM-20602's citation is the document without a
## revision, which is how flight_controllers.json cites it. The other three carry document and
## revision. Rather than invent a revision number to make the table look uniform, the row says what
## is actually known — and if someone pins the revision, this is where it goes.
const IMU_DENSITY := {
	"MPU-6000": {
		"density_deg_s_per_sqrt_hz": 0.005,
		"datasheet": "InvenSense PS-MPU-6000A-00 rev 3.4",
		"grade": "legacy",
	},
	"ICM-20602": {
		"density_deg_s_per_sqrt_hz": 0.004,
		"datasheet": "TDK ICM-20602 datasheet (revision not stated in the catalog's own citation)",
		"grade": "mainstream",
	},
	"ICM-42688-P": {
		"density_deg_s_per_sqrt_hz": 0.0028,
		"datasheet": "TDK DS-000347 rev 1.6",
		"grade": "current",
	},
	"BMI270": {
		"density_deg_s_per_sqrt_hz": 0.007,
		"datasheet": "Bosch BST-BMI270-DS000 rev 1.6",
		"grade": "budget",
	},
}

## Class-typical calibration residue by sensor grade, rad/s. THESE ARE NOT DATASHEET FIGURES and
## nothing in this file pretends otherwise — see the header. The span is the shipped catalog's own,
## 0.0012 on the ICM-42688-P up to 0.0026 on the BMI270, and it exists so that a builder's board
## lands somewhere defensible rather than on a number invented per part.
const BIAS_BY_GRADE := {
	"current": 0.0012,
	"mainstream": 0.0015,
	"legacy": 0.0017,
	"budget": 0.0026,
}

## What an IMU with no grade gets. The middle of the table rather than the best of it: a board
## Lothal knows nothing about should not be handed the quietest calibration in the catalog.
const DEFAULT_BIAS_RAD_S := 0.0017


func array_key() -> String:
	return FLIGHT_CONTROLLERS_KEY


func category() -> String:
	return "flight_controller"


func flight_controllers() -> Array:
	return records()


func get_flight_controller(part_id: String) -> Dictionary:
	return get_record(part_id)


static func load_from(path: String = SAVE_PATH) -> CustomFlightControllers:
	var document := CustomFlightControllers.new()
	document.read_from(path)
	return document


# ---------------------------------------------------------------------------
# The derivation
# ---------------------------------------------------------------------------

## The IMU's published rate noise density, or 0.0 for one this table has never heard of. Public
## because the self-check test asks for it directly, and because a caller that wants to know whether
## a part is known should ask that question rather than reach into the dictionary.
static func density_for(imu: String) -> float:
	if not IMU_DENSITY.has(imu):
		return 0.0
	return float(IMU_DENSITY[imu]["density_deg_s_per_sqrt_hz"])


static func datasheet_for(imu: String) -> String:
	if not IMU_DENSITY.has(imu):
		return ""
	return str(IMU_DENSITY[imu]["datasheet"])


static func known_imus() -> Array:
	return IMU_DENSITY.keys()


## The whole derivation, in one line, in the units the catalog publishes and the sim consumes.
## Density is deg/s per root-Hz; carried across the sample rate it becomes deg/s; radians follow.
static func derived_noise_rad_s(density_deg_s_per_sqrt_hz: float, sample_rate_hz: float) -> float:
	if density_deg_s_per_sqrt_hz <= 0.0 or sample_rate_hz <= 0.0:
		return 0.0
	return density_deg_s_per_sqrt_hz * sqrt(sample_rate_hz) * PI / 180.0


## Illustrative, by grade. Named for what it is at every call site — see the header, and see
## FcPlausibility, which says it again to the builder.
static func derived_bias_rad_s(imu: String) -> float:
	if not IMU_DENSITY.has(imu):
		return DEFAULT_BIAS_RAD_S
	return float(BIAS_BY_GRADE.get(str(IMU_DENSITY[imu]["grade"]), DEFAULT_BIAS_RAD_S))


# ---------------------------------------------------------------------------
# Building a record
# ---------------------------------------------------------------------------

## A catalog-shaped record from an IMU part number, a sample rate, and what is on the scale and the
## product page. Static, and the ONE place a record's shape is written down.
##
## `density_override` is for an IMU outside the table: a positive value is used as the density, and
## the record then stands on the builder's own citation rather than on this file's. `bias_override`
## is for someone who has characterised their board's calibration residue; anything else defers to
## the grade table. Both default to NAN rather than 0.0, so "not supplied" cannot be confused with
## "measured as zero" — a zero-noise gyro has an infinite D ceiling.
static func make_record(name: String, imu: String, sample_rate_hz: float, mass_g: float,
		pattern: String, processor: String, loop_rate_hz: int, source: String,
		density_override: float = NAN, bias_override: float = NAN) -> Dictionary:
	var density := density_override if density_override > 0.0 else density_for(imu)
	var noise := derived_noise_rad_s(density, sample_rate_hz)
	var bias := bias_override if bias_override > 0.0 else derived_bias_rad_s(imu)

	return {
		"part_id": id_for(name),
		"name": name,
		"category": "flight_controller",
		"mass_g": mass_g,
		"mounting": {
			"attachment": BOLT_ATTACHMENT,
			"pattern": pattern,
		},
		"specs": {
			"gyro_sample_rate_hz": sample_rate_hz,
			# Betaflight's default, taken rather than asked for. See the header: this is firmware
			# configuration living in a parts catalog, and moving it is a slice of its own.
			"gyro_cutoff_hz": Gyro.DEFAULT_CUTOFF_HZ,
			"gyro_noise_rad_s": noise,
			"gyro_bias_rad_s": bias,
		},
		"catalog": {
			"processor": processor,
			"imu": imu,
			"loop_rate_hz": loop_rate_hz,
		},
		"source": source,
		"derivation": {
			# True when this file's table supplied the density, false when the builder did — which
			# is the difference between "cited from a datasheet Lothal holds" and "cited by you".
			"gyro_noise_rad_s": not (density_override > 0.0),
			# Illustrative either way; false means a builder measured their own board.
			"gyro_bias_rad_s": not (bias_override > 0.0),
			"imu_density_deg_s_per_sqrt_hz": density,
		},
	}


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "flight_controller")


# ---------------------------------------------------------------------------
# The FC-specific refusals
# ---------------------------------------------------------------------------

## Each of these is a case where the sim would produce a number rather than a complaint.
##
## The one that carries the most weight is the unknown IMU with no density. Gyro.from_part falls
## back FIELD BY FIELD to the reference board's stock sensor, so a board with no derivable noise
## floor would not fail — it would quietly fly as an MPU-6000 at 1 kHz, and the D-gain ceiling
## RateTune computes would belong to a sensor the builder does not own.
func _category_problems(record: Dictionary, _catalog: PartsCatalog) -> Array[String]:
	var problems: Array[String] = []

	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		problems.append("specs is required: the gyro's sample rate, and the noise floor and bias derived from your IMU")
		return problems
	var specs := raw_specs as Dictionary

	# A zero sample rate is an infinite loop in Gyro.update, not a slow sensor.
	if not specs.has("gyro_sample_rate_hz") or float(specs["gyro_sample_rate_hz"]) <= 0.0:
		problems.append("specs.gyro_sample_rate_hz must be present and positive — it is the gyro rate in your Betaflight configuration, not the chip's maximum")

	# A zero cutoff is a divide-by-zero in the PT1.
	if specs.has("gyro_cutoff_hz") and float(specs["gyro_cutoff_hz"]) <= 0.0:
		problems.append("specs.gyro_cutoff_hz must be positive if present — leave it out to take Betaflight's 150 Hz default")

	var imu := str(record.get("catalog", {}).get("imu", "")).strip_edges()
	if imu == "":
		problems.append("catalog.imu is required — the gyro's noise floor is derived from the IMU part number, and it is printed on the product page")

	if not specs.has("gyro_noise_rad_s") or float(specs["gyro_noise_rad_s"]) <= 0.0:
		if imu != "" and density_for(imu) <= 0.0:
			problems.append("\"%s\" is not an IMU Lothal holds a datasheet for, so its noise density must be supplied: enter the part's rate noise density in deg/s/sqrt(Hz) and say where it came from. Lothal knows %s" % [
				imu, ", ".join(known_imus())])
		else:
			problems.append("specs.gyro_noise_rad_s must be present and positive — it is derived from the IMU's noise density and the sample rate, never typed")

	# Illustrative, but not absent: a zero bias is a claim that the calibration was perfect, which
	# is the one thing a bench calibration never is.
	if not specs.has("gyro_bias_rad_s") or float(specs["gyro_bias_rad_s"]) <= 0.0:
		problems.append("specs.gyro_bias_rad_s must be present and positive — it is an illustrative class-typical residue, not a measurement, and zero would claim a perfect calibration")

	var mounting: Variant = record.get("mounting", null)
	if not (mounting is Dictionary):
		problems.append("mounting is required: the board bolts, through a pattern like \"30.5x30.5\"")
	else:
		var block := mounting as Dictionary
		if str(block.get("attachment", "")) != BOLT_ATTACHMENT:
			problems.append("mounting.attachment must be \"%s\" — stacks bolt, and every reader assumes it" % BOLT_ATTACHMENT)
		if str(block.get("pattern", "")).strip_edges() == "":
			problems.append("mounting.pattern is required — without it nothing can tell you the board does not fit your frame")

	return problems
