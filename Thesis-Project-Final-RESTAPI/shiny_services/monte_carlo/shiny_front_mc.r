library(shiny)
library(bslib)
library(plotly)
library(httr)
library(jsonlite)
library(shinyjs)

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "minty"),
  title = "Population Viability Simulator (REST API)",
  
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
  
  spring_api_base <- "http://spring-backend:8085/api/collab"
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo",
      permission = if (!is.null(query$permission)) query$permission else "EDITOR"
    )
  })
  
  state <- reactiveValues(
    status = "IDLE", progress = 0, results = NULL, last_timestamp = 0
  )

  output$connection_status <- renderText({ "HTTP GET/POST" })

  # --- POST simulation request to Spring Boot ---
  observeEvent(input$run_sim, {
    id <- identity()
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
      sender = id$userId,
      appName = "MonteCarlo"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      res <- httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(30)
      )
      
      if (httr::status_code(res) == 200) {
        state$status <- "COMPLETE"
        state$progress <- 100
      } else {
        state$status <- "ERROR"
        enable("run_sim")
      }
    }, error = function(e) {
      state$status <- "ERROR"
      print(paste("POST Error:", e$message))
      enable("run_sim")
    })
  })
  
  # --- Poll Spring Boot for results every 500ms ---
  poll_trigger <- reactiveTimer(500)
  
  observe({
    poll_trigger()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      res <- httr::GET(get_url, httr::timeout(2))
      if (httr::status_code(res) == 200) {
        raw_text <- httr::content(res, "text", encoding = "UTF-8")
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)
          
          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            
            if (!is.null(data$type) && data$type == "RESULT") {
              state$results <- data
              state$status <- "COMPLETE"
              state$progress <- 100
              enable("run_sim")
            }
          }
        }
      }
    }, error = function(e) {
      # Fail silently
    })
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
    
    plot_ly(x = ~res$years) %>%
      add_ribbons(ymin = ~res$lower_95, ymax = ~res$upper_95, 
                  name = "95% Confidence", line = list(color = 'rgba(46, 204, 113, 0.2)'), fillcolor = 'rgba(46, 204, 113, 0.2)') %>%
      add_lines(y = ~res$sample_1, name = "Sample Trajectory 1", line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$sample_2, name = "Sample Trajectory 2", line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$sample_3, name = "Sample Trajectory 3", line = list(color = 'rgba(189, 195, 199, 0.6)', width = 1)) %>%
      add_lines(y = ~res$mean_path, name = "Mean Population", line = list(color = '#27ae60', width = 3)) %>%
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
