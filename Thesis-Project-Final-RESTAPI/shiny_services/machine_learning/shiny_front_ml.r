library(shiny)
library(bslib)
library(plotly)
library(httr)
library(jsonlite)
library(shinyjs)

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "materia"),
  title = "Eco-ML: Biodiversity Predictor (REST API)",
  
  sidebar = sidebar(
    title = "Model Configuration",
    selectInput("algo", "Algorithm:", choices = c("Random Forest" = "rf", "Gradient Boosting" = "gbm")),
    sliderInput("trees", "Number of Trees:", min = 50, max = 1000, value = 500),
    sliderInput("mtry", "Feature Subsampling (mtry):", min = 1, max = 5, value = 2),
    hr(),
    actionButton("train_btn", "Train Model on Mesh", class = "btn-primary", icon = icon("microchip")),
    hr(),
    uiOutput("status_ui"),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  layout_columns(
    card(
      card_header("Training Convergence"),
      plotlyOutput("loss_plot", height = "350px")
    ),
    card(
      card_header("Feature Importance"),
      plotlyOutput("importance_plot", height = "350px")
    )
  ),
  
  card(
    card_header("Mesh Compute Status"),
    uiOutput("progress_container")
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
    status = "IDLE", progress = 0, last_timestamp = 0,
    logs = data.frame(epoch = numeric(), mse = numeric()),
    importance = NULL
  )

  output$connection_status <- renderText({ "HTTP GET/POST" })

  # --- POST training request to Spring Boot ---
  observeEvent(input$train_btn, {
    id <- identity()
    state$status <- "RUNNING"
    state$progress <- 50
    state$logs <- data.frame(epoch = numeric(), mse = numeric())
    state$importance <- NULL
    disable("train_btn")
    
    payload <- list(
      command = "TRAIN_MODEL",
      trees = input$trees,
      mtry = input$mtry,
      sender = id$userId,
      appName = "MLTrainer"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      res <- httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(60)
      )
      
      if (httr::status_code(res) == 200) {
        state$status <- "COMPLETE"
        state$progress <- 100
      } else {
        state$status <- "ERROR"
        enable("train_btn")
      }
    }, error = function(e) {
      state$status <- "ERROR"
      print(paste("POST Error:", e$message))
      enable("train_btn")
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
            
            if (!is.null(data$type) && data$type == "TRAINING_COMPLETE") {
              state$importance <- data$importance
              state$status <- "COMPLETE"
              state$progress <- 100
              enable("train_btn")
              
              # Build epoch log from the response
              if (!is.null(data$epoch_log)) {
                log_df <- do.call(rbind, lapply(data$epoch_log, as.data.frame))
                state$logs <- log_df
              }
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
    if (state$status == "IDLE") return(p("Awaiting model configuration..."))
    HTML(sprintf('
      <div class="progress" style="height: 25px;">
        <div class="progress-bar progress-bar-striped progress-bar-animated bg-info" 
             role="progressbar" style="width: %s%%;">
             %s%%
        </div>
      </div>
    ', state$progress, state$progress))
  })

  output$loss_plot <- renderPlotly({
    req(nrow(state$logs) > 0)
    plot_ly(state$logs, x = ~epoch, y = ~mse, type = 'scatter', mode = 'lines+markers', name = 'MSE') %>%
      layout(yaxis = list(title = "Mean Squared Error"), xaxis = list(title = "Tree Iterations"))
  })

  output$importance_plot <- renderPlotly({
    req(state$importance)
    df <- data.frame(Feature = names(state$importance), Value = as.numeric(state$importance))
    plot_ly(df, x = ~Value, y = ~reorder(Feature, Value), type = 'bar', orientation = 'h') %>%
      layout(xaxis = list(title = "Importance Score"), yaxis = list(title = ""))
  })
}

shinyApp(ui, server)
