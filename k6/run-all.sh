#!/bin/bash
# Run all 8 k6 benchmarks against a deployed architecture.
#
# Usage:
#   ./k6/run-all.sh http://server-ip:30001 kafka
#   ./k6/run-all.sh http://server-ip:30001 rest
#
# Arguments:
#   $1 = base URL of the Angular frontend
#   $2 = architecture name — used for output directory naming
#
# Output per test:
#   k6/results/<arch>/<test>.json          — raw k6 time-series data
#   k6/results/<arch>/<test>-summary.json  — aggregated metrics (p50/p95/p99)
#   k6/results/<arch>/<test>.log           — console output with check results
#
# Note: The monolithic architecture has no Spring Boot API, so these
# tests are not applicable to it. Use Playwright tests instead.
set -euo pipefail

BASE_URL="${1:?Usage: $0 <base-url> <arch-name>}"
ARCH="${2:?Usage: $0 <base-url> <arch-name>}"
OUT="k6/results/${ARCH}"
mkdir -p "$OUT"

TESTS=(
  "01-state-relay-latency"
  "02-collaboration-latency"
  "03-save-restore-latency"
  "04-throughput"
  "05-data-loss"
  "06-cross-contamination"
  "07-session-lifecycle"
  "08-multi-user-collab"
  "09-websocket-presence"
)

TOTAL=${#TESTS[@]}
PASSED=0
FAILED=0

echo "================================================================"
echo "  k6 Benchmark Suite — ${ARCH} architecture"
echo "  Target: ${BASE_URL}"
echo "  Tests:  ${TOTAL}"
echo "================================================================"
echo ""

for i in "${!TESTS[@]}"; do
  TEST="${TESTS[$i]}"
  NUM=$((i + 1))
  echo "--- ${NUM}/${TOTAL}: ${TEST} ---"

  if k6 run \
    -e BASE_URL="$BASE_URL" \
    "k6/${TEST}.js" \
    --out "json=${OUT}/${TEST}.json" \
    --summary-export="${OUT}/${TEST}-summary.json" \
    2>&1 | tee "${OUT}/${TEST}.log"; then
    PASSED=$((PASSED + 1))
    echo "  -> PASSED"
  else
    FAILED=$((FAILED + 1))
    echo "  -> FAILED (see ${OUT}/${TEST}.log)"
  fi
  echo ""
done

echo "================================================================"
echo "  Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "  Output:  ${OUT}/"
echo "================================================================"
echo ""
echo "Files per test:"
echo "  *.json         — raw k6 time-series data (for custom plots)"
echo "  *-summary.json — aggregated metrics (p50, p95, p99, etc.)"
echo "  *.log          — console output with check results"
