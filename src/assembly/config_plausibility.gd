class_name ConfigPlausibility
extends RefCounted
## What this build's CONFIGURATION says about the aircraft — config-room design §5, slice C2.
## The sibling of ControlPlausibility and HarnessChecks, registered beside them in
## `Build.warnings()`, and under the same standing rule: WARN, NEVER BLOCK.
##
## Today it has one statement to make, and it is the one design §5.3 asks for by name. The motor
## map became an authored value in C2, which means it became possible to be wrong about — and the
## response to a wrong one is NOT to refuse it. The aircraft is built, the aircraft is flown, and
## it behaves as that aircraft would, which is badly: with the reaction torques no longer
## cancelling, four equal throttles spin it up about yaw and the pilot fights a rotation nobody
## commanded. The warning's whole job is to have said so BEFORE the flight rather than instead of
## it. tests/test_config_motors.gd asserts both halves in one check, because either alone is the
## wrong behaviour.
##
## The invariant it is written against is motor_layout.gd's own, stated at the top of that file:
## diagonal pairs (M1/M4, M2/M3) spin the SAME direction, adjacent pairs oppose. Props-in and
## props-out both satisfy it — they are the two maps that do — so this fires on neither, and a
## builder who flips the whole aircraft is told nothing, which is correct: that is a choice, not a
## mistake.

## The diagonal pairs. Named rather than inlined so the check reads as the invariant it is.
const DIAGONALS := [["M1", "M4"], ["M2", "M3"]]


static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	_unflyable_spin_map(build, out)
	_gps_rescue_without_gps(build, out)
	_bidir_dshot_unsupported(build, out)
	return out


## §5.3 — the map that cannot fly, said before it is flown.
##
## Two ways to fail one invariant, and they are reported as one warning because they are one
## mistake: a diagonal pair that opposes, or a net spin that is not zero. The second is what the
## pilot actually feels — the sum of the four reaction torques is what the airframe has to absorb,
## and a map summing to anything but zero has no throttle setting at which the aircraft holds
## heading.
static func _unflyable_spin_map(build: Build, out: Array[BuildWarning]) -> void:
	# ConfigFigures.spin_check: the same computation the Motor direction row's ✓ reads.
	var check := ConfigFigures.spin_check(build)
	var spin: Dictionary = check["spin"]
	var net := float(check["net"])
	var broken_pairs: Array[String] = []
	broken_pairs.assign(check["broken"])

	if net == 0.0 and broken_pairs.is_empty():
		return

	# The map is quoted back in full, because the builder is about to go and look at four
	# propellers and needs to know which of them this is about.
	var written: Array[String] = []
	for name in MotorLayout.MOTOR_NAMES:
		written.append("%s %s" % [name, MotorLayout.direction_name(float(spin[name]))])

	# Two failures, two sentences. A net of zero with a broken diagonal is a real and different
	# case — M1/M2 turning the same way while M3/M4 oppose sums to nothing and still cannot roll
	# and yaw independently — and quoting "+0" at that builder would read as a bug in Lothal.
	var reason := "the four reaction torques sum to %+.0f instead of cancelling, so four equal throttles spin the aircraft about yaw" % net
	if net == 0.0:
		reason = "the diagonal pair(s) %s disagree, so adjacent motors turn the same way and yaw is commanded by the wrong motors" % ", ".join(broken_pairs)

	out.append(BuildWarning.impossible(&"motor_spin_unflyable",
		("This motor map cannot fly — %s. %s. Lothal will fly it exactly as configured; "
		+ "check the direction of each motor in the Motors tab.") % [
			", ".join(written), reason],
		{"net_spin": net, "broken_diagonals": broken_pairs, "spin": spin}))


## §4.4 — GPS RESCUE CONFIGURED ON A BUILD WITH NO GPS. Design calls it "the single most useful
## check in the section", and the reason is the shape of the mistake: nothing about this build LOOKS
## wrong. Every part fits, the aircraft flies, and the failure is latent until the one moment the
## setting exists for — the link is gone, the quad is out of sight, and the behaviour the builder
## chose to save it cannot run because nothing on board knows where home is.
##
## LIMITING, NOT IMPOSSIBLE. The aircraft flies perfectly well; one configured behaviour cannot
## happen. Reading this in the same red as a 7" prop on a 3" frame would be wrong twice over.
##
## WHAT IT DOES NOT CLAIM: which arming flag a real board raises, or whether it falls back to drop,
## lands, or refuses to arm at all. §4.4 records that the flag names in this section are domain
## knowledge and are NOT verified against a firmware source; C7 is the slice that checks them. So
## this sentence says only the part that is certain from the build — the rescue has nothing to
## navigate with — and leaves the firmware to speak for itself.
static func _gps_rescue_without_gps(build: Build, out: Array[BuildWarning]) -> void:
	if FailsafeSettings.stage2(build.config) != FailsafeSettings.GPS_RESCUE:
		return
	if build.components.has("gps"):
		return

	out.append(BuildWarning.limiting(&"failsafe_gps_rescue_no_gps",
		("This build's stage 2 failsafe is GPS rescue, and no GPS is fitted — nothing on board can "
		+ "supply a position, so there is no home to fly back to and the rescue cannot run. Fit a "
		+ "GPS, or choose a behaviour this aircraft can carry out."),
		{"failsafe_stage2": FailsafeSettings.GPS_RESCUE, "gps_fitted": false,
			"fc": str(build.fc.get("name", ""))}))


## §4.4 — BIDIRECTIONAL DSHOT ASKED FOR OF AN ESC WHOSE PROTOCOL HAS NO RETURN PATH.
##
## C4 read `catalog.protocol` for the port budget and wrote in its own comment that it was making
## the WEAKER claim — that the wire is there — because bidirectional DShot was "a setting Lothal
## does not yet carry". C6 is the slice where it exists, so the stronger question can finally be
## asked: the builder has asked for rpm telemetry back down the signal wire, and the protocol on
## that wire decides whether that is a thing that can happen. A lookup, not a guess — design §8's
## third row.
##
## AN ESC PUBLISHING NO PROTOCOL STILL GETS A WORD, in the direction `_esc_telemetry_demand` already
## errs: the expensive failure here is telling a builder their setting is fine when it is not, so
## silence is not the safe answer and the sentence names what it could not read.
##
## The port budget is NOT recomputed from this setting, deliberately. A DShot ESC has its return
## path whether or not the feature is switched on, so the count C4 and C5 produce is unchanged and
## this check is a second, narrower question asked of the same field.
static func _bidir_dshot_unsupported(build: Build, out: Array[BuildWarning]) -> void:
	if not FailsafeSettings.bidir_dshot(build.config):
		return
	if build.esc.is_empty():
		return

	var protocol := str((build.esc.get("catalog", {}) as Dictionary).get("protocol", ""))
	if protocol.to_lower().begins_with(ControlPlausibility.DSHOT_PREFIX):
		return

	var esc_name := str(build.esc.get("name", "This ESC"))
	var reason := ("%s runs %s, which has no return path on the signal wire") % [esc_name, protocol]
	if protocol.is_empty():
		reason = ("%s does not publish a protocol, so Lothal cannot confirm it speaks DShot at "
			+ "all") % [esc_name]

	out.append(BuildWarning.limiting(&"bidir_dshot_unsupported",
		("Bidirectional DShot is switched on for this build, and %s — so the rpm it would send "
		+ "back never arrives, and anything downstream of it (RPM filtering above all) is "
		+ "configured against telemetry that is not coming.") % [reason],
		{"bidir_dshot": true, "protocol": protocol, "esc": esc_name}))
