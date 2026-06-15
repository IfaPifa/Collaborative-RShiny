# =============================================================================
# statesnap MODEL adapter for the BioDT honeybee pDT
# -----------------------------------------------------------------------------
# THE CORE IDEA (thesis): statesnap's capture_state() reads names(input) at the
# top-level session and therefore cannot see widgets that live inside Shiny
# module namespaces (ns("foo")). The BioDT honeybee app is deeply modular
# (box/Rhino), so flattening it would defeat the purpose.
#
# Instead of flattening the app, we adapt statesnap to the app's MODEL. BioDT's
# parent module (honeybee_beekeeper_server) already composes its children into a
# small set of reactive model fragments:
#     coordinates()   - from beekeeper_map
#     parameters()    - from beekeeper_param (list: parameters df + simulation df)
#     lookup()        - from beekeeper_lookup
#     experiment_list - from beekeeper_runsimulation (results)
#
# These reactives are namespace-free by construction: each module owns its own
# ns() internally and returns a plain value. So we capture/restore the COMPOSED
# MODEL, never raw inputs. Namespaces never enter statesnap.
#
# This module provides:
#   model_to_json(model)            - capture the model as a statesnap checkpoint
#   model_from_json(json)           - restore the model list from a checkpoint
#   result_from_json(json)          - pull the result table out of a backend reply
#   run_on_backend(model, base_url) - send model JSON, get result JSON over HTTP
#
# statesnap therefore serves two roles at once:
#   (1) reproducible checkpoint format (save/restore a run), and
#   (2) the WIRE FORMAT between the Shiny frontend and the Plumber backend.
# =============================================================================

box::use(
  statesnap[capture_state, restore_state],
  httr[POST, GET, content, status_code, timeout, content_type_json],
)

#' Assemble the honeybee domain model from the parent module's reactives.
#' Pass the *values* (already called), not the reactives.
#'
#' data.frames are coerced to COLUMN-oriented lists so they survive the JSON
#' round-trip intact. jsonlite serialises a data.frame row-oriented by default,
#' which on restore returns a list of row-objects and breaks column access
#' (df$lat). as.list() makes each column a named vector, which round-trips as a
#' named list the backend can read column-wise.
#' @export
build_model <- function(coordinates, parameters, lookup) {
  df_to_cols <- function(x) if (is.data.frame(x)) as.list(x) else x
  list(
    coordinates = df_to_cols(coordinates),
    parameters  = list(
      parameters = df_to_cols(parameters$parameters),
      simulation = df_to_cols(parameters$simulation)
    ),
    lookup      = df_to_cols(lookup)
  )
}

#' Capture the composed model as a statesnap JSON checkpoint.
#' No Shiny `input` is read -> module namespaces are irrelevant.
#' @export
model_to_json <- function(model) {
  # input = list(): we deliberately bypass input capture. The model is the
  # single registered reactive value, stored as a plain (JSON-serialisable) list.
  as.character(
    capture_state(input = list(), model = model)
  )
}

#' Restore the model list from a statesnap JSON checkpoint (no live session).
#' @export
model_from_json <- function(json) {
  val <- NULL
  setter <- function(x) val <<- x
  restore_state(NULL, json, model = setter)
  val
}

#' Extract the result table (and summaries) from a backend statesnap reply.
#' @export
result_from_json <- function(json) {
  out <- list(result = NULL, final_bees = NA, peak_bees = NA, total_honey = NA)
  capture <- function(name) function(x) out[[name]] <<- x
  restore_state(
    NULL, json,
    result      = capture("result"),
    final_bees  = capture("final_bees"),
    peak_bees   = capture("peak_bees"),
    total_honey = capture("total_honey")
  )
  out
}

#' Send the model to the Plumber backend and return the parsed result.
#' This is the frontend<->backend communication: statesnap JSON over HTTP.
#' @export
run_on_backend <- function(model, base_url = NULL) {
  if (is.null(base_url)) {
    base_url <- Sys.getenv("BEEHAVE_BACKEND_URL", "http://localhost:8000")
  }
  json <- model_to_json(model)
  res <- POST(
    url = file.path(base_url, "run"),
    body = json,
    content_type_json(),
    timeout(180)
  )
  if (status_code(res) != 200) {
    stop(sprintf("backend returned HTTP %d", status_code(res)))
  }
  reply_json <- content(res, as = "text", encoding = "UTF-8")
  result_from_json(reply_json)
}

#' Write a result table to a CSV in BioDT's expected output location, so the
#' unchanged beekeeper_plot module can read it via experiment_list().
#' Returns the file path.
#' @export
result_to_biodt_csv <- function(result_table, run_dir) {
  if (!dir.exists(run_dir)) dir.create(run_dir, recursive = TRUE)
  out_dir <- file.path(run_dir, "output")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  path <- file.path(out_dir, "output_id1_iter1.csv")
  # result_table arrives as a list of columns from JSON; coerce to data.frame
  # preserving BioDT's exact (ugly) column names.
  df <- as.data.frame(result_table, check.names = FALSE, stringsAsFactors = FALSE)
  utils::write.csv(df, path, row.names = FALSE)
  path
}
