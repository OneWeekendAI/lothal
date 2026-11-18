extends SceneTree
## B4 probe: where the 120 Hz tick goes. godot --headless --script res://tests/probe_tick_profile.gd
func _ms(t0: int, n: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _init() -> void:
	await process_frame
	var catalog := PartsCatalog.load_default()
	var build := DesignSession.default_for_class("five_inch").build(catalog)
	var sim: Node = load("res://src/scenes/main.tscn").instantiate()
	sim.initial_build = build
	sim.initial_drone_class = "five_inch"
	root.add_child(sim)
	await process_frame
	await process_frame
	for i in 20:
		sim._physics_process(1.0 / 120.0)
	var n := 240
	var t0 := Time.get_ticks_usec()
	for i in n:
		sim._physics_process(1.0 / 120.0)
	print("TICK %.3f ms" % _ms(t0, n))
	var core = sim.core
	var fc = sim.fc
	var sub: int = sim.SUBSTEPS
	var dt := 1.0 / 120.0 / sub
	t0 = Time.get_ticks_usec()
	for i in n * sub:
		fc.update(core.accel.reading_mps2, core.gyro.rate_rad_s, sim.rc, dt, core.vbat)
	print("FC per tick %.3f ms" % _ms(t0, n))
	var cmds = fc.update(core.accel.reading_mps2, core.gyro.rate_rad_s, sim.rc, dt, core.vbat)
	t0 = Time.get_ticks_usec()
	for i in n * sub:
		core.step(cmds, dt)
	print("core.step per tick %.3f ms" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in n:
		core.collision_world = CollisionWorld.new(sim.terrain, sim.obstacles, sim.course.gates)
	print("CollisionWorld.new %.3f ms" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in n:
		sim.hud.render(core, sim.build, sim.course, sim.lap_timer, false)
	print("hud %.3f ms" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in n:
		sim.drone_audio.update(core.observables, sim._chase_transform.origin)
	print("audio %.3f ms" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in n:
		sim._score_gates(1.0 / 120.0)
	print("score %.3f ms" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in n:
		sim._push_visual(core.rigid_body.position_m, core.rigid_body.orientation)
	print("push_visual %.3f ms" % _ms(t0, n))
	var m := n * sub
	var p = core.rigid_body.position_m
	t0 = Time.get_ticks_usec()
	for i in m:
		core.wind.update_at(dt, p, 1.0)
	print("  wind.update_at %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m:
		core.powertrain.step_in_flight(core.last_motor_cmds, dt, Vector3(0.5, 0.1, 0.3))
	print("  powertrain %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m:
		core._resolve_collisions()
	print("  collisions %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m:
		core.gyro.update(Vector3(0.1, 0, 0), dt)
	print("  gyro %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m:
		core.accel.update(Vector3(0, 9.8, 0), Vector3.ZERO, dt)
	print("  accel %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m:
		core._publish(Vector3(0, 9.8, 0))
	print("  publish %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m:
		core._mean_flap_tilt(Vector3(1, 0, 1))
	print("  flap_tilt %.3f ms/tick" % _ms(t0, n))
	var saved_cw = core.collision_world
	core.collision_world = null
	t0 = Time.get_ticks_usec()
	for i in m:
		core.step(cmds, dt)
	print("  step no-collide %.3f ms/tick" % _ms(t0, n))
	core.rotor_h_force_enabled = false
	t0 = Time.get_ticks_usec()
	for i in m:
		core.step(cmds, dt)
	print("  step no-collide no-H %.3f ms/tick" % _ms(t0, n))
	core.rotor_h_force_enabled = true
	core.collision_world = saved_cw
	var cw = core.collision_world
	print("  obstacles %d gates %d terrain %s" % [cw.obstacles.size(), cw.gates.size(), cw.terrain])
	t0 = Time.get_ticks_usec()
	for i in m * 9:
		cw.contact(p, 0.02)
	print("  contact x9 %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m:
		core.contact_points()
	print("  contact_points %.3f ms/tick" % _ms(t0, n))
	t0 = Time.get_ticks_usec()
	for i in m * 9:
		sim.terrain.height_at(p.x, p.z)
	print("  height_at x9 %.3f ms/tick" % _ms(t0, n))
	quit()
