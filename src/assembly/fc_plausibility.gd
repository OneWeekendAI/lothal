class_name FcPlausibility
extends RefCounted
## What a build says about a flight controller whose numbers came from a builder rather than from
## the catalog. The sibling to EscPlausibility, and the same rules hold: nothing here blocks
## anything, and the refusals are all in CustomFlightControllers.
##
## ---------------------------------------------------------------------------
## THE ONE THING THIS WARNING HAS TO GET RIGHT
## ---------------------------------------------------------------------------
##
## Two of the board's four gyro specs are derived, and THEY ARE NOT THE SAME KIND OF NUMBER. Saying
## "both derived" and stopping would flatten exactly the distinction the whole category is built
## around:
##
##   - `gyro_noise_rad_s` comes from the IMU's PUBLISHED rate noise density, carried across the
##     sample rate. The datasheet is named in the warning, because a builder who wants to check it
##     can, and because a citation is what separates this from the battery's derived resistance —
##     which is fitted against the catalog's own assumptions and reproduces them faithfully while
##     proving nothing.
##
##   - `gyro_bias_rad_s` is ILLUSTRATIVE. No datasheet publishes calibration residue. It is a
##     class-typical figure scaled by sensor grade, it varies unit to unit on real hardware, and the
##     word "illustrative" is in the message for that reason.
##
## The D-gain ceiling is quoted alongside, because the noise floor's whole consequence is how much D
## the board will pay for (RateTune.kd_ceiling_for), and a builder comparing two boards is comparing
## that, whether or not they know it yet.
##
## ---------------------------------------------------------------------------
## WHAT IS NOT WARNED ABOUT, AND WHY
## ---------------------------------------------------------------------------
##
## A high sample rate is not a fault. Four of the six shipped boards run 8 kHz and the reference
## board's 1 kHz is the unusual one — it is synced to Lothal's rate loop, which is the configuration
## every oracle in the project is defined at. An off-catalog rate is a legitimate board and gets no
## warning of its own; what it gets is the noise floor its rate and density imply, which is the
## honest answer.


static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	var fc: Dictionary = build.fc
	if not PartsCatalog.is_custom(str(fc.get("part_id", ""))):
		return out

	var specs: Dictionary = fc.get("specs", {})
	var derivation: Dictionary = fc.get("derivation", {})
	var imu := str(fc.get("catalog", {}).get("imu", "unknown IMU"))
	var rate := float(specs.get("gyro_sample_rate_hz", 0.0))
	var noise := float(specs.get("gyro_noise_rad_s", 0.0))
	var bias := float(specs.get("gyro_bias_rad_s", 0.0))
	var ceiling := RateTune.kd_ceiling_for(build)

	# Where the noise floor's authority actually comes from. Lothal's own datasheet when the IMU is
	# in the table; the builder's citation when it is not — and the difference is stated, because a
	# density someone typed is not a density Lothal can vouch for.
	var datasheet := CustomFlightControllers.datasheet_for(imu)
	var provenance: String
	if bool(derivation.get("gyro_noise_rad_s", true)) and datasheet != "":
		provenance = "derived from the %s's published rate noise density (%s) across %.0f Hz" % [
			imu, datasheet, rate]
	else:
		provenance = "derived from the noise density you supplied for the %s, across %.0f Hz — Lothal holds no datasheet for that part" % [
			imu, rate]

	var bias_clause: String
	if bool(derivation.get("gyro_bias_rad_s", true)):
		bias_clause = "Its %.4f rad/s bias is ILLUSTRATIVE — a class-typical calibration residue, not a measurement, because no datasheet publishes one and it varies board to board" % bias
	else:
		bias_clause = "Its %.4f rad/s bias is your own measurement, used as given" % bias

	out.append(BuildWarning.characteristic(&"custom_flight_controller",
		"%s is a board you entered: %.0f g, %.0f Hz gyro. Its %.4f rad/s noise floor is %s, and caps D at %.3f. %s. \"%s\"" % [
			fc.get("name", "This flight controller"), build.fc_mass_g(), rate, noise, provenance,
			ceiling, bias_clause, str(fc.get("source", "no source given"))],
		{"gyro_sample_rate_hz": rate, "gyro_noise_rad_s": noise, "gyro_bias_rad_s": bias,
			"imu": imu, "datasheet": datasheet, "kd_ceiling": ceiling,
			"mass_g": build.fc_mass_g()}))

	return out
