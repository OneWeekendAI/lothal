extends SceneTree
## Headless test runner: godot --headless --script res://tests/run_tests.gd
## Orchestrates each test module and prints PASS/FAIL per week1.md's Day 2 gate:
## all seven checks must print PASS before Day 3 (wiring into 3D) may begin.
##
## Each suite's results print as that suite finishes rather than being collected and
## dumped at the end, so a suite that hangs or crashes names itself instead of leaving
## the runner silent.

const SUITES := ["mass properties", "mass positions", "hover", "torque signs", "torque reference", "hover stability",
	"rate step response", "rate mode release", "translation", "parts system", "build panel", "details footers",
	"gate course", "course library", "course warnings", "field editor", "hud", "keyboard throttle", "observables", "rotor synth",
	"frame model", "mount points", "stack mesh", "battery mount", "motor mesh", "propeller mesh", "airframe", "mounting",
	"assembly tweaks", "prop rotation", "lab", "powertrain", "bench", "validation", "build validation",
	"battery rail", "battery model", "hover at charge", "pack current limit", "charge readouts", "esc", "esc bench", "battery bench", "frame bench", "pack charge", "battery mesh", "component mesh", "fpv view",
	"yaw authority", "gyro", "motor mixer", "control path", "stick release", "warnings", "build warnings",
	"flight controller", "rate tune", "catalog tuning", "pid tunes", "vibration", "forward flight", "air density", "flight recorder", "studio", "spectrum",
	"custom frames", "custom motors", "custom propellers", "custom batteries", "custom escs", "custom flight controllers", "electronics parts", "electronics ui", "custom parts ui", "update check", "licence check", "activation gate", "rust constants", "glass shell", "room host", "project", "project menu", "project container", "project wiring",
	"polygon props", "control effectiveness", "frame materials", "hardware mass",
	"airframe document", "airframe properties", "frame layouts", "frame export", "frame import", "airframe room", "arm beam", "arm profile", "frame edits", "frame plan editor", "frame workbench", "plate mesh", "airframe tabs",
	"propeller document", "blade geometry", "blade aero", "blade room", "bemt", "calibration", "bemt forward", "propulsion panel", "motor spin up", "soft mount", "bemt ratios", "prop guard", "guard mesh", "planform edits", "propulsion room", "authored blade", "thrust overlay", "campbell overlay", "vibration overlay", "spin up overlay", "prop disc overlay", "stl writer", "propulsion export", "guard row", "overlay tray"]

func _init() -> void:
	var total := 0
	var fail_count := 0

	for suite_name in SUITES:
		var results := _run_suite(suite_name)
		# A suite that returns nothing has crashed, or its class failed to register. Left
		# unchecked that reads as zero failures, and the runner cheerfully reports success
		# for tests it never ran — the one outcome a test runner must never produce.
		if results.is_empty():
			fail_count += 1
			total += 1
			print("[FAIL] suite \"%s\" produced no results (crashed, or class not registered)" % suite_name)
			continue

		for result in results:
			var status: String = "PASS" if result.passed else "FAIL"
			if not result.passed:
				fail_count += 1
			total += 1
			print("[%s] %s (%s)" % [status, result.name, result.detail])

	# THE LAID-OUT SUITE, LAST AND ON ITS OWN. Every suite above is synchronous by design; this one
	# needs frames, because the defects it covers are about where a container ENDED UP and no
	# container has a size until one has been processed. See `tests/test_shell_layout.gd` for why
	# that exception exists and what belongs in it. Run under --headless like the rest: these are
	# 2D control rects, which the dummy driver produces correctly — unlike a SubViewport's 3D
	# contents, which is why the capture tools are not headless.
	var layout_results: Array = await TestShellLayout.run(self)
	if layout_results.is_empty():
		fail_count += 1
		total += 1
		print("[FAIL] suite \"shell layout\" produced no results (crashed, or class not registered)")
	for result in layout_results:
		var status: String = "PASS" if result.passed else "FAIL"
		if not result.passed:
			fail_count += 1
		total += 1
		print("[%s] %s (%s)" % [status, result.name, result.detail])

	print("")
	if fail_count == 0:
		print("ALL %d TESTS PASSED" % total)
	else:
		print("%d/%d TESTS FAILED" % [fail_count, total])

	quit(1 if fail_count > 0 else 0)

func _run_suite(suite_name: String) -> Array:
	match suite_name:
		"airframe tabs": return TestAirframeTabs.run()
		"authored blade": return TestAuthoredBlade.run()
		"thrust overlay": return TestThrustOverlay.run()
		"campbell overlay": return TestCampbellOverlay.run()
		"vibration overlay": return TestVibrationOverlay.run()
		"spin up overlay": return TestSpinUpOverlay.run()
		"prop disc overlay": return TestPropDiscOverlay.run()
		"propeller document": return TestPropellerDocument.run()
		"blade geometry": return TestBladeGeometry.run()
		"blade aero": return TestBladeAero.run()
		"blade room": return TestBladeRoom.run()
		"bemt": return TestBemt.run()
		"calibration": return TestCalibration.run()
		"bemt forward": return TestBemtForward.run()
		"propulsion panel": return TestPropulsionPanel.run()
		"motor spin up": return TestMotorSpinUp.run()
		"soft mount": return TestSoftMount.run()
		"bemt ratios": return TestBemtRatios.run()
		"stl writer": return TestStlWriter.run()
		"propulsion export": return TestPropulsionExport.run()
		"guard row": return TestGuardRow.run()
		"overlay tray": return TestOverlayTray.run()
		"prop guard": return TestPropGuard.run()
		"guard mesh": return TestGuardMesh.run()
		"planform edits": return TestPlanformEdits.run()
		"propulsion room": return TestPropulsionRoom.run()
		"airframe document": return TestAirframeDocument.run()
		"frame layouts": return TestFrameLayouts.run()
		"frame export": return TestFrameExport.run()
		"frame import": return TestFrameImport.run()
		"airframe room": return TestAirframeRoom.run()
		"airframe properties": return TestAirframeProperties.run()
		"arm beam": return TestArmBeam.run()
		"arm profile": return TestArmProfile.run()
		"frame edits": return TestFrameEdits.run()
		"frame plan editor": return TestFramePlanEditor.run()
		"frame workbench": return TestFrameWorkbench.run()
		"plate mesh": return TestPlateMesh.run()
		"polygon props": return TestPolygonProps.run()
		"control effectiveness": return TestControlEffectiveness.run()
		"frame materials": return TestFrameMaterials.run()
		"hardware mass": return TestHardwareMass.run()
		"mass properties": return TestMassProperties.run()
		"mass positions": return TestMassPositions.run()
		"hover": return TestHover.run()
		"torque signs": return TestTorqueSigns.run()
		"torque reference": return TestTorqueReference.run()
		"hover stability": return TestHoverStability.run()
		"rate step response": return TestRateStepResponse.run()
		"rate mode release": return TestRateModeRelease.run()
		"translation": return TestTranslation.run()
		"parts system": return TestPartsSystem.run()
		"build panel": return TestBuildPanel.run()
		"details footers": return TestDetailsFooters.run()
		"gate course": return TestGateCourse.run()
		"course library": return TestCourseLibrary.run()
		"course warnings": return TestCourseWarnings.run()
		"field editor": return TestFieldEditor.run()
		"hud": return TestHud.run()
		"keyboard throttle": return TestKeyboardThrottle.run()
		"observables": return TestObservables.run()
		"rotor synth": return TestRotorSynth.run()
		"frame model": return TestFrameModel.run()
		"mount points": return TestMountPoints.run()
		"stack mesh": return TestStackMesh.run()
		"battery mount": return TestBatteryMount.run()
		"motor mesh": return TestMotorMesh.run()
		"propeller mesh": return TestPropellerMesh.run()
		"airframe": return TestAirframeModel.run()
		"mounting": return TestMounting.run()
		"assembly tweaks": return TestAssemblyTweaks.run()
		"prop rotation": return TestPropRotation.run()
		"lab": return TestLab.run()
		"powertrain": return TestPowertrain.run()
		"bench": return TestBench.run()
		"validation": return TestValidation.run()
		"build validation": return TestBuildValidation.run()
		"battery rail": return TestBatteryRail.run()
		"battery model": return TestBatteryModel.run()
		"hover at charge": return TestHoverAtCharge.run()
		"pack current limit": return TestPackCurrentLimit.run()
		"charge readouts": return TestChargeReadouts.run()
		"esc": return TestEsc.run()
		"esc bench": return TestEscBench.run()
		"battery bench": return TestBatteryBench.run()
		"frame bench": return TestFrameBench.run()
		"pack charge": return TestPackCharge.run()
		"battery mesh": return TestBatteryMesh.run()
		"component mesh": return TestComponentMesh.run()
		"fpv view": return TestFpvView.run()
		"yaw authority": return TestYawAuthority.run()
		"gyro": return TestGyro.run()
		"vibration": return TestVibration.run()
		"forward flight": return TestForwardFlight.run()
		"air density": return TestAirDensity.run()
		"flight recorder": return TestFlightRecorder.run()
		"studio": return TestStudio.run()
		"spectrum": return TestSpectrum.run()
		"motor mixer": return TestMotorMixer.run()
		"control path": return TestControlPath.run()
		"stick release": return TestStickRelease.run()
		"warnings": return TestWarnings.run()
		"build warnings": return TestBuildWarnings.run()
		"flight controller": return TestFlightController.run()
		"rate tune": return TestRateTune.run()
		"catalog tuning": return TestCatalogTuning.run()
		"pid tunes": return TestPidTunes.run()
		"custom frames": return TestCustomFrames.run()
		"custom motors": return TestCustomMotors.run()
		"custom propellers": return TestCustomPropellers.run()
		"custom batteries": return TestCustomBatteries.run()
		"custom escs": return TestCustomEscs.run()
		"custom flight controllers": return TestCustomFlightControllers.run()
		"electronics parts": return TestElectronicsParts.run()
		"electronics ui": return TestElectronicsUi.run()
		"custom parts ui": return TestCustomPartsUi.run()
		"update check": return TestUpdateCheck.run()
		"licence check": return TestLicenceCheck.run()
		"activation gate": return TestActivationGate.run()
		"rust constants": return TestRustConstants.run()
		"glass shell": return TestGlassShell.run()
		"room host": return TestRoomHost.run()
		"project": return TestProject.run()
		"project menu": return TestProjectMenu.run()
		"project container": return TestProjectContainer.run()
		"project wiring": return TestProjectWiring.run()
	push_error("unknown suite: %s" % suite_name)
	return []
