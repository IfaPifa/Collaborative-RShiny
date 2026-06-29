# Runnable client/server Monte Carlo demo using statesnap.
#
# This wires the frontend logic (frontend.R) to the in-process transport
# (transport.R) and the backend (backend.R), reproducing the request/result
# round-trip of the ShinySwarm REST architecture in a single process:
#
#   [run]  frontend POSTs params -> transport "request"
#          backend reads request, simulates, POSTs statesnap checkpoint
#                                 -> transport "result"
#   [poll] frontend GETs checkpoint, restore_state() -> live reactiveValues
#
# The reproducibility point made visible: the simulation is unseeded, so each
# run differs, yet the frontend always displays exactly what the backend
# computed -- because the computed result is shared, not recomputed.
#
# Run:
#   cd statesnap && Rscript -e \
#     "pkgload::load_all('.'); shiny::runApp('inst/examples/montecarlo-clientserver')"

library(shiny)
library(statesnap)

# Locate the sibling module files. When Shiny runs an app directory it sets the
# working directory to that directory, so the files are alongside this one.
.mc_dir <- if (file.exists("transport.R")) {
  "."
} else {
  "inst/examples/montecarlo-clientserver"
}
source(file.path(.mc_dir, "transport.R"), local = TRUE)
source(file.path(.mc_dir, "backend.R"), local = TRUE)
source(file.path(.mc_dir, "frontend.R"), local = TRUE)

SESSION_ID <- "demo-session"

ui <- fluidPage(
  titlePanel("statesnap - Monte Carlo (client/server)"),
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
      verbatimTextOutput("status")
    ),
    mainPanel(
      h3("Stochastic forecast (restored from backend checkpoint)"),
      plotOutput("sim_plot", height = "420px"),
      h4("Extinction risk (pop < 1 at horizon)"),
      verbatimTextOutput("kpi")
    )
  )
)

server <- function(input, output, session) {
  transport <- mc_transport()
  state  <- reactiveValues(results = NULL)
  status <- reactiveVal("Ready. Click 'Run simulation'.")

  # reactiveVal-style setter that writes into state$results, so restore_state()
  # can apply the backend checkpoint through it.
  results_setter <- function(x) {
    if (missing(x)) state$results else state$results <- x
  }

  observeEvent(input$run_sim, {
    status("Requesting simulation from backend...")

    # 1. Frontend POSTs the request.
    mc_frontend_request(transport, SESSION_ID, list(
      n0 = input$n0, growth_rate = input$growth_rate, env_var = input$env_var,
      paths = input$paths, years = input$years
    ))

    # 2. Backend processes it and posts back a statesnap checkpoint.
    mc_backend_handle(transport, SESSION_ID)

    # 3. Frontend pulls the checkpoint and restores it into state$results.
    applied <- mc_frontend_apply(transport, SESSION_ID, results_setter)
    status(if (applied) {
      "Backend result restored via statesnap (unseeded - differs each run)."
    } else {
      "No result returned."
    })
  })

  output$sim_plot <- renderPlot({
    req(state$results)
    res <- state$results
    yrs   <- unlist(res$years)
    mean_path <- unlist(res$mean_path)
    lower <- unlist(res$lower_95)
    upper <- unlist(res$upper_95)

    plot(yrs, mean_path, type = "n", ylim = range(c(lower, upper)),
         xlab = "Years from present", ylab = "Population size",
         main = "Mean path with 95% confidence band")
    polygon(c(yrs, rev(yrs)), c(upper, rev(lower)),
            col = rgb(0.18, 0.80, 0.44, 0.25), border = NA)
    lines(yrs, mean_path, col = "#27ae60", lwd = 3)
  })

  output$kpi <- renderText({
    req(state$results)
    sprintf("%.2f%%", unlist(state$results$extinction_prob) * 100)
  })

  output$status <- renderText(status())
}

shinyApp(ui, server)
