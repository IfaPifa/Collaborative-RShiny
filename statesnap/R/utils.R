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

# --- Namespace handling -------------------------------------------------------

# Normalise an `ns` argument into a literal prefix string (or NULL).
#
# Accepts NULL (no namespacing), a Shiny namespace function such as
# `shiny::NS("mod")` or `session$ns` (called with "" to obtain its separator-
# terminated prefix), or a bare module id string. A bare string gains Shiny's
# "-" separator unless it already ends with one. This lets callers capture a
# module's state from the root session (filtering + stripping the prefix) and
# restore it into a possibly differently-named module (re-adding a prefix),
# without the two ever double-prefixing.
.ns_prefix <- function(ns) {
  if (is.null(ns)) return(NULL)
  if (is.function(ns)) {
    prefix <- ns("")
    if (!is.character(prefix) || length(prefix) != 1L) {
      stop("ns(): namespace function did not return a single string",
           call. = FALSE)
    }
    return(prefix)
  }
  if (is.character(ns) && length(ns) == 1L && !is.na(ns) && nzchar(ns)) {
    if (endsWith(ns, "-")) return(ns)
    return(paste0(ns, "-"))
  }
  stop("ns must be NULL, a namespace function, or a non-empty string",
       call. = FALSE)
}

# --- JSON-safe value encoding -------------------------------------------------
#
# jsonlite serialises a data.frame row-oriented (an array of row objects). Read
# back with simplifyVector = FALSE that becomes a list of per-row lists, which
# does not reconstruct into the original data.frame -- columns come back NULL or
# mis-shaped. These helpers tag every data.frame (at any depth, inside inputs or
# reactive content) and store it column-oriented, then rebuild it on restore.
# Plain atomic values pass through untouched, so non-data.frame state is
# unaffected.

# Sentinel key marking an encoded data.frame in the JSON.
.df_tag <- ".__statesnap_df__"

# Capture default (sequential) row names as NULL so they are not stored; keep
# only meaningful (character) row names.
.df_row_names <- function(df) {
  rn <- attr(df, "row.names")
  if (is.null(rn)) return(NULL)
  n <- nrow(df)
  if (is.numeric(rn) && identical(as.integer(rn), seq_len(n))) return(NULL)
  as.list(as.character(rn))
}

# Recursively replace data.frames with a column-oriented tagged representation.
# Runs on live R values during capture.
.encode_value <- function(x) {
  if (is.data.frame(x)) {
    encoded <- list(
      TRUE,
      nrow(x),
      lapply(as.list(x), .encode_value),
      .df_row_names(x)
    )
    names(encoded) <- c(.df_tag, "nrow", "columns", "row_names")
    return(encoded)
  }
  if (is.list(x)) return(lapply(x, .encode_value))
  x
}

# Coerce a JSON-parsed array (a list of scalars, possibly containing NULLs from
# JSON null) back into an atomic vector, turning NULL into NA so the column
# length is preserved. Non-list input (a scalar that auto_unbox emitted) is
# returned unchanged.
.json_list_to_vector <- function(lst) {
  if (!is.list(lst)) return(lst)
  if (length(lst) == 0L) return(lst)
  nulls <- vapply(lst, is.null, logical(1))
  if (any(nulls)) lst[nulls] <- list(NA)
  unlist(lst, use.names = FALSE)
}

# Validate a tagged data.frame structure parsed from an untrusted checkpoint.
# A crafted payload could carry a non-list `columns` (e.g. a string), which
# would otherwise produce a silently malformed frame rather than an error. This
# rejects obviously broken shapes with a clear message, consistent with the
# other untrusted-input defences in restore_state().
.validate_df_tag <- function(x) {
  if (!is.list(x$columns)) {
    stop("restore_state(): malformed data.frame in checkpoint (columns must ",
         "be a list)", call. = FALSE)
  }
  nrow <- x$nrow
  if (!is.null(nrow) &&
      !(is.numeric(nrow) && length(nrow) == 1L && !is.na(nrow) && nrow >= 0)) {
    stop("restore_state(): malformed data.frame in checkpoint (invalid nrow)",
         call. = FALSE)
  }
  invisible(x)
}

# Rebuild a data.frame from its tagged, column-oriented representation.
.rebuild_data_frame <- function(x) {
  .validate_df_tag(x)
  cols <- x$columns
  col_names <- names(cols)
  if (is.null(col_names)) col_names <- rep("", length(cols))

  rebuilt <- lapply(cols, function(col) {
    d <- .decode_value(col)
    if (is.data.frame(d)) d else .json_list_to_vector(d)
  })
  names(rebuilt) <- col_names

  # as.data.frame() drops empty columns, so a 0-row frame would otherwise lose
  # its columns entirely. Rebuild the empty case explicitly to preserve the
  # column names and the stored row count. Column *types* of an empty frame
  # cannot be recovered from JSON (an empty atomic vector serialises to []),
  # so empty columns are reconstructed as logical(0) -- the names and shape are
  # what matter for a 0-row frame.
  nrow <- x$nrow
  is_empty <- (!is.null(nrow) && nrow == 0L) ||
    (length(rebuilt) > 0L &&
       all(vapply(rebuilt, function(c) length(c) == 0L, logical(1))))

  if (is_empty && length(col_names) > 0L) {
    empty_cols <- rep(list(logical(0)), length(col_names))
    names(empty_cols) <- col_names
    df <- as.data.frame(empty_cols,
                        stringsAsFactors = FALSE,
                        check.names = FALSE)
  } else {
    df <- as.data.frame(rebuilt,
                        stringsAsFactors = FALSE,
                        check.names = FALSE,
                        optional = TRUE)
  }

  rn <- x$row_names
  if (!is.null(rn)) {
    rownames(df) <- vapply(rn, as.character, character(1))
  }
  df
}

# Reverse .encode_value(): rebuild tagged data.frames, recurse through lists,
# leave scalars alone. Runs on JSON-parsed values during restore.
.decode_value <- function(x) {
  if (is.list(x)) {
    if (isTRUE(x[[.df_tag]])) return(.rebuild_data_frame(x))
    return(lapply(x, .decode_value))
  }
  x
}
