library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs)
library(promises)
library(future)

plan(multisession)

# --- UNIFIED MODERN UI DEFINITION ---
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
  
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Collaborative Data Exchange",
  
  sidebar = sidebar(
    title = "Session Context",
    uiOutput("session_info_ui"),
    hr(),
    
    h5("Upload Dataset"),
    p("Upload a small CSV to clean string columns (uppercase, trim whitespace, remove special chars).", style = "font-size: 0.9em; color: #555;"),
    fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
    actionButton("process_data", "Process & Sync", class="btn-success", icon = icon("cloud-upload-alt")),
    
    hr(),
    downloadButton("download_data", "Download Cleaned CSV", class="btn-info"),
    
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  card(
    card_header("Shared Data View", uiOutput("last_update_ui", inline = TRUE)),
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
      disable("file_upload"); disable("process_data")
    } else {
      enable("file_upload"); enable("process_data")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("Collaborative Polling", style = "color: #e67e22")),
      p("Session Key: ", code(substr(id$sessionId, 1, 8), "...")),
      p("Role: ", strong(permission_state()))
    )
  })

  output$connection_status <- renderText({ "🟢 System Online" })

  # --- POST uploaded CSV ---
  observeEvent(input$process_data, {
    if (permission_state() == "VIEWER") return()
    req(input$file_upload)
    
    id <- identity()
    df <- read.csv(input$file_upload$datapath, stringsAsFactors = FALSE)
    
    payload <- list(
      dataset = df,
      sender = id$userId,
      appName = "DataExchange"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    future_promise({
      httr::POST(url = post_url, body = toJSON(payload, auto_unbox = TRUE), encode = "raw", httr::content_type_json(), httr::timeout(10))
    }) %...>% (function(res) {
      if (httr::status_code(res) == 200) print("✅ CSV Synced successfully")
    })
  })
  
  # --- POLLING ---
  poll_trigger <- reactiveTimer(500)
  
  observe({
    poll_trigger()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    future_promise({
      res <- httr::GET(get_url, httr::timeout(2))
      if (httr::status_code(res) == 200) httr::content(res, "text", encoding = "UTF-8") else "{}"
    }) %...>% (function(raw_text) {
      if (nchar(raw_text) > 2) {
        data <- fromJSON(raw_text)
        if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
          state$last_timestamp <- data$timestamp
          state$last_sender <- data$sender
          if (!is.null(data$dataset)) shared_df(as.data.frame(data$dataset))
        }
      }
    })
  })

  output$data_table <- renderTable({ shared_df() })
  
  output$download_data <- downloadHandler(
    filename = function() { paste("cleaned_data_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
  
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Uploaded by:", state$last_sender))
  })
}
shinyApp(ui = ui, server = server)