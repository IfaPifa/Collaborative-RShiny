library(shiny)
library(bslib)
library(httr)
library(jsonlite)
library(shinyjs)
library(ggplot2)

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
    # 🚨 FIX 1: Explicitly defining choices as Strings
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
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo",
      permission = if (!is.null(query$permission)) query$permission else "EDITOR"
    )
  })
  
  state <- reactiveValues(last_timestamp = 0, last_sender = NULL, permission = "EDITOR")
  shared_data <- reactiveVal(mtcars)

  # --- DYNAMIC ROLE UPDATES ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      enable("update_plot"); enable("min_hp"); enable("cyl")
    } else {
      disable("update_plot"); disable("min_hp"); disable("cyl")
    }
  })

  observe({
    id <- identity()
    state$permission <- id$permission
    if (state$permission == "VIEWER") { disable("update_plot"); disable("min_hp"); disable("cyl") }
  })

  # --- SEND UPDATES (REST POST) ---
  observeEvent(input$update_plot, {
    if (state$permission == "VIEWER") return()
    id <- identity()
    payload <- list(min_hp = as.numeric(input$min_hp), cyl = as.numeric(input$cyl), sender = id$userId)
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    tryCatch({
      httr::POST(post_url, body = payload, encode = "json", httr::timeout(2))
    }, error = function(e) {})
  })

  # --- RECEIVE UPDATES (REST POLL) ---
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
            
            # 🚨 THE WIRETAP: Printing incoming data shape 🚨
            message("=== INCOMING REST SYNC ===")
            message(paste("Received data$cyl:", paste(data$cyl, collapse=", ")))
            message(paste("Class of data$cyl:", class(data$cyl)))
            
            if (!is.null(data$min_hp)) updateSliderInput(session, "min_hp", value = data$min_hp)
            if (!is.null(data$cyl)) {
              # 🚨 FIX 2: Explicitly matching string choices and unlisting the array
              updateCheckboxGroupInput(session, "cyl", choices = c("4", "6", "8"), selected = as.character(unlist(data$cyl)))
            }
            if (!is.null(data$data)) shared_data(as.data.frame(data$data))
          }
        }
      }
    }, error = function(e) {})
  })

  output$scatter_plot <- renderPlot({
    df <- shared_data()
    req(nrow(df) > 0)
    ggplot(df, aes(x = wt, y = mpg, color = as.factor(cyl))) +
      geom_point(size = 4) + geom_smooth(method = "lm", se = FALSE, color = "black") +
      theme_minimal() + labs(title = "MPG vs Weight", x = "Weight (1000 lbs)", y = "Miles/(US) gallon", color = "Cylinders")
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(p("User: ", strong(id$userId)), p("Role: ", strong(state$permission)))
  })
  output$last_update_ui <- renderUI({ req(state$last_sender); p(em(paste("Last filter sync by:", state$last_sender))) })
  output$connection_status <- renderText({ "System Online" }) 
}
shinyApp(ui = ui, server = server)