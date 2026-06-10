#!/bin/bash
# Monitor K8s pod resource usage during benchmark runs.
#
# Usage:
#   ./k6/monitor-resources.sh kafka &    # start in background
#   ./k6/run-all.sh http://... kafka     # run benchmarks
#   kill %1                              # stop monitoring
#
# Output:
#   k6/results/<arch>/resources.csv — timestamped CPU/memory per pod
#
# Requires: kubectl top pods (metrics-server must be installed)
set -euo pipefail

ARCH="${1:?Usage: $0 <arch-name> [interval-seconds]}"
INTERVAL="${2:-5}"
OUT="k6/results/${ARCH}"
mkdir -p "$OUT"
FILE="${OUT}/resources.csv"

echo "timestamp,pod,cpu_millicores,memory_mib" > "$FILE"
echo "Monitoring resources every ${INTERVAL}s → ${FILE}"
echo "Press Ctrl+C to stop."

while true; do
  TS=$(date +%s)
  kubectl top pods --no-headers 2>/dev/null | while read -r POD CPU MEM; do
    # Strip units: "250m" → 250, "128Mi" → 128
    CPU_VAL=$(echo "$CPU" | sed 's/m$//')
    MEM_VAL=$(echo "$MEM" | sed 's/Mi$//')
    echo "${TS},${POD},${CPU_VAL},${MEM_VAL}" >> "$FILE"
  done
  sleep "$INTERVAL"
done
