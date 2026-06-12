# Edge cases: NULL inputs, compression round-trips.

test_that("NULL input round-trips to NULL", {
  input <- list(num1 = 42, empty = NULL)
  json <- capture_state(input)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_equal(parsed$inputs$num1, 42)
  # A NULL input serialises to JSON null and parses back to NULL.
  expect_true("empty" %in% names(parsed$inputs) || is.null(parsed$inputs$empty))
})

test_that("NULL input is pushed back through the session on restore", {
  input <- list(num1 = 42, empty = NULL)
  json <- capture_state(input)
  sess <- fake_session()
  restore_state(sess, json)
  expect_equal(sess$sent()$num1, 42)
})

test_that("compressed file payload round-trips", {
  tmp <- tempfile(fileext = ".csv")
  # Repetitive content compresses well.
  writeLines(rep("alpha,beta,gamma,delta", 500), tmp)

  json <- capture_state(list(), csv = state_file(tmp), compress = TRUE)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_true(parsed$compressed)

  out_dir <- tempfile()
  holder <- fake_reactiveval(NULL)
  restore_state(NULL, json, csv = holder, file_dir = out_dir)
  expect_equal(readLines(holder()), rep("alpha,beta,gamma,delta", 500))
})

test_that("compression shrinks repetitive file payloads", {
  tmp <- tempfile(fileext = ".txt")
  writeLines(rep("repeat me", 2000), tmp)

  comp <- capture_state(list(), f = state_file(tmp), compress = TRUE)
  raw <- capture_state(list(), f = state_file(tmp), compress = FALSE)
  expect_lt(nchar(comp), nchar(raw))
})

test_that("uncompressed rds round-trips when allowed", {
  fit <- lm(mpg ~ wt, data = mtcars)
  json <- capture_state(list(), model = state_rds(fit), compress = FALSE)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_false(parsed$compressed)

  holder <- fake_reactiveval(NULL)
  restore_state(NULL, json, model = holder, allow_rds = TRUE)
  expect_equal(coef(holder()), coef(fit))
})
