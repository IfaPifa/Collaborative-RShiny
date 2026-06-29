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
#  REST poll-interval sweep (baked into the big run):
#    REST has no server push, so test 01's relay latency partly reflects how
#    often the client polls. Set POLL_SWEEP=1 to run the state-relay test once
#    per interval as part of the suite (REST architectures only; skipped for
#    kafka/monolithic). Every other test still runs once.
#      POLL_SWEEP=1 ./k6/run-suite.sh rest 5 http://localhost:30001
#    Override the intervals with POLL_SWEEP_MS (default "100 250 500 1000").
#    Each interval's output is suffixed (01-state-relay-latency-poll500-*)
#    and metrics carry a poll_ms tag.
#
#    To run just the sweep without the rest of the suite:
#      POLL_SWEEP=1 TESTS="01-state-relay-latency" \
#        ./k6/run-suite.sh rest 5 http://localhost:30001
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

# Default = full suite. Override with a space-separated TESTS env var to run a
# subset, e.g. for a quick smoke test:
#   TESTS="01-state-relay-latency 04-throughput" ./k6/run-suite.sh rest 1 http://localhost:30001
if [[ -n "${TESTS:-}" ]]; then
  read -r -a TESTS <<< "${TESTS}"
else
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
fi

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

# --- State reset between tests -------------------------------------------
# Flush Redis / PostgreSQL / Kafka backlog between tests so each test (and
# therefore each run) starts from a clean, comparable state. Without this the
# throughput test's leftover backlog makes successive runs progressively
# slower and the 5 runs cannot be averaged. Set RESET_BETWEEN=0 to disable.
RESET_BETWEEN="${RESET_BETWEEN:-1}"
RESET_METHOD="${RESET_METHOD:-flush}"   # flush (fast) | restart (thorough)
RESET_SCRIPT="${SCRIPT_DIR}/reset-state.sh"

# --- REST poll-interval sweep --------------------------------------------
# REST has no server push, so test 01's relay latency partly reflects how
# often the client polls. With POLL_SWEEP=1, the state-relay test runs once
# per interval in POLL_SWEEP_MS (every other test runs once at the default).
# Each interval's output is suffixed (e.g. 01-state-relay-latency-poll500)
# and metrics carry a poll_ms tag. Sweep applies to REST-like architectures
# only; it is skipped for kafka (push, no polling tax) and monolithic.
POLL_SWEEP="${POLL_SWEEP:-0}"
POLL_SWEEP_MS="${POLL_SWEEP_MS:-100 250 500 1000}"
RELAY_TEST="01-state-relay-latency"

# Architectures the sweep is meaningful for (substring match on ARCH so
# "rest", "rest-remote", "rest-local" all qualify).
sweep_applies() {
  [[ "${POLL_SWEEP}" == "1" && "${ARCH}" == rest* ]]
}

# --- Main loop ---
run_suite() {
  echo "=============================================="
  echo "  Architecture : ${ARCH}"
  echo "  Base URL     : ${BASE_URL}"
  echo "  Runs         : ${RUNS}"
  echo "  Results dir  : ${RESULTS_DIR}"
  echo "  Cooldown     : ${COOLDOWN}s between tests"
  echo "  State reset  : $( [[ "${RESET_BETWEEN}" == "1" ]] && echo "enabled (after every test, method=${RESET_METHOD})" || echo "DISABLED" )"
  echo "  Poll sweep   : $( sweep_applies && echo "ON — ${RELAY_TEST} over [${POLL_SWEEP_MS}] ms" || echo "off" )"
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

    # Build this run's job list. Each job is "test_file|label|poll_ms".
    # label names the output files; poll_ms (may be empty) is passed to k6.
    # With the sweep on (REST only), the relay test expands into one job per
    # interval; everything else is a single job with no poll_ms override.
    JOBS=()
    for test in "${TESTS[@]}"; do
      if [[ "${test}" == "${RELAY_TEST}" ]] && sweep_applies; then
        for ms in ${POLL_SWEEP_MS}; do
          JOBS+=("${test}|${test}-poll${ms}|${ms}")
        done
      else
        JOBS+=("${test}|${test}|")
      fi
    done

    for job in "${JOBS[@]}"; do
      IFS='|' read -r test label job_poll <<< "${job}"
      TEST_FILE="${SCRIPT_DIR}/${test}.js"
      SUMMARY_FILE="${RUN_DIR}/${label}-summary.json"
      RAW_FILE="${RUN_DIR}/${label}.json"
      LOG_FILE="${RUN_DIR}/${label}.log"

      if [[ ! -f "${TEST_FILE}" ]]; then
        echo "  [SKIP] ${test}.js not found"
        continue
      fi

      # Per-job poll interval: the sweep value if set, else any inherited
      # POLL_MS, else unset (test uses its own default).
      EFF_POLL="${job_poll:-${POLL_MS:-}}"

      echo -n "  [${run}/${RUNS}] ${label} ... "

      # Run k6, capture:
      #   --summary-export : aggregated metrics (avg/med/p90/p95), tags flattened
      #   --out json=      : raw time-series WITH tags (app_name) for per-app plots
      #   LOG_FILE         : full console output with per-app check results
      k6 run \
        -e "BASE_URL=${BASE_URL}" \
        ${EFF_POLL:+-e "POLL_MS=${EFF_POLL}"} \
        --summary-export="${SUMMARY_FILE}" \
        --out "json=${RAW_FILE}" \
        "${TEST_FILE}" \
        > "${LOG_FILE}" 2>&1 \
        && echo "DONE" \
        || echo "DONE (with errors — check ${LOG_FILE})"

      # Compress the raw time-series (can be large for throughput tests)
      if [[ -f "${RAW_FILE}" ]]; then
        gzip -f "${RAW_FILE}"
      fi

      # Reset runtime state so the NEXT job starts clean. Runs after every
      # job (including throughput, the main contaminator). This also covers
      # the gap between runs since it runs after the last job of each run.
      if [[ "${RESET_BETWEEN}" == "1" && -x "${RESET_SCRIPT}" ]]; then
        RESET_METHOD="${RESET_METHOD}" "${RESET_SCRIPT}" "${ARCH}" \
          || echo "    [reset] non-fatal error — continuing."
      fi

      # Cooldown between jobs to let the system stabilize
      if [[ "${job}" != "${JOBS[-1]}" ]]; then
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

# Verify k6 exists before doing anything else (clear error instead of a
# cryptic instant failure under set -e).
if ! command -v k6 &>/dev/null; then
  echo "[FATAL] k6 not found in PATH. Install k6 before running the suite." >&2
  exit 127
fi

# systemd-inhibit needs a D-Bus / login session, which is often absent over
# SSH. If it can't actually run, it would fail instantly and (under set -e)
# abort the whole suite in 0 seconds. Probe it first and fall back to direct
# execution rather than killing the run.
if [[ -n "${INHIBIT_CMD}" ]]; then
  if ! ${INHIBIT_CMD} true &>/dev/null; then
    echo "[WARN] '${INHIBIT_CMD%% *}' is present but not usable here (no session/D-Bus?)."
    echo "       Falling back to direct execution. On a server this is fine —"
    echo "       use tmux so the run survives disconnects."
    INHIBIT_CMD=""
  fi
fi

if [[ -n "${INHIBIT_CMD}" ]]; then
  echo "[INFO] Sleep prevention active: ${INHIBIT_CMD}"
  ${INHIBIT_CMD} bash -c "$(declare -f run_suite); $(declare -f sweep_applies); ARCH='${ARCH}' RUNS='${RUNS}' BASE_URL='${BASE_URL}' SCRIPT_DIR='${SCRIPT_DIR}' RESULTS_DIR='${RESULTS_DIR}' COOLDOWN='${COOLDOWN}' RESET_BETWEEN='${RESET_BETWEEN}' RESET_METHOD='${RESET_METHOD}' RESET_SCRIPT='${RESET_SCRIPT}' POLL_MS='${POLL_MS:-}' POLL_SWEEP='${POLL_SWEEP}' POLL_SWEEP_MS='${POLL_SWEEP_MS}' RELAY_TEST='${RELAY_TEST}' TESTS=(${TESTS[*]}); run_suite"
else
  run_suite
fi
