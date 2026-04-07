library(shiny)
library(bslib)
library(plotly)
library(jsonlite)
library(kafka)
library(shinyjs)
library(shinyWidgets) # Required for the progress bar

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "materia"),
  title = "Eco-ML: Biodiversity Predictor",
  
  sidebar = sidebar(
    title = "Model Configuration",
    selectInput("algo", "Algorithm:", choices = c("Random Forest" = "rf", "Gradient Boosting" = "gbm")),
    sliderInput("trees", "Number of Trees:", min = 50, max = 1000, value = 500),
    sliderInput("mtry", "Feature Subsampling (mtry):", min = 1, max = 5, value = 2),
    hr(),
    actionButton("train_btn", "Train Model on Mesh", class = "btn-primary", icon = icon("microchip")),
    hr(),
    uiOutput("model_stats")
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
    card_header("Mesh Status"),
    progressBar(id = "train_progress", value = 0, display_pct = TRUE, status = "info")
  )
)

server <- function(input, output, session) {
  
  # 1. Dynamically parse the Angular routing URL for collaborative routing
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo_ml_session"
    )
  })
  
  routingKey <- reactive({ identity()$sessionId })
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, 
                          logs = data.frame(epoch = numeric(), mse = numeric()),
                          importance = NULL, running = FALSE)

  # 2. Safely connect to Kafka on boot
  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      
      # Prevent Kafka partition fighting by making group.id unique per user
      s_id <- if(!is.null(query$sessionId)) query$sessionId else "solo"
      u_id <- if(!is.null(query$userId)) query$userId else sample(1000:9999, 1)
      group_name <- paste0("front_ml_", s_id, "_", u_id)
      
      broker <- "kafka:9092"
      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker, 
        "group.id" = group_name,
        "auto.offset.reset" = "latest",
        "enable.auto.commit" = "true"
      ))
      state$consumer$subscribe("output")
      state$producer <- Producer$new(list("bootstrap.servers" = broker))
      state$connected <- TRUE
    }, error = function(e) { print(paste("Kafka Connection Error:", e$message)) })
  })

  # 3. Trigger the asynchronous Machine Learning pipeline
  observeEvent(input$train_btn, {
    req(state$connected)
    state$running <- TRUE
    state$logs <- data.frame(epoch = numeric(), mse = numeric())
    disable("train_btn")
    
    payload <- list(
      command = "TRAIN_MODEL",
      trees = input$trees,
      mtry = input$mtry,
      sender = identity()$userId
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })

  # 4. Consume real-time Kafka epochs safely
  poll_trigger <- reactivePoll(300, session, checkFunc = function() Sys.time(), valueFunc = function() Sys.time())
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    
    tryCatch({
      messages <- state$consumer$consume(100)
      if (length(messages) > 0) {
        for (m in messages) {
          if (!is.null(m$key) && m$key == routingKey()) {
            data <- fromJSON(m$value)
            
            # Safely check for data$type to prevent NULL pointer crashes
            if (!is.null(data$type) && data$type == "EPOCH_UPDATE") {
              
              # FIX: Guard to lock the UI for passive observers
              if (!state$running) {
                state$running <- TRUE
                shinyjs::disable("train_btn")
              }
              
              state$logs <- rbind(state$logs, data.frame(epoch = data$epoch, mse = data$mse))
              updateProgressBar(session, "train_progress", value = data$percent)
              
            } else if (!is.null(data$type) && data$type == "TRAINING_COMPLETE") {
              state$importance <- data$importance
              state$running <- FALSE
              enable("train_btn")
            }
          }
        }
      }
    }, error = function(e) { print(paste("Consumption Error:", e$message)) })
  })

  # 5. Render dynamic UI
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