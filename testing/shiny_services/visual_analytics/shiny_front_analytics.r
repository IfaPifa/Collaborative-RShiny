library(shiny)
library(jsonlite)
library(kafka)
library(shinyjs)
library(ggplot2)

ui <- fluidPage(
  useShinyjs(), 
  titlePanel("Benchmark 1: Visual Analytics"),
  sidebarLayout(
    sidebarPanel(
      h4("Data Filters"),
      sliderInput("min_hp", "Minimum Horsepower:", min = 50, max = 300, value = 50),
      checkboxGroupInput("cyl", "Cylinders:", choices = c(4, 6, 8), selected = c(4, 6, 8)),
      actionButton("update_plot", "Sync Plot"),
      hr(),
      uiOutput("session_info_ui")
    ),
    mainPanel(
      plotOutput("scatter_plot"),
      uiOutput("last_update_ui")
    )
  )
)

server <- function(input, output, session) {
  
  # --- IDENTICAL KAFKA & PERMISSION LOGIC ---
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
  shared_data <- reactiveVal(mtcars) # Default plot state

  observe({
    if (state$permission == "VIEWER") {
      disable("min_hp"); disable("cyl"); disable("update_plot")
    } else {
      enable("min_hp"); enable("cyl"); enable("update_plot")
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(p("Role: ", strong(state$permission)))
  })

  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      
      broker <- "kafka:9092"
      state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = paste0("front_", sample(10000:99999, 1)), "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  # --- SEND DATA TO BACKEND ---
  observeEvent(input$update_plot, {
    req(state$connected, !is.null(state$producer))
    payload <- list(
      min_hp = input$min_hp,
      cyl = input$cyl,
      sender = identity()$userId,
      role = state$permission
    )
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })
  
  # --- RECEIVE DATA FROM BACKEND ---
  poll_trigger <- reactivePoll(500, session, checkFunc = function() { as.numeric(Sys.time()) }, valueFunc = function() { as.numeric(Sys.time()) })
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    messages <- state$consumer$consume(100)
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$type) && data$type == "SYSTEM") {
            # Handle role changes
            if (!is.null(data$targetUser) && data$targetUser == identity()$userId) {
              state$permission <- data$newRole
              if (data$newRole %in% c("EDITOR", "OWNER")) {
                state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
              } else {
                state$producer <- NULL
              }
            }
          } else if (!is.null(data$data)) {
            # Update the plot data and UI sliders to match the sender
            shared_data(as.data.frame(data$data))
            state$last_sender <- data$sender
            updateSliderInput(session, "min_hp", value = data$min_hp)
            updateCheckboxGroupInput(session, "cyl", selected = data$cyl)
          }
        }
      }
    }
  })

  # --- RENDER GGPLOT ---
  output$scatter_plot <- renderPlot({
    df <- shared_data()
    req(nrow(df) > 0) # Don't plot if filter removes all data
    ggplot(df, aes(x = wt, y = mpg, color = as.factor(cyl))) +
      geom_point(size = 4) +
      geom_smooth(method = "lm", se = FALSE, color = "black") +
      theme_minimal() +
      labs(title = "MPG vs Weight", x = "Weight (1000 lbs)", y = "Miles/(US) gallon", color = "Cylinders")
  })
  
  output$last_update_ui <- renderUI({ req(state$last_sender); p(em(paste("Last updated by:", state$last_sender))) })
}
shinyApp(ui = ui, server = server)