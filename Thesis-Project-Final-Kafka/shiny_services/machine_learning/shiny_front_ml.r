library(shiny)
library(bslib)
library(plotly)
library(jsonlite)
library(kafka)
library(shinyjs)

ui <- page_sidebar(
  useShinyjs(),

  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),

  theme = bs_theme(version = 5, preset = "materia"),
  title = "Eco-ML: Biodiversity Predictor (Kafka)",

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
    status = "IDLE", progress = 0,
    logs = data.frame(epoch = numeric(), mse = numeric()),
    importance = NULL
  )

  # --- DYNAMIC ROLE UPDATES FROM ANGULAR ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
      enable("algo"); enable("trees"); enable("mtry"); enable("train_btn")
    } else {
      state$producer <- NULL
      disable("algo"); disable("trees"); disable("mtry"); disable("train_btn")
    }
  })

  observe({
    if (state$permission == "VIEWER") {
      disable("algo"); disable("trees"); disable("mtry"); disable("train_btn")
    } else {
      enable("algo"); enable("trees"); enable("mtry"); enable("train_btn")
    }
  })

  # --- KAFKA CONNECTION ---
  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"

      broker <- "kafka:9092"
      consumer_group <- paste0("front_ml_", session$token)

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

  # --- SEND TRAINING REQUEST ---
  observeEvent(input$train_btn, {
    req(state$connected)
    if (is.null(state$producer) || state$permission == "VIEWER") return()

    state$status <- "RUNNING"
    state$progress <- 5
    disable("train_btn")

    payload <- list(
      command = "TRAIN_MODEL",
      trees = input$trees,
      mtry = input$mtry,
      algo = input$algo,
      sender = identity()$userId,
      role = state$permission,
      appName = "MLTrainer"
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })

  # --- RECEIVE UPDATES ---
  poll_trigger <- reactivePoll(200, session,
    checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); return(as.numeric(Sys.time())) },
    valueFunc = function() { return(as.numeric(Sys.time())) }
  )

  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    result <- state$consumer$consume(10)
    msg <- result_message(result)

    if (!result_has_error(result) && !is.null(msg$value)) {
      if (!is.null(msg$key) && msg$key == routingKey()) {
        data <- fromJSON(msg$value)
        if (!is.null(data$appName) && data$appName != "MLTrainer") return()

        if (!is.null(data$type) && data$type == "TRAINING_COMPLETE") {
          if (!is.null(data$status)) state$status <- data$status
          if (!is.null(data$importance)) state$importance <- data$importance
          state$progress <- 100

          if (!is.null(data$logs)) {
            el <- data$logs
            if (is.data.frame(el)) {
              state$logs <- el
            } else if (is.list(el)) {
              state$logs <- do.call(rbind, lapply(el, as.data.frame))
            }
          }

          state$last_sender <- if (!is.null(data$sender)) data$sender else "System"
          enable("train_btn")
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
    if (state$status == "IDLE") return(p("Awaiting model configuration..."))

    if (state$status == "success") {
      return(HTML('
        <div class="progress" style="height: 25px;">
          <div class="progress-bar bg-success" role="progressbar" style="width: 100%;">
               COMPLETE
          </div>
        </div>
      '))
    }

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

    imp_data <- state$importance
    if (is.list(imp_data) && !is.data.frame(imp_data)) {
      df <- data.frame(Feature = names(imp_data), Importance = as.numeric(unlist(imp_data)), stringsAsFactors = FALSE)
    } else if (is.matrix(imp_data)) {
      df <- data.frame(Feature = rownames(imp_data), Importance = as.numeric(imp_data[, 1]), stringsAsFactors = FALSE)
    } else if (is.data.frame(imp_data)) {
      if (ncol(imp_data) == 1) {
        df <- data.frame(Feature = rownames(imp_data), Importance = as.numeric(imp_data[, 1]), stringsAsFactors = FALSE)
      } else {
        df <- data.frame(Feature = imp_data[, 1], Importance = as.numeric(imp_data[, 2]), stringsAsFactors = FALSE)
      }
    } else {
      req(FALSE)
    }

    if (is.null(df$Feature) || length(df$Feature) == 0) {
      df$Feature <- paste("Feature", seq_len(nrow(df)))
    }
    df <- df[order(df$Importance, decreasing = FALSE), ]

    plot_ly(df, x = ~Importance, y = ~factor(Feature, levels = Feature), type = 'bar', orientation = 'h',
            marker = list(color = '#2ecc71')) %>%
      layout(xaxis = list(title = "Importance Score"), yaxis = list(title = ""))
  })
}

shinyApp(ui, server)
