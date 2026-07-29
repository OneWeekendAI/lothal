class_name LapTimer
extends RefCounted
## Times laps of the GateCourse and remembers the best one across sessions.
##
## The clock starts when the first gate is taken, not when the scene loads — otherwise
## every first lap of a session carries however long the pilot spent reading the build
## panel, and the best time becomes unbeatable-by-accident rather than earned.

const SAVE_PATH := "user://best_lap.json"

var current_lap_s := 0.0
var last_lap_s := 0.0
var best_lap_s := 0.0     ## 0.0 means "no lap recorded yet"
var running := false
var save_path: String

## Tests pass their own path; the game uses user://. Left injectable so the suite can
## never write over a real best time.
func _init(p_save_path: String = SAVE_PATH) -> void:
	save_path = p_save_path
	load_best()

func tick(delta: float) -> void:
	if running:
		current_lap_s += delta

## Called when a gate is cleared. The first gate starts the clock; completing a lap
## records it and immediately starts the next one, so a flown circuit times continuously.
func on_gate_passed(completed_lap: bool) -> void:
	if not running:
		running = true
		current_lap_s = 0.0
		return

	if completed_lap:
		last_lap_s = current_lap_s
		if best_lap_s <= 0.0 or last_lap_s < best_lap_s:
			best_lap_s = last_lap_s
			save_best()
		current_lap_s = 0.0

## A crash voids the lap in progress. Timing through a reset would reward crashing into
## the ground as a shortcut, since the respawn skips whatever was between here and the
## last gate.
func invalidate_lap() -> void:
	running = false
	current_lap_s = 0.0

static func format(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.--"
	var minutes := int(seconds) / 60
	var remainder := seconds - float(minutes * 60)
	return "%d:%05.2f" % [minutes, remainder]

func load_best() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	# A corrupt or hand-edited save must not take the game down with it — a missing best
	# time is a cosmetic loss, and refusing to boot over it is not.
	if parsed is Dictionary and parsed.has("best_lap_s"):
		best_lap_s = maxf(float(parsed["best_lap_s"]), 0.0)

func save_best() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("could not write best lap to %s" % save_path)
		return
	file.store_string(JSON.stringify({"best_lap_s": best_lap_s}))
	file.close()
