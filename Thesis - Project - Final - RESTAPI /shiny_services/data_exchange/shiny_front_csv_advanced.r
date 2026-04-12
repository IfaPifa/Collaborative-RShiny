library(shiny)
library(jsonlite)
library(kafka)
library(shinyjs)

# Allow up to 1GB uploads for massive ecological datasets
options(shiny.maxRequestSize = 1000 * 1024^2) 

# Ensure the shared data directory exists
shared_dir <- "/app/shared_data"
dir.create(shared_dir, showWarnings = FALSE)

ui <- fluidPage(
  useShinyjs(),
  titlePanel("Benchmark 2: Microclimate Anomaly Detector (LTER-LIFE)"),
  sidebarLayout(
    sidebarPanel(
      h4("Upload Sensor Data"),
      p("Upload raw high-frequency sensor logs (Must include: Timestamp, SiteID, Temperature, SoilMoisture)."),
      fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
      
      h4("Ecological Parameters"),
      sliderInput("threshold", "Heatwave Anomaly Threshold (°C):", 
                  min = 15, max = 45, value = 28.5, step = 0.5),
      
      actionButton("process_data", "Run Out-of-Core Analysis", class="btn-primary"),
      hr(),
      downloadButton("download_data", "Download Daily Summary"),
      hr(),
      uiOutput("session_info_ui")
    ),
    mainPanel(
      h4("Collaborative Daily Ecosystem Summary"),
      p(em("Note: Heavy lifting is done on the backend. Only analysis parameters are synced via Kafka.")),
      tableOutput("data_table"),
      uiOutput("last_update_ui")
    )
  )
)

server <- function(input, output, session) {
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(userId = if (!is.null(query$userId)) query$userId else "anonymous", 
         sessionId = if (!is.null(query$sessionId)) query$sessionId else NULL)
  })
  routingKey <- reactive({ id <- identity(); if (!is.null(id$sessionId)) id$sessionId else id$userId })
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, permission = "EDITOR", last_sender = NULL)
  shared_df <- reactiveVal(data.frame(Message="Awaiting Data..."))

  observe({
    if (state$permission == "VIEWER") { 
      disable("file_upload"); disable("process_data"); disable("threshold")
    } else { 
      enable("file_upload"); enable("process_data"); enable("threshold") 
    }
  })

  output$session_info_ui <- renderUI({ p("Role: ", strong(state$permission)) })

  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      broker <- "kafka:9092"
      
      state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = paste0("front_", sample(10000:99999, 1)), "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  # --- INGESTION & KAFKA POINTER SYNC (RACE CONDITION FIX) ---
  observeEvent(input$process_data, {
    req(state$connected, !is.null(state$producer), input$file_upload)
    
    # 1. Generate Unique Fingerprint to prevent overlapping concurrent uploads
    unique_fingerprint <- paste0(identity()$userId, "_", as.integer(Sys.time()), "_", sample(1000:9999, 1))
    raw_filename <- paste0("raw_", unique_fingerprint, ".csv")
    raw_file_path <- file.path(shared_dir, raw_filename)
    
    # 2. Save massive file to the shared volume
    file.copy(input$file_upload$datapath, raw_file_path, overwrite = TRUE)
    
    # 3. Send the UNIQUE POINTER and PARAMETERS over Kafka
    payload <- list(
      action = "ANALYZE_CLIMATE",
      file = raw_filename,
      threshold = input$threshold,
      sender = identity()$userId, 
      role = state$permission
    )
    
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })
  
  # --- LISTENING FOR RESULTS ---
  poll_trigger <- reactivePoll(500, session, checkFunc = function() as.numeric(Sys.time()), valueFunc = function() as.numeric(Sys.time()))
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    messages <- state$consumer$consume(100)
    
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$type) && data$type == "SYSTEM" && !is.null(data$targetUser) && data$targetUser == identity()$userId) {
              state$permission <- data$newRole
              state$producer <- if (data$newRole %in% c("EDITOR", "OWNER")) Producer$new(list("bootstrap.servers" = "kafka:9092")) else NULL
          } else if (!is.null(data$action) && data$action == "CLIMATE_READY") {
            
            # Read the EXACT processed summary from the shared volume pointer
            summary_file_path <- file.path(shared_dir, data$file)
            if (file.exists(summary_file_path)) {
              processed_data <- read.csv(summary_file_path)
              shared_df(processed_data)
              state$last_sender <- data$sender
            }
          }
        }
      }
    }
  })

  output$data_table <- renderTable({ shared_df() })
  
  output$download_data <- downloadHandler(
    filename = function() { paste("lter_daily_summary_", Sys.Date(), ".csv", sep="") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
  
  output$last_update_ui <- renderUI({ req(state$last_sender); p(em(paste("Analysis triggered by:", state$last_sender))) })
}
shinyApp(ui = ui, server = server)