# Data frames must survive the JSON round-trip. jsonlite serialises a
# data.frame row-oriented, which does not reconstruct under
# simplifyVector = FALSE; statesnap stores them column-oriented instead.

test_that("a data.frame in inputs round-trips exactly", {
  df <- data.frame(
    id = 1:3,
    name = c("a", "b", "c"),
    value = c(1.5, 2.5, 3.5),
    stringsAsFactors = FALSE
  )
  json <- capture_state(list(table = df))

  holder <- fake_reactiveval(NULL)
  # Inputs need a session; capture the pushed value via a fake session.
  sess <- fake_session()
  state <- restore_state(sess, json)

  restored <- sess$sent()$table
  expect_s3_class(restored, "data.frame")
  expect_equal(restored, df)
})

test_that("a data.frame in a reactiveVal round-trips exactly", {
  df <- data.frame(
    lat = c(52.37, 48.85),
    lon = c(4.90, 2.35),
    stringsAsFactors = FALSE
  )
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), coords = rv)

  rv(data.frame(lat = 0, lon = 0))           # mutate after capture
  restore_state(NULL, json, coords = rv)
  expect_equal(rv(), df)
})

test_that("column types are preserved (no stringsAsFactors drift)", {
  df <- data.frame(
    chr = c("x", "y"),
    int = c(10L, 20L),
    num = c(1.1, 2.2),
    lgl = c(TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), d = rv)
  rv(NULL)
  restore_state(NULL, json, d = rv)
  out <- rv()

  expect_type(out$chr, "character")
  expect_type(out$int, "integer")
  expect_type(out$num, "double")
  expect_type(out$lgl, "logical")
})

test_that("NA values inside a column survive", {
  df <- data.frame(
    a = c(1, NA, 3),
    b = c("p", "q", NA),
    stringsAsFactors = FALSE
  )
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), d = rv)
  rv(NULL)
  restore_state(NULL, json, d = rv)
  out <- rv()

  expect_equal(out$a, c(1, NA, 3))
  expect_true(is.na(out$b[3]))
})

test_that("character row names are preserved", {
  df <- data.frame(x = c(1, 2), y = c(3, 4))
  rownames(df) <- c("first", "second")
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), d = rv)
  rv(NULL)
  restore_state(NULL, json, d = rv)
  expect_equal(rownames(rv()), c("first", "second"))
})

test_that("a single-row data.frame round-trips", {
  df <- data.frame(a = 1, b = "x", stringsAsFactors = FALSE)
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), d = rv)
  rv(NULL)
  restore_state(NULL, json, d = rv)
  expect_equal(rv(), df)
})

test_that("a nested data.frame inside a list round-trips", {
  payload <- list(
    meta = "run-1",
    table = data.frame(a = 1:2, b = c("u", "v"), stringsAsFactors = FALSE)
  )
  rv <- fake_reactiveval(payload)
  json <- capture_state(list(), p = rv)
  rv(NULL)
  restore_state(NULL, json, p = rv)
  out <- rv()
  expect_equal(out$meta, "run-1")
  expect_s3_class(out$table, "data.frame")
  expect_equal(out$table, payload$table)
})

test_that("a 0-row data.frame keeps its columns and shape", {
  df <- data.frame(a = integer(0), b = character(0), stringsAsFactors = FALSE)
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), d = rv)
  rv(NULL)
  restore_state(NULL, json, d = rv)
  out <- rv()

  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_equal(names(out), c("a", "b"))
})

test_that("factor columns degrade to character (documented boundary)", {
  df <- data.frame(g = factor(c("lo", "hi", "lo")), n = 1:3)
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), d = rv)
  rv(NULL)
  restore_state(NULL, json, d = rv)
  out <- rv()

  # Class is not preserved, but the labels (values) survive intact.
  expect_type(out$g, "character")
  expect_equal(out$g, c("lo", "hi", "lo"))
  expect_equal(out$n, 1:3)
})

test_that("Date columns degrade to character (documented boundary)", {
  df <- data.frame(when = as.Date(c("2020-01-01", "2020-06-15")), v = c(1, 2))
  rv <- fake_reactiveval(df)
  json <- capture_state(list(), d = rv)
  rv(NULL)
  restore_state(NULL, json, d = rv)
  out <- rv()

  expect_type(out$when, "character")
  expect_equal(out$when, c("2020-01-01", "2020-06-15"))
})

test_that("a malformed data.frame tag in a checkpoint is rejected", {
  tag <- statesnap:::.df_tag
  bad <- sprintf(
    '{"reactives":{"d":{"type":"value","content":{"%s":true,"nrow":2,"columns":"notalist"}}},"compressed":false}',
    tag
  )
  holder <- fake_reactiveval(NULL)
  expect_error(
    restore_state(NULL, bad, d = holder),
    "malformed data.frame"
  )

  bad_nrow <- sprintf(
    '{"reactives":{"d":{"type":"value","content":{"%s":true,"nrow":-5,"columns":{"a":[1]}}}},"compressed":false}',
    tag
  )
  expect_error(
    restore_state(NULL, bad_nrow, d = holder),
    "invalid nrow"
  )
})

test_that("scalar NA restores as NULL (documented na = null boundary)", {
  # Outside a data-frame column there is no type context, so a scalar NA
  # serialises to JSON null and restores as NULL. Pinned so the choice is
  # intentional rather than accidental.
  json <- capture_state(list(x = NA, y = 5))
  sess <- fake_session()
  restore_state(sess, json)
  expect_null(sess$sent()$x)
  expect_equal(sess$sent()$y, 5)
})

test_that("the BioDT parameters/simulation model shape round-trips", {
  # Mirrors the honeybee PoC: a list of two data frames captured as one model.
  model <- list(
    parameters = data.frame(
      name = c("N_INITIAL_BEES", "N_INITIAL_MITES_HEALTHY"),
      value = c(12000, 200),
      stringsAsFactors = FALSE
    ),
    simulation = data.frame(
      key = c("SimulationYearStart", "DaysLimit"),
      val = c("2016", "365"),
      stringsAsFactors = FALSE
    )
  )
  rv <- fake_reactiveval(model)
  json <- capture_state(list(), model = rv)
  rv(NULL)
  restore_state(NULL, json, model = rv)
  out <- rv()

  expect_equal(out$parameters, model$parameters)
  expect_equal(out$simulation, model$simulation)
  # The bug this guards: the value column must not come back NULL.
  expect_equal(out$parameters$value, c(12000, 200))
})
