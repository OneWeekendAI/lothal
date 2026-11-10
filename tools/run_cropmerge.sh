#!/usr/bin/env bash
## L5.1: acres per battery as a range, class "mapper" and the reference build "mavic_3m", Illinois preset world polygon.
##   tools/run_cropmerge.sh [--n=8] [--seed=1] [--max-sim-min=N]
## Runs in a scratch HOME so nothing is written to the real user dir.
cd "$(dirname "$0")/.." || exit 2
H=$(mktemp -d "${TMPDIR:-/tmp}/lothal-cropmerge.XXXX")
HOME=$H godot --headless --script res://tools/run_cropmerge.gd -- "$@"
rc=$?
rm -rf "$H"
exit $rc
