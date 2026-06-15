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
#' @param s3 An optional [s3_config()] describing an S3-compatible object store.
#'   When supplied, any [state_file()] or [state_rds()] blob whose compressed
#'   size reaches `threshold` is uploaded to the store and represented in the
#'   JSON by a small claim-check reference instead of an inline base64 payload.
#'   This is the claim-check pattern: it keeps large objects (e.g. single-cell
#'   datasets of hundreds of megabytes) off the message bus, which can only carry
#'   the kilobyte-sized reference. Defaults to `NULL` (everything inline,
#'   unchanged behaviour).
#' @param threshold Size in bytes at or above which a blob is offloaded to `s3`
#'   rather than embedded inline. Ignored when `s3` is `NULL`. Defaults to
#'   256 KB.
#' @return A JSON string (length-1 character vector) of class
#'   `statesnap_state`.
#' @seealso [restore_state()], [s3_config()]
#' @importFrom jsonlite toJSON
#' @importFrom base64enc base64encode
#' @export
#' @examples
#' \dontrun{
#' json <- capture_state(input, result = result, model = state_rds(fit))
#'
#' # Offload large objects to MinIO/S3, keep only a reference on the bus:
#' s3 <- s3_config(bucket = "shinyswarm-state",
#'                 endpoint = "http://127.0.0.1:9000",
#'                 access_key = "minio", secret_key = "minio123")
#' json <- capture_state(input, seurat = state_rds(obj), s3 = s3)
#' }
capture_state <- function(input, ..., max_size = NULL, compress = TRUE,
                          s3 = NULL, threshold = .default_s3_threshold) {
  if (is.null(max_size)) max_size <- .default_max_size
  if (!is.null(s3) && !.is_s3_config(s3)) {
    stop("capture_state(): 's3' must be an s3_config() object or NULL",
         call. = FALSE)
  }
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
                            max_size = max_size, compress = compress,
                            s3 = s3, threshold = threshold)

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
#
# When an s3 store is configured and a blob's (post-compression) size reaches
# threshold, the blob is uploaded and represented by a claim-check reference
# rather than an inline base64 payload, so the heavy bytes stay off the message
# bus. The original `filename` (for files) is preserved alongside the reference
# so restore can write the file back under its real name.
.capture_one <- function(rv, max_size, compress, s3 = NULL,
                         threshold = .default_s3_threshold) {
  if (inherits(rv, "statesnap_file")) {
    # max_size bounds *embedded* blobs only. When a store is configured the file
    # may be offloaded (referenced, not embedded), so we read without the inline
    # ceiling and re-apply it below only if the blob actually stays inline.
    read_ceiling <- if (!is.null(s3)) NULL else max_size
    raw <- .read_file_raw(rv$path, max_size = read_ceiling)
    comp <- if (compress) .gzip_raw(raw) else raw
    if (.should_offload(comp, s3, threshold)) {
      ref <- .s3_put(s3, comp, format = "file", compressed = compress)
      ref$filename <- basename(rv$path)
      ref$blobType <- "file"
      return(ref)
    }
    .check_blob_size(raw, "file", max_size = max_size)  # inline ceiling
    return(list(
      type = "file",
      filename = basename(rv$path),
      content = .b64_encode_raw(comp)
    ))
  }

  if (inherits(rv, "statesnap_rds")) {
    raw <- serialize(rv$obj, NULL)
    comp <- if (compress) .gzip_raw(raw) else raw
    if (.should_offload(comp, s3, threshold)) {
      # Offloaded to object storage: not embedded, so the inline max_size does
      # not apply. Integrity on restore is enforced via the recorded size/ETag.
      ref <- .s3_put(s3, comp, format = "rds", compressed = compress)
      ref$blobType <- "rds"
      return(ref)
    }
    .check_blob_size(raw, "rds", max_size = max_size)  # inline ceiling
    return(list(
      type = "rds",
      content = .b64_encode_raw(comp)
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
