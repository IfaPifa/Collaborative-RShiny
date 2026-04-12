library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs) 

# --- MODERN ECO UI DEFINITION ---
ui <- page_sidebar(
  useShinyjs(), 
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

# --- SERVER LOGIC (HTTP POLLING) ---
server <- function(input, output, session) {
  
  # Internal Docker-network URL for Spring Boot
  spring_api_base <- "http://spring-backend:8085/api/collab"
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo",
      permission = if (!is.null(query$permission)) query$permission else "EDITOR"
    )
  })
  
  state <- reactiveValues(
    log = "Initializing HTTP Polling...",
    last_timestamp = 0,
    last_sender = NULL,
    current_sum = 0
  )

  # Permissions check
  observe({
    if (identity()$permission == "VIEWER") {
      disable("num1"); disable("num2"); disable("calculate")
    } else {
      enable("num1"); enable("num2"); enable("calculate")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("Session Key: ", code(substr(id$sessionId, 1, 8), "...")),
      p("Role: ", strong(id$permission))
    )
  })

  output$connection_status <- renderText({ "🌐 HTTP GET/POST" })
  output$debug_log <- renderText({ state$log })
  output$result <- renderText({ state$current_sum })
  
  output$last_update_ui <- renderUI({
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Vault updated by:", state$last_sender))
  })

  # --- 1. THE HTTP POST (Push State to Vault) ---
  observeEvent(input$calculate, {
    id <- identity()
    if (id$permission == "VIEWER") return()
    
    payload <- list(
      num1 = input$num1,
      num2 = input$num2,
      sender = id$userId
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/calculate")
    state$log <- paste("Sending POST request to Spring Boot Vault...\nURL:", post_url)
    
    tryCatch({
      res <- httr::POST(
        url = post_url,
        body = payload,
        encode = "json",
        httr::timeout(5)
      )
      
      if (httr::status_code(res) == 200) {
        state$log <- "✅ Successfully saved to Spring Boot Redis Vault."
      } else {
        state$log <- paste("❌ HTTP Error:", httr::status_code(res))
      }
    }, error = function(e) {
      state$log <- paste("❌ Network Error:", e$message)
    })
  })
  
  # --- 2. THE HTTP GET (Poll Vault for State) ---
  # This fires twice a second, simulating real-time Kafka
  poll_trigger <- reactiveTimer(500) 
  
  observe({
    poll_trigger()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      res <- httr::GET(get_url, httr::timeout(2))
      if (httr::status_code(res) == 200) {
        
        raw_text <- httr::content(res, "text", encoding = "UTF-8")
        
        # If Redis is empty, it returns "{}"
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)
          
          # Check if this is a NEW state by comparing timestamps
          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            state$current_sum <- data$result
            state$last_sender <- data$sender
            state$log <- paste("📥 New Vault Data detected! Sent by:", data$sender)
            
            # Update local UI inputs (prevent infinite update loops)
            if (input$num1 != data$num1) updateNumericInput(session, "num1", value = data$num1)
            if (input$num2 != data$num2) updateNumericInput(session, "num2", value = data$num2)
          }
        }
      }
    }, error = function(e) {
      # Fail silently on polling timeouts to avoid spamming the UI log
    })
  })
}

shinyApp(ui = ui, server = server)