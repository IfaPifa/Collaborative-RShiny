library(shiny)
library(bslib)
library(plotly)
library(dplyr)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE Microclimate Sensors (Monolithic)",

  sidebar = sidebar(
    title = "Sensor Filters",
    sliderInput("min_temp", "Minimum Temperature (\u00b0F):", min = 50, max = 100, value = 65),
    checkboxGroupInput("months", "Active Months:",
                       choices = list("May" = "5", "June" = "6", "July" = "7", "August" = "8", "September" = "9"),
                       selected = c("5", "6", "7", "8", "9")),
    actionButton("update_plot", "Update Visualization", class = "btn-success", icon = icon("cloud-upload-alt")),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
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
    card_header("Ozone Concentration Matrix"),
    plotlyOutput("scatter_plot")
  )
)

server <- function(input, output, session) {

  base_data <- na.omit(airquality)

  filtered_data <- reactive({
    req(input$months)
    base_data %>% filter(Temp >= input$min_temp, Month %in% as.numeric(input$months))
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
    p <- ggplot2::ggplot(df, ggplot2::aes(x = Temp, y = Ozone, color = as.factor(MonthName))) +
      ggplot2::geom_point(size = 3, alpha = 0.8) +
      ggplot2::theme_minimal() +
      ggplot2::scale_color_brewer(palette = "Set2")
    ggplotly(p)
  })
}

shinyApp(ui = ui, server = server)
