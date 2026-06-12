# Internal helpers. Not exported.

# Default ceiling for any single embedded blob (file or serialised object),
# measured on the decoded bytes. 50 MB is generous for checkpoints while still
# bounding a malicious or runaway payload.
.default_max_size <- 50L * 1024L * 1024L

# Compress a raw vector to offset the ~33 percent base64 inflation.
#
# Uses a gzfile connection (true gzip framing, magic 0x1f 0x8b) rather than
# memCompress(type = "gzip") -- which actually emits raw zlib format -- so that
# .gunzip_raw() can stream-decompress the result through gzfile and enforce a
# size cap. Keeping both ends on gzfile guarantees the formats match.
.gzip_raw <- function(raw) {
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)
  con <- gzfile(tf, open = "wb")
  writeBin(raw, con)
  close(con)
  readBin(tf, "raw", n = file.info(tf)$size)
}

# Reverse .gzip_raw(), bounding the decompressed size to guard against a
# "decompression bomb" (a small payload that expands to many GB). Instead of
# allocating the whole output up front like memDecompress(), this streams the
# gzip data through a connection in chunks and aborts as soon as the running
# total exceeds max_size, so peak allocation stays bounded regardless of how
# large the payload claims to decompress to.
.gunzip_raw <- function(raw, max_size = .default_max_size) {
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)
  writeBin(raw, tf)

  con <- gzfile(tf, open = "rb")
  on.exit(close(con), add = TRUE)

  chunk_size <- 1024L * 1024L          # 1 MB read window
  chunks <- list()
  total <- 0
  repeat {
    chunk <- readBin(con, "raw", n = chunk_size)
    if (length(chunk) == 0L) break
    total <- total + length(chunk)
    if (!is.null(max_size) && total > max_size) {
      stop(sprintf(
        "restore_state(): decompressed payload exceeds max_size (%.0f bytes)",
        max_size
      ), call. = FALSE)
    }
    chunks[[length(chunks) + 1L]] <- chunk
  }
  if (length(chunks) == 0L) return(raw(0))
  do.call(c, chunks)
}

# base64-encode a raw vector.
.b64_encode_raw <- function(raw) {
  base64enc::base64encode(raw)
}

# base64-decode to a raw vector.
.b64_decode_raw <- function(txt) {
  base64enc::base64decode(txt)
}

# Read a file fully into a raw vector, enforcing a size ceiling so a huge file
# cannot exhaust memory during capture.
.read_file_raw <- function(path, max_size = .default_max_size) {
  size <- file.info(path)$size
  if (is.na(size)) {
    stop(sprintf("state_file(): file not found: %s", path), call. = FALSE)
  }
  if (!is.null(max_size) && size > max_size) {
    stop(sprintf(
      "state_file(): file %s is %.0f bytes, exceeds max_size (%.0f bytes)",
      path, size, max_size
    ), call. = FALSE)
  }
  readBin(path, "raw", n = size)
}

# Enforce a ceiling on a decoded blob before further processing on restore.
.check_blob_size <- function(raw, what, max_size = .default_max_size) {
  if (!is.null(max_size) && length(raw) > max_size) {
    stop(sprintf(
      "restore_state(): %s payload is %d bytes, exceeds max_size (%.0f bytes)",
      what, length(raw), max_size
    ), call. = FALSE)
  }
  invisible(raw)
}

# Reject filenames that could escape the target directory (path traversal).
# Returns a safe basename; errors on anything suspicious.
.safe_filename <- function(filename) {
  if (!is.character(filename) || length(filename) != 1L || is.na(filename)) {
    stop("restore_state(): checkpoint has an invalid filename", call. = FALSE)
  }
  if (grepl("[/\\\\]", filename) ||         # contains a path separator
      grepl("^([A-Za-z]:|~)", filename) ||  # drive letter or home expansion
      filename %in% c("", ".", "..")) {
    stop(sprintf(
      "restore_state(): unsafe filename in checkpoint: %s", filename
    ), call. = FALSE)
  }
  basename(filename)
}

# Detect a Shiny reactiveValues object without requiring shiny at load time.
.is_reactivevalues <- function(x) {
  if (requireNamespace("shiny", quietly = TRUE)) {
    return(shiny::is.reactivevalues(x))
  }
  inherits(x, "reactivevalues")
}

# Pull a plain list of values out of a reactiveValues object.
.reactivevalues_to_list <- function(x) {
  if (requireNamespace("shiny", quietly = TRUE)) {
    return(shiny::reactiveValuesToList(x))
  }
  stop("shiny is required to read reactiveValues", call. = FALSE)
}
