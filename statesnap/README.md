# statesnap

Transport-agnostic full-state capture and restore for interactive R applications.

`statesnap` serialises a complete set of inputs and computed values — into a
single JSON string, and restores it later. Unlike input-only sharing
(`shinyURL`, bookmarking), which forces the receiver to recompute outputs,
full-state capture preserves the computed outputs themselves. For
non-deterministic analyses (e.g. a Monte Carlo simulation without `set.seed()`),
this is the difference between reproducing a result and getting a different one —
**and it needs no fixed seed**, because the computed result, not the recipe to
recompute it, is what gets shared. (See [Fidelity caveats](#fidelity-caveats)
for the precise meaning of "preserves".)

The library is **transport-agnostic**: it produces and consumes JSON only. How
that JSON is transmitted or persisted — REST, Kafka, Redis, a file, a database —
is the caller's concern.

**Shiny is supported but not required.** The inputs and accessors are duck-typed,
so the core works with any list-like collection of values and any getter/setter
function; Shiny `reactiveVal`/`reactiveValues` are just one supported case. Shiny
is a suggested dependency, needed only for live `reactiveValues` and for pushing
inputs back through a session.

This package is the standalone, reusable distillation of the checkpoint
mechanism built for the *ShinySwarm* thesis system (the package is named
`statesnap` to keep the library distinct from that system). It needs no
microservice infrastructure.

## Installation

```r
# from a local source checkout
install.packages("statesnap", repos = NULL, type = "source")

# or, during development
# remotes::install_github("<user>/statesnap")
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
library(statesnap)

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

## Fidelity caveats

The checkpoint is JSON, a text-based, schema-less format. It guarantees the
**values** you put in, but not the full R type system around them. Two
consequences are worth knowing:

- **Numeric precision is very high, but not bit-identical for floating-point
  vectors.** Numbers are written as decimal text with full precision
  (`toJSON(..., digits = NA)`), but the decimal→binary→decimal conversion is not
  guaranteed bit-exact. In practice a restored vector of doubles matches the
  original to within ~1e-13 — far tighter than any analysis would observe, and
  vastly better than the default 4-decimal rounding, but not literally
  byte-for-byte. Scalars typically round-trip identically; the discrepancy shows
  up across vectors. If you need byte-identical doubles, wrap the object in
  `state_rds()`, which uses R's binary serialisation.
- **Captured numeric vectors come back as lists.** `restore_state()` parses with
  `simplifyVector = FALSE` so `jsonlite` cannot silently reshape your data. A
  side effect is that a numeric vector stored inside a captured list returns as a
  list of numbers — the values are intact, but the container type is not.
  Recover the atomic vector with `as.numeric(unlist(x))`.

These are the inherent boundary of JSON serialisation, documented so a value
arriving as a list (or a double differing in its last digits) is expected
behaviour, not a bug.

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
`shiny::testServer()`. A Monte Carlo set (`test-montecarlo.R`), modelled on the
ShinySwarm population-viability simulator, captures an unseeded stochastic result
and asserts that a restore reproduces it while a fresh recomputation diverges; it
also pins the two fidelity caveats above (floating-point tolerance, list-typed
vector return). The package passes `R CMD check` with no errors, warnings, or
notes.

## Status

Prototype (v0.1.0) accompanying the ShinySwarm Master's thesis, University of
Amsterdam. Demonstrates the design's feasibility; not yet hardened for
production.
