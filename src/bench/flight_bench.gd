extends Node
## A reproducible flight for measuring what Lothal costs a machine — the numbers a published
## "minimum system requirements" line has to come from.
##
##   Lothal -- --bench-flight [--seconds=60] [--uncapped]      (see bench_launcher.gd)
##
## Boots the real field scene (main.tscn, the same one the Sim toggle opens) and flies it with
## scripted KEY PRESSES, not by writing the rc struct: the input goes through main.gd's own
## _read_keyboard, so the bench exercises the path a pilot does and no second control route
## exists. The route is fixed, so two machines fly the same flight. Crashes are part of it —
## the respawn path is real work a pilot's machine also does.
##
## It lives in src/ rather than tools/ because tools/ is excluded from every export preset,
## and the whole point is to run the SHIPPED build on other people's hardware.
##
## Output: one JSON line per second, then a SUMMARY line, on stdout and in
## user://bench/flight_bench.jsonl. CPU% is not here — Godot cannot see its own process CPU;
## sample it from outside (ps / Task Manager) while this runs.
##
## --uncapped turns vsync off, so the frame rate reads as headroom rather than as the display's
## refresh rate. Without it, a 60 Hz panel reports 60 on every machine that can keep up.

const DEFAULT_SECONDS := 60.0
const MAIN_SCENE := "res://src/scenes/main.tscn"
const OUT_PATH := "user://bench/flight_bench.jsonl"

## The route, as (start_s, keys held). Each entry holds until the next. Climb out, fly forward
## with alternating turns so the camera sweeps the whole course, then repeat.
const ROUTE := [
	[0.0, [KEY_W]],
	[2.5, [KEY_UP]],
	[6.0, [KEY_UP, KEY_LEFT]],
	[7.0, [KEY_UP, KEY_W]],
	[10.0, [KEY_UP, KEY_RIGHT, KEY_D]],
	[11.5, [KEY_UP]],
	[14.0, [KEY_UP, KEY_A, KEY_W]],
	[16.0, [KEY_DOWN]],
	[18.0, []],
]
const ROUTE_PERIOD_S := 20.0

var _seconds := DEFAULT_SECONDS
var _elapsed := 0.0
var _held: Array = []
var _frame_ms: PackedFloat32Array = []
var _second_frames: PackedFloat32Array = []
var _next_report_s := 1.0
var _out: FileAccess
var _main: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			_seconds = maxf(5.0, arg.substr(10).to_float())
		elif arg == "--uncapped":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	_out = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)


func _process(delta: float) -> void:
	_elapsed += delta
	_frame_ms.append(delta * 1000.0)
	_second_frames.append(delta * 1000.0)
	_steer(fmod(_elapsed, ROUTE_PERIOD_S))
	if _elapsed >= _next_report_s:
		_next_report_s += 1.0
		_emit(_sample())
		_second_frames.clear()
	if _elapsed >= _seconds:
		_steer_release_all()
		_emit(_summary())
		if _out != null:
			_out.close()
		get_tree().quit()


func _steer(t: float) -> void:
	var want: Array = []
	for step in ROUTE:
		if t >= step[0]:
			want = step[1]
	if want == _held:
		return
	for key in _held:
		if key not in want:
			_send(key, false)
	for key in want:
		if key not in _held:
			_send(key, true)
	_held = want.duplicate()


func _steer_release_all() -> void:
	for key in _held:
		_send(key, false)
	_held = []


func _send(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _sample() -> Dictionary:
	# Where the drone is, so a run that sat on the pad cannot pass for a flight.
	var pos := Vector3.ZERO
	if _main.get("core") != null:
		pos = _main.core.rigid_body.position_m
	return {
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
		"t": snappedf(_elapsed, 0.01),
		"fps": Engine.get_frames_per_second(),
		"frame_ms_worst": snappedf(_max(_second_frames), 0.01),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	}


## Frame-time percentiles over the whole run, skipping the first 3 s of load and shader compile —
## those are a one-off, and a steady-state requirement should not be set by them.
func _summary() -> Dictionary:
	var skip := 0
	var acc := 0.0
	while skip < _frame_ms.size() and acc < 3000.0:
		acc += _frame_ms[skip]
		skip += 1
	var steady := _frame_ms.slice(skip)
	steady.sort()
	var n := steady.size()
	var mean := 0.0
	for v in steady:
		mean += v
	mean = mean / n if n > 0 else 0.0
	return {
		"summary": true,
		"seconds": snappedf(_elapsed, 0.01),
		"frames": n,
		"avg_fps": snappedf(1000.0 / mean, 0.1) if mean > 0.0 else 0.0,
		"frame_ms_p50": snappedf(_pct(steady, 0.50), 0.01),
		"frame_ms_p99": snappedf(_pct(steady, 0.99), 0.01),
		"frame_ms_max": snappedf(steady[n - 1], 0.01) if n > 0 else 0.0,
		"static_mb_peak": snappedf(OS.get_static_memory_peak_usage() / 1048576.0, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"gpu": RenderingServer.get_video_adapter_name(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"os": OS.get_name() + " " + OS.get_version(),
	}


static func _pct(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(sorted.size() - 1, int(p * sorted.size()))]


static func _max(values: PackedFloat32Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, v)
	return m


func _emit(row: Dictionary) -> void:
	var line := JSON.stringify(row)
	print("BENCH ", line)
	if _out != null:
		_out.store_line(line)
		_out.flush()
