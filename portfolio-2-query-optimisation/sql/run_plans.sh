#!/usr/bin/env bash
# Usage: PGDATABASE=konga_p2 bash sql/run_plans.sh before|after
# One warm-up, then three measurements. Plans and results use the same snapshot.
set -euo pipefail
LABEL=${1:?label required (before|after)}
case "$LABEL" in before|after) ;; *) echo 'Label must be before or after' >&2; exit 1 ;; esac
cd "$(dirname "$0")"
export PGDATABASE=${PGDATABASE:-konga_p2}
export PGHOST=${PGHOST:-/tmp}
OUT=${PLAN_OUT_DIR:-../evidence/$LABEL}
mkdir -p "$OUT"
# Preserve support for the original PSQL="psql -d database ..." override.
read -r -a PSQL_CMD <<< "${PSQL:-psql}"
SUMMARY=$OUT/summary.tsv
: > "$SUMMARY"
for f in queries/q*.sql; do
  q=$(basename "$f" .sql)
  output=$(mktemp)
  trap 'rm -f "$output"' EXIT
  {
    printf '%s\n' 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'
    for run in 0 1 2 3; do
      printf '%s\n' 'EXPLAIN (ANALYZE, BUFFERS, TIMING ON)'
      cat "$f"
    done
    printf '\\echo RESULT_START\n'
    cat "$f"
    printf '%s\n' 'ROLLBACK;'
  } | "${PSQL_CMD[@]}" -X -q -A -t -v ON_ERROR_STOP=1 > "$output"
  # awk is available on macOS; GNU grep -P is not required.
  median=$(awk '/^Execution Time:/ {n++; if (n>1) print $3}' "$output" | sort -n | sed -n '2p')
  [ -n "$median" ] || { echo "No execution time for $q" >&2; exit 1; }
  # Select the fourth plan without retaining the preceding three plans.
  awk '/^RESULT_START$/ {exit} {lines[NR]=$0} /^Execution Time:/ {ends[++n]=NR}
       END {for(i=ends[3]+1;i<=ends[4];i++) print lines[i]}' "$output" > "$OUT/$q.plan.txt"
  awk '/^RESULT_START$/ {capture=1; next} capture && n++<15 {print}' "$output" > "$OUT/$q.result.txt"
  printf '%s\t%s\n' "$q" "$median" >> "$SUMMARY"
  printf '%s  median %s ms\n' "$q" "$median"
  rm -f "$output"
  trap - EXIT
done
