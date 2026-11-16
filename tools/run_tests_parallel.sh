#!/usr/bin/env bash
## Runs tests/run_tests.gd (+ the SR suites) sharded across N parallel godot processes.
##   tools/run_tests_parallel.sh              # JOBS=7 workers
##   JOBS=4 tools/run_tests_parallel.sh
##   WORKER_TIMEOUT=2700 (seconds per worker, default 45 min; the summary names the suite that hung)
##   ONLY="a|b" run just those suites (no tail, no SR); handy for trying the runner out
##   TIMINGS=<file>  per-suite seconds, default tools/suite_timings.tsv; rewritten after every run and
##                   used for greedy longest-first packing on the next one.
## Same safety as tools/run_tests_safe.sh: each worker gets its OWN scratch HOME under $HOME (never
## /var/folders), so no worker can touch the real Lothal user data nor another worker's files.
## Only PIDs this script started are ever signalled. No pkill, no killall.
## Needs bash 3.2 (macOS): no wait -n, no associative arrays.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
JOBS="${JOBS:-7}"
WORKER_TIMEOUT="${WORKER_TIMEOUT:-2700}"
TIMINGS="${TIMINGS:-$REPO_ROOT/tools/suite_timings.tsv}"
OUT="${OUT:-$REPO_ROOT/.test_runs/parallel.$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
HOMES=()
cleanup() {
	local h
	for h in ${HOMES[@]+"${HOMES[@]}"}; do rm -rf "$h"; done
}
interrupt() {
	echo "[parallel] interrupted; stopping the workers this script started" >&2
	local f p
	for f in "$OUT"/pid_*; do
		[[ -f "$f" ]] || continue
		p="$(cat "$f")"
		kill -TERM "$p" 2>/dev/null || true
	done
	exit 130
}
trap cleanup EXIT
trap interrupt INT TERM

python3 -I "$SCRIPT_DIR/run_tests_parallel.py" pack tests/run_tests.gd "$TIMINGS" "$JOBS" "$OUT" || exit 2

# run_bounded <limit> <log> <pidfile> <cmd...>: background run, appends to log, on expiry kills only that pid (returns 124).
run_bounded() {
	local limit="$1" log="$2" pidfile="$3"
	shift 3
	"$@" >>"$log" 2>&1 &
	local child=$!
	echo "$child" >"$pidfile"
	local waited=0
	while kill -0 "$child" 2>/dev/null; do
		if [[ "$waited" -ge "$limit" ]]; then
			echo "[WATCHDOG] worker timed out after ${limit}s; terminating pid $child (ours)" >>"$log"
			kill -TERM "$child" 2>/dev/null || true
			sleep 5
			if kill -0 "$child" 2>/dev/null; then kill -KILL "$child" 2>/dev/null || true; fi
			wait "$child" 2>/dev/null || true
			return 124
		fi
		sleep 1
		waited=$((waited + 1))
	done
	local st=0
	wait "$child" || st=$?
	return "$st"
}

worker() {
	local k="$1" home="$2"
	local shard="$OUT/shard_$k.txt" log="$OUT/worker_$k.log"
	local names="" tail=0 sr=0 line st=0
	while read -r line; do
		[[ -z "$line" ]] && continue
		case "$line" in
			@tail) tail=1 ;;
			@sr) sr=1 ;;
			*) names="${names:+$names|}$line" ;;
		esac
	done <"$shard"
	: >"$log"
	if [[ -n "$names" || "$tail" -eq 1 ]]; then
		local args=("only=${names:-__none__}")
		if [[ "$tail" -eq 0 ]]; then args+=("notail"); fi
		run_bounded "$WORKER_TIMEOUT" "$log" "$OUT/pid_$k" env HOME="$home" godot --headless --script res://tests/run_tests.gd -- "${args[@]}" || st=$?
	fi
	if [[ "$sr" -eq 1 && "$st" -ne 124 ]]; then
		local s2=0 sr_t0=$SECONDS
		run_bounded "$WORKER_TIMEOUT" "$log" "$OUT/pid_$k" env HOME="$home" godot --headless --script res://tests/sim_reality/run_suites.gd -- prefix=sr || s2=$?
		echo "[time] @sr | $((SECONDS - sr_t0)).0" >>"$log"
		if [[ "$s2" -ne 0 ]]; then st="$s2"; fi
	fi
	echo "$st" >"$OUT/status_$k"
}

T0=$SECONDS
echo "[parallel] $JOBS workers, logs in $OUT"
k=0
while [[ "$k" -lt "$JOBS" ]]; do
	h="${HOME}/.lothal-test-home.par.$$.$k.$RANDOM"
	mkdir -p "$h"
	HOMES+=("$h")
	worker "$k" "$h" &
	k=$((k + 1))
done
wait
# Timing-budget suites (SERIAL in run_tests_parallel.py), alone: every shard has exited, nothing else of ours is alive.
NW="$JOBS"
if [[ -f "$OUT/shard_$JOBS.txt" ]]; then
	h="${HOME}/.lothal-test-home.par.$$.serial.$RANDOM"
	mkdir -p "$h"
	HOMES+=("$h")
	echo "[parallel] shards done; running the timing-budget suites serially"
	worker "$JOBS" "$h"
	NW=$((JOBS + 1))
fi
WALL=$((SECONDS - T0))

statuses=""
k=0
while [[ "$k" -lt "$NW" ]]; do
	s=1
	if [[ -f "$OUT/status_$k" ]]; then s="$(cat "$OUT/status_$k")"; fi
	statuses="${statuses:+$statuses,}$s"
	k=$((k + 1))
done
python3 -I "$SCRIPT_DIR/run_tests_parallel.py" summary "$OUT" "$TIMINGS" "$WALL" "$NW" "$statuses"
exit $?
