library(shiny)
library(bslib)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Collaborative Data Exchange (Monolithic)",

  sidebar = sidebar(
    title = "Data Upload",
    p("Upload a small CSV to clean string columns (uppercase, trim whitespace, remove special chars).",
      style = "font-size: 0.9em; color: #555;"),
    fileInput("file_upload", "Choose CSV File", accept = c(".csv")),
    actionButton("process_data", "Process Data", class = "btn-success", icon = icon("cloud-upload-alt")),
    hr(),
    downloadButton("download_data", "Download Cleaned CSV", class = "btn-info"),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
  ),

  card(
    card_header("Cleaned Data View"),
    div(style = "overflow-x: auto;", tableOutput("data_table"))
  )
)

server <- function(input, output, session) {

  shared_df <- reactiveVal(data.frame(Message = "Awaiting Data..."))

  observeEvent(input$process_data, {
    req(input$file_upload)
    df <- read.csv(input$file_upload$datapath, stringsAsFactors = FALSE)

    # Inline backend logic: capitalize, trim, remove special chars
    if (nrow(df) > 0) {
      for (col in names(df)) {
        if (is.character(df[[col]])) {
          df[[col]] <- toupper(trimws(df[[col]]))
          df[[col]] <- gsub("[^A-Z0-9 ]", "", df[[col]])
        }
      }
    }

    shared_df(df)
  })

  output$data_table <- renderTable({ shared_df() })

  output$download_data <- downloadHandler(
    filename = function() { paste("cleaned_data_", Sys.Date(), ".csv", sep = "") },
    content = function(file) { write.csv(shared_df(), file, row.names = FALSE) }
  )
}

shinyApp(ui = ui, server = server)
