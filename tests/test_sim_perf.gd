class_name TestSimPerf
extends RefCounted
## Budget for the flying sim's per-tick cost. History: the HUD re-solved the whole aircraft's hover
## current (Build.remaining_flight_time_min, ~3.9 ms) on EVERY 120 Hz physics tick, so a tick cost
## 6.5 ms against an 8.3 ms budget and the windowed sim crawled at ~13 fps, while a headless core
## step stayed at 0.2 ms. Nothing measured the whole `_physics_process`, so nothing noticed.
##
## The budget is 1 ms per tick (measured 0.17 ms fixed, 6.5 ms regressed on an M5), averaged over
## 120 ticks after a warm-up so one-off solves do not decide it. Timing is machine-dependent, so the
## bound has a 6x margin on the good number and a 6x gap to the bad one.

const TICKS := 120
const BUDGET_MS := 1.0


static func run(tree: SceneTree) -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var build := DesignSession.default_for_class("five_inch").build(catalog)
	var sim: Node = load("res://src/scenes/main.tscn").instantiate()
	sim.initial_build = build
	sim.initial_drone_class = "five_inch"
	tree.root.add_child(sim)
	await tree.process_frame
	await tree.process_frame
	for i in 20:
		sim._physics_process(1.0 / 120.0)

	var t0 := Time.get_ticks_usec()
	for i in TICKS:
		sim._physics_process(1.0 / 120.0)
	var tick_ms := (Time.get_ticks_usec() - t0) / 1000.0 / TICKS
	results.append(TestResult.new("sim physics tick (FC, rotors, HUD, audio, scoring) stays under 1 ms",
		tick_ms < BUDGET_MS, "%.3f ms per 120 Hz tick (budget %.1f)" % [tick_ms, BUDGET_MS]))

	var solves_before: int = sim.hud.remaining_solves
	for i in TICKS:
		sim._physics_process(1.0 / 120.0)
	var solves: int = sim.hud.remaining_solves - solves_before
	results.append(TestResult.new("the HUD's time-left solve is not run on every tick",
		solves <= 3, "%d solves in %d ticks" % [solves, TICKS]))

	# Prop wash: soft round puffs. The hard-edged rectangles came from quads sliced by the ground.
	var wash := PropWash.new()
	var quad: QuadMesh = wash._particles.draw_pass_1
	var mat: StandardMaterial3D = quad.material
	var tex: GradientTexture2D = mat.albedo_texture
	var edge_alpha := tex.gradient.sample(1.0).a
	results.append(TestResult.new("prop wash puffs fade to nothing before the quad edge and fade against the ground",
		edge_alpha == 0.0 and mat.proximity_fade_enabled and tex.gradient.sample(0.9).a == 0.0,
		"edge alpha %.2f, proximity fade %s" % [edge_alpha, mat.proximity_fade_enabled]))
	wash.free()
	sim.queue_free()
	return results
