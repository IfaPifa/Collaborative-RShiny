library(shiny)
library(bslib)
library(jsonlite)
library(kafka)
library(shinyjs)

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

# --- SERVER LOGIC (KAFKA) ---
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
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, permission = "EDITOR", last_sender = NULL)
  shared_df <- reactiveVal(data.frame(Message="Awaiting Data..."))

  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
      showNotification("You have been granted Edit access!", type = "message")
    } else {
      state$producer <- NULL
      showNotification("Your Edit access was revoked. You are now a Viewer.", type = "warning")
    }
  })

  observe({
    if (state$permission == "VIEWER") { disable("file_upload"); disable("process_data") } 
    else { enable("file_upload"); enable("process_data") }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    if (!is.null(id$sessionId) && id$sessionId != "solo") {
      tagList(
        p(strong("Mode: "), span("Collaborative Streaming", style = "color: green")),
        p("Session Key: ", code(substr(id$sessionId, 0, 8), "...")),
        p("Role: ", strong(state$permission))
      )
    } else {
      tagList(p(strong("Mode: "), span("Solo / Private", style = "color: gray")), p("User: ", id$userId))
    }
  })

  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      broker <- "kafka:9092"
      
      state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = paste0("front_csv_", sample(10000:99999, 1)), "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) state$producer <- Producer$new(list("bootstrap.servers" = broker))
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  output$connection_status <- renderText({ if (state$connected) "🟢 System Online" else "❌ Offline" })

  observeEvent(input$process_data, {
    req(state$connected, !is.null(state$producer), input$file_upload)
    df <- read.csv(input$file_upload$datapath, stringsAsFactors = FALSE)
    payload <- list(dataset = df, sender = identity()$userId, role = state$permission)
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })
  
  poll_trigger <- reactivePoll(500, session, checkFunc = function() as.numeric(Sys.time()), valueFunc = function() as.numeric(Sys.time()))
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    messages <- state$consumer$consume(100)
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          if (!is.null(data$dataset)) {
            shared_df(as.data.frame(data$dataset))
            state$last_sender <- data$sender
          }
        }
      }
    }
  })

  output$data_table <- renderTable({ shared_df() })
  
  output$download_data <- downloadHandler(
    filename = function() { paste("cleaned_data_", Sys.Date(), ".csv", sep="") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
  
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Uploaded by:", state$last_sender))
  })
}
shinyApp(ui = ui, server = server)