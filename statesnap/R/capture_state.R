#' Capture the full state of a Shiny session to JSON
#'
#' Serialises every input value plus the explicitly registered reactive values
#' into a single JSON string. Because R's reactive system exposes no way to
#' discover `reactiveVal`/`reactiveValues` objects automatically, the reactive
#' values to capture must be passed by name through `...`.
#'
#' The function is transport-agnostic: it returns a JSON string and never sends
#' or stores anything. The caller decides how to persist or transmit the result
#' (REST, Kafka, Redis, file, database).
#'
#' Each registered value is dispatched by type:
#' \itemize{
#'   \item [state_file()] -- file read from disk, gzip-compressed, embedded base64.
#'   \item [state_rds()]  -- arbitrary R object serialised, gzip-compressed, base64.
#'   \item `reactiveValues` -- converted to a named list.
#'   \item `reactiveVal` (or any zero-arg function) -- called to read its value.
#'   \item a plain value -- stored as-is.
#' }
#'
#' Note: a `reactiveVal` is itself a function, so any plain function passed
#' through `...` is treated as a `reactiveVal` and \emph{called}. To store a
#' function as data, wrap it in [state_rds()].
#'
#' @section Modular (namespaced) apps:
#' In a Shiny module the inputs are namespaced (e.g. `mod-num1`) but the module
#' server only ever refers to them locally (`input$num1`). Pass `ns` -- a module
#' id, a namespace function (`shiny::NS("mod")` or `session$ns`) -- to capture
#' only that module's inputs and store them under their \emph{local} names. The
#' resulting checkpoint is namespace-relative and can be restored into a module
#' with a different id, so an unmodified modular app round-trips without a
#' separate model layer. With `ns = NULL` (the default) all inputs are captured
#' verbatim, preserving the original behaviour.
#'
#' @section Data frames:
#' `jsonlite` serialises a data.frame row-oriented, which does not survive a
#' `simplifyVector = FALSE` round-trip. `capture_state()` detects data.frames
#' at any depth (in inputs or reactive content) and stores them column-oriented
#' so [restore_state()] reconstructs them with column names, row count, atomic
#' column types (character/integer/double/logical), intra-column `NA`s and
#' character row names preserved. No caller action is needed. Boundaries:
#' non-atomic column classes degrade to their JSON scalar form (a `factor`
#' restores as character, a `Date`/`POSIXct` as character), and an empty (0-row)
#' frame keeps its column names but reconstructs empty columns as `logical(0)`.
#' Wrap a frame in [state_rds()] for a byte-exact, class-preserving round-trip.
#'
#' @param input The Shiny `input` object (or any list-like of input values).
#' @param ... Named reactive values to capture, optionally wrapped with
#'   [state_file()] or [state_rds()].
#' @param ns Optional namespace selector for modular apps: a module id string,
#'   a namespace function (`shiny::NS("mod")` / `session$ns`), or `NULL` (the
#'   default) to capture every input verbatim. When supplied, only inputs in
#'   that namespace are captured and they are stored under their local names.
#' @param max_size Maximum size in bytes for any single embedded blob (file or
#'   serialised object), measured before base64 encoding. Guards against
#'   memory-exhausting payloads. Set `NULL` to disable. Defaults to 50 MB.
#' @param compress Whether to gzip-compress file and object payloads before
#'   base64 encoding. Offsets base64's ~33 percent inflation. Defaults to `TRUE`.
#' @return A JSON string (length-1 character vector) of class
#'   `statesnap_state`.
#' @seealso [restore_state()]
#' @importFrom jsonlite toJSON
#' @importFrom base64enc base64encode
#' @export
#' @examples
#' \dontrun{
#' json <- capture_state(input, result = result, model = state_rds(fit))
#' }
capture_state <- function(input, ..., ns = NULL,
                          max_size = NULL, compress = TRUE) {
  if (is.null(max_size)) max_size <- .default_max_size
  prefix <- .ns_prefix(ns)
  state <- list()

  # 1. Capture input values by name. When a namespace is given, keep only that
  #    module's inputs and store them under their local (de-namespaced) names so
  #    the checkpoint is portable across module ids. Data frames are encoded
  #    column-oriented so they survive the JSON round-trip.
  input_names <- names(input)
  if (is.null(input_names)) input_names <- character(0)
  if (!is.null(prefix)) {
    keep <- startsWith(input_names, prefix)
    input_names <- input_names[keep]
  }
  inputs <- lapply(input_names, function(name) .encode_value(input[[name]]))
  if (!is.null(prefix)) {
    names(inputs) <- substring(input_names, nchar(prefix) + 1L)
  } else {
    names(inputs) <- input_names
  }
  state$inputs <- inputs
  if (!is.null(prefix)) state$ns <- prefix

  # 2. Capture registered reactive values, dispatching on type.
  extras <- list(...)
  state$reactives <- lapply(extras, .capture_one,
                            max_size = max_size, compress = compress)

  # 3. Metadata.
  state$timestamp <- as.numeric(Sys.time())
  state$compressed <- isTRUE(compress)

  # digits = NA preserves full numeric precision, which is essential for exact
  # reproducibility of non-deterministic outputs (the whole point of full-state
  # capture vs input-only sharing).
  # na = "null" emits JSON null for NA so restore can turn it back into NA
  # (preserving numeric/logical column type); the default would stringify NA.
  json <- jsonlite::toJSON(
    state, auto_unbox = TRUE, force = TRUE,
    null = "null", na = "null", digits = NA
  )
  structure(as.character(json), class = "statesnap_state")
}

# Dispatch a single registered value to its tagged representation.
.capture_one <- function(rv, max_size, compress) {
  if (inherits(rv, "statesnap_file")) {
    raw <- .read_file_raw(rv$path, max_size = max_size)
    if (compress) raw <- .gzip_raw(raw)
    return(list(
      type = "file",
      filename = basename(rv$path),
      content = .b64_encode_raw(raw)
    ))
  }

  if (inherits(rv, "statesnap_rds")) {
    raw <- serialize(rv$obj, NULL)
    .check_blob_size(raw, "rds", max_size = max_size)
    if (compress) raw <- .gzip_raw(raw)
    return(list(
      type = "rds",
      content = .b64_encode_raw(raw)
    ))
  }

  if (.is_reactivevalues(rv)) {
    return(list(
      type = "reactiveValues",
      content = .encode_value(.reactivevalues_to_list(rv))
    ))
  }

  if (is.function(rv)) {
    # reactiveVal or any zero-arg accessor.
    return(list(
      type = "reactiveVal",
      content = .encode_value(rv())
    ))
  }

  # Plain value passed directly.
  list(type = "value", content = .encode_value(rv))
}
