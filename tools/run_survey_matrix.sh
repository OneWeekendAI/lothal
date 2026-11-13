#!/usr/bin/env bash
## Batch survey runner: tools/run_survey_matrix.sh SPECS.json OUT.csv [JOBS=5] [WALL_S=1200]
## SPECS.json is a JSON array of run specs (keys in src/autopilot/survey_matrix.gd). Rows are APPENDED to OUT.csv in spec order
## (header written if the file is new). ONE godot process PER SPEC (JOBS at a time, each with its own scratch HOME): a fresh process
## per run, because three runs once hung ~4.4 h as the SECOND spec of a long-lived process and ran in ~60 s as the first spec of a new one.
## Two guards: the runner's own max_wall_s (spec key, default 900 s; an error row "wall_cap") and a process kill at WALL_S
## (perl alarm, kills only that godot) that writes an error row with the run_id and no figures. About 40 s per run.
cd "$(dirname "$0")/.." || exit 2
SPECS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$2; JOBS=${3:-5}; WALL=${4:-1200}
[ -f "$SPECS" ] && [ -n "$OUT" ] || { echo "usage: $0 SPECS.json OUT.csv [JOBS] [WALL_S]"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/lothal-matrix.XXXX")
N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$SPECS")
one() {
  local i=$1 H="$T/home$1"; mkdir -p "$H"
  HOME=$H perl -e 'alarm shift; exec @ARGV' "$WALL" godot --headless --path . --script res://tools/run_survey_matrix.gd -- --specs="$SPECS" --only="$i" > "$T/out$i.txt" 2>&1
  if ! grep -q "^ROW" "$T/out$i.txt"; then
    python3 - "$SPECS" "$i" "$WALL" >> "$T/out$i.txt" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))[int(sys.argv[2])]
cols = open("src/autopilot/survey_matrix.gd").read().split("const COLUMNS := [")[1].split("]")[0]
cols = [c.strip().strip('"') for c in cols.replace("\n", "").replace("\t", "").split(",")]
row = {c: "" for c in cols}
for k in ("run_id", "group", "sensor", "field"):
    row[k] = str(s.get(k, ""))
row["ended_by"] = "process_killed"
row["warnings"] = "error: godot process produced no row within %s s wall (killed or crashed); no figures" % sys.argv[3]
print("ROW\t%s\t%s" % (sys.argv[2], ",".join('"%s"' % v if "," in v else v for v in (row[c] for c in cols))))
print("WALL\t%s\t%s" % (sys.argv[2], sys.argv[3]))
PY
  fi
  rm -rf "$H"
}
export -f one; export T SPECS WALL
seq 0 $((N - 1)) | xargs -P "$JOBS" -I{} bash -c 'one {}'
if [ ! -s "$OUT" ]; then
  python3 -c "import re;print(','.join(re.findall(r'\"([a-z0-9_]+)\"',open('src/autopilot/survey_matrix.gd').read().split('const COLUMNS := [')[1].split(']')[0])))" > "$OUT"
fi
grep -h "^ROW" "$T"/out*.txt | sort -t$'\t' -k2,2n | cut -f3- > "$T/rows.csv"
cat "$T/rows.csv" >> "$OUT"
grep -h "^WALL" "$T"/out*.txt | cut -f3 | awk '{s+=$1;n++} END{if(n)printf "%d runs, %.1f s mean wall per run\n", n, s/n}'
rm -rf "$T"
