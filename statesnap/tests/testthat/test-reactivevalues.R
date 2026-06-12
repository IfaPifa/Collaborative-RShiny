# Tests for the reactiveValues capture/restore branch, including the exact
# (non-additive) restore guarantee. Requires shiny for real reactiveValues.

test_that("reactiveValues capture/restore round-trips", {
  skip_if_not_installed("shiny")
  library(shiny)

  shiny::reactiveConsole(TRUE)
  on.exit(shiny::reactiveConsole(FALSE), add = TRUE)

  rv <- reactiveValues(a = 1, b = 2)
  json <- capture_state(list(), store = rv)

  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_equal(parsed$reactives$store$type, "reactiveValues")
  expect_equal(parsed$reactives$store$content$a, 1)
  expect_equal(parsed$reactives$store$content$b, 2)
})

test_that("reactiveValues restore is exact: stale keys are cleared", {
  skip_if_not_installed("shiny")
  library(shiny)

  shiny::reactiveConsole(TRUE)
  on.exit(shiny::reactiveConsole(FALSE), add = TRUE)

  # Checkpoint authored by 'Alice': {a=1, b=2}
  alice <- reactiveValues(a = 1, b = 2)
  json <- capture_state(list(), store = alice)

  # 'Bob' restores into a session that already has different keys.
  bob <- reactiveValues(a = 99, c = 999)
  restore_state(NULL, json, store = bob)

  result <- shiny::reactiveValuesToList(bob)
  # Alice's values are reproduced exactly.
  expect_equal(result$a, 1)
  expect_equal(result$b, 2)
  # Shiny cannot truly delete a reactiveValues key, but the stale key from Bob
  # is cleared to NULL so its value does not leak into the restored state.
  expect_null(result$c)
})
