library(shiny)
library(httr)
library(jsonlite)
library(shinyjs)

ui <- fluidPage(
  useShinyjs(),
  titlePanel("Benchmark 2: Data Exchange (REST API)"),
  sidebarLayout(
    sidebarPanel(
      h4("Upload Dataset"),
      p("Upload a small CSV to clean string columns (uppercase, trim whitespace, remove special characters)."),
      fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
      actionButton("process_data", "Process & Sync Data", class="btn-primary"),
      hr(),
      downloadButton("download_data", "Download Cleaned CSV"),
      hr(),
      uiOutput("session_info_ui"),
      hr(),
      h5("Architecture:"),
      textOutput("connection_status")
    ),
    mainPanel(
      h4("Shared Data View"),
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
      disable("file_upload"); disable("process_data")
    } else {
      enable("file_upload"); enable("process_data")
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

  # --- POST uploaded CSV to Spring Boot ---
  observeEvent(input$process_data, {
    id <- identity()
    if (id$permission == "VIEWER") return()
    req(input$file_upload)
    
    df <- read.csv(input$file_upload$datapath, stringsAsFactors = FALSE)
    
    payload <- list(
      dataset = df,
      sender = id$userId,
      appName = "DataExchange"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(10)
      )
    }, error = function(e) {
      print(paste("POST Error:", e$message))
    })
  })
  
  # --- Poll Spring Boot for state every 500ms ---
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
            state$last_sender <- data$sender
            
            if (!is.null(data$dataset)) {
              shared_df(as.data.frame(data$dataset))
            }
          }
        }
      }
    }, error = function(e) {
      # Fail silently on polling timeouts
    })
  })

  output$data_table <- renderTable({ shared_df() })
  
  output$download_data <- downloadHandler(
    filename = function() { paste("cleaned_data_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
  
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    p(em(paste("Data uploaded/processed by:", state$last_sender))) 
  })
}
shinyApp(ui = ui, server = server)

