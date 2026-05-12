library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs)

# Allow up to 1GB uploads for massive ecological datasets
options(shiny.maxRequestSize = 1000 * 1024^2) 

shared_dir <- "/app/shared_data"
dir.create(shared_dir, showWarnings = FALSE)

# --- UNIFIED MODERN UI DEFINITION ---
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
  title = "LTER-LIFE: Microclimate Anomaly Detector",
  
  sidebar = sidebar(
    title = "Session Context",
    uiOutput("session_info_ui"),
    hr(),
    
    h5("Upload Sensor Data"),
    p("Upload raw high-frequency sensor logs.", style = "font-size: 0.85em; color: #666;"),
    fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
    
    h5("Ecological Parameters"),
    sliderInput("threshold", "Heatwave Anomaly Threshold (°C):", 
                min = 15, max = 45, value = 28.5, step = 0.5),
    
    actionButton("process_data", "Run Out-of-Core Analysis", class = "btn-success", icon = icon("microchip")),
    hr(),
    downloadButton("download_data", "Download Daily Summary", class = "btn-info"),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  card(
    card_header("Collaborative Daily Ecosystem Summary", uiOutput("last_update_ui", inline = TRUE)),
    div(style = "overflow-x: auto;", tableOutput("data_table"))
  )
)

# --- SERVER LOGIC (REST) ---
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
  
  state <- reactiveValues(last_timestamp = 0, last_sender = NULL)
  shared_df <- reactiveVal(data.frame(Message = "Awaiting Data..."))

  observe({
    if (permission_state() == "VIEWER") {
      disable("file_upload"); disable("process_data"); disable("threshold")
    } else {
      enable("file_upload"); enable("process_data"); enable("threshold")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("Session Key: ", code(substr(id$sessionId, 1, 8), "...")),
      p("Role: ", strong(permission_state()))
    )
  })

  output$connection_status <- renderText({ "🟢 System Online" })

  observeEvent(input$process_data, {
    if (permission_state() == "VIEWER") return()
    req(input$file_upload)
    
    id <- identity()
    
    # 1. UNIQUE FINGERPRINT FOR CONCURRENCY
    unique_fingerprint <- paste0(id$userId, "_", as.integer(Sys.time()), "_", sample(1000:9999, 1))
    raw_filename <- paste0("raw_", unique_fingerprint, ".csv")
    raw_file_path <- file.path(shared_dir, raw_filename)
    
    file.copy(input$file_upload$datapath, raw_file_path, overwrite = TRUE)
    
    payload <- list(
      action = "ANALYZE_CLIMATE",
      file = raw_filename,
      threshold = input$threshold,
      sender = id$userId,
      appName = "ClimateAnomaly"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      httr::POST(url = post_url, body = toJSON(payload, auto_unbox = TRUE), encode = "raw", httr::content_type_json(), httr::timeout(30))
    }, error = function(e) { print(paste("POST Error:", e$message)) })
  })
  
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
              summary_file_path <- file.path(shared_dir, data$file)
              if (file.exists(summary_file_path)) {
                shared_df(read.csv(summary_file_path))
              }
            }
          }
        }
      }
    }, error = function(e) {})
  })

  output$data_table <- renderTable({ shared_df() })
  output$download_data <- downloadHandler(
    filename = function() { paste("lter_daily_summary_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Analysis triggered by:", state$last_sender))
  })
}
shinyApp(ui = ui, server = server)