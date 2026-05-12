library(shiny)
library(bslib)

# --- TRADITIONAL UI DEFINITION ---
ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Data Exchange Baseline",
  
  sidebar = sidebar(
    title = "Session Context",
    p(strong("Mode: "), span("Traditional Monolith", style = "color: #d35400")),
    hr(),
    
    h5("Upload Dataset"),
    p("Upload a small CSV to clean string columns (uppercase, trim whitespace, remove special chars).", style = "font-size: 0.9em; color: #555;"),
    fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
    actionButton("process_data", "Process Locally", class="btn-success", icon = icon("cogs")),
    
    hr(),
    downloadButton("download_data", "Download Cleaned CSV", class="btn-info"),
    
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
  
  # Hold the cleaned dataset in a local reactive value
  local_df <- reactiveVal(data.frame(Message = "Awaiting Data..."))
  
  observeEvent(input$process_data, {
    req(input$file_upload)
    
    # 1. Read the file
    df <- read.csv(input$file_upload$datapath, stringsAsFactors = FALSE)
    
    # 2. String Manipulation (Exact same logic as the Java/Kafka backends)
    if (nrow(df) > 0) {
      for (col in names(df)) {
        if (is.character(df[[col]])) {
          df[[col]] <- toupper(trimws(df[[col]]))
          df[[col]] <- gsub("[^A-Z0-9 ]", "", df[[col]])
        }
      }
    }
    
    # 3. Save to local state
    local_df(df)
  })
  
  # Render the table
  output$data_table <- renderTable({ local_df() })
  
  # Handle the download
  output$download_data <- downloadHandler(
    filename = function() { paste("cleaned_data_local_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(local_df(), file, row.names = FALSE) }
  )
}

# Bind to 0.0.0.0 for Docker compatibility
shinyApp(ui = ui, server = server, options = list(host = "0.0.0.0", port = 3838))