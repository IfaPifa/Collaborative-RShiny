library(shiny)
library(jsonlite)
library(kafka)
library(shinyjs)

ui <- fluidPage(
  useShinyjs(),
  titlePanel("Benchmark 4: Monte Carlo Simulator"),
  sidebarLayout(
    sidebarPanel(
      h4("Simulation Parameters"),
      numericInput("n_iter", "Iterations (N):", value = 10000, min = 100, max = 1000000),
      sliderInput("mean_val", "Target Mean:", min = -50, max = 50, value = 0),
      sliderInput("sd_val", "Standard Deviation:", min = 1, max = 20, value = 5),
      actionButton("run_sim", "Run Simulation", class="btn-primary"),
      hr(),
      uiOutput("session_info_ui")
    ),
    mainPanel(
      h4("Simulation Results"),
      plotOutput("sim_plot"),
      verbatimTextOutput("sim_stats"),
      uiOutput("last_update_ui")
    )
  )
)

server <- function(input, output, session) {
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(userId = if (!is.null(query$userId)) query$userId else "anonymous", sessionId = if (!is.null(query$sessionId)) query$sessionId else NULL)
  })
  routingKey <- reactive({ id <- identity(); if (!is.null(id$sessionId)) id$sessionId else id$userId })
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, permission = "EDITOR", last_sender = NULL)
  sim_results <- reactiveVal(NULL)

  observe({
    if (state$permission == "VIEWER") { disable("n_iter"); disable("mean_val"); disable("sd_val"); disable("run_sim") } 
    else { enable("n_iter"); enable("mean_val"); enable("sd_val"); enable("run_sim") }
  })

  output$session_info_ui <- renderUI({ p("Role: ", strong(state$permission)) })

  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      broker <- "kafka:9092"
      state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = paste0("front_", sample(10000:99999, 1)), "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
      state$consumer$subscribe("output")
      if (state$permission %in% c("EDITOR", "OWNER")) state$producer <- Producer$new(list("bootstrap.servers" = broker))
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  observeEvent(input$run_sim, {
    req(state$connected, !is.null(state$producer))
    payload <- list(n_iter = input$n_iter, mean_val = input$mean_val, sd_val = input$sd_val, sender = identity()$userId, role = state$permission)
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
          if (!is.null(data$type) && data$type == "SYSTEM" && !is.null(data$targetUser) && data$targetUser == identity()$userId) {
              state$permission <- data$newRole
              state$producer <- if (data$newRole %in% c("EDITOR", "OWNER")) Producer$new(list("bootstrap.servers" = "kafka:9092")) else NULL
          } else if (!is.null(data$hist_counts)) {
            sim_results(data)
            state$last_sender <- data$sender
            updateNumericInput(session, "n_iter", value = data$n_iter)
            updateSliderInput(session, "mean_val", value = data$mean_val)
            updateSliderInput(session, "sd_val", value = data$sd_val)
          }
        }
      }
    }
  })

  output$sim_plot <- renderPlot({
    res <- sim_results()
    req(res)
    barplot(res$hist_counts, names.arg = round(res$hist_mids, 1), col = "steelblue", main = "Distribution of Simulated Data", xlab = "Value", ylab = "Frequency")
  })
  
  output$sim_stats <- renderText({
    res <- sim_results()
    req(res)
    paste0("Calculated Mean: ", round(res$calc_mean, 4), "\nCalculated SD: ", round(res$calc_sd, 4))
  })
  
  output$last_update_ui <- renderUI({ req(state$last_sender); p(em(paste("Last run by:", state$last_sender))) })
}
shinyApp(ui = ui, server = server)