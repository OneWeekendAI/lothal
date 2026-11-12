#!/usr/bin/env bash
## Batch survey runner: tools/run_survey_matrix.sh SPECS.json OUT.csv [JOBS=5]
## SPECS.json is a JSON array of run specs (keys in src/autopilot/survey_matrix.gd). Rows are APPENDED to OUT.csv in spec order
## (header written if the file is new). One godot process per job, each with its own scratch HOME. About 40 s per run.
cd "$(dirname "$0")/.." || exit 2
SPECS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$2; JOBS=${3:-5}
[ -f "$SPECS" ] && [ -n "$OUT" ] || { echo "usage: $0 SPECS.json OUT.csv [JOBS]"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/lothal-matrix.XXXX")
for ((j = 0; j < JOBS; j++)); do
  H="$T/home$j"; mkdir -p "$H"
  HOME=$H godot --headless --path . --script res://tools/run_survey_matrix.gd -- --specs="$SPECS" --shard=$j --shards=$JOBS > "$T/out$j.txt" 2>&1 &
done
wait
if [ ! -s "$OUT" ]; then
  python3 -c "import re;print(','.join(re.findall(r'\"([a-z0-9_]+)\"',open('src/autopilot/survey_matrix.gd').read().split('const COLUMNS := [')[1].split(']')[0])))" > "$OUT"
fi
grep -h "^ROW" "$T"/out*.txt | sort -t$'\t' -k2,2n | cut -f3- > "$T/rows.csv"
cat "$T/rows.csv" >> "$OUT"
grep -h "^WALL" "$T"/out*.txt | cut -f3 | awk '{s+=$1;n++} END{if(n)printf "%d runs, %.1f s mean wall per run\n", n, s/n}'
rm -rf "$T"
