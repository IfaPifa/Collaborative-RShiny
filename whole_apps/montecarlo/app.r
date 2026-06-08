library(shiny)
library(bslib)
library(plotly)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "Population Viability Simulator (Monolithic)",

  sidebar = sidebar(
    title = "Ecological Parameters",
    numericInput("n0", "Initial Population:", value = 500, min = 10),
    sliderInput("growth_rate", "Intrinsic Growth Rate (r):",
                min = -0.1, max = 0.1, value = 0.02, step = 0.01),
    sliderInput("env_var", "Environmental Variance:",
                min = 0.01, max = 0.5, value = 0.15, step = 0.01),
    numericInput("paths", "Simulated Trajectories:", value = 5000, min = 1000, step = 1000),
    numericInput("years", "Projection Years:", value = 50, min = 10),
    actionButton("run_sim", "Run Simulation", class = "btn-success", icon = icon("leaf")),
    hr(),
    uiOutput("status_ui"),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
  ),

  card(
    card_header("Mesh Compute Status"),
    uiOutput("progress_container")
  ),

  card(
    card_header("Stochastic Trajectory Forecast"),
    plotlyOutput("sim_plot"),
    card_footer(uiOutput("kpi_footer"))
  )
)

server <- function(input, output, session) {

  state <- reactiveValues(status = "IDLE", progress = 0, results = NULL)

  observeEvent(input$run_sim, {
    state$status <- "RUNNING"
    state$progress <- 50
    state$results <- NULL

    # Inline backend logic: stochastic population simulation
    n0 <- input$n0
    r <- input$growth_rate
    K <- n0 * 10
    sigma <- input$env_var
    n_paths <- input$paths
    n_years <- input$years

    all_paths <- matrix(0, nrow = n_paths, ncol = n_years + 1)
    all_paths[, 1] <- n0

    for (t in 2:(n_years + 1)) {
      noise <- rnorm(n_paths, mean = 0, sd = sigma)
      growth <- r * all_paths[, t - 1] * (1 - all_paths[, t - 1] / K)
      all_paths[, t] <- pmax(0, all_paths[, t - 1] + growth + noise * all_paths[, t - 1])
    }

    mean_path <- colMeans(all_paths)
    lower_95 <- apply(all_paths, 2, quantile, probs = 0.025)
    upper_95 <- apply(all_paths, 2, quantile, probs = 0.975)
    extinction_prob <- mean(all_paths[, n_years + 1] < 1)

    samples <- all_paths[sample(n_paths, min(3, n_paths)), ]

    state$results <- list(
      years = 0:n_years,
      mean_path = mean_path,
      lower_95 = lower_95,
      upper_95 = upper_95,
      sample_1 = samples[1, ],
      sample_2 = if (nrow(samples) >= 2) samples[2, ] else samples[1, ],
      sample_3 = if (nrow(samples) >= 3) samples[3, ] else samples[1, ],
      extinction_prob = extinction_prob
    )

    state$status <- "COMPLETE"
    state$progress <- 100
  })

  output$status_ui <- renderUI({
    color <- ifelse(state$status == "RUNNING", "color: #e67e22;", "color: #27ae60;")
    p("Status: ", strong(state$status, style = color))
  })

  output$progress_container <- renderUI({
    if (state$status == "IDLE") return(p("Awaiting simulation parameters..."))
    HTML(sprintf('
      <div class="progress" style="height: 25px;">
        <div class="progress-bar progress-bar-striped %s bg-success"
             role="progressbar" style="width: %s%%;">
             %s%%
        </div>
      </div>
    ', ifelse(state$status == "RUNNING", "progress-bar-animated", ""),
       state$progress, state$progress))
  })

  output$sim_plot <- renderPlotly({
    req(state$results)
    res <- state$results

    plot_ly(x = ~res$years) %>%
      add_ribbons(ymin = ~res$lower_95, ymax = ~res$upper_95,
                  name = "95% Confidence",
                  line = list(color = "rgba(46, 204, 113, 0.2)"),
                  fillcolor = "rgba(46, 204, 113, 0.2)") %>%
      add_lines(y = ~res$sample_1, name = "Sample 1",
                line = list(color = "rgba(189, 195, 199, 0.6)", width = 1)) %>%
      add_lines(y = ~res$sample_2, name = "Sample 2",
                line = list(color = "rgba(189, 195, 199, 0.6)", width = 1)) %>%
      add_lines(y = ~res$sample_3, name = "Sample 3",
                line = list(color = "rgba(189, 195, 199, 0.6)", width = 1)) %>%
      add_lines(y = ~res$mean_path, name = "Mean Population",
                line = list(color = "#27ae60", width = 3)) %>%
      layout(
        xaxis = list(title = "Years from Present"),
        yaxis = list(title = "Population Size"),
        hovermode = "x unified"
      )
  })

  output$kpi_footer <- renderUI({
    req(state$results)
    ext_risk <- round(state$results$extinction_prob * 100, 2)
    HTML(sprintf(
      "<strong>Extinction Risk (Pop < 1):</strong> <span style='color: %s;'>%s%%</span>",
      ifelse(ext_risk > 5, "red", "green"), ext_risk
    ))
  })
}

shinyApp(ui = ui, server = server)
