# End-to-end proofs against the real Shiny reactive engine that a modular app
# round-trips. Two complementary scenarios:
#
#   1. Capture/restore *inside* a module needs no special handling: Shiny scopes
#      the module's `input` to local names and auto-namespaces the module
#      session's sendInputMessage(), so statesnap works untouched (ns = NULL).
#   2. Capture *from the parent/root session* sees fully-qualified names
#      (mod-num1); the `ns` argument slices one module's state out and
#      re-qualifies it on restore.
#
# Skipped if shiny is unavailable.

test_that("a module round-trips untouched, no ns needed (local input scope)", {
  skip_if_not_installed("shiny")
  library(shiny)

  checkpoint <- tempfile(fileext = ".json")

  calc_server <- function(id) {
    moduleServer(id, function(input, output, session) {
      total <- reactiveVal(0)
      observeEvent(input$calculate, total(input$num1 + input$num2))
      observeEvent(input$save_btn, {
        # No ns: inside a module, input is already local-scoped.
        writeLines(capture_state(input, total = total), checkpoint)
      })
      observeEvent(input$restore_btn, {
        json <- paste(readLines(checkpoint), collapse = "\n")
        restore_state(session, json, total = total)
      })
    })
  }

  testServer(calc_server, args = list(id = "calc"), {
    session$setInputs(num1 = 42, num2 = 58, calculate = 1)
    expect_equal(total(), 100)

    session$setInputs(save_btn = 1)
    expect_true(file.exists(checkpoint))

    # The module captured its inputs under their local names.
    saved <- jsonlite::fromJSON(
      paste(readLines(checkpoint), collapse = "\n"), simplifyVector = FALSE
    )
    expect_true(all(c("num1", "num2") %in% names(saved$inputs)))
    expect_null(saved$ns)

    # Mutate, then restore: the computed value comes back exactly.
    session$setInputs(num1 = 1, num2 = 2, calculate = 2)
    expect_equal(total(), 3)
    session$setInputs(restore_btn = 1)
    expect_equal(total(), 100)
  })
})

test_that("ns slices a child module's state from the parent session", {
  skip_if_not_installed("shiny")
  library(shiny)

  checkpoint <- tempfile(fileext = ".json")

  app_server <- function(input, output, session) {
    # A parent-level control snapshots just the 'calc' child module.
    observeEvent(input$save_all, {
      writeLines(capture_state(input, ns = "calc"), checkpoint)
    })
  }

  testServer(app_server, {
    # Parent session sees fully-qualified child input names.
    session$setInputs(`calc-num1` = 42, `calc-num2` = 58)
    session$setInputs(`other-z` = 7)
    session$setInputs(save_all = 1)

    saved <- jsonlite::fromJSON(
      paste(readLines(checkpoint), collapse = "\n"), simplifyVector = FALSE
    )
    # Only the calc module, stored under local names.
    expect_named(saved$inputs, c("num1", "num2"), ignore.order = TRUE)
    expect_equal(saved$ns, "calc-")
    expect_equal(saved$inputs$num1, 42)
  })
})

test_that("a parent-captured slice restores re-qualified, into any module id", {
  skip_if_not_installed("shiny")
  library(shiny)

  # Capture slice for module 'calc' from a literal parent input map.
  parent_input <- list(`calc-num1` = 42, `calc-num2` = 58, `other-z` = 7)
  json <- capture_state(parent_input, ns = "calc")

  # Restore into the same id.
  sess <- fake_session()
  restore_state(sess, json)
  expect_equal(sess$sent()$`calc-num1`, 42)
  expect_equal(sess$sent()$`calc-num2`, 58)

  # Restore re-targeted into a differently-named module.
  sess2 <- fake_session()
  restore_state(sess2, json, ns = "calc2")
  expect_equal(sess2$sent()$`calc2-num1`, 42)
  expect_null(sess2$sent()$`calc-num1`)
})
