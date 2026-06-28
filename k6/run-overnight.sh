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
# ==========================================================================
set -uo pipefail

RUNS="${RUNS:-5}"
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
    || log "${arch}: suite reported errors (thresholds may have failed — this is expected; continuing)"

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
