# Tests for the S3 claim-check transport.
#
# The "live" tests need a reachable S3-compatible store. They read connection
# details from environment variables and skip when the store is not available,
# so the suite stays runnable anywhere. Locally, point them at MinIO:
#   STATESNAP_S3_ENDPOINT=http://127.0.0.1:9000
#   STATESNAP_S3_BUCKET=shinyswarm-state
#   AWS_ACCESS_KEY_ID=minio  AWS_SECRET_ACCESS_KEY=minio123

s3_test_config <- function() {
  endpoint <- Sys.getenv("STATESNAP_S3_ENDPOINT", "http://127.0.0.1:9000")
  bucket <- Sys.getenv("STATESNAP_S3_BUCKET", "shinyswarm-state")
  ak <- Sys.getenv("AWS_ACCESS_KEY_ID", "minio")
  sk <- Sys.getenv("AWS_SECRET_ACCESS_KEY", "minio123")
  s3_config(bucket = bucket, endpoint = endpoint,
            access_key = ak, secret_key = sk)
}

# Skip unless paws.storage is installed AND the store answers a list call.
skip_if_no_s3 <- function() {
  skip_if_not_installed("paws.storage")
  cfg <- s3_test_config()
  ok <- tryCatch({
    svc <- statesnap:::.s3_client(cfg)
    svc$list_objects_v2(Bucket = cfg$bucket, MaxKeys = 1L)
    TRUE
  }, error = function(e) FALSE)
  if (!ok) skip("no reachable S3-compatible store for claim-check tests")
  cfg
}

# --- Pure (no network) tests -------------------------------------------------

test_that("s3_config validates and stores its fields", {
  cfg <- s3_config(bucket = "b", endpoint = "http://x:9000",
                   access_key = "k", secret_key = "s")
  expect_s3_class(cfg, "statesnap_s3_config")
  expect_equal(cfg$bucket, "b")
  expect_equal(cfg$prefix, "states")
  expect_equal(cfg$ttl_seconds, 86400L)
  expect_error(s3_config(bucket = ""), "non-empty")
  expect_error(s3_config(bucket = c("a", "b")), "single")
})

test_that("capture_state rejects a non-s3_config s3 argument", {
  expect_error(
    capture_state(list(a = 1), x = state_rds(1:10), s3 = list(bucket = "b")),
    "s3_config"
  )
})

test_that("restore_state rejects a non-s3_config s3 argument", {
  json <- capture_state(list(a = 1), x = state_rds(1:10))
  expect_error(
    restore_state(NULL, json, x = function(v) {}, s3 = "nope"),
    "s3_config"
  )
})

test_that("small blobs stay inline even when an s3 store is configured", {
  cfg <- s3_config(bucket = "b", endpoint = "http://x:9000",
                   access_key = "k", secret_key = "s")
  # No network call expected: 1:10 is far below the 256 KB threshold.
  json <- capture_state(list(a = 1), x = state_rds(1:10), s3 = cfg)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_equal(parsed$reactives$x$type, "rds")
  expect_true(!is.null(parsed$reactives$x$content))
})

test_that("a claim-check checkpoint cannot be restored without an s3 config", {
  # Hand-craft a claim-check reference so this needs no network at capture time.
  ref <- list(type = "claim-check", blobType = "rds", store = "s3",
              bucket = "b", key = "states/x.rds", compressed = TRUE,
              sizeBytes = 10, etag = "deadbeef")
  state <- list(inputs = list(), reactives = list(payload = ref),
                compressed = TRUE)
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, force = TRUE)
  expect_error(
    restore_state(NULL, json, payload = function(v) {}, allow_rds = TRUE),
    "claim-check reference but no"
  )
})

# --- Live tests against a real store -----------------------------------------

test_that("large rds offloads to S3 and the bus carries only a reference", {
  cfg <- skip_if_no_s3()
  big <- matrix(stats::rnorm(250000), nrow = 500)  # ~1.9 MB, above threshold

  json <- capture_state(list(gene = "MS4A1"), payload = state_rds(big),
                        s3 = cfg)
  expect_lt(nchar(json), 5000)  # reference is kilobyte-sized, not megabytes

  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  ref <- parsed$reactives$payload
  expect_equal(ref$type, "claim-check")
  expect_equal(ref$blobType, "rds")
  expect_equal(ref$store, "s3")
  expect_true(nzchar(ref$key))
  expect_true(nzchar(ref$etag))
  expect_gt(ref$sizeBytes, 100000)
})

test_that("large rds round-trips identically through the claim-check", {
  cfg <- skip_if_no_s3()
  big <- matrix(stats::rnorm(250000), nrow = 500)

  json <- capture_state(list(a = 1), payload = state_rds(big), s3 = cfg)

  restored <- NULL
  setter <- function(v) restored <<- v
  restore_state(NULL, json, payload = setter, s3 = cfg, allow_rds = TRUE)
  expect_identical(big, restored)
})

test_that("allow_rds gate applies to claim-check rds payloads", {
  cfg <- skip_if_no_s3()
  big <- matrix(stats::rnorm(250000), nrow = 500)
  json <- capture_state(list(a = 1), payload = state_rds(big), s3 = cfg)
  expect_error(
    restore_state(NULL, json, payload = function(v) {}, s3 = cfg,
                  allow_rds = FALSE),
    "refusing to unserialize"
  )
})

test_that("integrity check detects a swapped/corrupted object", {
  cfg <- skip_if_no_s3()
  big <- matrix(stats::rnorm(250000), nrow = 500)
  json <- capture_state(list(a = 1), payload = state_rds(big), s3 = cfg)
  ref <- jsonlite::fromJSON(json, simplifyVector = FALSE)$reactives$payload

  # Overwrite the stored object with something of a different size.
  svc <- statesnap:::.s3_client(cfg)
  svc$put_object(Bucket = cfg$bucket, Key = ref$key,
                 Body = charToRaw("corrupted"))

  expect_error(
    restore_state(NULL, json, payload = function(v) {}, s3 = cfg,
                  allow_rds = TRUE),
    "size mismatch|ETag mismatch"
  )
})

test_that("offloaded blobs are exempt from the inline max_size ceiling", {
  cfg <- skip_if_no_s3()
  # ~4 MB object, but cap the inline ceiling at 1 MB. An embedded blob this big
  # would be rejected; an offloaded one must succeed, because the ceiling bounds
  # only inline payloads and the reference is integrity-checked by size/ETag.
  big <- matrix(stats::rnorm(500000), nrow = 1000)
  small_cap <- 1024L * 1024L

  json <- capture_state(list(a = 1), payload = state_rds(big),
                        s3 = cfg, max_size = small_cap)
  ref <- jsonlite::fromJSON(json, simplifyVector = FALSE)$reactives$payload
  expect_equal(ref$type, "claim-check")

  restored <- NULL
  restore_state(NULL, json, payload = function(v) restored <<- v,
                s3 = cfg, allow_rds = TRUE, max_size = small_cap)
  expect_identical(big, restored)
})

test_that("large file offloads and restores under its original name", {
  cfg <- skip_if_no_s3()
  # Build a file whose *compressed* size still exceeds the 256 KB threshold.
  # Random bytes are incompressible, so the offload decision (made on the
  # post-gzip size) fires.
  tmp <- tempfile(fileext = ".bin")
  writeBin(as.raw(sample(0:255, 600L * 1024L, replace = TRUE)), tmp)
  on.exit(unlink(tmp), add = TRUE)
  expect_gt(file.info(tmp)$size, 256L * 1024L)

  json <- capture_state(list(a = 1), data = state_file(tmp), s3 = cfg)
  ref <- jsonlite::fromJSON(json, simplifyVector = FALSE)$reactives$data
  expect_equal(ref$type, "claim-check")
  expect_equal(ref$blobType, "file")

  out_dir <- tempfile()
  dir.create(out_dir)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  restored_path <- NULL
  restore_state(NULL, json, data = function(p) restored_path <<- p,
                s3 = cfg, file_dir = out_dir)
  expect_true(file.exists(restored_path))
  expect_equal(basename(restored_path), basename(tmp))
  orig_bytes <- readBin(tmp, "raw", n = file.info(tmp)$size)
  back_bytes <- readBin(restored_path, "raw", n = file.info(restored_path)$size)
  expect_identical(orig_bytes, back_bytes)
})
