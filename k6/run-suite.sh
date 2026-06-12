#!/usr/bin/env bash
# ==========================================================================
#  run-suite.sh — Run the full k6 benchmark suite N times
#
#  Usage:
#    ./k6/run-suite.sh <architecture> [runs] [base_url]
#
#  Examples:
#    ./k6/run-suite.sh rest 5 http://localhost:30001        # REST on server
#    ./k6/run-suite.sh kafka 5 http://localhost:30002       # Kafka on server
#    ./k6/run-suite.sh rest-local 5 http://188.245.60.172:30001  # REST from laptop
#    ./k6/run-suite.sh monolithic 5 http://localhost:30003  # Monolithic baseline
#
#  Results saved to: k6/results/<architecture>/run-<N>/<test>-summary.json
#
#  Laptop sleep prevention:
#    macOS:  caffeinate -dims is used automatically
#    Linux:  systemd-inhibit is used automatically
#    If neither works, disable sleep manually in system settings.
# ==========================================================================
set -euo pipefail

ARCH="${1:?Usage: $0 <architecture> [runs] [base_url]}"
RUNS="${2:-5}"
BASE_URL="${3:-http://localhost:30001}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results/${ARCH}"

TESTS=(
  "00-baseline"
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

# --- Sleep prevention wrapper ---
INHIBIT_CMD=""
if command -v caffeinate &>/dev/null; then
  # macOS: prevent display sleep, idle sleep, disk sleep, system sleep
  INHIBIT_CMD="caffeinate -dims"
elif command -v systemd-inhibit &>/dev/null; then
  # Linux: prevent idle/sleep/shutdown
  INHIBIT_CMD="systemd-inhibit --what=idle:sleep --who=k6-suite --why='Running benchmarks' --mode=block"
fi

# --- Cooldown between tests (seconds) ---
COOLDOWN=30

# --- Main loop ---
run_suite() {
  echo "=============================================="
  echo "  Architecture : ${ARCH}"
  echo "  Base URL     : ${BASE_URL}"
  echo "  Runs         : ${RUNS}"
  echo "  Results dir  : ${RESULTS_DIR}"
  echo "  Cooldown     : ${COOLDOWN}s between tests"
  echo "  Sleep inhibit: ${INHIBIT_CMD:-none (disable sleep manually!)}"
  echo "=============================================="
  echo ""

  for run in $(seq 1 "${RUNS}"); do
    RUN_DIR="${RESULTS_DIR}/run-${run}"
    mkdir -p "${RUN_DIR}"

    echo ""
    echo "====== RUN ${run}/${RUNS} ======"
    echo "  Output: ${RUN_DIR}"
    echo ""

    for test in "${TESTS[@]}"; do
      TEST_FILE="${SCRIPT_DIR}/${test}.js"
      SUMMARY_FILE="${RUN_DIR}/${test}-summary.json"
      LOG_FILE="${RUN_DIR}/${test}.log"

      if [[ ! -f "${TEST_FILE}" ]]; then
        echo "  [SKIP] ${test}.js not found"
        continue
      fi

      echo -n "  [${run}/${RUNS}] ${test} ... "

      # Run k6, capture both summary JSON and full log
      k6 run \
        -e "BASE_URL=${BASE_URL}" \
        --summary-export="${SUMMARY_FILE}" \
        "${TEST_FILE}" \
        > "${LOG_FILE}" 2>&1 \
        && echo "DONE" \
        || echo "DONE (with errors — check ${LOG_FILE})"

      # Cooldown between tests to let the system stabilize
      if [[ "${test}" != "${TESTS[-1]}" ]]; then
        echo "         cooling down ${COOLDOWN}s ..."
        sleep "${COOLDOWN}"
      fi
    done

    # Cooldown between runs
    if [[ "${run}" -lt "${RUNS}" ]]; then
      echo ""
      echo "  --- Cooldown between runs: 60s ---"
      sleep 60
    fi
  done

  echo ""
  echo "=============================================="
  echo "  ALL ${RUNS} RUNS COMPLETE"
  echo "  Results in: ${RESULTS_DIR}/run-{1..${RUNS}}/"
  echo "=============================================="
}

# Run with sleep prevention if available
if [[ -n "${INHIBIT_CMD}" ]]; then
  echo "[INFO] Sleep prevention active: ${INHIBIT_CMD}"
  ${INHIBIT_CMD} bash -c "$(declare -f run_suite); ARCH='${ARCH}' RUNS='${RUNS}' BASE_URL='${BASE_URL}' SCRIPT_DIR='${SCRIPT_DIR}' RESULTS_DIR='${RESULTS_DIR}' COOLDOWN='${COOLDOWN}' TESTS=(${TESTS[*]}); run_suite"
else
  echo "[WARN] No sleep prevention found. Disable sleep manually!"
  echo "  macOS: System Settings → Energy → Prevent sleep"
  echo "  Linux: systemctl mask sleep.target suspend.target"
  echo ""
  run_suite
fi
