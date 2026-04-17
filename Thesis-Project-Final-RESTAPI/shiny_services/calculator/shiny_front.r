library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs) 
library(promises)
library(future)

# Enable background workers for async HTTP requests
plan(multisession)

# --- MODERN ECO UI DEFINITION ---
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
  title = "LTER-LIFE: Sensor Deployment Calculator (REST API)",
  
  sidebar = sidebar(
    title = "Session Context",
    uiOutput("session_info_ui"),
    hr(),
    numericInput("num1", "Camera Traps (Zone A):", value = 0),
    numericInput("num2", "Acoustic Sensors (Zone B):", value = 0),
    actionButton("calculate", "Sync to Vault", class = "btn-success", icon = icon("cloud-upload-alt")),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  layout_columns(
    value_box(
      title = "Total Active Sensors",
      value = h1(textOutput("result"), style = "font-weight: bold;"), 
      showcase = icon("tower-broadcast"),
      theme = "success"
    )
  ),
  
  card(
    card_header("REST Synchronization Log", uiOutput("last_update_ui", inline = TRUE)),
    verbatimTextOutput("debug_log")
  )
)

# --- SERVER LOGIC (ASYNC HTTP POLLING) ---
server <- function(input, output, session) {
  
  spring_api_base <- "http://spring-backend:8085/api/collab"
  
  # Reactive state for permissions to allow dynamic updates
  permission_state <- reactiveVal("EDITOR")
  
  # Update permission state when Angular sends a postMessage
  observeEvent(input$role_update, {
    permission_state(input$role_update)
  })
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    
    # Initialize from URL, but let the reactiveVal drive the actual UI lock
    if (!is.null(query$permission) && permission_state() == "EDITOR") {
        permission_state(query$permission)
    }
    
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })
  
  state <- reactiveValues(
    log = "Initializing Async HTTP Polling...",
    last_timestamp = 0,
    last_sender = NULL,
    current_sum = 0
  )

  # Dynamic Permissions Enforcer
  observe({
    if (permission_state() == "VIEWER") {
      disable("num1"); disable("num2"); disable("calculate")
    } else {
      enable("num1"); enable("num2"); enable("calculate")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("Async REST Polling", style = "color: #e67e22")),
      p("Session Key: ", code(substr(id$sessionId, 1, 8), "...")),
      p("Role: ", strong(permission_state()))
    )
  })

  output$connection_status <- renderText({ "🌐 Async GET/POST" })
  output$debug_log <- renderText({ state$log })
  output$result <- renderText({ state$current_sum })
  
  output$last_update_ui <- renderUI({
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Vault updated by:", state$last_sender))
  })

  # --- 1. ASYNC HTTP POST ---
  observeEvent(input$calculate, {
    if (permission_state() == "VIEWER") return()
    
    id <- identity()
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/calculate")
    
    # MUST extract reactive inputs BEFORE entering the background future
    payload <- list(num1 = input$num1, num2 = input$num2, sender = id$userId)
    
    state$log <- paste("Sending Async POST request to Vault...\nURL:", post_url)
    
    future_promise({
      # BACKGROUND THREAD (Cannot access input$ or state$ here)
      httr::POST(url = post_url, body = payload, encode = "json", httr::timeout(5))
    }) %...>% (function(res) {
      # BACK ON MAIN THREAD
      if (httr::status_code(res) == 200) {
        state$log <- "✅ Successfully saved to Spring Boot Redis Vault."
      } else {
        state$log <- paste("❌ HTTP Error:", httr::status_code(res))
      }
    }) %...!% (function(error) {
      state$log <- paste("❌ Network Error:", error$message)
    })
  })
  
  # --- 2. ASYNC HTTP GET POLLING ---
  # Can safely run at 500ms now without choking the main thread
  poll_trigger <- reactiveTimer(500) 
  
  observe({
    poll_trigger()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    future_promise({
      # BACKGROUND THREAD
      res <- httr::GET(get_url, httr::timeout(2))
      if (httr::status_code(res) == 200) {
        httr::content(res, "text", encoding = "UTF-8")
      } else {
        "{}"
      }
    }) %...>% (function(raw_text) {
      # BACK ON MAIN THREAD
      if (nchar(raw_text) > 2) {
        data <- fromJSON(raw_text)
        
        if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
          state$last_timestamp <- data$timestamp
          state$current_sum <- data$result
          state$last_sender <- data$sender
          state$log <- paste("📥 New Vault Data detected! Sent by:", data$sender)
          
          # Isolate input updates
          isolate({
            if (input$num1 != data$num1) updateNumericInput(session, "num1", value = data$num1)
            if (input$num2 != data$num2) updateNumericInput(session, "num2", value = data$num2)
          })
        }
      }
    })
  })
}

shinyApp(ui = ui, server = server)