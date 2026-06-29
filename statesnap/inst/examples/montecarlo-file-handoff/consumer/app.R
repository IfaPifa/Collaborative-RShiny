# CONSUMER app (right window in the demo).
#
# A completely separate app instance that shares NOTHING with the producer
# except the checkpoint file on disk. It does not run any simulation; it only
# reads the file and restore_state()s into its own state -- reproducing exactly
# what the producer computed.

library(shiny)
library(statesnap)

src <- if (file.exists("../sim.R")) "../sim.R" else
  "inst/examples/montecarlo-file-handoff/sim.R"
source(src, local = TRUE)

CHECKPOINT <- mc_checkpoint_path()

ui <- fluidPage(
  tags$head(tags$style(HTML("body{background:#f3f6fb}"))),
  titlePanel("CONSUMER - Monte Carlo (loads state from file)"),
  sidebarLayout(
    sidebarPanel(
      p("This app runs no simulation. It restores the producer's state."),
      actionButton("load_btn", "Load from file", class = "btn-primary"),
      actionButton("refresh", "Check file"),
      tags$hr(),
      verbatimTextOutput("status")
    ),
    mainPanel(
      h3("Restored forecast"),
      plotOutput("sim_plot", height = "380px"),
      h4("Extinction risk"),
      verbatimTextOutput("kpi"),
      tags$small(textOutput("path"))
    )
  )
)

server <- function(input, output, session) {
  state  <- reactiveValues(results = NULL)
  status <- reactiveVal("Waiting. Save in the producer, then click 'Load from file'.")

  # reactiveVal-style setter so restore_state() can write into state$results.
  setter <- function(x) if (missing(x)) state$results else state$results <- x

  observeEvent(input$load_btn, {
    if (!file.exists(CHECKPOINT)) {
      status("No checkpoint file yet - save one in the producer first.")
      return()
    }
    json <- paste(readLines(CHECKPOINT), collapse = "\n")
    restore_state(session, json, results = setter)
    status("Restored producer's state from file via statesnap.")
  })

  observeEvent(input$refresh, {
    status(if (file.exists(CHECKPOINT))
      "Checkpoint file is present - click 'Load from file'." else
      "No checkpoint file yet.")
  })

  output$sim_plot <- renderPlot({ req(state$results); mc_plot(state$results, "Restored from producer") })
  output$kpi <- renderText({ req(state$results)
    sprintf("%.2f%%", as.numeric(unlist(state$results$extinction_prob)) * 100) })
  output$status <- renderText(status())
  output$path <- renderText(paste("Checkpoint file:", CHECKPOINT))
}

shinyApp(ui, server)
