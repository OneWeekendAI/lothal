#!/usr/bin/env bash
## SR0: fly every reference aircraft headless and print predicted-vs-published. Exit 1 if any is out
## of band. Extra args go to the script, e.g. `tools/run_sim_reality.sh --capacity-scale=0.7`.
cd "$(dirname "$0")/.." || exit 2
exec godot --headless --script res://tests/sim_reality/run_harness.gd -- "$@"
