library(shiny)
library(bslib)
library(plotly)
library(jsonlite)
library(kafka)
library(shinyjs)

# Tunable polling parameters (override via env vars in K8s ConfigMap)
POLL_INTERVAL_MS  <- as.integer(Sys.getenv("POLL_INTERVAL_MS", "150"))
CONSUME_TIMEOUT_MS <- as.integer(Sys.getenv("CONSUME_TIMEOUT_MS", "50"))

ui <- page_sidebar(
  useShinyjs(),

  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),

  theme = bs_theme(version = 5, preset = "minty"),
  title = "Population Viability Simulator (Kafka)",

  sidebar = sidebar(
    title = "Ecological Parameters",
    numericInput("n0", "Initial Population:", value = 500, min = 10),
    sliderInput("growth_rate", "Intrinsic Growth Rate (r):", min = -0.1, max = 0.1, value = 0.02, step = 0.01),
    sliderInput("env_var", "Environmental Variance:", min = 0.01, max = 0.5, value = 0.15, step = 0.01),
    numericInput("paths", "Simulated Trajectories:", value = 5000, min = 1000, step = 1000),
    numericInput("years", "Projection Years:", value = 50, min = 10),
    actionButton("run_sim", "Launch Swarm Compute", class = "btn-success", icon = icon("leaf")),
    hr(),
    uiOutput("status_ui"),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),

  layout_columns(
    col_widths = c(12),
    card(
      card_header("Mesh Compute Status"),
      uiOutput("progress_container")
    )
  ),

  card(
    card_header("Stochastic Trajectory Forecast"),
    plotlyOutput("sim_plot"),
    card_footer(uiOutput("kpi_footer"))
  )
)

server <- function(input, output, session) {

  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })

  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId) && id$sessionId != "solo") return(id$sessionId)
    return(id$userId)
  })

  state <- reactiveValues(
    connected = FALSE, consumer = NULL, producer = NULL,
    permission = "EDITOR", last_sender = NULL,
    status = "IDLE", progress = 0, results = NULL
  )

  # --- DYNAMIC ROLE UPDATES FROM ANGULAR ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
      enable("run_sim"); enable("n0")
    } else {
      state$producer <- NULL
      disable("run_sim"); disable("n0")
    }
  })

  observe({
    if (state$permission == "VIEWER") {
      disable("run_sim"); disable("n0")
    } else {
      enable("run_sim"); enable("n0")
    }
  })

  # --- KAFKA CONNECTION ---
  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"

      broker <- "kafka:9092"
      consumer_group <- paste0("front_mc_", session$token)

      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker,
        "group.id" = consumer_group,
        "auto.offset.reset" = "latest",
        "enable.auto.commit" = "true",
        "max.poll.interval.ms" = "600000"
      ))
      state$consumer$subscribe("output")

      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) {
      print(e$message)
      invalidateLater(5000, session)
    })
  })

  output$connection_status <- renderText({ "\U0001f7e2 System Online" })

  # --- SEND SIMULATION REQUEST ---
  observeEvent(input$run_sim, {
    req(state$connected)
    if (is.null(state$producer) || state$permission == "VIEWER") return()

    state$status <- "RUNNING"
    state$progress <- 50
    state$results <- NULL
    disable("run_sim")

    payload <- list(
      command = "START_SIMULATION",
      n0 = input$n0,
      growth_rate = input$growth_rate,
      env_var = input$env_var,
      paths = input$paths,
      years = input$years,
      sender = identity()$userId,
      role = state$permission,
      appName = "MonteCarlo"
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })

  # --- RECEIVE UPDATES ---
  poll_trigger <- reactivePoll(POLL_INTERVAL_MS, session,
    checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); return(as.numeric(Sys.time())) },
    valueFunc = function() { return(as.numeric(Sys.time())) }
  )

  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    result <- state$consumer$consume(CONSUME_TIMEOUT_MS)
    msg <- result_message(result)

    if (!result_has_error(result) && !is.null(msg$value)) {
      if (!is.null(msg$key) && msg$key == routingKey()) {
        data <- fromJSON(msg$value)
        if (!is.null(data$appName) && data$appName != "MonteCarlo") return()

        if (!is.null(data$type) && data$type == "RESULT") {
          state$results <- data
          state$status <- "COMPLETE"
          state$progress <- 100
          state$last_sender <- if (!is.null(data$sender)) data$sender else "System"
          enable("run_sim")
        }
      }
    }
  })

  # --- UI RENDERERS ---
  output$status_ui <- renderUI({
    p("Mesh Status: ", strong(state$status,
      style = ifelse(state$status == "RUNNING", "color: #e67e22;", "color: #27ae60;")))
  })

  output$progress_container <- renderUI({
    if (state$status == "IDLE") return(p("Awaiting simulation parameters..."))
    HTML(sprintf('
      <div class="progress" style="height: 25px;">
        <div class="progress-bar progress-bar-striped progress-bar-animated bg-success"
             role="progressbar" style="width: %s%%;">
             %s%%
        </div>
      </div>
    ', state$progress, state$progress))
  })

  output$sim_plot <- renderPlotly({
    req(state$results)
    res <- state$results

    plot_ly(x = ~res$years) %>%
      add_ribbons(ymin = ~res$lower_95, ymax = ~res$upper_95,
                  name = "95% Confidence", line = list(color = 'rgba(46, 204, 113, 0.2)'),
                  fillcolor = 'rgba(46, 204, 113, 0.2)') %>%
      add_lines(y = ~res$sample_1, name = "Sample Trajectory 1",
                line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$sample_2, name = "Sample Trajectory 2",
                line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$sample_3, name = "Sample Trajectory 3",
                line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$mean_path, name = "Mean Population",
                line = list(color = '#27ae60', width = 3)) %>%
      layout(
        xaxis = list(title = "Years from Present"),
        yaxis = list(title = "Population Size"),
        hovermode = "x unified"
      )
  })

  output$kpi_footer <- renderUI({
    req(state$results)
    ext_risk <- round(state$results$extinction_prob * 100, 2)
    HTML(sprintf("<strong>Extinction Risk (Pop < 1):</strong> <span style='color: %s;'>%s%%</span>",
                 ifelse(ext_risk > 5, "red", "green"), ext_risk))
  })
}

shinyApp(ui = ui, server = server)
