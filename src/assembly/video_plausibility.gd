class_name VideoPlausibility
extends RefCounted
## What a build says about the parts the picture passes through — video-room design §3, slice V4.
## The sibling to ControlPlausibility, registered beside it in `Build.warnings()`, and under the same
## standing rule: WARN, NEVER BLOCK. Every statement quotes the numbers it was computed from.
##
## Two statements, and two deliberate silences.
##
## ---------------------------------------------------------------------------
## THE CLEARANCE WARNING SPEAKS ONLY WHEN THE TILT IS THE CAUSE
## ---------------------------------------------------------------------------
##
## Design §3 says a tilted camera's vertical extent, l·sin θ + h·cos θ, against the plate gap
## MountLayout computes, "both from published dimensions — no invented spec". Half of that is wrong.
## The camera box is published; THE GAP IS NOT. MountLayout's default standoff is 1.5 times the
## lumped `Build.FRAME_PLATE_THICKNESS_M` of 10 mm, which leaves 5 mm between the plates' faces on
## every frame — shorter than every camera in the catalog stands LEVEL, the 15 mm nano included.
##
## So a warning on the absolute comparison would fire on the reference build and on every aircraft
## in the app, and the ceiling it quoted would be a ratio wearing a measurement's confidence. That is
## the noise `CameraView`'s history warns about and the confident-guess failure ControlPlausibility's
## header names. Neither is said.
##
## What IS sayable is the part the tilt adds: a camera that fits between the plates level and does
## not fit tipped up. Both halves compare the same box against the same gap, so whatever is wrong
## with the gap is wrong equally on both sides, and the sentence is about the one thing the builder
## just changed. It fires when the builder has raised the standoffs far enough for the camera to fit
## and then tipped it past what they leave — which is the real Saturday-afternoon failure.
##
## The mutation that proves it: measure the camera untilted (tilt 0 in the second call) and the
## fixture in `tests/test_video_warnings.gd` goes silent.
##
## The height is the PUBLISHED box rotated by `Build.camera_tilt_transform` — the rotation the
## drawing uses — rather than the drawn mesh, because this runs on a Build with no node in hand, and
## the published box is what a builder can check against the part. See `camera_standing_height_m`.
##
## A camera straddles the plate's front edge in MountLayout's seat, so the DRAWING does not show the
## collision this describes: half of the box is ahead of the plates. A real camera sits between the
## side plates, behind the top plate's edge, and there the whole tipped box has to fit. The check is
## about the aircraft; the seat is a drawing simplification it does not inherit.
##
## ---------------------------------------------------------------------------
## WHY A TRANSMITTER WITH NO ANTENNA IS SAID, AND A CAMERA WITH NO TRANSMITTER IS NOT
## ---------------------------------------------------------------------------
##
## A VTX powered with nothing on its connector reflects its own output back into the amplifier, and
## a builder who removed the antenna from the rail and kept the transmitter has built exactly that.
## It is said as CHARACTERISTIC rather than LIMITING, because some small boards carry a wire antenna
## of their own and no VTX in `vtxs.json` says whether it does — so Lothal cannot tell a whoop board
## with its whip soldered on from a forgotten antenna, and the sentence admits that.
##
## It does NOT fire on the whoop-AIO shape, because that shape fits no separate VTX at all.
##
## A CAMERA WITH NO TRANSMITTER IS NOT SAID, and that is the AIO case the other way round: a whoop
## AIO board carries the VTX on the flight controller, and no board in `flight_controllers.json`
## says whether it has one. The honest version of that warning would fire on every whoop modelled
## honestly — a camera fitted, the VTX on the board — and a warning on every whoop is one nobody
## reads. A transmitter with no camera is not said either: it costs grams and nothing else.

## How much taller than the gap a camera must stand before it is said. Half a millimetre, the same
## tolerance `AirframeModel.component_fit_warnings` gives a part against its plate.
const CLEARANCE_TOLERANCE_M := 0.0005


static func warnings_for(build: Build) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	_tilt_into_the_top_plate(build, out)
	_vtx_without_antenna(build, out)

	return out


## §3 — the uptilt tips a camera that fits level into the top plate. See the header for why only
## the part the tilt adds is said.
static func _tilt_into_the_top_plate(build: Build, out: Array[BuildWarning]) -> void:
	if not build.components.has("camera"):
		return
	# A moulded frame has no plates to strike (AirframeDocument's construction rule), and the bays
	# MountLayout still lists for it are space, not a stack.
	var specs: Dictionary = build.frame.get("specs", {})
	if str(specs.get("construction", AirframeDocument.CONSTRUCTION_PLATE)) \
			== AirframeDocument.CONSTRUCTION_MOULDED:
		return

	# The floor and the ceiling are MountLayout's own faces, at the standoffs actually fitted: the
	# camera bay is the bottom plate's upper face and `rx_bay` is the top plate's underside. Read,
	# not re-derived from the gap and a thickness.
	var mounts := build.mount_points()
	var bay_floor := MountLayout.by_id(mounts, "camera_bay")
	var bay_ceiling := MountLayout.by_id(mounts, "rx_bay")
	if bay_floor == null or bay_ceiling == null:
		return
	var clear_m := bay_ceiling.position.y - bay_floor.position.y

	var camera: Dictionary = build.components["camera"]
	var tilt_deg := float(build.assembly_value("camera_tilt_deg"))
	var level_m := Build.camera_standing_height_m(camera, 0.0)
	var standing_m := Build.camera_standing_height_m(camera, tilt_deg)
	if level_m > clear_m + CLEARANCE_TOLERANCE_M or standing_m <= clear_m + CLEARANCE_TOLERANCE_M:
		return

	var size := Build.component_size_of(camera)
	out.append(BuildWarning.limiting(&"camera_tilt_into_top_plate",
		("Tipped up %.0f°, the %s (%.0f mm long, %.0f mm tall) stands %.1f mm; the plates leave "
		+ "%.1f mm between them. Level it stands %.1f mm and fits — the uptilt is what puts it into "
		+ "the top plate. Taller standoffs or less tilt.") % [
			tilt_deg, str(camera.get("name", "camera")), size.z * 1000.0, size.y * 1000.0,
			standing_m * 1000.0, clear_m * 1000.0, level_m * 1000.0],
		{"tilt_deg": tilt_deg, "standing_mm": standing_m * 1000.0, "level_mm": level_m * 1000.0,
			"clear_mm": clear_m * 1000.0, "camera": str(camera.get("name", ""))}))


## A transmitter fitted with no antenna. See the header for the severity and for why the two
## neighbouring cases are not said.
static func _vtx_without_antenna(build: Build, out: Array[BuildWarning]) -> void:
	if not build.components.has("vtx") or build.components.has("antenna"):
		return
	var vtx: Dictionary = build.components["vtx"]
	out.append(BuildWarning.characteristic(&"vtx_without_antenna",
		("The %s is fitted and no antenna is. Powered with nothing on its connector, a transmitter "
		+ "can damage its own output stage. If this board carries its own wire antenna this is "
		+ "correct and Lothal cannot tell, because no transmitter in this catalog says whether it "
		+ "does.") % str(vtx.get("name", "video transmitter")),
		{"vtx": str(vtx.get("name", "")), "antenna_fitted": false}))
