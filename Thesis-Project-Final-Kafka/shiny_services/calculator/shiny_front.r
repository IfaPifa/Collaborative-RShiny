library(shiny)
library(jsonlite)
library(kafka)
library(shinyjs) 

# --- UI DEFINITION ---
ui <- fluidPage(
  useShinyjs(), 
  
  titlePanel("ShinySwarm: Collaborative Calc"),
  sidebarLayout(
    sidebarPanel(
      h4("Session Context"),
      uiOutput("session_info_ui"),
      hr(),
      
      # INPUTS
      numericInput("num1", "Enter first integer:", value = 0),
      numericInput("num2", "Enter second integer:", value = 0),
      actionButton("calculate", "Calculate / Sync"),
      
      hr(),
      h5("System Status:"),
      textOutput("connection_status")
    ),
    mainPanel(
      h3("Result:"),
      h1(textOutput("result"), style = "color: #4F46E5; font-weight: bold;"),
      
      uiOutput("last_update_ui"),
      
      hr(),
      h5("Debug Log:"),
      verbatimTextOutput("debug_log")
    )
  )
)

# --- SERVER LOGIC ---
server <- function(input, output, session) {
  
  # 1. PARSE IDENTITY
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else NULL
      # Notice: We removed static permission from here. It's now stateful!
    )
  })
  
  # 2. ROUTING KEY LOGIC
  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId)) return(id$sessionId)
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

  # INITIALIZE KAFKA CONNECTION
  observe({
    if (state$connected) return()
    
    tryCatch({
      # Load initial permission from URL
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
        showNotification("Viewer Mode: Input Stream Disconnected", type = "warning", duration = 10)
      }
      
      state$connected <- TRUE
      
    }, error = function(e) {
      state$log <- paste("Kafka Error:", e$message)
    })
  })

  output$connection_status <- renderText({
    if (state$connected) "✅ Online" else "❌ Offline"
  })
  
  output$debug_log <- renderText({ state$log })

  # 4. SEND REQUEST (Producer)
  observeEvent(input$calculate, {
    req(state$connected)
    
    # HARD STOP: Enforce lack of producer
    if (is.null(state$producer)) {
      showNotification("Write access denied by architecture.", type = "error")
      return()
    }
    
    id <- identity()
    
    # Send dynamic permission for Backend verification
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
          
          # --- THE MAGIC LAYER: DYNAMIC PERMISSION OVERRIDE ---
          if (!is.null(data$type) && data$type == "SYSTEM") {
            id <- identity()
            
            # Is this system message meant for me?
            if (!is.null(data$targetUser) && data$targetUser == id$userId) {
              newRole <- data$newRole
              state$permission <- newRole
              
              if (newRole %in% c("EDITOR", "OWNER")) {
                # Grant write access: Create Producer
                broker <- "kafka:9092"
                state$producer <- Producer$new(list("bootstrap.servers" = broker))
                state$log <- paste("System granted", newRole, "access. Producer Active.")
                showNotification("You have been granted Edit access! You can now interact.", type = "message", duration = 10)
              } else {
                # Revoke write access: Destroy Producer
                state$producer <- NULL
                state$log <- paste("System revoked write access. Role:", newRole)
                showNotification("Your Edit access was revoked. You are now a Viewer.", type = "warning", duration = 10)
              }
            }
          } else if (!is.null(data$result)) {
            # Normal calculation payload
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
    p(em(paste("Last updated by:", state$last_sender)), style = "font-size: 0.9em; color: #666;")
  })
}

shinyApp(ui = ui, server = server)