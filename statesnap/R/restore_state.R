#' Restore a captured state back into a Shiny session
#'
#' Reverses [capture_state()]. Inputs are pushed back into their widgets via
#' `session$sendInputMessage()`, and each registered reactive value is set from
#' the checkpoint. The reactive values to restore must be passed by name through
#' `...`, matching the names used at capture time.
#'
#' @section Security:
#' A checkpoint is untrusted input -- in the cross-user restore scenario it was
#' authored by a different user. This function defends against two attacks:
#' \itemize{
#'   \item \strong{Path traversal}: embedded filenames are reduced to a safe
#'     basename and rejected if they contain path separators or drive letters,
#'     so a restored file cannot escape `file_dir`.
#'   \item \strong{Arbitrary code execution}: restoring a [state_rds()] payload
#'     calls [base::unserialize()], which can execute code while reconstructing
#'     certain objects. This is disabled by default (`allow_rds = FALSE`). Only
#'     enable it for checkpoints from a trusted source.
#' }
#' A `max_size` ceiling also bounds each decoded blob to prevent
#' memory-exhaustion from a crafted checkpoint.
#'
#' @param session The Shiny `session` object. May be `NULL` when restoring only
#'   reactive values outside of a live session (e.g. in tests).
#' @param state_json A JSON string produced by [capture_state()].
#' @param ... Named reactive values to restore (the live `reactiveVal` /
#'   `reactiveValues` objects, \emph{not} wrappers).
#' @param file_dir Directory to write restored [state_file()] contents into.
#'   Defaults to a per-call temporary directory.
#' @param allow_rds Whether to restore [state_rds()] payloads via
#'   [base::unserialize()]. Defaults to `FALSE` because unserialising untrusted
#'   data can execute arbitrary code. Set `TRUE` only for trusted checkpoints.
#' @param max_size Maximum size in bytes for any single decoded blob. Guards
#'   against memory-exhausting payloads. Set `NULL` to disable. Defaults to
#'   50 MB.
#' @return Invisibly, the parsed state list.
#' @seealso [capture_state()]
#' @importFrom jsonlite fromJSON
#' @importFrom base64enc base64decode
#' @export
#' @examples
#' \dontrun{
#' restore_state(session, json, result = result)
#' restore_state(session, json, model = fit, allow_rds = TRUE)  # trusted only
#' }
restore_state <- function(session, state_json, ...,
                          file_dir = tempdir(),
                          allow_rds = FALSE,
                          max_size = NULL) {
  if (is.null(max_size)) max_size <- .default_max_size

  state <- tryCatch(
    jsonlite::fromJSON(state_json, simplifyVector = FALSE),
    error = function(e) {
      stop(sprintf(
        "restore_state(): could not parse checkpoint JSON: %s",
        conditionMessage(e)
      ), call. = FALSE)
    }
  )

  compressed <- isTRUE(state$compressed)

  # 1. Restore inputs (requires a live session).
  if (!is.null(session) && !is.null(state$inputs)) {
    for (name in names(state$inputs)) {
      value <- state$inputs[[name]]
      session$sendInputMessage(name, list(value = value))
    }
  }

  # 2. Restore reactive values, dispatching on the stored type.
  extras <- list(...)
  if (!is.null(state$reactives)) {
    for (name in names(state$reactives)) {
      if (!name %in% names(extras)) next
      .restore_one(extras[[name]], state$reactives[[name]],
                   file_dir = file_dir, compressed = compressed,
                   allow_rds = allow_rds, max_size = max_size)
    }
  }

  invisible(state)
}

# Restore a single value into its live reactive, reversing .capture_one().
.restore_one <- function(rv, saved, file_dir, compressed, allow_rds, max_size) {
  type <- saved$type

  if (identical(type, "file")) {
    raw <- .b64_decode_raw(saved$content)
    # Bound size during decompression (guards against decompression bombs);
    # for uncompressed payloads, check the decoded size directly.
    if (compressed) {
      raw <- .gunzip_raw(raw, max_size = max_size)
    } else {
      .check_blob_size(raw, "file", max_size = max_size)
    }
    safe_name <- .safe_filename(saved$filename)
    if (!dir.exists(file_dir)) dir.create(file_dir, recursive = TRUE)
    path <- file.path(file_dir, safe_name)
    writeBin(raw, path)
    # If a setter was supplied, hand it the restored path.
    if (is.function(rv)) rv(path)
    return(invisible(path))
  }

  if (identical(type, "rds")) {
    if (!isTRUE(allow_rds)) {
      stop(
        "restore_state(): refusing to unserialize an rds payload. ",
        "Set allow_rds = TRUE only for trusted checkpoints.",
        call. = FALSE
      )
    }
    raw <- .b64_decode_raw(saved$content)
    if (compressed) {
      raw <- .gunzip_raw(raw, max_size = max_size)
    } else {
      .check_blob_size(raw, "rds", max_size = max_size)
    }
    obj <- unserialize(raw)
    if (is.function(rv)) rv(obj)
    return(invisible(obj))
  }

  if (identical(type, "reactiveValues")) {
    # Exact restore: clear keys absent from the checkpoint so the live object
    # reproduces the saved state rather than merging (union) with whatever keys
    # the receiving session already had. This prevents value leakage in the
    # cross-user restore scenario. Note: Shiny cannot truly delete a
    # reactiveValues key, so a stale key is set to NULL (its value is cleared)
    # rather than removed entirely.
    if (.is_reactivevalues(rv)) {
      live_keys <- names(.reactivevalues_to_list(rv))
      saved_keys <- names(saved$content)
      for (key in setdiff(live_keys, saved_keys)) {
        rv[[key]] <- NULL
      }
    }
    for (key in names(saved$content)) {
      rv[[key]] <- saved$content[[key]]
    }
    return(invisible(rv))
  }

  # "reactiveVal" or "value": set via the setter if available.
  if (is.function(rv)) rv(saved$content)
  invisible(saved$content)
}
