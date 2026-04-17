library(shiny)
library(bslib)
library(plotly)
library(jsonlite)
library(httr)
library(shinyjs)
library(dplyr)
library(promises)
library(future)

# Enable background workers
plan(multisession)

# Safe data load
base_data <- na.omit(airquality)

ui <- page_sidebar(
  useShinyjs(),
  # JavaScript listener for real-time demotion from Angular
  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),
  
  theme = bs_theme(version = 5, preset = "minty"), 
  title = "LTER-LIFE Microclimate Sensors",
  
  sidebar = sidebar(
    title = "Sensor Filters",
    sliderInput("min_temp", "Minimum Temperature (°F):", min = 50, max = 100, value = 65),
    checkboxGroupInput("months", "Active Months:", 
                       choices = list("May"=5, "June"=6, "July"=7, "August"=8, "September"=9), 
                       selected = c(5, 6, 7, 8, 9)),
    actionButton("update_plot", "Sync State to Swarm", class = "btn-success", icon = icon("cloud-upload-alt")),
    hr(),
    uiOutput("session_info_ui"),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  layout_columns(
    value_box(
      title = "Valid Sensor Readings",
      value = textOutput("kpi_count"),
      showcase = icon("leaf"),
      theme = "success"
    ),
    value_box(
      title = "Average Ozone (ppb)",
      value = textOutput("kpi_ozone"),
      showcase = icon("wind"),
      theme = "info"
    )
  ),
  
  card(
    card_header(
      "Ozone Concentration Matrix",
      uiOutput("last_update_badge", inline = TRUE)
    ),
    plotlyOutput("scatter_plot")
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
  
  state <- reactiveValues(
    last_timestamp = 0,
    last_sender = NULL
  )

  # Permissions Enforcer
  observe({
    if (permission_state() == "VIEWER") {
      disable("min_temp"); disable("months"); disable("update_plot")
    } else {
      enable("min_temp"); enable("months"); enable("update_plot")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(p("User: ", strong(id$userId)), p("Role: ", strong(permission_state())))
  })
  
  output$connection_status <- renderText({ "🌐 Async GET/POST" })

  # --- 1. ASYNC HTTP POST ---
  observeEvent(input$update_plot, {
    if (permission_state() == "VIEWER") return()
    
    id <- identity()
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/calculate")
    
    # Capture inputs locally
    payload <- list(min_temp = input$min_temp, months = input$months, sender = id$userId)
    
    future_promise({
      # Background thread
      httr::POST(post_url, body = payload, encode = "json", httr::timeout(5))
    }) %...!% (function(error) { 
      print(error$message) 
    })
  })
  
  # --- 2. ASYNC HTTP GET ---
  poll_trigger <- reactiveTimer(500) 
  
  observe({
    poll_trigger()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    future_promise({
      # Background thread
      res <- httr::GET(get_url, httr::timeout(2))
      if (httr::status_code(res) == 200) {
        httr::content(res, "text", encoding = "UTF-8")
      } else {
        "{}"
      }
    }) %...>% (function(raw_text) {
      # Main thread
      if (nchar(raw_text) > 2) {
        data <- fromJSON(raw_text)
        
        if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
          state$last_timestamp <- data$timestamp
          state$last_sender <- data$sender
          
          isolate({
            if (input$min_temp != data$min_temp) {
              updateSliderInput(session, "min_temp", value = data$min_temp)
            }
            updateCheckboxGroupInput(session, "months", selected = as.character(data$months))
          })
        }
      }
    })
  })

  filtered_data <- reactive({
    req(input$months)
    base_data %>% filter(Temp >= input$min_temp, Month %in% input$months)
  })

  output$kpi_count <- renderText({ nrow(filtered_data()) })
  output$kpi_ozone <- renderText({
    df <- filtered_data()
    if (nrow(df) == 0) return("N/A")
    round(mean(df$Ozone), 1)
  })

  output$scatter_plot <- renderPlotly({
    df <- filtered_data()
    req(nrow(df) > 0)
    df$MonthName <- month.abb[df$Month]
    p <- ggplot(df, aes(x = Temp, y = Ozone, color = as.factor(MonthName))) +
      geom_point(size = 3, alpha = 0.8) +
      theme_minimal() +
      scale_color_brewer(palette = "Set2")
    ggplotly(p)
  })
  
  output$last_update_badge <- renderUI({ 
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Synced by:", state$last_sender)) 
  })
}

shinyApp(ui = ui, server = server)