test_that("restore_state pushes inputs back through the session", {
  input <- list(num1 = 42, num2 = 58)
  json <- capture_state(input)

  sess <- fake_session()
  restore_state(sess, json)

  expect_equal(sess$sent()$num1, 42)
  expect_equal(sess$sent()$num2, 58)
})

test_that("capture then restore round-trips a reactiveVal", {
  result <- fake_reactiveval(100)
  json <- capture_state(list(num1 = 1), result = result)

  # Simulate the value changing after the checkpoint.
  result(999)
  expect_equal(result(), 999)

  # Restore should bring back the saved value.
  restore_state(NULL, json, result = result)
  expect_equal(result(), 100)
})

test_that("restore_state round-trips an embedded file", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("x,y", "3,4"), tmp)
  json <- capture_state(list(), csv = state_file(tmp))

  out_dir <- tempfile()
  path_holder <- fake_reactiveval(NULL)
  restore_state(NULL, json, csv = path_holder, file_dir = out_dir)

  restored_path <- path_holder()
  expect_true(file.exists(restored_path))
  expect_equal(readLines(restored_path), c("x,y", "3,4"))
})

test_that("restore_state round-trips a serialised R object", {
  fit <- lm(mpg ~ wt, data = mtcars)
  json <- capture_state(list(), model = state_rds(fit))

  holder <- fake_reactiveval(NULL)
  restore_state(NULL, json, model = holder, allow_rds = TRUE)

  expect_s3_class(holder(), "lm")
  expect_equal(coef(holder()), coef(fit))
})

test_that("restore_state ignores reactives that were not registered", {
  result <- fake_reactiveval(5)
  json <- capture_state(list(), result = result)

  # Restore without passing 'result' -- should not error.
  expect_silent(restore_state(NULL, json))
})

test_that("non-deterministic output is preserved, not recomputed", {
  # Emulate a Monte Carlo result captured without set.seed().
  draw <- fake_reactiveval(mean(runif(1000)))
  saved <- draw()
  json <- capture_state(list(n = 1000), draw = draw)

  # A different "run" produces a different value.
  draw(mean(runif(1000)))
  expect_false(isTRUE(all.equal(draw(), saved)))

  # Full-state restore brings back the exact captured value.
  restore_state(NULL, json, draw = draw)
  expect_equal(draw(), saved)
})
