class_name TestGateCourse
extends RefCounted
## Day 6's gate logic, which is pure geometry and therefore fully testable headless.
##
## The check that earns its keep is the tunnelling one. Gate detection is the kind of code
## that passes a hand-flown smoke test and then fails exactly when the pilot is going fast
## enough to care, because a per-frame "is the drone inside the ring" test samples a 23 cm
## step at 100 km/h and can step clean over the ring. Every other test here would pass a
## naive proximity implementation; that one is the reason the segment test exists.

static func run() -> Array:
	var results: Array = []
	results.append_array(_geometry())
	results.append_array(_passage())
	results.append_array(_ordering())
	results.append_array(_timing())
	return results

static func _geometry() -> Array:
	var results: Array = []
	var course := GateCourse.new()

	results.append(TestResult.new(
		"course is eight gates in a closed loop",
		course.gates.size() == 8,
		"%d gates" % course.gates.size()
	))

	# Every gate's normal should be the direction to the NEXT gate, near enough — that is
	# what makes the course flyable as a circuit rather than a set of unrelated hoops.
	var worst_alignment := 1.0
	for i in course.gates.size():
		var here: Dictionary = course.gates[i]
		var next: Dictionary = course.gates[(i + 1) % course.gates.size()]
		var to_next: Vector3 = (next["position"] - here["position"]).normalized()
		worst_alignment = minf(worst_alignment, to_next.dot(here["normal"]))

	results.append(TestResult.new(
		"every gate faces the next one (the circuit is flyable in order)",
		worst_alignment > 0.9,
		"worst normal-to-next alignment = %.3f" % worst_alignment
	))

	var min_height := INF
	for gate in course.gates:
		min_height = minf(min_height, float(gate["position"].y) - GateCourse.GATE_INNER_RADIUS_M)
	results.append(TestResult.new(
		"no gate's ring intersects the ground",
		min_height > 0.0,
		"lowest ring edge sits %.2f m above ground" % min_height
	))

	return results

static func _passage() -> Array:
	var results: Array = []
	var course := GateCourse.new()
	var gate: Dictionary = course.gates[0]
	var origin: Vector3 = gate["position"]
	var normal: Vector3 = gate["normal"]

	results.append(TestResult.new(
		"flying through the middle of a gate counts",
		GateCourse.segment_passes_gate(origin - normal * 0.5, origin + normal * 0.5, gate),
		"centred crossing"
	))

	# 40 m/s through a 120 Hz frame is a 33 cm step; this is a deliberately brutal 6 m one.
	# A proximity test ("within the ring radius this frame") fails here and passes everything
	# else in this suite.
	results.append(TestResult.new(
		"a single huge step straight through a gate still counts (no tunnelling)",
		GateCourse.segment_passes_gate(origin - normal * 3.0, origin + normal * 3.0, gate),
		"6 m step across the ring in one frame"
	))

	# Off to one side of the ring, same plane crossing. Must NOT count.
	var sideways := normal.cross(Vector3.UP).normalized() * (GateCourse.GATE_INNER_RADIUS_M + 0.6)
	results.append(TestResult.new(
		"passing the gate plane outside the ring does not count",
		not GateCourse.segment_passes_gate(
			origin + sideways - normal * 0.5, origin + sideways + normal * 0.5, gate),
		"crossed %.1f m off-centre through a %.1f m ring" % [sideways.length(), GateCourse.GATE_INNER_RADIUS_M]
	))

	results.append(TestResult.new(
		"flying over the top of a gate does not count",
		not GateCourse.segment_passes_gate(
			origin + Vector3.UP * 3.0 - normal * 0.5, origin + Vector3.UP * 3.0 + normal * 0.5, gate),
		"crossed the plane 3 m above the ring"
	))

	results.append(TestResult.new(
		"flying backwards through a gate does not count (the course has a direction)",
		not GateCourse.segment_passes_gate(origin + normal * 0.5, origin - normal * 0.5, gate),
		"reverse crossing of a centred gate"
	))

	results.append(TestResult.new(
		"hovering near a gate without crossing it does not count",
		not GateCourse.segment_passes_gate(origin - normal * 0.4, origin - normal * 0.3, gate),
		"moved 10 cm, stayed on the approach side"
	))

	# The start line has to be lined up with gate 1, or a new pilot's first instinct —
	# push forward — flies into the rim. This failed the first time it was looked at: the
	# drone spawned in the middle of the circuit, where every gate is edge-on.
	var start := course.start_position()
	var straight_ahead := start + course.start_forward() * (GateCourse.START_SETBACK_M + 4.0)
	results.append(TestResult.new(
		"flying straight ahead from the start goes through gate 1",
		GateCourse.segment_passes_gate(start, straight_ahead, course.gates[0]),
		"start %v -> %v" % [start, straight_ahead]
	))

	results.append(TestResult.new(
		"the start line is above the ground and short of gate 1",
		start.y > 1.0 and start.distance_to(course.gates[0]["position"]) > 2.0,
		"start is %.1f m up, %.1f m short of gate 1" % [start.y, start.distance_to(course.gates[0]["position"])]
	))

	return results

static func _ordering() -> Array:
	var results: Array = []
	var course := GateCourse.new()

	# Fly gate 3 while gate 1 is due.
	var gate3: Dictionary = course.gates[2]
	var scored_out_of_order := course.advance(
		gate3["position"] - gate3["normal"] * 0.5, gate3["position"] + gate3["normal"] * 0.5)

	results.append(TestResult.new(
		"gates must be taken in order — a skipped gate scores nothing",
		not scored_out_of_order and course.next_gate_index == 0,
		"flew gate 3 first; next gate is still %d" % (course.next_gate_index + 1)
	))

	var laps := 0
	var passes := 0
	for i in course.gates.size():
		var gate: Dictionary = course.gates[i]
		if course.advance(gate["position"] - gate["normal"] * 0.5, gate["position"] + gate["normal"] * 0.5):
			passes += 1
			if course.just_completed_lap():
				laps += 1

	results.append(TestResult.new(
		"flying all eight in order completes exactly one lap",
		passes == 8 and laps == 1 and course.next_gate_index == 0,
		"%d gates, %d lap(s), re-armed at gate %d" % [passes, laps, course.next_gate_index + 1]
	))

	# Respawn must put the drone at the last gate cleared, not back at the origin.
	course.reset()
	var gate1: Dictionary = course.gates[0]
	course.advance(gate1["position"] - gate1["normal"] * 0.5, gate1["position"] + gate1["normal"] * 0.5)
	var respawn := course.respawn_position()
	results.append(TestResult.new(
		"a crash respawns at the last gate cleared, not at the start",
		respawn.distance_to(gate1["position"]) < 2.0 and respawn.y > 1.0,
		"respawn %.1f m from gate 1, %.1f m up" % [respawn.distance_to(gate1["position"]), respawn.y]
	))

	# And that respawn point must not instantly re-score the gate it spawned past.
	results.append(TestResult.new(
		"respawning past a gate does not immediately re-trigger it",
		not GateCourse.segment_passes_gate(respawn, respawn + gate1["normal"] * 0.1, course.gates[1]),
		"respawn sits beyond gate 1, and gate 2 is the one now due"
	))

	return results

static func _timing() -> Array:
	var results: Array = []
	var save_path := "user://test_best_lap.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	var timer := LapTimer.new(save_path)

	# Time spent before the first gate must not land on the lap.
	timer.tick(5.0)
	results.append(TestResult.new(
		"the clock does not run before the first gate is taken",
		timer.current_lap_s == 0.0,
		"5 s of pre-start idling recorded as %.2f s" % timer.current_lap_s
	))

	timer.on_gate_passed(false)          # gate 1 — starts the clock
	for i in 6:
		timer.tick(1.0)
		timer.on_gate_passed(false)      # gates 2-7
	timer.tick(1.0)
	timer.on_gate_passed(true)           # gate 8 — lap complete, 7 s

	results.append(TestResult.new(
		"a completed lap is timed from the first gate",
		absf(timer.last_lap_s - 7.0) < 0.001 and absf(timer.best_lap_s - 7.0) < 0.001,
		"lap = %.2f s, best = %.2f s" % [timer.last_lap_s, timer.best_lap_s]
	))

	results.append(TestResult.new(
		"the next lap starts from zero, not from the last lap's total",
		timer.current_lap_s == 0.0,
		"current lap = %.2f s immediately after completing one" % timer.current_lap_s
	))

	# A slower lap must not overwrite the best.
	for i in 9:
		timer.tick(1.0)
	timer.on_gate_passed(true)
	results.append(TestResult.new(
		"a slower lap does not overwrite the best time",
		absf(timer.best_lap_s - 7.0) < 0.001 and absf(timer.last_lap_s - 9.0) < 0.001,
		"9.00 s lap flown; best still %.2f s" % timer.best_lap_s
	))

	# A faster one must.
	for i in 4:
		timer.tick(1.0)
	timer.on_gate_passed(true)
	results.append(TestResult.new(
		"a faster lap takes the best time",
		absf(timer.best_lap_s - 4.0) < 0.001,
		"4.00 s lap flown; best now %.2f s" % timer.best_lap_s
	))

	results.append(TestResult.new(
		"the best time survives a restart (persisted to disk)",
		absf(LapTimer.new(save_path).best_lap_s - 4.0) < 0.001,
		"reloaded best = %.2f s" % LapTimer.new(save_path).best_lap_s
	))

	# Crashing must void the lap in progress rather than time through the respawn.
	timer.on_gate_passed(false)
	timer.tick(3.0)
	timer.invalidate_lap()
	timer.tick(3.0)
	results.append(TestResult.new(
		"a crash voids the lap in progress instead of timing through the respawn",
		not timer.running and timer.current_lap_s == 0.0,
		"post-crash clock = %.2f s, running = %s" % [timer.current_lap_s, timer.running]
	))

	results.append(TestResult.new(
		"lap times render as m:ss.hh",
		LapTimer.format(83.25) == "1:23.25" and LapTimer.format(0.0) == "--:--.--",
		"83.25 s -> %s, no lap -> %s" % [LapTimer.format(83.25), LapTimer.format(0.0)]
	))

	return results
