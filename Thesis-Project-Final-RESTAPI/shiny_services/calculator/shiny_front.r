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
      
      state$connected <- TRUE
      
    }, error = function(e) {
      state$log <- paste("Kafka Error:", e$message)
    })
  })

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
    state$log <- paste("Sent update to:", key_to_use)
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
          
          if (!is.null(data$type) && data$type == "SYSTEM") {
            id <- identity()
            if (!is.null(data$targetUser) && data$targetUser == id$userId) {
              newRole <- data$newRole
              state$permission <- newRole
              
              if (newRole %in% c("EDITOR", "OWNER")) {
                broker <- "kafka:9092"
                state$producer <- Producer$new(list("bootstrap.servers" = broker))
                state$log <- paste("System granted", newRole, "access. Producer Active.")
                showNotification("You have been granted Edit access! You can now interact.", type = "message", duration = 10)
              } else {
                state$producer <- NULL
                state$log <- paste("System revoked write access. Role:", newRole)
                showNotification("Your Edit access was revoked. You are now a Viewer.", type = "warning", duration = 10)
              }
            }
          } else if (!is.null(data$result) && !is.na(data$result)) {
            # --- BULLETPROOF UI UPDATES ---
            current_sum(data$result)
            
            state$last_sender <- if (!is.null(data$sender)) data$sender else "System"
            state$log <- paste("Synced with update from:", state$last_sender)
            
            # ONLY update if the JSON explicitly provided a valid number
            if (!is.null(data$num1) && !is.na(as.numeric(data$num1))) {
              updateNumericInput(session, "num1", value = as.numeric(data$num1))
            }
            if (!is.null(data$num2) && !is.na(as.numeric(data$num2))) {
              updateNumericInput(session, "num2", value = as.numeric(data$num2))
            }
          }
        }
      }
    }
  })

  output$result <- renderText({ current_sum() })
  
  output$last_update_ui <- renderUI({
    req(state$last_sender)
    p(em(paste("Last updated by:", state$last_sender)), style = "font-size: 0.9em; color: #666;")
  })
}

shinyApp(ui = ui, server = server)