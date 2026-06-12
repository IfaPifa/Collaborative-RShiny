test_that("state_file builds the right object", {
  w <- state_file("/tmp/foo.csv")
  expect_s3_class(w, "statesnap_file")
  expect_equal(w$path, "/tmp/foo.csv")
})

test_that("state_file rejects bad input", {
  expect_error(state_file(c("a", "b")))
  expect_error(state_file(42))
})

test_that("state_rds wraps any object", {
  w <- state_rds(list(a = 1))
  expect_s3_class(w, "statesnap_rds")
  expect_equal(w$obj, list(a = 1))
})

test_that("capture_state errors on a missing file", {
  expect_error(
    capture_state(list(), csv = state_file("/no/such/file.csv")),
    "file not found"
  )
})
