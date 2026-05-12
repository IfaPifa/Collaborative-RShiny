library(shiny)
library(bslib)
library(dplyr)

# --- TRADITIONAL UI DEFINITION ---
ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Climate Anomaly Baseline",
  
  sidebar = sidebar(
    title = "Session Context",
    p(strong("Mode: "), span("Traditional Monolith", style = "color: #d35400")),
    hr(),
    
    h5("Upload Sensor Data"),
    p("Upload raw high-frequency sensor logs.", style = "font-size: 0.85em; color: #666;"),
    fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
    
    h5("Ecological Parameters"),
    sliderInput("threshold", "Heatwave Anomaly Threshold (°C):", 
                min = 15, max = 45, value = 28.5, step = 0.5),
    
    actionButton("process_data", "Process Locally", class="btn-success", icon = icon("microchip")),
    hr(),
    downloadButton("download_data", "Download Daily Summary", class="btn-info"),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  card(
    card_header("Local Data View"),
    div(style = "overflow-x: auto;", tableOutput("data_table"))
  )
)

# --- TRADITIONAL SERVER LOGIC ---
server <- function(input, output, session) {
  
  output$connection_status <- renderText({ "🟢 Local Execution (No Network)" })
  
  local_df <- reactiveVal(data.frame(Message = "Awaiting Data..."))
  
  observeEvent(input$process_data, {
    req(input$file_upload)
    
    df <- read.csv(input$file_upload$datapath, stringsAsFactors = FALSE)
    df$Date <- as.Date(df$Timestamp)
            
    summary_df <- df %>%
      group_by(SiteID, Date) %>%
      summarize(
        Daily_Mean_Temp = mean(Temperature, na.rm = TRUE),
        Daily_Mean_Moisture = mean(SoilMoisture, na.rm = TRUE),
        .groups = 'drop'
      ) %>%
      mutate(Heatwave_Anomaly = ifelse(Daily_Mean_Temp > input$threshold, "YES", "NO"))
    
    local_df(summary_df)
  })
  
  output$data_table <- renderTable({ local_df() })
  
  output$download_data <- downloadHandler(
    filename = function() { paste("lter_daily_summary_local_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(local_df(), file, row.names = FALSE) }
  )
}

# Bind to 0.0.0.0 for Docker compatibility
shinyApp(ui = ui, server = server, options = list(host = "0.0.0.0", port = 3838))