#!/usr/bin/env bash
# Dispatch between running the test suite (default) and serving the example app.
#
#   (no args) | test   -> run the full testthat suite, exit with its status
#   app                 -> serve the Monte Carlo client/server app on :8100
#   <anything else>     -> passed through to Rscript -e as a raw expression
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
  *)
    exec Rscript -e "$cmd"
    ;;
esac
