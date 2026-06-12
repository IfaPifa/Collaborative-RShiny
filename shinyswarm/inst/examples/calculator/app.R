# Calculator demo for the shinyswarm package.
#
# Shows the full-state save/restore pattern from the thesis: the app saves a
# checkpoint with capture_state(), the user changes inputs, then restore_state()
# brings the saved state back exactly. Transport here is a local file, but the
# same JSON could go to REST, Kafka, Redis, or a database unchanged.

library(shiny)
library(shinyswarm)

CHECKPOINT <- file.path(tempdir(), "calculator-checkpoint.json")

ui <- fluidPage(
  titlePanel("shinyswarm - Calculator demo"),
  sidebarLayout(
    sidebarPanel(
      numericInput("num1", "Number 1", value = 10),
      numericInput("num2", "Number 2", value = 5),
      actionButton("calculate", "Calculate", class = "btn-primary"),
      tags$hr(),
      actionButton("save_btn", "Save checkpoint"),
      actionButton("restore_btn", "Restore checkpoint"),
      tags$hr(),
      verbatimTextOutput("status")
    ),
    mainPanel(
      h3("Result"),
      verbatimTextOutput("result"),
      h4("Last captured JSON"),
      verbatimTextOutput("json")
    )
  )
)

server <- function(input, output, session) {
  result <- reactiveVal(0)
  last_json <- reactiveVal("(none yet)")
  status <- reactiveVal("Ready.")

  observeEvent(input$calculate, {
    result(input$num1 + input$num2)
  })

  output$result <- renderText(result())
  output$json <- renderText(last_json())
  output$status <- renderText(status())

  # Save: capture inputs + the computed result in one call.
  observeEvent(input$save_btn, {
    json <- capture_state(input, result = result)
    writeLines(json, CHECKPOINT)        # transport = local file
    last_json(json)
    status(paste("Saved checkpoint to", CHECKPOINT))
  })

  # Restore: read the checkpoint and push everything back.
  observeEvent(input$restore_btn, {
    if (!file.exists(CHECKPOINT)) {
      status("No checkpoint saved yet.")
      return()
    }
    json <- paste(readLines(CHECKPOINT), collapse = "\n")
    restore_state(session, json, result = result)
    status("Restored checkpoint - inputs and result match the saved state.")
  })
}

shinyApp(ui, server)
