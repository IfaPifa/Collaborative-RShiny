library(shiny)
library(bslib)
library(jsonlite)
library(kafka)
library(shinyjs) 

# --- MODERN ECO UI DEFINITION ---
ui <- page_sidebar(
  useShinyjs(), 
  theme = bs_theme(version = 5, preset = "minty"), # Ecological green theme
  title = "LTER-LIFE: Sensor Deployment Calculator",
  
  sidebar = sidebar(
    title = "Session Context",
    uiOutput("session_info_ui"),
    hr(),
    
    # INPUTS (IDs preserved for Playwright Tests)
    numericInput("num1", "Camera Traps (Zone A):", value = 0),
    numericInput("num2", "Acoustic Sensors (Zone B):", value = 0),
    actionButton("calculate", "Sync to Mesh", class = "btn-success", icon = icon("sync")),
    
    hr(),
    h5("Mesh Connection:"),
    textOutput("connection_status")
  ),
  
  layout_columns(
    # KPI Box for the Result
    value_box(
      title = "Total Active Sensors",
      # Wrapped in h1 so Playwright tests can find it easily
      value = h1(textOutput("result"), style = "font-weight: bold;"), 
      showcase = icon("tower-broadcast"),
      theme = "success"
    )
  ),
  
  card(
    card_header("Synchronization Log", uiOutput("last_update_ui", inline = TRUE)),
    verbatimTextOutput("debug_log")
  )
)

# --- SERVER LOGIC (Identical Kafka Routing & Identity Management) ---
server <- function(input, output, session) {
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else NULL
    )
  })
  
  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId)) return(id$sessionId)
    return(id$userId)
  })
  
  state <- reactiveValues(
    connected = FALSE, log = "Initializing...", consumer = NULL,
    producer = NULL, last_sender = NULL, permission = "EDITOR"
  )

  observe({
    if (state$permission == "VIEWER") {
      disable("num1"); disable("num2"); disable("calculate")
    } else {
      enable("num1"); enable("num2"); enable("calculate")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    if (!is.null(id$sessionId)) {
      tagList(
        p(strong("Mode: "), span("Collaborative", style = "color: #27ae60")),
        p("Session Key: ", code(substr(id$sessionId, 0, 8), "...")),
        p("Role: ", strong(state$permission))
      )
    } else {
      tagList(
        p(strong("Mode: "), span("Solo / Private", style = "color: gray")),
        p("User: ", id$userId)
      )
    }
  })

  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      
      broker <- "kafka:9092"
      consumer_group <- paste0("front_", sample(10000:99999, 1))
      
      state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = consumer_group, "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
        state$log <- paste("Connected as", state$permission, "- Full Duplex")
      } else {
        state$producer <- NULL
        state$log <- "Connected as VIEWER - Read-Only"
      }
      state$connected <- TRUE
    }, error = function(e) { state$log <- paste("Kafka Error:", e$message) })
  })

  output$connection_status <- renderText({ if (state$connected) "✅ Online" else "❌ Offline" })
  output$debug_log <- renderText({ state$log })

  observeEvent(input$calculate, {
    req(state$connected)
    if (is.null(state$producer)) return()
    
    payload <- list(
      num1 = input$num1, num2 = input$num2,
      sender = identity()$userId, role = state$permission, timestamp = as.numeric(Sys.time())
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
    state$log <- paste("Sent update to:", routingKey())
  })
  
  current_sum <- reactiveVal(0)
  poll_trigger <- reactivePoll(500, session, checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); return(as.numeric(Sys.time())) }, valueFunc = function() { return(as.numeric(Sys.time())) })
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    messages <- state$consumer$consume(100)
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$type) && data$type == "SYSTEM") {
            if (!is.null(data$targetUser) && data$targetUser == identity()$userId) {
              state$permission <- data$newRole
              if (data$newRole %in% c("EDITOR", "OWNER")) {
                state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
                state$log <- "System granted access. Producer Active."
              } else {
                state$producer <- NULL
                state$log <- "System revoked write access."
              }
            }
          } else if (!is.null(data$result)) {
            current_sum(data$result)
            state$last_sender <- if (!is.null(data$sender)) data$sender else "System"
            state$log <- paste("Synced with update from:", state$last_sender)
            updateNumericInput(session, "num1", value = data$num1)
            updateNumericInput(session, "num2", value = data$num2)
          }
        }
      }
    }
  })

  output$result <- renderText({ current_sum() })
  
  output$last_update_ui <- renderUI({
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Last updated by:", state$last_sender))
  })
}

shinyApp(ui = ui, server = server)