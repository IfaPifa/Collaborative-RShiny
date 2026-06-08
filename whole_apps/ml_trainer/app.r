library(shiny)
library(bslib)
library(plotly)
library(randomForest)

# Generate synthetic LTER data on startup
set.seed(42)
n <- 2000
train_data <- data.frame(
  temp = rnorm(n, 15, 5),
  humidity = runif(n, 20, 100),
  wind_speed = rexp(n, 0.5),
  elevation = runif(n, 0, 2000),
  ndvi = runif(n, 0.1, 0.9)
)
train_data$biodiversity <- with(train_data,
  0.3 * ndvi + 0.2 * (temp / 30) - 0.1 * (wind_speed / 5) +
  0.15 * (humidity / 100) + rnorm(n, 0, 0.1)
)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "materia"),
  title = "Eco-ML: Biodiversity Predictor (Monolithic)",

  sidebar = sidebar(
    title = "Model Configuration",
    selectInput("algo", "Algorithm:",
                choices = c("Random Forest" = "rf", "Gradient Boosting" = "gbm")),
    sliderInput("trees", "Number of Trees:", min = 50, max = 1000, value = 500),
    sliderInput("mtry", "Feature Subsampling (mtry):", min = 1, max = 5, value = 2),
    hr(),
    actionButton("train_btn", "Train Model", class = "btn-primary", icon = icon("microchip")),
    hr(),
    uiOutput("status_ui"),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
  ),

  layout_columns(
    card(
      card_header("Training Convergence"),
      plotlyOutput("loss_plot", height = "350px")
    ),
    card(
      card_header("Feature Importance"),
      plotlyOutput("importance_plot", height = "350px")
    )
  ),

  card(
    card_header("Compute Status"),
    uiOutput("progress_container")
  )
)

server <- function(input, output, session) {

  state <- reactiveValues(
    status = "IDLE", progress = 0,
    logs = data.frame(epoch = numeric(), mse = numeric()),
    importance = NULL
  )

  observeEvent(input$train_btn, {
    state$status <- "RUNNING"
    state$progress <- 5
    state$logs <- data.frame(epoch = numeric(), mse = numeric())
    state$importance <- NULL

    # Inline backend logic: train random forest in chunks to produce convergence logs
    n_trees <- input$trees
    mtry_val <- min(input$mtry, ncol(train_data) - 1)
    chunk_size <- max(10, n_trees %/% 10)
    logs <- data.frame(epoch = numeric(), mse = numeric())

    for (i in seq(chunk_size, n_trees, by = chunk_size)) {
      model <- randomForest(
        biodiversity ~ ., data = train_data,
        ntree = i, mtry = mtry_val
      )
      preds <- predict(model, train_data)
      mse <- mean((train_data$biodiversity - preds)^2)
      logs <- rbind(logs, data.frame(epoch = i, mse = round(mse, 6)))
    }

    # Final model for importance
    final_model <- randomForest(
      biodiversity ~ ., data = train_data,
      ntree = n_trees, mtry = mtry_val,
      importance = TRUE
    )

    imp <- importance(final_model)
    imp_df <- data.frame(
      Feature = rownames(imp),
      Importance = as.numeric(imp[, 1]),
      stringsAsFactors = FALSE
    )

    state$logs <- logs
    state$importance <- imp_df
    state$status <- "success"
    state$progress <- 100
  })

  output$status_ui <- renderUI({
    color <- ifelse(state$status == "RUNNING", "color: #e67e22;", "color: #27ae60;")
    p("Status: ", strong(state$status, style = color))
  })

  output$progress_container <- renderUI({
    if (state$status == "IDLE") return(p("Awaiting model configuration..."))
    if (state$status == "success") {
      return(HTML('
        <div class="progress" style="height: 25px;">
          <div class="progress-bar bg-success" role="progressbar" style="width: 100%;">
               COMPLETE
          </div>
        </div>
      '))
    }
    HTML(sprintf('
      <div class="progress" style="height: 25px;">
        <div class="progress-bar progress-bar-striped progress-bar-animated bg-info"
             role="progressbar" style="width: %s%%;">
             %s%%
        </div>
      </div>
    ', state$progress, state$progress))
  })

  output$loss_plot <- renderPlotly({
    req(nrow(state$logs) > 0)
    plot_ly(state$logs, x = ~epoch, y = ~mse,
            type = "scatter", mode = "lines+markers", name = "MSE") %>%
      layout(yaxis = list(title = "Mean Squared Error"),
             xaxis = list(title = "Tree Iterations"))
  })

  output$importance_plot <- renderPlotly({
    req(state$importance)
    df <- state$importance
    df <- df[order(df$Importance, decreasing = FALSE), ]
    plot_ly(df, x = ~Importance, y = ~factor(Feature, levels = Feature),
            type = "bar", orientation = "h",
            marker = list(color = "#2ecc71")) %>%
      layout(xaxis = list(title = "Importance Score"), yaxis = list(title = ""))
  })
}

shinyApp(ui, server)
