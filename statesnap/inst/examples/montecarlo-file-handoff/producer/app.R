# PRODUCER app (left window in the demo).
#
# Runs the stochastic simulation and SAVES a statesnap checkpoint to a shared
# file. The consumer app reads that same file. Record both windows side by side:
#   1. Click "Run simulation"  -> a forecast appears (changes every run, no seed)
#   2. Click "Save checkpoint to file"
#   3. Switch to the consumer window and click "Load from file"
#      -> the consumer shows the identical forecast.

library(shiny)
library(statesnap)

src <- if (file.exists("../sim.R")) "../sim.R" else
  "inst/examples/montecarlo-file-handoff/sim.R"
source(src, local = TRUE)

CHECKPOINT <- mc_checkpoint_path()

ui <- fluidPage(
  tags$head(tags$style(HTML("body{background:#f3fbf6}"))),
  titlePanel("PRODUCER - Monte Carlo (saves state to file)"),
  sidebarLayout(
    sidebarPanel(
      numericInput("n0", "Initial population", value = 500, min = 10),
      sliderInput("growth_rate", "Growth rate (r)", min = -0.1, max = 0.1,
                  value = 0.02, step = 0.01),
      sliderInput("env_var", "Environmental variance", min = 0.01, max = 0.5,
                  value = 0.15, step = 0.01),
      numericInput("paths", "Trajectories", value = 2000, min = 100, step = 100),
      numericInput("years", "Projection years", value = 30, min = 5),
      actionButton("run_sim", "Run simulation", class = "btn-success"),
      tags$hr(),
      actionButton("save_btn", "Save checkpoint to file", class = "btn-primary"),
      tags$hr(),
      verbatimTextOutput("status")
    ),
    mainPanel(
      h3("Stochastic forecast"),
      plotOutput("sim_plot", height = "380px"),
      h4("Extinction risk"),
      verbatimTextOutput("kpi"),
      tags$small(textOutput("path"))
    )
  )
)

server <- function(input, output, session) {
  state  <- reactiveValues(results = NULL)
  status <- reactiveVal("Ready. Click 'Run simulation'.")

  observeEvent(input$run_sim, {
    state$results <- mc_simulate(input$n0, input$growth_rate, input$env_var,
                                 input$paths, input$years)
    status("Simulation run (unseeded - differs every time).")
  })

  observeEvent(input$save_btn, {
    req(state$results)
    json <- capture_state(input, results = state$results)
    writeLines(json, CHECKPOINT)
    status(paste0("Saved checkpoint (", nchar(json), " bytes). ",
                  "Now load it in the consumer window."))
  })

  output$sim_plot <- renderPlot({ req(state$results); mc_plot(state$results, "Producer forecast") })
  output$kpi <- renderText({ req(state$results)
    sprintf("%.2f%%", as.numeric(unlist(state$results$extinction_prob)) * 100) })
  output$status <- renderText(status())
  output$path <- renderText(paste("Checkpoint file:", CHECKPOINT))
}

shinyApp(ui, server)
