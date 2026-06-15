# Namespace-aware capture/restore: a modular Shiny app's namespaced inputs
# (mod-num1) are captured under their local names (num1) and re-qualified on
# restore, so an unmodified module round-trips without a model layer.

test_that("ns filters to one module and stores local names", {
  input <- list(
    `mod-num1` = 42,
    `mod-num2` = 58,
    `other-x`  = 1,
    top        = 99
  )
  json <- capture_state(input, ns = "mod")
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_named(parsed$inputs, c("num1", "num2"))
  expect_equal(parsed$inputs$num1, 42)
  expect_equal(parsed$inputs$num2, 58)
  expect_equal(parsed$ns, "mod-")
})

test_that("ns accepts a namespace function (shiny::NS style)", {
  ns <- function(id = "") paste0("calc-", id)   # mimics shiny::NS("calc")
  input <- list(`calc-a` = 1, `calc-b` = 2, `zz-c` = 3)
  json <- capture_state(input, ns = ns)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_named(parsed$inputs, c("a", "b"))
  expect_equal(parsed$ns, "calc-")
})

test_that("restore re-qualifies names back into the captured namespace", {
  input <- list(`mod-num1` = 42, `mod-num2` = 58)
  json <- capture_state(input, ns = "mod")

  sess <- fake_session()
  restore_state(sess, json)

  # Pushed back under the fully-qualified names, not the local ones.
  expect_equal(sess$sent()$`mod-num1`, 42)
  expect_equal(sess$sent()$`mod-num2`, 58)
  expect_null(sess$sent()$num1)
})

test_that("restore can re-target a different module id", {
  input <- list(`mod-num1` = 42)
  json <- capture_state(input, ns = "mod")

  sess <- fake_session()
  restore_state(sess, json, ns = "other")

  expect_equal(sess$sent()$`other-num1`, 42)
  expect_null(sess$sent()$`mod-num1`)
})

test_that("ns = NULL preserves verbatim behaviour", {
  input <- list(`mod-num1` = 42, top = 7)
  json <- capture_state(input)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_named(parsed$inputs, c("mod-num1", "top"))
  expect_null(parsed$ns)

  sess <- fake_session()
  restore_state(sess, json)
  expect_equal(sess$sent()$`mod-num1`, 42)
  expect_equal(sess$sent()$top, 7)
})

test_that("a trailing-separator module id is not doubled", {
  input <- list(`mod-x` = 1)
  json <- capture_state(input, ns = "mod-")
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_equal(parsed$ns, "mod-")
  expect_named(parsed$inputs, "x")
})

test_that("namespaced capture still carries data.frame inputs", {
  df <- data.frame(a = 1:2, b = c("x", "y"), stringsAsFactors = FALSE)
  input <- list(`mod-tbl` = df, `mod-n` = 5)
  json <- capture_state(input, ns = "mod")

  sess <- fake_session()
  restore_state(sess, json)
  expect_equal(sess$sent()$`mod-tbl`, df)
  expect_equal(sess$sent()$`mod-n`, 5)
})

test_that("invalid ns is rejected", {
  expect_error(capture_state(list(), ns = c("a", "b")), "ns must be")
  expect_error(capture_state(list(), ns = 1L), "ns must be")
})
