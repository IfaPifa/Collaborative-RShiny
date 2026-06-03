library(shiny)
library(bslib)
library(plotly)
library(httr)
library(jsonlite)
library(shinyjs)
library(promises)
library(future)

plan(multisession)

ui <- page_sidebar(
  useShinyjs(),
  
  # Listen for Angular sending the "ROLE_UPDATE" WebSocket message into the iframe
  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),
  
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
  
  permission_state <- reactiveVal("EDITOR")
  
  observeEvent(input$role_update, {
    permission_state(input$role_update)
  })
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    if (!is.null(query$permission) && permission_state() == "EDITOR") {
        permission_state(query$permission)
    }
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })
  
  state <- reactiveValues(
    last_timestamp = 0, 
    last_sender = NULL,
    status = "IDLE",
    progress = 0,
    logs = data.frame(epoch = numeric(), mse = numeric()),
    importance = NULL
  )

  observe({
    if (permission_state() == "VIEWER") {
      disable("algo"); disable("trees"); disable("mtry"); disable("train_btn")
    } else {
      enable("algo"); enable("trees"); enable("mtry"); enable("train_btn")
    }
  })

  output$connection_status <- renderText({ "🟢 System Online" })

  # --- POST EVENT WITH EAGER UI UPDATE ---
  observeEvent(input$train_btn, {
    if (permission_state() == "VIEWER") return()
    
    id <- identity()
    payload <- list(
      command = "TRAIN_MODEL",
      trees = input$trees,
      mtry = input$mtry,
      algo = input$algo,
      sender = id$userId,
      appName = "MLTrainer"
    )
    
    state$status <- "RUNNING"
    state$progress <- 5 
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    future_promise({
      httr::POST(url = post_url, body = toJSON(payload, auto_unbox = TRUE), encode = "raw", httr::content_type_json(), httr::timeout(60))
    }) %...>% (function(res) {
      if (httr::status_code(res) == 200) {
        print("✅ ML Training completed and synced!")
        
        raw_text <- httr::content(res, "text", encoding = "UTF-8")
        
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)
          
          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            
            # Pure state mapping
            if (!is.null(data$status)) state$status <- data$status
            if (!is.null(data$progress)) state$progress <- data$progress
            if (!is.null(data$importance)) state$importance <- data$importance
            
            if (!is.null(data$logs)) {
              el <- data$logs
              if (is.data.frame(el)) {
                state$logs <- el
              } else if (is.list(el)) {
                state$logs <- do.call(rbind, lapply(el, as.data.frame))
              }
            }
          }
        }
      } else {
        print(paste("❌ Training failed with status:", httr::status_code(res)))
        state$status <- "FAILED"
      }
    })
  })

  # --- POLLING LOOP ---
  poll_trigger <- reactiveTimer(500)
  
  observe({
    poll_trigger()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      future_promise({
        res <- httr::GET(get_url, httr::timeout(2))
        if (httr::status_code(res) == 200) httr::content(res, "text", encoding = "UTF-8") else "{}"
      }) %...>% (function(raw_text) {
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)
          
          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            
            # Pure state mapping
            if (!is.null(data$status)) state$status <- data$status
            if (!is.null(data$progress)) state$progress <- data$progress
            if (!is.null(data$importance)) state$importance <- data$importance
            
            if (!is.null(data$logs)) {
              el <- data$logs
              if (is.data.frame(el)) {
                state$logs <- el
              } else if (is.list(el)) {
                state$logs <- do.call(rbind, lapply(el, as.data.frame))
              }
            }
          }
        }
      })
    }, error = function(e) {
      # Fail silently
    })
  })

  # --- UI RENDERERS ---
  output$status_ui <- renderUI({
    p("Mesh Status: ", strong(state$status, style = ifelse(state$status == "RUNNING", "color: #e67e22;", "color: #27ae60;")))
  })

  output$progress_container <- renderUI({
    if (state$status == "IDLE") return(p("Awaiting model configuration..."))
    
    # --- THE PROPER FIX: End of Loading State ---
    if (state$status == "success") {
      return(HTML('
        <div class="progress" style="height: 25px;">
          <div class="progress-bar bg-success" role="progressbar" style="width: 100%;">
               COMPLETE
          </div>
        </div>
      '))
    }

    # --- While Running: Show Animated Progress ---
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
    
    plot_ly(df, x = ~Importance, y = ~factor(Feature, levels = Feature), type = 'bar', orientation = 'h', marker = list(color = '#2ecc71')) %>%
      layout(xaxis = list(title = "Importance Score"), yaxis = list(title = ""))
  })
}

shinyApp(ui, server)