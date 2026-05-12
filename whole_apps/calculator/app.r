library(shiny)
library(bslib)

# --- TRADITIONAL UI ---
ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Sensor Calculator",
  
  sidebar = sidebar(
    title = "Session Context",
    p(strong("Mode: "), span("Traditional Monolith", style = "color: #d35400")),
    hr(),
    
    numericInput("num1", "Camera Traps (Zone A):", value = 0),
    numericInput("num2", "Acoustic Sensors (Zone B):", value = 0),
    actionButton("calculate", "Calculate Natively", class = "btn-success", icon = icon("calculator")),
    
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  layout_columns(
    value_box(
      title = "Total Active Sensors",
      value = h1(textOutput("result"), style = "font-weight: bold;"), 
      showcase = icon("tower-broadcast", lib = "font-awesome"),
      theme = "success"
    )
  )
)

# --- TRADITIONAL SERVER ---
server <- function(input, output, session) {
  
  output$connection_status <- renderText({ "🟢 Local Execution (No Network)" })
  
  # Standard Shiny reactivity, no HTTP polling or Kafka streams
  current_sum <- eventReactive(input$calculate, {
    input$num1 + input$num2
  }, ignoreNULL = FALSE)
  
  output$result <- renderText({ 
    current_sum() 
  })
}

# Bind to 0.0.0.0 for Docker compatibility
shinyApp(ui = ui, server = server, options = list(host = "0.0.0.0", port = 3838))