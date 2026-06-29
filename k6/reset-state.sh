#!/usr/bin/env bash
# ==========================================================================
#  reset-state.sh — Light, data-only flush between benchmark tests/runs
#
#  Why: the throughput test (and to a lesser degree save/restore) leaves
#  state behind — a Kafka backlog, Redis keys, and PostgreSQL rows. Without
#  clearing it, each successive run starts more clogged than the last, so the
#  5 runs are not independent and cannot be averaged. This script returns the
#  system to a clean, comparable starting point WITHOUT a full teardown.
#
#  What it does NOT do: it does not delete/redeploy anything (use
#  k8s/teardown.sh for switching architectures). It only flushes runtime data.
#
#  Preserves seed/config data: app_user and shiny_apps are seeded once at
#  backend startup (DataInitializer, "if empty" guards). A data-only flush
#  does not restart the backend, so those tables MUST be kept or the system
#  breaks. Only benchmark-generated tables are truncated.
#
#  Two methods (set RESET_METHOD):
#    flush   (default) — fast in-place data wipe. Postgres TRUNCATE plus the
#                        arch's live store: Redis FLUSHALL (REST) or Kafka
#                        delete-records (Kafka). ~seconds. R workers keep
#                        their in-memory state.
#
#  Note: REST uses Redis (no Kafka); Kafka uses Kafka topics (no Redis). The
#  script touches only the store that exists for the given architecture.
#    restart           — thorough: rollout-restart Redis, Kafka and the shiny
#                        workers (all have NO persistent volume, so they come
#                        back empty), then TRUNCATE Postgres (it DOES have a
#                        PVC, so a restart alone would not clear it). Slower
#                        (waits for pods Ready) but gives every test a fully
#                        fresh process state. Time is not a constraint, so this
#                        is the most rigorous choice.
#
#  Usage:
#    ./k6/reset-state.sh <architecture>
#      <architecture> = rest | kafka | monolithic (anything containing
#                       "kafka" enables the Kafka steps)
#    RESET_METHOD=restart ./k6/reset-state.sh kafka
#
#  Requirements: kubectl with access to the cluster (default namespace).
#  Safe to skip: if kubectl is unreachable it warns and returns 0 so a
#  benchmark started from a machine without cluster access is not aborted.
# ==========================================================================
set -uo pipefail

ARCH="${1:-}"
RESET_METHOD="${RESET_METHOD:-flush}"

# shiny worker deployments (3 replicas each) — restarted in 'restart' method
SHINY_DEPLOYS=(
  shiny-front shiny-front-analytics shiny-front-analytics-advanced
  shiny-front-csv shiny-front-csv-advanced shiny-front-mc shiny-front-map
  shiny-front-ml shiny-back shiny-back-analytics shiny-back-analytics-advanced
  shiny-back-csv shiny-back-csv-advanced shiny-back-mc shiny-back-map
  shiny-back-ml
)

# --- Cluster reachability check (non-fatal) ------------------------------
if ! command -v kubectl &>/dev/null; then
  echo "    [reset] kubectl not found — SKIPPING state reset (data may carry over)." >&2
  exit 0
fi
if ! kubectl get pods &>/dev/null; then
  echo "    [reset] cluster not reachable — SKIPPING state reset (data may carry over)." >&2
  exit 0
fi

# Run a command in the first pod of a deployment; warn (don't fail) on error.
exec_in() {
  local deploy="$1"; shift
  local pod
  pod="$(kubectl get pod -l app="${deploy}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  if [[ -z "${pod}" ]]; then
    # Fall back to deployment-name selector if the app= label differs.
    pod="$(kubectl get pod -o name 2>/dev/null | grep -m1 "${deploy}" | cut -d/ -f2)"
  fi
  if [[ -z "${pod}" ]]; then
    echo "    [reset] pod for '${deploy}' not found — skipping that step." >&2
    return 0
  fi
  kubectl exec "${pod}" -- "$@" 2>/dev/null \
    || echo "    [reset] command in '${deploy}' returned non-zero — continuing." >&2
}

# Truncate only benchmark-generated tables. KEEP app_user + shiny_apps:
# they are seeded once at backend startup (DataInitializer "if empty"), so a
# data-only flush must not remove them or the system breaks.
truncate_pg() {
  exec_in db psql -U user -d shinyswarm -c \
    "TRUNCATE saved_states, collaboration_sessions, session_participants, notifications RESTART IDENTITY CASCADE;" \
    >/dev/null
  echo "    [reset]   postgres: benchmark tables truncated (seed data kept)"
}

# Clear the Kafka input/output backlog by deleting records up to the current
# end offset. Topics remain; Spring auto-recreates them if missing.
flush_kafka_records() {
  # Enumerate every input topic (per-app: input.calculator, input.montecarlo,
  # ... plus the legacy "input" fallback) and the shared output topic. The
  # per-app topic split means a static "input output" list would leave each
  # app's backlog uncleared and contaminate successive throughput runs.
  local topics
  topics=$(exec_in kafka bash -c \
    "kafka-topics.sh --bootstrap-server localhost:9092 --list \
      | grep -E '^(input|output)'" 2>/dev/null | tr -d '\r')

  if [[ -z "${topics}" ]]; then
    echo "    [reset]   kafka: no input/output topics found (skipping)"
    return
  fi

  for topic in ${topics}; do
    exec_in kafka bash -c \
      "kafka-delete-records.sh --bootstrap-server localhost:9092 \
        --offset-json-file <(kafka-run-class.sh kafka.tools.GetOffsetShell \
          --broker-list localhost:9092 --topic ${topic} \
        | awk -F: '{printf \"{\\\"partitions\\\":[{\\\"topic\\\":\\\"${topic}\\\",\\\"partition\\\":%s,\\\"offset\\\":%s}],\\\"version\\\":1}\", \$2, \$3}')" \
      >/dev/null 2>&1 \
      || echo "    [reset]   kafka: warning — could not flush ${topic}"
  done
  echo "    [reset]   kafka: backlog cleared for topics: $(echo ${topics} | tr '\n' ' ')"
}

echo "    [reset] resetting runtime state (arch=${ARCH:-unknown}, method=${RESET_METHOD}) ..."

# Architecture-specific stores:
#   REST  uses Redis for live state (no Kafka).
#   Kafka uses Kafka topics for live state (no Redis).
# Both use PostgreSQL for checkpoints.
IS_KAFKA=false
[[ "${ARCH}" == *kafka* ]] && IS_KAFKA=true

if [[ "${RESET_METHOD}" == "restart" ]]; then
  # ---- Thorough method: rollout-restart ephemeral pods, truncate Postgres --
  # Redis / Kafka and the shiny workers have NO volumes, so a restart brings
  # them back empty (clean store, fresh R processes).
  if [[ "${IS_KAFKA}" == true ]]; then
    echo "    [reset]   rollout restart: kafka"
    kubectl rollout restart deploy/kafka >/dev/null 2>&1 || \
      echo "    [reset]   (kafka restart failed — continuing)" >&2
  else
    echo "    [reset]   rollout restart: redis"
    kubectl rollout restart deploy/redis >/dev/null 2>&1 || \
      echo "    [reset]   (redis restart failed — continuing)" >&2
  fi

  echo "    [reset]   rollout restart: shiny workers (${#SHINY_DEPLOYS[@]} deployments)"
  for d in "${SHINY_DEPLOYS[@]}"; do
    kubectl rollout restart "deploy/${d}" >/dev/null 2>&1 || true
  done

  # Wait for everything to come back Ready before proceeding.
  echo "    [reset]   waiting for pods to become Ready ..."
  if [[ "${IS_KAFKA}" == true ]]; then
    kubectl rollout status deploy/kafka --timeout=180s >/dev/null 2>&1 || true
  else
    kubectl rollout status deploy/redis --timeout=180s >/dev/null 2>&1 || true
  fi
  for d in "${SHINY_DEPLOYS[@]}"; do
    kubectl rollout status "deploy/${d}" --timeout=180s >/dev/null 2>&1 || true
  done

  # Postgres has a PVC, so a restart would NOT clear it — truncate explicitly.
  truncate_pg

  # Extra settle time for fresh backends to register / reconnect.
  sleep 10

else
  # ---- Fast method: in-place data flush -----------------------------------
  if [[ "${IS_KAFKA}" == true ]]; then
    flush_kafka_records
  else
    exec_in redis redis-cli FLUSHALL >/dev/null
    echo "    [reset]   redis: FLUSHALL done"
  fi
  truncate_pg
  sleep 3
fi

echo "    [reset] done."
