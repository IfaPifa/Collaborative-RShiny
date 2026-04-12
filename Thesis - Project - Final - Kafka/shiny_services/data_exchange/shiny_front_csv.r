library(shiny)
library(jsonlite)
library(kafka)
library(shinyjs)

ui <- fluidPage(
  useShinyjs(),
  titlePanel("Benchmark 2: Data Exchange"),
  sidebarLayout(
    sidebarPanel(
      h4("Upload Dataset"),
      p("Upload a small CSV to clean string columns (uppercase, trim whitespace, remove special characters)."),
      fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
      actionButton("process_data", "Process & Sync Data", class="btn-primary"),
      hr(),
      downloadButton("download_data", "Download Cleaned CSV"),
      hr(),
      uiOutput("session_info_ui")
    ),
    mainPanel(
      h4("Shared Data View"),
      tableOutput("data_table"),
      uiOutput("last_update_ui")
    )
  )
)

server <- function(input, output, session) {
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(userId = if (!is.null(query$userId)) query$userId else "anonymous", sessionId = if (!is.null(query$sessionId)) query$sessionId else NULL)
  })
  routingKey <- reactive({ id <- identity(); if (!is.null(id$sessionId)) id$sessionId else id$userId })
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, permission = "EDITOR", last_sender = NULL)
  shared_df <- reactiveVal(data.frame(Message="Awaiting Data..."))

  observe({
    if (state$permission == "VIEWER") { disable("file_upload"); disable("process_data") } 
    else { enable("file_upload"); enable("process_data") }
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
      if (state$permission %in% c("EDITOR", "OWNER")) state$producer <- Producer$new(list("bootstrap.servers" = broker))
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  observeEvent(input$process_data, {
    req(state$connected, !is.null(state$producer), input$file_upload)
    
    # Read the uploaded CSV
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
          if (!is.null(data$type) && data$type == "SYSTEM" && !is.null(data$targetUser) && data$targetUser == identity()$userId) {
              state$permission <- data$newRole
              state$producer <- if (data$newRole %in% c("EDITOR", "OWNER")) Producer$new(list("bootstrap.servers" = "kafka:9092")) else NULL
          } else if (!is.null(data$dataset)) {
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
  
  output$last_update_ui <- renderUI({ req(state$last_sender); p(em(paste("Data uploaded/processed by:", state$last_sender))) })
}
shinyApp(ui = ui, server = server)