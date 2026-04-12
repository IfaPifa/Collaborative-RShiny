library(shiny)
library(bslib)
library(plotly)
library(jsonlite)
library(kafka)
library(shinyjs)

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "minty"), # Ecological, clean green theme
  title = "Population Viability Simulator",
  
  sidebar = sidebar(
    title = "Ecological Parameters",
    numericInput("n0", "Initial Population:", value = 500, min = 10),
    sliderInput("growth_rate", "Intrinsic Growth Rate (r):", min = -0.1, max = 0.1, value = 0.02, step = 0.01),
    sliderInput("env_var", "Environmental Variance:", min = 0.01, max = 0.5, value = 0.15, step = 0.01),
    numericInput("paths", "Simulated Trajectories:", value = 5000, min = 1000, step = 1000),
    numericInput("years", "Projection Years:", value = 50, min = 10),
    actionButton("run_sim", "Launch Swarm Compute", class = "btn-success", icon = icon("leaf")),
    hr(),
    uiOutput("status_ui")
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
  
  identity <- reactive({ list(userId = "researcher_01", sessionId = "session_eco_mc") }) 
  routingKey <- reactive({ identity()$sessionId })
  
  state <- reactiveValues(
    connected = FALSE, consumer = NULL, producer = NULL, 
    status = "IDLE", progress = 0, results = NULL
  )
  
  observe({
    if (state$connected) return()
    broker <- "kafka:9092"
    state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = paste0("front_eco_", sample(10000:99999, 1)), "auto.offset.reset" = "latest"))
    state$consumer$subscribe("output")
    state$producer <- Producer$new(list("bootstrap.servers" = broker))
    state$connected <- TRUE
  })

  observeEvent(input$run_sim, {
    req(state$connected)
    state$status <- "RUNNING"
    state$progress <- 0
    state$results <- NULL
    disable("run_sim") 
    
    payload <- list(
      command = "START_SIMULATION",
      n0 = input$n0,
      growth_rate = input$growth_rate,
      env_var = input$env_var,
      paths = input$paths,
      years = input$years,
      sender = identity()$userId
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })
  
  poll_trigger <- reactivePoll(200, session, checkFunc = function() { as.numeric(Sys.time()) }, valueFunc = function() { as.numeric(Sys.time()) })
  
  observe({
    poll_trigger()
    req(state$connected)
    messages <- state$consumer$consume(100)
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$type) && data$type == "PROGRESS") {
            state$progress <- data$percent
          } else if (!is.null(data$type) && data$type == "RESULT") {
            state$progress <- 100
            state$status <- "COMPLETE"
            state$results <- data
            enable("run_sim")
          }
        }
      }
    }
  })

  output$status_ui <- renderUI({
    p("Mesh Status: ", strong(state$status, style = ifelse(state$status == "RUNNING", "color: #e67e22;", "color: #27ae60;")))
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
    
    p <- plot_ly(x = ~res$years) %>%
      # 95% Confidence Band
      add_ribbons(ymin = ~res$lower_95, ymax = ~res$upper_95, 
                  name = "95% Confidence", line = list(color = 'rgba(46, 204, 113, 0.2)'), fillcolor = 'rgba(46, 204, 113, 0.2)') %>%
      # Sample paths (to show the random noise)
      add_lines(y = ~res$sample_1, name = "Sample Trajectory 1", line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$sample_2, name = "Sample Trajectory 2", line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$sample_3, name = "Sample Trajectory 3", line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      # Mean path
      add_lines(y = ~res$mean_path, name = "Mean Population", line = list(color = '#27ae60', width = 3)) %>%
      layout(
        xaxis = list(title = "Years from Present"),
        yaxis = list(title = "Population Size"),
        hovermode = "x unified"
      )
    p
  })
  
  output$kpi_footer <- renderUI({
    req(state$results)
    ext_risk <- round(state$results$extinction_prob * 100, 2)
    HTML(sprintf("<strong>Extinction Risk (Pop < 1):</strong> <span style='color: %s;'>%s%%</span>", 
                 ifelse(ext_risk > 5, "red", "green"), ext_risk))
  })
}

shinyApp(ui = ui, server = server)