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
	"gate course", "site", "fingerprint survival", "terrain", "terrain mesh", "obstacles", "ground authority", "real files", "conditions", "field room", "course library", "course warnings", "hud", "keyboard throttle", "observables", "rotor synth",
	"frame model", "mount points", "stack mesh", "battery mount", "motor mesh", "propeller mesh", "airframe", "mounting",
	"assembly tweaks", "prop rotation", "lab", "powertrain", "bench", "validation", "build validation",
	"battery rail", "battery model", "hover at charge", "pack current limit", "charge readouts", "esc", "esc bench", "battery bench", "frame bench", "pack charge", "battery mesh", "component mesh", "fpv view",
	"yaw authority", "gyro", "wind", "wind numbers", "motor mixer", "control path", "stick release", "warnings", "build warnings", "warning rows",
	"flight controller", "rate tune", "catalog tuning", "pid tunes", "vibration", "forward flight", "air density", "flight recorder", "studio", "spectrum",
	"custom frames", "custom motors", "custom propellers", "custom batteries", "custom escs", "custom flight controllers", "electronics parts", "electronics ui", "custom parts ui", "update check", "licence check", "activation gate", "rust constants", "glass shell", "room host", "project", "project menu", "project container", "project wiring",
	"polygon props", "control effectiveness", "frame materials", "hardware mass",
	"airframe document", "airframe properties", "frame layouts", "frame export", "frame import", "airframe room", "arm beam", "arm profile", "frame edits", "frame plan editor", "frame workbench", "plate mesh", "airframe tabs",
	"propeller document", "blade geometry", "blade aero", "blade room", "bemt", "calibration", "bemt forward", "propulsion panel", "motor spin up", "soft mount", "bemt ratios", "prop guard", "guard mesh", "planform edits", "propulsion room", "authored blade", "thrust overlay", "campbell overlay", "vibration overlay", "spin up overlay", "prop disc overlay", "stl writer", "propulsion export", "guard row", "overlay tray", "dock", "camera view", "part finder",
	"wire gauge", "power parts", "harness", "harness checks", "power room",
	"control parts", "control components", "control rails", "component registration", "control persistence", "control warnings", "custom control components", "config motors", "config motor map", "config ports", "config failsafe", "config arming", "config rates", "config sheet",
	"camera tilt", "video warnings", "video panel",
	"print room", "arm guard", "camera mount", "antenna mount", "printed export", "printed divergence", "fabrication", "gps mast", "battery pad", "stl bodies", "printed infill", "printed drawn"]

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
	#
	# RULING 71 — CALLED FROM A HELPER, AND `await`ED OUT HERE. This used to be
	# `await TestShellLayout.run(self)` inline, in `_init()` itself, above `quit()`, on the one
	# suite in the repo with a non-zero arity and an unusual contract — precisely the shape that
	# produced every orphaned process this plan paid for. An abort inline takes `_init()` with it,
	# never reaches `quit()`, and idles for ever: 1200 s under `tools/run_tests_safe.sh`'s
	# watchdog, and UNBOUNDED under the raw `godot --headless --script res://tests/run_tests.gd`
	# that the wrapper's own header promises keeps working.
	#
	# The `is Array` guard is not belt-and-braces. `_call_layout_run()` is typed `Variant`, and a
	# GDScript abort hands the caller that function's return-type default — `null` — which is not
	# an `Array`. Normalising to `[]` here is what turns a silent hang into the loud `[FAIL]` two
	# lines down. `tools/run_one_suite.gd:93-99` keeps the same refusal for the same reason.
	#
	# WHAT THIS DOES NOT COVER, said plainly: `run()` awaits frames, so an abort raised AFTER its
	# first suspend leaves a function state that is never resumed, and this `await` never returns.
	# The helper cannot contain that one — nothing in GDScript can — and the watchdog in
	# `tools/run_tests_safe.sh` is the backstop for it. What the helper DOES contain is the abort
	# raised synchronously at or before the call, which is the Ruling-71 shape: a wrong arity, an
	# unregistered class, an error in the suite's own prologue.
	var layout_returned: Variant = await _call_layout_run()
	var layout_results: Array = layout_returned if layout_returned is Array else []
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

	# RULING 71. The last line the runner prints, on every path, pass or fail. A log that ends
	# WITHOUT it was cut off mid-run — the process hung, or was terminated by the watchdog in
	# `tools/run_tests_safe.sh`; a log that ends WITH it ran to completion and was merely truncated
	# afterwards (Godot's exit-time RID-leak warnings routinely bury the total, which is why the
	# count is grepped and not tailed). Without this marker those two cases look identical, and
	# telling them apart was costing a re-run every time.
	print("[runner] run_tests.gd reached the end of _init(); exiting %d" % (1 if fail_count > 0 else 0))
	quit(1 if fail_count > 0 else 0)

## Calls the laid-out suite's `run()` FROM A HELPER. Ruling 71, and see the call site above for
## what the inline version cost and what it does not buy.
##
## This is a coroutine and it has to be: `TestShellLayout.run()` is one, and GDScript makes
## calling a coroutine without `await` a PARSE error, so there is no "hand the state back
## un-awaited" shape available. The containment is still real — an abort raised synchronously
## inside `run()` kills THIS function, which returns `null` to a caller that is still alive to
## refuse it, where inline the same abort killed `_init()` itself and the process idled for ever.
##
## Do not inline this call back into `_init()`.
func _call_layout_run() -> Variant:
	return await TestShellLayout.run(self)


## EVERY SUITE IS DISPATCHED FROM HERE, AND THAT IS STRUCTURAL — NOT TIDINESS. Ruling 71.
##
## A GDScript runtime error aborts the function it is raised in and lets the CALLER resume with
## that function's return-type default. All ~160 `run()` calls below are therefore contained: an
## abort in any of them kills THIS function, `_init()` resumes with an empty `Array`, and
## `:34-39` reports a loud `[FAIL]` naming the suite. Inline the `match` into `_init()` — an
## obvious tidy-up, and it looks like one — and the same abort takes `_init()` with it, `quit()`
## is never reached, and the full suite hangs for ever. Nothing else in this file states that
## dependency, which is why it is stated here. Do not inline this dispatch.
func _run_suite(suite_name: String) -> Array:
	match suite_name:
		# F9 — terrain and wind in the lap fingerprint, and the pre-field best laps proved to survive it
		"fingerprint survival": return TestFingerprintSurvival.run()
		# F3 (plans/2026-09-21-field-room-plan.md). The shape vocabulary and height_at — pure, analytic, nothing drawn.
		"terrain": return TestTerrain.run()
		# F5 — the mesh and collider, drawn and rebuilt from one description (Terrain.height_at)
		"terrain mesh": return TestTerrainMesh.run()
		# F6 — obstacles: vocabulary, placement on the terrain, collision, the three new warnings
		"obstacles": return TestObstacles.run()
		# F4 — terrain is the ground authority
		"ground authority": return TestGroundAuthority.run()
		# F4 review round 2 — the hold that puts a builder's files back after an abort
		"real files": return TestRealFiles.run()
		"airframe tabs": return TestAirframeTabs.run()
		"camera view": return TestCameraView.run()
		# QC3: the dock lost nothing — every action the three retired clusters offered, by name.
		"dock": return TestDock.run()
		# PW1 (plans/2026-09-10-power-room-plan.md). Pure data and pure code — no UI, no physics.
		"wire gauge": return TestWireGauge.run()
		"power parts": return TestPowerParts.run()
		# C1 (plans/2026-09-12-control-room-plan.md). Pure data — gps.json, buzzers.json and the
		# loader branch that refuses a row declaring the wrong category.
		# C4: the five registrations a new category touches, asserted together and per component.
		"component registration": return TestComponentRegistration.run()
		# C5: gps and buzzer across a save and a reopen, incl. the pre-existence fixture.
		"control persistence": return TestControlPersistence.run()
		"custom control components": return TestCustomControlComponents.run()
		# C6: ControlPlausibility, LinkDetails and the GPS mast field.
		"control warnings": return TestControlWarnings.run()
		# C2: spin direction from the build, one accessor, today's constants pinned as the default.
		"config motors": return TestConfigMotors.run()
		# C3: the motor map drawn on the aircraft, and the props-in/props-out control behind it.
		"config motor map": return TestConfigMotorMap.run()
		# C5: the supply side of the port budget — uart_range, the typed override, the provenance.
		"config ports": return TestConfigPorts.run()
		# C6: the failsafe panel and the three checks predictable from a build.
		"config failsafe": return TestConfigFailsafe.run()
		# C7: the teaching half of §4.4 — the arming list, in the firmware's own flag names.
		"config arming": return TestConfigArming.run()
		# C8: rates and modes, and the sim-versus-real max-rate statement.
		"config rates": return TestConfigRates.run()
		# C9: the config sheet — the artifact that leaves the room.
		"config sheet": return TestConfigSheet.run()
		"control parts": return TestControlParts.run()
		"control components": return TestControlComponents.run()
		"control rails": return TestControlRails.run()
		"harness": return TestHarness.run()
		"harness checks": return TestHarnessChecks.run()
		"power room": return TestPowerRoom.run()
		# Printed-room PR0 (plans/2026-09-14-printed-room-plan.md).
		"print room": return TestPrintRoom.run()
		# PR1: the arm guard — geometry, refusal, clearance, opt-in mass, drawn = exported.
		"arm guard": return TestArmGuard.run()
		# PR2: the camera mount — a cheek at the tilt, a per-drone plate gap, refusal, no mass.
		"camera mount": return TestCameraMount.run()
		# PR3: the antenna mount — rings, bar, a tube at the whip's lean, labelled standoff guesses.
		"antenna mount": return TestAntennaMount.run()
		# PR4: every printed part into the drone's printed/ with a print record; refusals refuse only themselves.
		"printed export": return TestPrintedExport.run()
		# PR5: on open, a printed part that no longer matches what the build generates is said, with why.
		"printed divergence": return TestPrintedDivergence.run()
		# PR9: printable vs bought, per catalog entry (W1P.2) — no shipped value invented.
		"fabrication": return TestFabrication.run()
		# PR10: the GPS mast — post, flange, pad; mast height from the tweak; opt-in mass on the mast.
		"gps mast": return TestGpsMast.run()
		# PR11: the battery pad — bands and rails with open strap slots; opt-in mass under Build's own pack seat.
		"battery pad": return TestBatteryPad.run()
		# PR13: StlWriter checks each body; touching plates are legal, a mis-wound face inside one is not.
		"stl bodies": return TestStlBodies.run()
		# PR15: one infill convention — every weighted printed part reads PrintSettings, and its row says so.
		"printed infill": return TestPrintedInfill.run()
		# PR16-PR18: fitted printed parts drawn from their exported triangles, where they are weighed or held.
		"printed drawn": return TestPrintedDrawn.run()
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
		# QC1/QC2 (plans/2026-09-19-quiet-canvas-design.md §6): the summoned finder — browse mode
		# with nothing typed, and preview-and-restore across any number of previews.
		"part finder": return TestPartFinder.run()
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
		# F1 (plans/2026-09-21-field-room-plan.md). Pure model and persistence — no UI.
		"site": return TestSite.run()
		# F2 (plans/2026-09-21-field-room-plan.md). Conditions, and air composed from site + conditions.
		"conditions": return TestConditions.run()
		# F10 (plans/2026-09-21-field-room-plan.md). The Field room in the glass shell.
		"field room": return TestFieldRoom.run()
		"course library": return TestCourseLibrary.run()
		"course warnings": return TestCourseWarnings.run()
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
		"camera tilt": return TestCameraTilt.run()
		# V4 (plans/2026-09-13-video-room-design.md §3): VideoPlausibility.
		"video warnings": return TestVideoWarnings.run()
		# V5: Video's Camera panel, driven on a real shell.
		"video panel": return TestVideoPanel.run()
		"yaw authority": return TestYawAuthority.run()
		"gyro": return TestGyro.run()
		# F7: wind in Sim.
		"wind": return TestWind.run()
		# F8: wind in Lab — the headline numbers under the selected conditions.
		"wind numbers": return TestWindNumbers.run()
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
		"warning rows": return TestWarningRows.run()
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
