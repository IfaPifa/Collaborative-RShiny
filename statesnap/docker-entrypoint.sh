#!/usr/bin/env bash
# Dispatch between running the test suite (default) and serving example apps.
#
#   (no args) | test  -> run the full testthat suite, exit with its status
#   app               -> serve the client/server Monte Carlo app on :8100
#   handoff           -> serve BOTH the producer (:8100) and consumer (:8200)
#                        apps that share a checkpoint file, for the file
#                        hand-off demo / video
#   <anything else>   -> passed through to Rscript -e as a raw expression
set -euo pipefail

cmd="${1:-test}"

case "$cmd" in
  test)
    exec Rscript -e "pkgload::load_all('.'); testthat::test_dir('tests/testthat', stop_on_failure = TRUE)"
    ;;
  app)
    # 0.0.0.0 so the published port is reachable from the host.
    exec Rscript -e "pkgload::load_all('.'); shiny::runApp('inst/examples/montecarlo-clientserver', host = '0.0.0.0', port = 8100)"
    ;;
  handoff)
    # Producer and consumer share one checkpoint file. Put it on a writable,
    # optionally host-mounted path so the file is visible/persistent.
    export STATESNAP_CHECKPOINT="${STATESNAP_CHECKPOINT:-/pkg/checkpoints/mc-handoff.json}"
    mkdir -p "$(dirname "$STATESNAP_CHECKPOINT")"
    echo "Hand-off checkpoint file: $STATESNAP_CHECKPOINT"
    echo "Producer: http://127.0.0.1:8100   Consumer: http://127.0.0.1:8200"

    Rscript -e "shiny::runApp('inst/examples/montecarlo-file-handoff/producer', host = '0.0.0.0', port = 8100)" &
    producer_pid=$!
    Rscript -e "shiny::runApp('inst/examples/montecarlo-file-handoff/consumer', host = '0.0.0.0', port = 8200)" &
    consumer_pid=$!

    # If either app exits, stop the other and surface the failure.
    trap 'kill "$producer_pid" "$consumer_pid" 2>/dev/null || true' EXIT
    wait -n "$producer_pid" "$consumer_pid"
    ;;
  *)
    exec Rscript -e "$cmd"
    ;;
esac
