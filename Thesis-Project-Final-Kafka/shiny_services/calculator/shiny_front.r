library(shiny)
library(bslib)
library(jsonlite)
library(kafka)
library(shinyjs) 

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
  
  # Modern theme for your thesis demo
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Collaborative Sensor Calculator",
  
  sidebar = sidebar(
    title = "Session Context",
    uiOutput("session_info_ui"),
    hr(),
    
    # Standardized Inputs
    numericInput("num1", "Camera Traps (Zone A):", value = 0),
    numericInput("num2", "Acoustic Sensors (Zone B):", value = 0),
    actionButton("calculate", "Sync Data", class = "btn-success", icon = icon("cloud-upload-alt")),
    
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  # Main Dashboard Area
  layout_columns(
    value_box(
      title = "Total Active Sensors",
      value = h1(textOutput("result"), style = "font-weight: bold;"), 
      showcase = icon("tower-broadcast", lib = "font-awesome"),
      theme = "success"
    )
  ),
  
  # Debug / Sync Log
  card(
    card_header("Synchronization Log", uiOutput("last_update_ui", inline = TRUE)),
    verbatimTextOutput("debug_log")
  )
)

# --- SERVER LOGIC (KAFKA EVENT STREAMING) ---
server <- function(input, output, session) {
  
  # 1. PARSE IDENTITY
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })
  
  # 2. ROUTING KEY LOGIC
  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId) && id$sessionId != "solo") return(id$sessionId)
    return(id$userId)
  })
  
  # 3. KAFKA CONNECTION & STATE
  state <- reactiveValues(
    connected = FALSE,
    log = "Initializing...",
    consumer = NULL,
    producer = NULL,
    last_sender = NULL,
    permission = "EDITOR" # Will be overwritten on load
  )

  # --- DYNAMIC ROLE UPDATES FROM ANGULAR ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      broker <- "kafka:9092"
      state$producer <- Producer$new(list("bootstrap.servers" = broker))
      state$log <- paste("Angular granted", input$role_update, "access. Producer Active.")
      showNotification("You have been granted Edit access!", type = "message")
    } else {
      state$producer <- NULL
      state$log <- "Angular revoked write access. Role: VIEWER"
      showNotification("Your Edit access was revoked. You are now a Viewer.", type = "warning")
    }
  })

  # --- DYNAMIC UI LOCK/UNLOCK ---
  observe({
    if (state$permission == "VIEWER") {
      disable("num1")
      disable("num2")
      disable("calculate")
    } else {
      enable("num1")
      enable("num2")
      enable("calculate")
    }
  })

  # UI Info
  output$session_info_ui <- renderUI({
    id <- identity()
    if (!is.null(id$sessionId) && id$sessionId != "solo") {
      tagList(
        p(strong("Mode: "), span("Collaborative Streaming", style = "color: green")),
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

  # INITIALIZE KAFKA CONNECTION
  observe({
    if (state$connected) return()
    
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      
      broker <- "kafka:9092"
      consumer_group <- paste0("front_", sample(10000:99999, 1))
      
      # A. ALWAYS CREATE CONSUMER (Read-Path)
      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker,
        "group.id" = consumer_group,
        "auto.offset.reset" = "latest", 
        "enable.auto.commit" = "true"
      ))
      state$consumer$subscribe("output")
      
      # B. CONDITIONALLY CREATE PRODUCER (Write-Path)
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
        state$log <- paste("Connected as", state$permission, "- Full Duplex")
      } else {
        state$producer <- NULL
        state$log <- paste("Connected as VIEWER - Read-Only (No Producer)")
      }
      
      state$connected <- TRUE
      
    }, error = function(e) {
      state$log <- paste("Kafka Error:", e$message)
    })
  })

  # Unified connection string for the agnostic Playwright test
  output$connection_status <- renderText({
    if (state$connected) "🟢 System Online" else "❌ Offline"
  })
  
  output$debug_log <- renderText({ state$log })

  # 4. SEND REQUEST (Producer)
  observeEvent(input$calculate, {
    req(state$connected)
    
    if (is.null(state$producer)) {
      showNotification("Write access denied by architecture.", type = "error")
      return()
    }
    
    id <- identity()
    
    payload <- list(
      num1 = input$num1,
      num2 = input$num2,
      sender = id$userId,
      role = state$permission, 
      timestamp = as.numeric(Sys.time())
    )
    
    key_to_use <- routingKey()
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = key_to_use)
    state$log <- paste("Sent update to topic 'input' with key:", key_to_use)
  })
  
  # 5. RECEIVE UPDATES (Consumer)
  current_sum <- reactiveVal(0)
  
  poll_trigger <- reactivePoll(500, session,
    checkFunc = function() {
      if (!isTRUE(state$connected)) return(NULL)
      return(as.numeric(Sys.time()))
    },
    valueFunc = function() { return(as.numeric(Sys.time())) }
  )
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    
    messages <- state$consumer$consume(100)
    
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$result)) {
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
    span(class = "badge bg-success float-end", paste("Updated by:", state$last_sender))
  })
}

shinyApp(ui = ui, server = server)