# Integration test against the real Shiny reactive engine via testServer().
# Skipped automatically if shiny is unavailable.

test_that("save/restore round-trips through a real Shiny server", {
  skip_if_not_installed("shiny")
  library(shiny)

  checkpoint <- tempfile(fileext = ".json")

  server <- function(input, output, session) {
    result <- reactiveVal(0)

    observeEvent(input$calculate, {
      result(input$num1 + input$num2)
    })

    observeEvent(input$save_btn, {
      json <- capture_state(input, result = result)
      writeLines(json, checkpoint)
    })

    observeEvent(input$restore_btn, {
      json <- paste(readLines(checkpoint), collapse = "\n")
      restore_state(session, json, result = result)
    })

    # Expose result for the test harness.
    output$result <- renderText(result())
    exportTestValues(result = result())
  }

  testServer(server, {
    # Compute 42 + 58 = 100 and save it.
    session$setInputs(num1 = 42, num2 = 58)
    session$setInputs(calculate = 1)
    expect_equal(result(), 100)

    session$setInputs(save_btn = 1)
    expect_true(file.exists(checkpoint))

    # Change state to something different.
    session$setInputs(num1 = 1, num2 = 2)
    session$setInputs(calculate = 2)
    expect_equal(result(), 3)

    # Restore: the saved result reactiveVal comes back exactly.
    session$setInputs(restore_btn = 1)
    expect_equal(result(), 100)

    # Inputs were pushed back through the session too.
    saved <- jsonlite::fromJSON(
      paste(readLines(checkpoint), collapse = "\n"),
      simplifyVector = FALSE
    )
    expect_equal(saved$inputs$num1, 42)
    expect_equal(saved$inputs$num2, 58)
  })
})
