test_that("capture_state serialises inputs to JSON", {
  input <- list(num1 = 42, num2 = 58, label = "hi")
  json <- capture_state(input)

  expect_s3_class(json, "statesnap_state")
  expect_length(json, 1L)

  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_equal(parsed$inputs$num1, 42)
  expect_equal(parsed$inputs$num2, 58)
  expect_equal(parsed$inputs$label, "hi")
  expect_true(is.numeric(parsed$timestamp))
})

test_that("capture_state reads reactiveVal accessors", {
  input <- list(num1 = 10)
  result <- fake_reactiveval(100)

  json <- capture_state(input, result = result)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_equal(parsed$reactives$result$type, "reactiveVal")
  expect_equal(parsed$reactives$result$content, 100)
})

test_that("capture_state embeds files via state_file", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,2"), tmp)

  json <- capture_state(list(), csv = state_file(tmp), compress = FALSE)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_equal(parsed$reactives$csv$type, "file")
  expect_equal(parsed$reactives$csv$filename, basename(tmp))
  decoded <- rawToChar(base64enc::base64decode(parsed$reactives$csv$content))
  expect_match(decoded, "a,b")
})

test_that("capture_state serialises R objects via state_rds", {
  fit <- lm(mpg ~ wt, data = mtcars)

  json <- capture_state(list(), model = state_rds(fit), compress = FALSE)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_equal(parsed$reactives$model$type, "rds")
  obj <- unserialize(base64enc::base64decode(parsed$reactives$model$content))
  expect_s3_class(obj, "lm")
  expect_equal(coef(obj), coef(fit))
})

test_that("capture_state handles empty input gracefully", {
  json <- capture_state(list())
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_length(parsed$inputs, 0L)
})
