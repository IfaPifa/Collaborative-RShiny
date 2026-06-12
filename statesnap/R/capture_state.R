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
#' @param input The Shiny `input` object (or any list-like of input values).
#' @param ... Named reactive values to capture, optionally wrapped with
#'   [state_file()] or [state_rds()].
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
capture_state <- function(input, ..., max_size = NULL, compress = TRUE) {
  if (is.null(max_size)) max_size <- .default_max_size
  state <- list()

  # 1. Capture all input values by name.
  input_names <- names(input)
  if (is.null(input_names)) input_names <- character(0)
  inputs <- lapply(input_names, function(name) input[[name]])
  names(inputs) <- input_names
  state$inputs <- inputs

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
  json <- jsonlite::toJSON(
    state, auto_unbox = TRUE, force = TRUE, null = "null", digits = NA
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
      content = .reactivevalues_to_list(rv)
    ))
  }

  if (is.function(rv)) {
    # reactiveVal or any zero-arg accessor.
    return(list(
      type = "reactiveVal",
      content = rv()
    ))
  }

  # Plain value passed directly.
  list(type = "value", content = rv)
}
