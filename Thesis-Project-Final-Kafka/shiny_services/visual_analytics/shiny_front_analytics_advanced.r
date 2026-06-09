library(shiny)
library(bslib)
library(plotly)
library(jsonlite)
library(kafka)
library(shinyjs)
library(dplyr)

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
  title = "LTER-LIFE Microclimate Sensors (Kafka)",

  sidebar = sidebar(
    title = "Sensor Filters",
    sliderInput("min_temp", "Minimum Temperature (\u00b0F):", min = 50, max = 100, value = 65),
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

  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })

  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId) && id$sessionId != "solo") return(id$sessionId)
    return(id$userId)
  })

  state <- reactiveValues(
    connected = FALSE, consumer = NULL, producer = NULL,
    permission = "EDITOR", last_sender = NULL
  )

  base_data <- na.omit(airquality)

  # --- DYNAMIC ROLE UPDATES FROM ANGULAR ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
      enable("update_plot"); enable("min_temp"); enable("months")
    } else {
      state$producer <- NULL
      disable("update_plot"); disable("min_temp"); disable("months")
    }
  })

  observe({
    if (state$permission == "VIEWER") {
      disable("update_plot"); disable("min_temp"); disable("months")
    } else {
      enable("update_plot"); enable("min_temp"); enable("months")
    }
  })

  # --- KAFKA CONNECTION ---
  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"

      broker <- "kafka:9092"
      consumer_group <- paste0("front_adv_analytics_", session$token)

      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker,
        "group.id" = consumer_group,
        "auto.offset.reset" = "latest",
        "enable.auto.commit" = "true",
        "max.poll.interval.ms" = "600000"
      ))
      state$consumer$subscribe("output")

      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) {
      print(e$message)
      invalidateLater(5000, session)
    })
  })

  # --- SEND FILTER STATE ---
  observeEvent(input$update_plot, {
    req(state$connected)
    if (is.null(state$producer) || state$permission == "VIEWER") return()

    payload <- list(
      min_temp = as.numeric(input$min_temp),
      months = as.numeric(input$months),
      sender = identity()$userId,
      role = state$permission,
      appName = "Advanced"
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })

  # --- RECEIVE UPDATES ---
  poll_trigger <- reactivePoll(200, session,
    checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); return(as.numeric(Sys.time())) },
    valueFunc = function() { return(as.numeric(Sys.time())) }
  )

  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    result <- state$consumer$consume(10)
    msg <- result_message(result)

    if (!result_has_error(result) && !is.null(msg$value)) {
      if (!is.null(msg$key) && msg$key == routingKey()) {
        data <- fromJSON(msg$value)
        if (!is.null(data$appName) && data$appName != "Advanced") return()

        if (!is.null(data$min_temp)) {
          state$last_sender <- if (!is.null(data$sender)) data$sender else "System"
          updateSliderInput(session, "min_temp", value = as.numeric(data$min_temp))

          if (!is.null(data$months)) {
            updateCheckboxGroupInput(session, "months",
              choices = list("May"="5", "June"="6", "July"="7", "August"="8", "September"="9"),
              selected = as.character(unlist(data$months)))
          }
        }
      }
    }
  })

  # --- REACTIVE DATA FILTER ---
  filtered_data <- reactive({
    req(input$months)
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
      p("User: ", strong(id$userId)),
      p("Role: ", strong(state$permission))
    )
  })

  output$last_update_badge <- renderUI({
    req(state$last_sender)
    span(class = "badge bg-success float-end", paste("Synced by:", state$last_sender))
  })

  output$connection_status <- renderText({ "\U0001f7e2 System Online" })
}

shinyApp(ui = ui, server = server)
