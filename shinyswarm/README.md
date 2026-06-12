# shinyswarm

Full-state capture and restore for Shiny applications.

`shinyswarm` serialises the complete state of a Shiny session — both inputs and
computed reactive values — into a single JSON string, and restores it later.
Unlike input-only sharing (`shinyURL`, bookmarking), which forces the receiving
session to recompute outputs, full-state capture preserves the outputs exactly.
For non-deterministic analyses (e.g. a Monte Carlo simulation without
`set.seed()`), this is the difference between reproducing a result and getting a
different one.

The library is **transport-agnostic**: it produces and consumes JSON only. How
that JSON is transmitted or persisted — REST, Kafka, Redis, a file, a database —
is the caller's concern.

This package is the standalone, reusable distillation of the checkpoint
mechanism built for the ShinySwarm thesis. It works with any Shiny app and needs
no microservice infrastructure.

## Installation

```r
# from a local source checkout
install.packages("shinyswarm", repos = NULL, type = "source")

# or, during development
# remotes::install_github("<user>/shinyswarm")
```

Dependencies: `jsonlite`, `base64enc`. `shiny` is suggested (required only to
capture/restore live `reactiveValues`).

## The two functions

```r
capture_state(input, ..., max_size = NULL, compress = TRUE)
restore_state(session, state_json, ..., file_dir = tempdir(),
              allow_rds = FALSE, max_size = NULL)
```

Reactive values cannot be discovered automatically in R, so you register the
ones you want to capture by name through `...`.

## Quick start

```r
library(shiny)
library(shinyswarm)

server <- function(input, output, session) {
  result <- reactiveVal(0)

  observeEvent(input$calculate, {
    result(input$num1 + input$num2)
  })

  output$result <- renderText(result())

  # Save: one line. Transport is yours to choose.
  observeEvent(input$save_btn, {
    json <- capture_state(input, result = result)
    writeLines(json, "checkpoint.json")   # or POST it, or produce to Kafka...
  })

  # Restore: one line.
  observeEvent(input$restore_btn, {
    json <- paste(readLines("checkpoint.json"), collapse = "\n")
    restore_state(session, json, result = result)
  })
}
```

## Typed wrappers

Some state is not plain JSON. Wrap it so `capture_state()` knows how to handle
it; the output is still a single JSON string.

```r
json <- capture_state(
  input,
  result    = result,                       # reactiveVal: value is read
  shared_df = shared_df,                     # reactiveVal holding a data frame
  csv_file  = state_file("data/summary.csv"),  # file: read + gzip + base64
  model     = state_rds(trained_model)         # R object: serialize + gzip + base64
)
```

On restore, pass the live reactives back by the same names:

```r
restore_state(session, json,
              result = result, shared_df = shared_df,
              csv_file = csv_path, model = model_rv,
              allow_rds = TRUE)   # required to unserialize objects (see Security)
```

## Transport is your choice

```r
json <- capture_state(input, result = result)

httr::POST("http://backend/state", body = json)            # REST
producer$produce("output", json, key = session_id)          # Kafka
writeLines(json, "checkpoint.json")                         # file
DBI::dbExecute(con, "INSERT INTO states(data) VALUES(?)", list(json))  # database
```

## Security

A checkpoint is **untrusted input** — in a cross-user restore, it was authored
by someone else. `restore_state()` defends against three attacks:

| Attack | Defence |
|---|---|
| Path traversal via crafted filename | Filenames reduced to a safe basename; separators, drive letters and `..` rejected |
| Arbitrary code execution via `unserialize()` | `state_rds` restore disabled unless `allow_rds = TRUE` (trusted checkpoints only) |
| Memory exhaustion / decompression bomb | `max_size` ceiling enforced **during** streaming decompression (default 50 MB) |

Only set `allow_rds = TRUE` for checkpoints you trust.

## Known limitations

These are inherent to Shiny's design and are documented as further work:

- **`fileInput` widgets** cannot be restored via `sendInputMessage()`. Use
  `state_file()` to embed the uploaded file's contents in the checkpoint instead.
- **Shiny modules** use namespaced input IDs (`module1-slider`). Restoring across
  module session boundaries is not yet supported; capture/restore within a module
  works if called from inside that module's server.
- **Reactives must be registered explicitly** — R exposes no API to discover all
  `reactiveVal`/`reactiveValues` in a session, so you pass them by name.
- **`reactiveValues` keys cannot be deleted** in Shiny; on restore, stale keys are
  cleared to `NULL` rather than removed, so their values do not leak.

## Examples

- `inst/examples/calculator/app.R` — a runnable Shiny app with Save/Restore
  buttons.
- `inst/examples/demo-roundtrip.R` — a headless script (no server/browser) that
  demonstrates round-trips, non-deterministic reproducibility, file embedding,
  and the path-traversal defence.

```sh
Rscript inst/examples/demo-roundtrip.R          # if installed
# or run from the package root on a source checkout
```

## Testing

```r
# from the package root
testthat::test_local()
```

The suite (`tests/testthat/`) covers serialisation round-trips, non-deterministic
reproducibility, the typed wrappers, the security defences (path traversal,
`allow_rds` gate, size limits, decompression bomb), exact `reactiveValues`
restore, and an integration test against Shiny's reactive engine via
`shiny::testServer()`. The package passes `R CMD check` with no errors,
warnings, or notes.

## Status

Prototype (v0.1.0) accompanying the ShinySwarm Master's thesis, University of
Amsterdam. Demonstrates the design's feasibility; not yet hardened for
production.
