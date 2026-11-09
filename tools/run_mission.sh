#!/usr/bin/env bash
## SR4: fly one ready-made mission headless and print a one-screen summary + the JSON path.
##   tools/run_mission.sh --class=five_inch --mission=survey [--seed=1 --height=25 --speed=3 --front=0.75 --side=0.65
##     --reserve=25 --wind=5 --wind-from=90 --gust=1 --capacity-scale=1 --out=/tmp/x.json]
## Exit: 0 completed, 1 failed/aborted, 2 usage error. Missions: hover_endurance cruise_loop range_test survey follow_path test_pack.
cd "$(dirname "$0")/.." || exit 2
exec godot --headless --script res://tools/run_mission.gd -- "$@"
