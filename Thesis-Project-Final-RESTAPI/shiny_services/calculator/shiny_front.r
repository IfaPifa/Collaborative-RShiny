library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs)
library(promises)
library(future)

plan(multisession)

# --- UI DEFINITION ---
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
  title = "LTER-LIFE: Collaborative Sensor Calculator",

  sidebar = sidebar(
    title = "Session Context",
    uiOutput("session_info_ui"),
    hr(),

    numericInput("num1", "Camera Traps (Zone A):", value = 0),
    numericInput("num2", "Acoustic Sensors (Zone B):", value = 0),
    actionButton("calculate", "Sync Data", class = "btn-success", icon = icon("cloud-upload-alt")),

    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),

  layout_columns(
    value_box(
      title = "Total Active Sensors",
      value = h1(textOutput("result"), style = "font-weight: bold;"),
      showcase = icon("tower-broadcast", lib = "font-awesome"),
      theme = "success"
    )
  ),

  card(
    card_header("Synchronization Log", uiOutput("last_update_ui", inline = TRUE)),
    verbatimTextOutput("debug_log")
  )
)

# --- SERVER LOGIC (REST) ---
server <- function(input, output, session) {

  spring_api_base <- "http://spring-backend:8085/api/collab"

  permission_state <- reactiveVal("EDITOR")

  observeEvent(input$role_update, {
    permission_state(input$role_update)
  })

  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    if (!is.null(query$permission) && permission_state() == "EDITOR") {
      permission_state(query$permission)
    }
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })

  state <- reactiveValues(
    last_timestamp = 0,
    last_sender = NULL,
    log = "Initializing..."
  )

  current_sum <- reactiveVal(0)

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
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("Session Key: ", code(substr(id$sessionId, 1, 8), "...")),
      p("Role: ", strong(permission_state()))
    )
  })

  output$connection_status <- renderText({ "\U0001f7e2 System Online" })

  output$debug_log <- renderText({ state$log })

  # --- POST (send calculation to Spring -> Plumber -> Redis) ---
  observeEvent(input$calculate, {
    if (permission_state() == "VIEWER") return()

    id <- identity()
    payload <- list(
      appName = "Calculator",
      num1 = input$num1,
      num2 = input$num2,
      sender = id$userId,
      role = permission_state(),
      timestamp = as.numeric(Sys.time())
    )

    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")

    future_promise({
      httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(10)
      )
    }) %...>% (function(res) {
      if (httr::status_code(res) == 200) {
        print("Calculator sync sent successfully")

        raw_text <- httr::content(res, "text", encoding = "UTF-8")
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)
          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            state$last_sender <- data$sender
            if (!is.null(data$result) && !is.na(data$result)) {
              current_sum(data$result)
            }
            state$log <- paste("Synced with update from:", data$sender)
          }
        }
      } else {
        state$log <- paste("Sync failed with status:", httr::status_code(res))
      }
    })
  })

  # --- POLLING (receive updates from Redis via Spring) ---
  poll_trigger <- reactiveTimer(500)

  observe({
    poll_trigger()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")

    tryCatch({
      future_promise({
        res <- httr::GET(get_url, httr::timeout(2))
        if (httr::status_code(res) == 200) httr::content(res, "text", encoding = "UTF-8") else "{}"
      }) %...>% (function(raw_text) {
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)

          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            state$last_sender <- if (!is.null(data$sender)) data$sender else "System"
            state$log <- paste("Synced with update from:", state$last_sender)

            if (!is.null(data$result) && !is.na(data$result)) {
              current_sum(data$result)
            }

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
      })
    }, error = function(e) {})
  })

  output$result <- renderText({ current_sum() })

  output$last_update_ui <- renderUI({
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Last updated by:", state$last_sender))
  })
}

shinyApp(ui = ui, server = server)