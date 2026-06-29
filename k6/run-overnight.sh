#!/usr/bin/env bash
# ==========================================================================
#  run-overnight.sh — Full unattended REST + Kafka benchmark (5 runs each)
#
#  Deploys each architecture, runs the full 10-test suite 5x, extracts CSVs,
#  and commits results. Designed to run in tmux and be checked in the morning.
#
#  Does NOT use 'set -e' for the whole flow: a failure in one architecture
#  should NOT prevent the other from running. Each phase is guarded and logged,
#  and a final summary reports what succeeded.
#
#  Usage (from repo root, inside tmux):
#     ./k6/run-overnight.sh
#
#  Override runs:  RUNS=3 ./k6/run-overnight.sh
#
#  REST poll sweep is ON by default: the state-relay test runs once per
#  interval (100/250/500/1000 ms) for REST so you get the latency/load curve.
#  Kafka is unaffected (push, no polling). Disable with POLL_SWEEP=0.
# ==========================================================================
set -uo pipefail

RUNS="${RUNS:-5}"
# Fold the REST poll-interval sweep into the run by default. run-suite.sh's
# sweep_applies guard restricts it to rest* archs, so exporting it globally is
# safe — Kafka ignores it.
export POLL_SWEEP="${POLL_SWEEP:-1}"
REST_URL="http://localhost:30001"
KAFKA_URL="http://localhost:30002"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="overnight-${TS}.log"

REST_OK=0
KAFKA_OK=0

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

run_arch() {
  local arch="$1" deploy="$2" url="$3"
  log "===== ${arch^^}: teardown ====="
  bash k8s/teardown.sh >>"$LOG" 2>&1 || { log "${arch}: teardown failed"; return 1; }

  log "===== ${arch^^}: deploy ====="
  bash "k8s/${deploy}" >>"$LOG" 2>&1 || { log "${arch}: deploy failed"; return 1; }

  log "===== ${arch^^}: wait for all pods ready ====="
  kubectl wait --for=condition=ready pod --all --timeout=420s >>"$LOG" 2>&1 \
    || { log "${arch}: pods did not become ready"; kubectl get pods >>"$LOG" 2>&1; return 1; }
  sleep 30   # let the backend settle before load

  log "===== ${arch^^}: run suite (${RUNS} runs) ====="
  ./k6/run-suite.sh "$arch" "$RUNS" "$url" >>"$LOG" 2>&1 \
    || log "${arch}: suite exited non-zero (threshold failures are expected; verifying output below)"

  # Verify the suite actually produced summary files. A threshold failure is
  # fine, but ZERO summaries means the suite died early (e.g. k6 missing,
  # deploy not ready) and the run is invalid — do not report success.
  local n_summaries
  n_summaries=$(find "k6/results/${arch}" -name '*-summary.json' 2>/dev/null | wc -l)
  if [[ "$n_summaries" -eq 0 ]]; then
    log "${arch}: NO results produced — suite failed to run. See ${LOG}."
    return 1
  fi
  log "${arch}: produced ${n_summaries} summary file(s)"

  log "===== ${arch^^}: extract CSVs ====="
  ./k6/extract-results.sh "$arch" >>"$LOG" 2>&1 || { log "${arch}: extract failed"; return 1; }

  log "===== ${arch^^}: DONE ====="
  return 0
}

log "############################################"
log "# Overnight benchmark started"
log "# RUNS=${RUNS}  log=${LOG}"
log "############################################"

git pull origin main >>"$LOG" 2>&1 || log "warning: git pull failed (continuing with local code)"

if run_arch "rest" "deploy-rest.sh" "$REST_URL"; then REST_OK=1; fi
if run_arch "kafka" "deploy-kafka.sh" "$KAFKA_URL"; then KAFKA_OK=1; fi

log "===== Committing results ====="
git add k6/results/ >>"$LOG" 2>&1
if git commit -m "Benchmark results: REST(ok=${REST_OK}) Kafka(ok=${KAFKA_OK}), ${RUNS} runs each

Co-authored-by: Ona <no-reply@ona.com>" >>"$LOG" 2>&1; then
  git push origin main >>"$LOG" 2>&1 && log "results pushed to main" || log "warning: git push failed — results are committed locally"
else
  log "nothing to commit (no new results?)"
fi

log "############################################"
log "# SUMMARY"
log "#   REST  : $([ $REST_OK -eq 1 ] && echo PASS || echo FAILED)"
log "#   Kafka : $([ $KAFKA_OK -eq 1 ] && echo PASS || echo FAILED)"
log "#   Full log: ${LOG}"
log "############################################"
