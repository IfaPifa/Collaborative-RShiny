library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs)
library(ggplot2)
library(promises)
library(future)

plan(multisession)

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
  title = "LTER-LIFE: Visual Analytics (REST API)",

  sidebar = sidebar(
    title = "Data Filters",
    sliderInput("min_hp", "Minimum Horsepower:", min = 50, max = 300, value = 50),
    checkboxGroupInput("cyl", "Cylinders:", choices = c("4", "6", "8"), selected = c("4", "6", "8")),
    actionButton("update_plot", "Sync Plot", class = "btn-success", icon = icon("sync")),
    hr(),
    uiOutput("session_info_ui"),
    hr(),
    uiOutput("last_update_ui"),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),

  card(
    card_header("Interactive Scatter Plot"),
    plotOutput("scatter_plot", height = "600px")
  )
)

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

  state <- reactiveValues(last_timestamp = 0, last_sender = NULL)

  observe({
    if (permission_state() == "VIEWER") {
      disable("update_plot"); disable("min_hp"); disable("cyl")
    } else {
      enable("update_plot"); enable("min_hp"); enable("cyl")
    }
  })

  # --- POST (send filter state to Spring -> Plumber -> Redis) ---
  observeEvent(input$update_plot, {
    if (permission_state() == "VIEWER") return()

    id <- identity()
    payload <- list(
      min_hp = as.numeric(input$min_hp),
      cyl = as.numeric(input$cyl),
      sender = id$userId,
      appName = "Analytics"
    )

    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")

    future_promise({
      httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(5)
      )
    }) %...>% (function(res) {
      if (httr::status_code(res) == 200) {
        print("Plot sync sent successfully")

        raw_text <- httr::content(res, "text", encoding = "UTF-8")
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)
          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            state$last_sender <- data$sender
          }
        }
      } else {
        print(paste("Sync failed:", httr::status_code(res)))
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
      res <- httr::GET(get_url, httr::timeout(2))
      if (httr::status_code(res) == 200) {
        raw_text <- httr::content(res, "text", encoding = "UTF-8")
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)

          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            state$last_sender <- data$sender

            # Sync slider
            if (!is.null(data$min_hp)) {
              updateSliderInput(session, "min_hp", value = as.numeric(data$min_hp))
            }

            # Sync checkboxes — key matches what backend returns
            if (!is.null(data$cyl)) {
              updateCheckboxGroupInput(session, "cyl",
                choices = c("4", "6", "8"),
                selected = as.character(unlist(data$cyl)))
            }
          }
        }
      }
    }, error = function(e) {})
  })

  # --- REACTIVE DATA FILTER ---
  filtered_data <- reactive({
    df <- mtcars
    df <- df[df$hp >= input$min_hp, ]

    if (!is.null(input$cyl)) {
      df <- df[df$cyl %in% as.numeric(input$cyl), ]
    } else {
      df <- df[0, ]
    }
    df
  })

  # --- RENDER PLOT ---
  output$scatter_plot <- renderPlot({
    df <- filtered_data()
    req(nrow(df) > 0)

    ggplot(df, aes(x = wt, y = mpg, color = as.factor(cyl))) +
      geom_point(size = 4) + geom_smooth(method = "lm", se = FALSE, color = "black") +
      theme_minimal() + labs(title = "MPG vs Weight", x = "Weight (1000 lbs)", y = "Miles/(US) gallon", color = "Cylinders")
  })

  # --- UI RENDERERS ---
  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(p("User: ", strong(id$userId)), p("Role: ", strong(permission_state())))
  })

  output$last_update_ui <- renderUI({
    req(state$last_sender)
    p(em(paste("Last filter sync by:", state$last_sender)))
  })

  output$connection_status <- renderText({ "🟢 System Online" })
}

shinyApp(ui = ui, server = server)
