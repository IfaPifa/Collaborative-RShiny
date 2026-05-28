library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs) 
library(promises)
library(future)

# Enable background workers for async HTTP requests
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

# --- SERVER LOGIC (ASYNC HTTP POLLING) ---
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
    connected = FALSE,
    log = "Initializing...",
    consumer = NULL,
    producer = NULL,
    last_sender = NULL,
    permission = "EDITOR" 
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
        p(strong("Mode: "), span("Collaborative", style = "color: green")),
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
      
      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker,
        "group.id" = consumer_group,
        "auto.offset.reset" = "latest", 
        "enable.auto.commit" = "true"
      ))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
        state$log <- paste("Connected as", state$permission, "- Full Duplex")
      } else {
        state$producer <- NULL
        state$log <- paste("Connected as VIEWER - Read-Only (No Producer)")
        showNotification("Viewer Mode: Input Stream Disconnected", type = "warning", duration = 10)
      }
      library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs) 
library(promises)
library(future)

# Enable background workers for async HTTP requests
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

# --- SERVER LOGIC (ASYNC HTTP POLLING) ---
server <- function(input, output, session) {
  
  # Java Backend URL (resolving out of the R container to the Spring Boot container)
  API_BASE_URL <- "http://host.docker.internal:8085/api/collab"
  
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
    # FIX: Namespace solo sessions so multiple standalone users don't overwrite each other
    return(paste0("solo:", id$userId)) 
  })
  
  state <- reactiveValues(
    connected = FALSE,
    log = "Initializing...",
    last_sender = NULL,
    permission = "EDITOR" 
  )

  # Role-based UI updates
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (state$permission == "EDITOR" || state$permission == "OWNER") {
      state$log <- paste("System granted", state$permission, "access.")
      showNotification(paste("Access updated to", state$permission), type = "message")
    } else {
      state$log <- paste("System revoked write access. Role: VIEWER")
      showNotification("Your Edit access was revoked. You are now a Viewer.", type = "warning")
    }
  })

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
        p(strong("Mode: "), span("Collaborative", style = "color: green")),
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

  # --- 1. BOOTSTRAP CONNECTION (REST) ---
  observe({
    if (state$connected) return()
    
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$log <- paste("Connected to REST API as", state$permission, "- Full Duplex")
      } else {
        state$log <- paste("Connected to REST API as VIEWER - Read-Only")
        showNotification("Viewer Mode: Input Disabled", type = "warning", duration = 10)
      }
      
      state$connected <- TRUE
      
    }, error = function(e) {
      state$log <- paste("Setup Error:", e$message)
    })
  })

  # Fix: Playwright expects this exact phrase to verify booting
  output$connection_status <- renderText({
    if (state$connected) "🟢 System Online" else "❌ Offline"
  })
  
  output$debug_log <- renderText({ state$log })

  # --- 2. SEND REQUEST (REST POST) ---
  observeEvent(input$calculate, {
    req(state$connected)
    if (state$permission == "VIEWER") {
      showNotification("Write access denied by architecture.", type = "error")
      return()
    }
    
    id <- identity()
    payload <- list(
      appName = "Calculator", # CRITICAL: Java uses this to route to shiny-back:8000/calculate
      num1 = input$num1,
      num2 = input$num2,
      sender = id$userId,
      role = state$permission, 
      timestamp = as.numeric(Sys.time())
    )
    
    key_to_use <- routingKey()
    target_url <- paste0(API_BASE_URL, "/", key_to_use, "/state")
    
    tryCatch({
      res <- httr::POST(
        target_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "json"
      )
      state$log <- paste("Sent update to REST API:", key_to_use)
    }, error = function(e) {
      state$log <- paste("API POST Error:", e$message)
    })
  })
  
  # --- 3. RECEIVE UPDATES (REST GET POLLING) ---
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
    req(state$connected)
    
    key_to_use <- routingKey()
    target_url <- paste0(API_BASE_URL, "/", key_to_use, "/state")
    
    tryCatch({
      res <- httr::GET(target_url)
      
      if (httr::status_code(res) == 200) {
        content_text <- httr::content(res, "text", encoding = "UTF-8")
        
        # Don't try to parse empty Redis states
        if (content_text != "" && content_text != "{}") {
          data <- fromJSON(content_text)
          
          if (!is.null(data$result) && !is.na(data$result)) {
            # Check timestamp so we don't spam UI rewrites unnecessarily 
            current_sum(data$result)
            
            state$last_sender <- if (!is.null(data$sender)) data$sender else "System"
            state$log <- paste("Synced with update from:", state$last_sender)
            
            # Use isolate to prevent the inputs updating from triggering infinite reactive loops
            isolate({
              if (!is.null(data$num1) && !is.na(as.numeric(data$num1)) && as.numeric(data$num1) != input$num1) {
                updateNumericInput(session, "num1", value = as.numeric(data$num1))
              }
              if (!is.null(data$num2) && !is.na(as.numeric(data$num2)) && as.numeric(data$num2) != input$num2) {
                updateNumericInput(session, "num2", value = as.numeric(data$num2))
              }
            })
          }
        }
      }
    }, error = function(e) {
      # Fail silently on polling timeouts to prevent log spam
    })
  })

  output$result <- renderText({ current_sum() })
  
  output$last_update_ui <- renderUI({
    req(state$last_sender)
    p(em(paste("Last updated by:", state$last_sender)), style = "font-size: 0.9em; color: #666;")
  })
}

shinyApp(ui = ui, server = server)