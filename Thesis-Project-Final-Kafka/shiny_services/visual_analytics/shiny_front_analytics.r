library(shiny)
library(bslib)
library(jsonlite)
library(kafka)
library(shinyjs)
library(ggplot2)

# --- UNIFIED MODERN UI DEFINITION ---
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
  title = "LTER-LIFE: Visual Analytics (Kafka Event Stream)",
  
  sidebar = sidebar(
    title = "Data Filters",
    sliderInput("min_hp", "Minimum Horsepower:", min = 50, max = 300, value = 50),
    checkboxGroupInput("cyl", "Cylinders:", choices = c(4, 6, 8), selected = c(4, 6, 8)),
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
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, last_sender = NULL, permission = "EDITOR")
  shared_data <- reactiveVal(mtcars)

  # --- DYNAMIC ROLE UPDATES ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
      enable("update_plot"); enable("min_hp"); enable("cyl")
    } else {
      state$producer <- NULL
      disable("update_plot"); disable("min_hp"); disable("cyl")
    }
  })

  # --- INITIAL ROLE CHECK ---
  observe({
    query <- parseQueryString(session$clientData$url_search)
    if (!is.null(query$permission)) state$permission <- query$permission
    if (state$permission == "VIEWER") {
      disable("update_plot"); disable("min_hp"); disable("cyl")
    }
  })

  # --- KAFKA CONNECTION ---
  observe({
    if (state$connected) return()
    tryCatch({
      broker <- "kafka:9092"
      consumer_group <- paste0("front_analytics_", sample(10000:99999, 1))
      state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = consumer_group, "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
      state$consumer$subscribe("output")
      if (state$permission %in% c("EDITOR", "OWNER")) state$producer <- Producer$new(list("bootstrap.servers" = broker))
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  # --- SEND UPDATES ---
  observeEvent(input$update_plot, {
    req(state$connected)
    if (is.null(state$producer) || state$permission == "VIEWER") return()
    
    payload <- list(
      min_hp = as.numeric(input$min_hp),
      cyl = as.numeric(input$cyl),
      sender = identity()$userId,
      role = state$permission
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })
  
  # --- RECEIVE UPDATES ---
  poll_trigger <- reactivePoll(500, session,
    checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); return(as.numeric(Sys.time())) },
    valueFunc = function() { return(as.numeric(Sys.time())) }
  )
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    messages <- state$consumer$consume(100)
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$data)) {
            shared_data(as.data.frame(data$data))
            state$last_sender <- data$sender
            updateSliderInput(session, "min_hp", value = data$min_hp)
            updateCheckboxGroupInput(session, "cyl", selected = data$cyl)
          }
        }
      }
    }
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