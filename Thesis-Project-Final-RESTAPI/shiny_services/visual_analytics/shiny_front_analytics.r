library(shiny)
library(httr)
library(jsonlite)
library(shinyjs)
library(ggplot2)

ui <- fluidPage(
  useShinyjs(), 
  titlePanel("Benchmark 1: Visual Analytics (REST API)"),
  sidebarLayout(
    sidebarPanel(
      h4("Data Filters"),
      sliderInput("min_hp", "Minimum Horsepower:", min = 50, max = 300, value = 50),
      checkboxGroupInput("cyl", "Cylinders:", choices = c(4, 6, 8), selected = c(4, 6, 8)),
      actionButton("update_plot", "Sync Plot"),
      hr(),
      uiOutput("session_info_ui"),
      hr(),
      h5("Architecture:"),
      textOutput("connection_status")
    ),
    mainPanel(
      plotOutput("scatter_plot"),
      uiOutput("last_update_ui")
    )
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
  
  state <- reactiveValues(last_timestamp = 0, last_sender = NULL)
  shared_data <- reactiveVal(mtcars)

  observe({
    if (identity()$permission == "VIEWER") {
      disable("min_hp"); disable("cyl"); disable("update_plot")
    } else {
      enable("min_hp"); enable("cyl"); enable("update_plot")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("Role: ", strong(id$permission))
    )
  })

  output$connection_status <- renderText({ "HTTP GET/POST" })

  # --- POST state to Spring Boot on button click ---
  observeEvent(input$update_plot, {
    id <- identity()
    if (id$permission == "VIEWER") return()
    
    payload <- list(
      min_hp = input$min_hp,
      cyl = input$cyl,
      sender = id$userId,
      appName = "Analytics"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(5)
      )
    }, error = function(e) {
      print(paste("POST Error:", e$message))
    })
  })
  
  # --- Poll Spring Boot for state every 500ms ---
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
            
            # Update UI inputs to match remote state
            if (!is.null(data$min_hp) && input$min_hp != data$min_hp) {
              updateSliderInput(session, "min_hp", value = data$min_hp)
            }
            if (!is.null(data$cyl)) {
              updateCheckboxGroupInput(session, "cyl", selected = as.character(data$cyl))
            }
            
            # Update plot data if the backend returned filtered data
            if (!is.null(data$data)) {
              shared_data(as.data.frame(data$data))
            }
          }
        }
      }
    }, error = function(e) {
      # Fail silently on polling timeouts
    })
  })

  # --- Render ggplot ---
  output$scatter_plot <- renderPlot({
    df <- shared_data()
    req(nrow(df) > 0)
    ggplot(df, aes(x = wt, y = mpg, color = as.factor(cyl))) +
      geom_point(size = 4) +
      geom_smooth(method = "lm", se = FALSE, color = "black") +
      theme_minimal() +
      labs(title = "MPG vs Weight", x = "Weight (1000 lbs)", y = "Miles/(US) gallon", color = "Cylinders")
  })
  
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    p(em(paste("Last updated by:", state$last_sender))) 
  })
}
shinyApp(ui = ui, server = server)
