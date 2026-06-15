# S3 claim-check transport for statesnap.
#
# Large state (e.g. a single-cell Seurat/AnnData object that runs to hundreds of
# megabytes) cannot ride inline through a message bus: Kafka caps messages near
# 1 MB and Redis is in-memory. The claim-check enterprise integration pattern
# solves this by storing the heavy payload in an object store and sending only a
# small reference ("claim check") through the bus. The receiver redeems the
# reference to fetch the payload.
#
# This module adds that transport to statesnap without changing its contract:
# capture_state() still returns a single JSON string and restore_state() still
# consumes one. The difference is that, when an S3 store is configured and a blob
# exceeds the threshold, the JSON carries a kilobyte-sized reference instead of
# the megabytes of base64 payload.

#' Describe an S3-compatible object store
#'
#' Builds the configuration that [capture_state()] and [restore_state()] use to
#' offload large state to, and fetch it from, an S3-compatible object store
#' (AWS S3, MinIO, etc.). Because the same API targets MinIO locally and AWS S3
#' in production, only the `endpoint` changes between environments.
#'
#' @param bucket Bucket name that holds the state objects.
#' @param endpoint Service endpoint URL. For MinIO this is typically
#'   `http://127.0.0.1:9000`; leave `NULL` to use the AWS default for `region`.
#' @param access_key,secret_key Credentials. Default to the standard
#'   `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables.
#' @param region Region string. Defaults to `us-east-1` (MinIO ignores it).
#' @param prefix Key prefix under which objects are written. Defaults to
#'   `"states"`.
#' @param ttl_seconds Advisory time-to-live recorded in the reference, for a
#'   later cleanup job. Defaults to one day. Not enforced by this package.
#' @return An object of class `statesnap_s3_config`.
#' @export
#' @examples
#' \dontrun{
#' s3 <- s3_config(bucket = "shinyswarm-state",
#'                 endpoint = "http://127.0.0.1:9000",
#'                 access_key = "minio", secret_key = "minio123")
#' }
s3_config <- function(bucket,
                      endpoint = NULL,
                      access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
                      secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY"),
                      region = "us-east-1",
                      prefix = "states",
                      ttl_seconds = 86400L) {
  if (!is.character(bucket) || length(bucket) != 1L || !nzchar(bucket)) {
    stop("s3_config() requires a single non-empty bucket name", call. = FALSE)
  }
  structure(
    list(
      bucket = bucket,
      endpoint = endpoint,
      access_key = access_key,
      secret_key = secret_key,
      region = region,
      prefix = prefix,
      ttl_seconds = as.integer(ttl_seconds)
    ),
    class = "statesnap_s3_config"
  )
}

# Build a paws.storage S3 service handle from an s3_config. Path-style access is
# forced because MinIO (and most non-AWS stores) do not support virtual-hosted
# bucket subdomains.
.s3_client <- function(cfg) {
  if (!requireNamespace("paws.storage", quietly = TRUE)) {
    stop(
      "statesnap S3 transport requires the 'paws.storage' package. ",
      "Install it with install.packages('paws.storage').",
      call. = FALSE
    )
  }
  config <- list(
    credentials = list(
      creds = list(
        access_key_id = cfg$access_key,
        secret_access_key = cfg$secret_key
      )
    ),
    region = cfg$region,
    s3_force_path_style = TRUE
  )
  if (!is.null(cfg$endpoint) && nzchar(cfg$endpoint)) {
    config$endpoint <- cfg$endpoint
  }
  paws.storage::s3(config = config)
}

# Generate a collision-resistant object key: <prefix>/<timestamp>-<rand>.<ext>.
.s3_make_key <- function(cfg, format) {
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%OS3Z", tz = "UTC")
  rand <- paste(sample(c(0:9, letters[1:6]), 8, replace = TRUE), collapse = "")
  ext <- switch(format, rds = "rds", file = "bin", format)
  paste0(cfg$prefix, "/", stamp, "-", rand, ".", ext)
}

# Strip the quotes that S3 wraps around ETag values so they compare cleanly.
.s3_clean_etag <- function(etag) {
  if (is.null(etag)) return(NA_character_)
  gsub('"', "", etag, fixed = TRUE)
}

# Upload a raw payload and return a claim-check reference list. The reference is
# small, JSON-safe and self-describing: it carries everything the receiver needs
# to fetch, verify and deserialise the payload.
.s3_put <- function(cfg, raw, format, compressed) {
  svc <- .s3_client(cfg)
  key <- .s3_make_key(cfg, format)
  res <- svc$put_object(Bucket = cfg$bucket, Key = key, Body = raw)
  list(
    type = "claim-check",            # statesnap restore dispatch key
    kind = "claim-check",
    schema = 1L,
    store = "s3",
    bucket = cfg$bucket,
    key = key,
    format = format,                 # rds | file
    compressed = isTRUE(compressed),
    sizeBytes = length(raw),
    etag = .s3_clean_etag(res$ETag),
    createdAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    ttlSeconds = cfg$ttl_seconds
  )
}

# Redeem a claim-check reference: fetch the object and verify integrity against
# the size and ETag recorded at capture time, so a partial or swapped object is
# detected rather than silently deserialised.
.s3_get <- function(cfg, ref) {
  svc <- .s3_client(cfg)
  bucket <- if (!is.null(ref$bucket)) ref$bucket else cfg$bucket
  out <- svc$get_object(Bucket = bucket, Key = ref$key)
  raw <- out$Body

  if (!is.null(ref$sizeBytes) && length(raw) != as.numeric(ref$sizeBytes)) {
    stop(sprintf(
      "restore_state(): claim-check size mismatch (expected %s, got %d bytes)",
      ref$sizeBytes, length(raw)
    ), call. = FALSE)
  }
  ref_etag <- if (!is.null(ref$etag)) ref$etag else NA_character_
  got_etag <- .s3_clean_etag(out$ETag)
  if (!is.na(ref_etag) && !is.na(got_etag) && !identical(ref_etag, got_etag)) {
    stop(sprintf(
      "restore_state(): claim-check ETag mismatch (expected %s, got %s)",
      ref_etag, got_etag
    ), call. = FALSE)
  }
  raw
}

# Predicate used by capture dispatch.
.is_s3_config <- function(x) inherits(x, "statesnap_s3_config")
