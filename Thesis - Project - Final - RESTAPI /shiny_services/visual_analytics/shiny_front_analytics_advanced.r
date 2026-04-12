library(shiny)
library(bslib)
library(plotly)
library(jsonlite)
library(kafka)
library(shinyjs)
library(dplyr)

ui <- page_sidebar(
  useShinyjs(),
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
    uiOutput("session_info_ui")
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
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else NULL
    )
  })
  
  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId)) return(id$sessionId)
    return(id$userId)
  })
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, last_sender = NULL, permission = "EDITOR")
  base_data <- na.omit(airquality)

  observe({
    if (state$permission == "VIEWER") {
      disable("min_temp"); disable("months"); disable("update_plot")
    } else {
      enable("min_temp"); enable("months"); enable("update_plot")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(p("User: ", strong(id$userId)), p("Role: ", strong(state$permission)))
  })

  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      
      # FIX: Unique Consumer Group per user/session to avoid partition fighting
      s_id <- if(!is.null(query$sessionId)) query$sessionId else "solo"
      u_id <- if(!is.null(query$userId)) query$userId else sample(1000:9999, 1)
      group_name <- paste0("front_", s_id, "_", u_id)
      
      broker <- "kafka:9092"
      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker, 
        "group.id" = group_name, 
        "auto.offset.reset" = "latest", 
        "enable.auto.commit" = "true"
      ))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  observeEvent(input$update_plot, {
    req(state$connected, !is.null(state$producer))
    payload <- list(
      type = "STATE_UPDATE", # Explicit type for advanced backend consistency
      min_temp = input$min_temp,
      months = input$months,
      sender = identity()$userId,
      role = state$permission
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })
  
  poll_trigger <- reactivePoll(500, session, checkFunc = function() as.numeric(Sys.time()), valueFunc = function() as.numeric(Sys.time()))
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    messages <- state$consumer$consume(100)
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          if (!is.null(data$type) && data$type == "STATE_UPDATE") {
            state$last_sender <- data$sender
            updateSliderInput(session, "min_temp", value = data$min_temp)
            updateCheckboxGroupInput(session, "months", selected = data$months)
          }
        }
      }
    }
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