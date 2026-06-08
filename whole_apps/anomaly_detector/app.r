library(shiny)
library(bslib)
library(dplyr)

options(shiny.maxRequestSize = 1000 * 1024^2)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Microclimate Anomaly Detector (Monolithic)",

  sidebar = sidebar(
    title = "Sensor Data",
    p("Upload raw high-frequency sensor logs.",
      style = "font-size: 0.85em; color: #666;"),
    fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
    h5("Ecological Parameters"),
    sliderInput("threshold", "Heatwave Anomaly Threshold (\u00b0C):",
                min = 15, max = 45, value = 28.5, step = 0.5),
    actionButton("process_data", "Run Analysis", class = "btn-success", icon = icon("microchip")),
    hr(),
    downloadButton("download_data", "Download Daily Summary", class = "btn-info"),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
  ),

  card(
    card_header("Daily Ecosystem Summary"),
    div(style = "overflow-x: auto;", tableOutput("data_table"))
  )
)

server <- function(input, output, session) {

  shared_df <- reactiveVal(data.frame(Message = "Awaiting Data..."))

  observeEvent(input$process_data, {
    req(input$file_upload)
    raw <- read.csv(input$file_upload$datapath, stringsAsFactors = FALSE)

    # Inline backend logic: daily aggregation + anomaly detection
    threshold <- input$threshold

    if ("date" %in% names(raw) && "temperature" %in% names(raw)) {
      summary_df <- raw %>%
        group_by(date) %>%
        summarise(
          mean_temp = round(mean(temperature, na.rm = TRUE), 2),
          max_temp = round(max(temperature, na.rm = TRUE), 2),
          min_temp = round(min(temperature, na.rm = TRUE), 2),
          readings = n(),
          .groups = "drop"
        ) %>%
        mutate(anomaly = ifelse(max_temp > threshold, "HEATWAVE", "NORMAL"))

      shared_df(summary_df)
    } else {
      # Fallback: just show raw data if columns don't match
      shared_df(raw)
    }
  })

  output$data_table <- renderTable({ shared_df() })

  output$download_data <- downloadHandler(
    filename = function() { paste("lter_daily_summary_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
}

shinyApp(ui = ui, server = server)
