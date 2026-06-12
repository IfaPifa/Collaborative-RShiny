# Security regression tests. A checkpoint is untrusted input in the cross-user
# restore scenario, so these guard against malicious payloads.

# Build a checkpoint by hand, bypassing capture_state(), to simulate a crafted
# checkpoint from an attacker.
craft_file_checkpoint <- function(filename, content = "pwned", compressed = FALSE) {
  raw <- charToRaw(content)
  if (compressed) raw <- memCompress(raw, "gzip")
  jsonlite::toJSON(list(
    inputs = list(),
    compressed = compressed,
    reactives = list(
      f = list(type = "file", filename = filename,
               content = base64enc::base64encode(raw))
    )
  ), auto_unbox = TRUE)
}

test_that("path traversal via ../ is rejected", {
  target <- tempfile("safe_"); dir.create(target)
  escaped <- file.path(dirname(target), "ESCAPED.txt")
  if (file.exists(escaped)) unlink(escaped)

  json <- craft_file_checkpoint("../ESCAPED.txt")
  holder <- fake_reactiveval(NULL)

  expect_error(
    restore_state(NULL, json, f = holder, file_dir = target),
    "unsafe filename"
  )
  expect_false(file.exists(escaped))
})

test_that("absolute paths are rejected", {
  json <- craft_file_checkpoint("/tmp/abs_escape.txt")
  holder <- fake_reactiveval(NULL)
  expect_error(
    restore_state(NULL, json, f = holder, file_dir = tempfile()),
    "unsafe filename"
  )
})

test_that("a clean filename still restores", {
  target <- tempfile("ok_")
  json <- craft_file_checkpoint("data.csv", content = "a,b\n1,2")
  holder <- fake_reactiveval(NULL)
  restore_state(NULL, json, f = holder, file_dir = target)
  expect_true(file.exists(file.path(target, "data.csv")))
})

test_that("rds restore is refused by default and allowed with opt-in", {
  fit <- lm(mpg ~ wt, data = mtcars)
  json <- capture_state(list(), model = state_rds(fit))
  holder <- fake_reactiveval(NULL)

  # Default: refused.
  expect_error(
    restore_state(NULL, json, model = holder),
    "refusing to unserialize"
  )

  # Opt-in: works.
  restore_state(NULL, json, model = holder, allow_rds = TRUE)
  expect_s3_class(holder(), "lm")
})

test_that("oversized file is rejected at capture", {
  big <- tempfile(); writeBin(raw(2048), big)
  expect_error(
    capture_state(list(), f = state_file(big), max_size = 1024),
    "exceeds max_size"
  )
})

test_that("oversized rds is rejected at capture", {
  expect_error(
    capture_state(list(), x = state_rds(raw(4096)), max_size = 512),
    "exceeds max_size"
  )
})

test_that("malformed JSON gives a friendly error", {
  expect_error(
    restore_state(NULL, "{not valid json"),
    "could not parse checkpoint JSON"
  )
})

test_that("decompression bomb is rejected during decompression", {
  # A tiny gzip payload that expands to 20 MB. Build true gzip framing with
  # gzfile so it matches what restore_state() decompresses.
  big <- raw(20L * 1024L * 1024L)
  tf <- tempfile()
  con <- gzfile(tf, open = "wb"); writeBin(big, con); close(con)
  gz <- readBin(tf, "raw", n = file.info(tf)$size)
  expect_lt(length(gz), 100L * 1024L)  # compressed payload is small

  payload <- jsonlite::toJSON(list(
    inputs = list(), compressed = TRUE,
    reactives = list(f = list(
      type = "file", filename = "bomb.bin",
      content = base64enc::base64encode(gz)
    ))
  ), auto_unbox = TRUE)

  out_dir <- tempfile()
  holder <- fake_reactiveval(NULL)
  expect_error(
    restore_state(NULL, payload, f = holder,
                  file_dir = out_dir, max_size = 1024L * 1024L),
    "exceeds max_size"
  )
  # Nothing was written.
  expect_null(holder())
})

test_that("a normal compressed payload still restores after bomb guard", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,2"), tmp)
  json <- capture_state(list(), f = state_file(tmp), compress = TRUE)

  out_dir <- tempfile()
  holder <- fake_reactiveval(NULL)
  restore_state(NULL, json, f = holder, file_dir = out_dir)
  expect_equal(readLines(holder()), c("a,b", "1,2"))
})
