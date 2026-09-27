extends Node
## Autoload: `Lothal -- --bench-flight [--seconds=60] [--uncapped]` boots straight into the
## scripted benchmark flight (flight_bench.gd) instead of the app.
##
## A flag and not a scene path because release export templates refuse a scene path on the
## command line ("compiled without support for path overrides") — measured on the shipped
## macOS build, which is the build the bench exists to run.
##
## The flag opens nothing a user could not already reach by clicking Sim.

const FLAG := "--bench-flight"
const BENCH_SCENE := "res://src/bench/flight_bench.tscn"


func _ready() -> void:
	if FLAG not in OS.get_cmdline_user_args():
		return
	get_tree().change_scene_to_file.call_deferred(BENCH_SCENE)
