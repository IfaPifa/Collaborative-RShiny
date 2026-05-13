library(shiny)
library(bslib)
library(plotly)
library(httr)
library(jsonlite)
library(shinyjs)
library(dplyr)

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "minty"), 
  title = "LTER-LIFE Microclimate Sensors (REST API)",
  
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
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo",
      permission = if (!is.null(query$permission)) query$permission else "EDITOR"
    )
  })
  
  state <- reactiveValues(last_timestamp = 0, last_sender = NULL)
  base_data <- na.omit(airquality)

  observe({
    if (identity()$permission == "VIEWER") {
      disable("min_temp"); disable("months"); disable("update_plot")
    } else {
      enable("min_temp"); enable("months"); enable("update_plot")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("User: ", strong(id$userId)),
      p("Role: ", strong(id$permission))
    )
  })

  output$connection_status <- renderText({ "🟢 System Online" })

  # --- POST state to Spring Boot on button click ---
  observeEvent(input$update_plot, {
    id <- identity()
    print(paste(">>> SYNC CLICKED | userId:", id$userId, "| sessionId:", id$sessionId, "| permission:", id$permission))
    if (id$permission == "VIEWER") {
      print(">>> BLOCKED: user is VIEWER")
      return()
    }
    
    payload <- list(
      min_temp = input$min_temp,
      months = input$months,
      sender = id$userId,
      appName = "Advanced"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    print(paste(">>> POSTing to:", post_url))
    print(paste(">>> Payload:", toJSON(payload, auto_unbox = TRUE)))
    
    tryCatch({
      res <- httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(5)
      )
      print(paste(">>> POST response status:", httr::status_code(res)))
      print(paste(">>> POST response body:", httr::content(res, "text", encoding = "UTF-8")))
    }, error = function(e) {
      print(paste(">>> POST Error:", e$message))
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
            print(paste(">>> POLL: new state from", data$sender, "| min_temp:", data$min_temp, "| months:", paste(data$months, collapse=",")))
            
            if (!is.null(data$min_temp) && !is.null(input$min_temp) && input$min_temp != data$min_temp) {
              print(paste(">>> Updating min_temp:", input$min_temp, "->", data$min_temp))
              updateSliderInput(session, "min_temp", value = data$min_temp)
            }
            if (!is.null(data$months)) {
              print(paste(">>> Updating months to:", paste(as.character(data$months), collapse=",")))
              updateCheckboxGroupInput(session, "months", selected = as.character(data$months))
            }
          }
        }
      }
    }, error = function(e) {
      # Fail silently on polling timeouts
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
