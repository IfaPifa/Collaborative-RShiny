library(shiny)
library(bslib)
library(plotly)
library(httr)
library(jsonlite)
library(shinyjs)
library(dplyr)

# UI Definition: Using string values to ensure strict type matching during updates
ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "minty"), 
  title = "LTER-LIFE Microclimate Sensors (REST API)",
  
  # WebSockets role sync
  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),
  
  sidebar = sidebar(
    title = "Sensor Filters",
    sliderInput("min_temp", "Minimum Temperature (°F):", min = 50, max = 100, value = 65),
    checkboxGroupInput("months", "Active Months:", 
                       choices = list("May"="5", "June"="6", "July"="7", "August"="8", "September"="9"), 
                       selected = c("5", "6", "7", "8", "9")),
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
  
  # --- IDENTITY & STATE TRACKING ---
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo",
      permission = if (!is.null(query$permission)) query$permission else "EDITOR"
    )
  })
  
  state <- reactiveValues(
    last_timestamp = 0, 
    last_sender = NULL, 
    permission = "EDITOR"
  )
  
  base_data <- na.omit(airquality)

  # --- DYNAMIC ROLE MANAGEMENT ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
  })

  observe({
    if (state$permission == "VIEWER") {
      disable("update_plot"); disable("min_temp"); disable("months")
    } else {
      enable("update_plot"); enable("min_temp"); enable("months")
    }
  })

  # --- ASYNC POST EVENT (Save to Swarm) ---
  observeEvent(input$update_plot, {
    if (state$permission == "VIEWER") return()
    
    id <- identity()
    # Ensure POST body sends numeric months to match backend API schema
    payload <- list(
      min_temp = as.numeric(input$min_temp),
      months = as.numeric(input$months),
      sender = id$userId,
      appName = "Advanced"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    try({
      httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(5)
      )
    })
  })
  
  # --- SYNCHRONOUS POLLING LOOP ---
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
            
            if (!is.null(data$min_temp)) updateSliderInput(session, "min_temp", value = data$min_temp)
            
            # Explicitly cast to character to match UI definition
            if (!is.null(data$months)) {
              updateCheckboxGroupInput(session, "months", 
                                       choices = list("May"="5", "June"="6", "July"="7", "August"="8", "September"="9"),
                                       selected = as.character(unlist(data$months)))
            }
          }
        }
      }
    }, error = function(e) {})
  })

  # --- REACTIVE DATA FILTER ---
  filtered_data <- reactive({
    req(input$months)
    # Cast input$months back to numeric for dplyr filtering
    base_data %>% filter(Temp >= input$min_temp, Month %in% as.numeric(input$months))
  })

  # --- UI RENDERING ---
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
  
  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("User: ", strong(id$userId)),
      p("Role: ", strong(state$permission))
    )
  })

  output$last_update_badge <- renderUI({ 
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Synced by:", state$last_sender)) 
  })
  
  output$connection_status <- renderText({ "🟢 System Online" })
}

shinyApp(ui = ui, server = server)