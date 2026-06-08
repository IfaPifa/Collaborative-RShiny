library(shiny)
library(bslib)
library(ggplot2)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Visual Analytics (Monolithic)",

  sidebar = sidebar(
    title = "Filter Controls",
    sliderInput("min_hp", "Minimum Horsepower:", min = 50, max = 350, value = 100),
    checkboxGroupInput("cyl", "Cylinders:",
                       choices = c("4" = 4, "6" = 6, "8" = 8),
                       selected = c(4, 6, 8)),
    actionButton("update_plot", "Update Visualization", class = "btn-success", icon = icon("chart-bar")),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
  ),

  layout_columns(
    value_box(
      title = "Matching Vehicles",
      value = textOutput("kpi_count"),
      showcase = icon("car"),
      theme = "success"
    ),
    value_box(
      title = "Average MPG",
      value = textOutput("kpi_mpg"),
      showcase = icon("gas-pump"),
      theme = "info"
    )
  ),

  card(
    card_header("Horsepower vs MPG"),
    plotOutput("scatter_plot")
  )
)

server <- function(input, output, session) {

  filtered_data <- reactive({
    df <- mtcars
    df <- df[df$hp >= input$min_hp & df$cyl %in% as.numeric(input$cyl), ]
    df
  })

  output$kpi_count <- renderText({ nrow(filtered_data()) })

  output$kpi_mpg <- renderText({
    df <- filtered_data()
    if (nrow(df) == 0) return("N/A")
    round(mean(df$mpg), 1)
  })

  output$scatter_plot <- renderPlot({
    df <- filtered_data()
    req(nrow(df) > 0)
    ggplot(df, aes(x = hp, y = mpg, color = as.factor(cyl))) +
      geom_point(size = 3, alpha = 0.8) +
      theme_minimal() +
      scale_color_brewer(palette = "Set2") +
      labs(x = "Horsepower", y = "Miles per Gallon", color = "Cylinders")
  })
}

shinyApp(ui = ui, server = server)
