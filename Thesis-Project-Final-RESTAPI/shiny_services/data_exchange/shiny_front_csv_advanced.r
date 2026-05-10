library(shiny)
library(httr)
library(jsonlite)
library(shinyjs)

# Allow up to 1GB uploads for massive ecological datasets
options(shiny.maxRequestSize = 1000 * 1024^2) 

shared_dir <- "/app/shared_data"
dir.create(shared_dir, showWarnings = FALSE)

ui <- fluidPage(
  useShinyjs(),
  titlePanel("Benchmark 2: Microclimate Anomaly Detector (REST API)"),
  sidebarLayout(
    sidebarPanel(
      h4("Upload Sensor Data"),
      p("Upload raw high-frequency sensor logs (Must include: Timestamp, SiteID, Temperature, SoilMoisture)."),
      fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
      
      h4("Ecological Parameters"),
      sliderInput("threshold", "Heatwave Anomaly Threshold (C):", 
                  min = 15, max = 45, value = 28.5, step = 0.5),
      
      actionButton("process_data", "Run Out-of-Core Analysis", class = "btn-primary"),
      hr(),
      downloadButton("download_data", "Download Daily Summary"),
      hr(),
      uiOutput("session_info_ui"),
      hr(),
      h5("Architecture:"),
      textOutput("connection_status")
    ),
    mainPanel(
      h4("Collaborative Daily Ecosystem Summary"),
      tableOutput("data_table"),
      uiOutput("last_update_ui")
    )
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
  
  state <- reactiveValues(last_timestamp = 0, last_sender = NULL)
  shared_df <- reactiveVal(data.frame(Message = "Awaiting Data..."))

  observe({
    if (identity()$permission == "VIEWER") {
      disable("file_upload"); disable("process_data"); disable("threshold")
    } else {
      enable("file_upload"); enable("process_data"); enable("threshold")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("Role: ", strong(id$permission))
    )
  })

  output$connection_status <- renderText({ "HTTP GET/POST" })

  # --- Upload file to shared volume, then POST pointer to Spring Boot ---
  observeEvent(input$process_data, {
    id <- identity()
    if (id$permission == "VIEWER") return()
    req(input$file_upload)
    
    # Generate unique fingerprint to prevent overlapping concurrent uploads
    unique_fingerprint <- paste0(id$userId, "_", as.integer(Sys.time()), "_", sample(1000:9999, 1))
    raw_filename <- paste0("raw_", unique_fingerprint, ".csv")
    raw_file_path <- file.path(shared_dir, raw_filename)
    
    # Save massive file to the shared volume
    file.copy(input$file_upload$datapath, raw_file_path, overwrite = TRUE)
    
    # Send the pointer and parameters to Spring Boot
    payload <- list(
      action = "ANALYZE_CLIMATE",
      file = raw_filename,
      threshold = input$threshold,
      sender = id$userId,
      appName = "ClimateAnomaly"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(30)
      )
    }, error = function(e) {
      print(paste("POST Error:", e$message))
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
            
            if (!is.null(data$action) && data$action == "CLIMATE_READY") {
              state$last_sender <- data$sender
              
              # Read the processed summary from the shared volume
              summary_file_path <- file.path(shared_dir, data$file)
              if (file.exists(summary_file_path)) {
                processed_data <- read.csv(summary_file_path)
                shared_df(processed_data)
              }
            }
          }
        }
      }
    }, error = function(e) {
      # Fail silently
    })
  })

  output$data_table <- renderTable({ shared_df() })
  
  output$download_data <- downloadHandler(
    filename = function() { paste("lter_daily_summary_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
  
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    p(em(paste("Analysis triggered by:", state$last_sender))) 
  })
}
shinyApp(ui = ui, server = server)