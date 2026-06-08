library(shiny)
library(bslib)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "LTER-LIFE: Sensor Calculator (Monolithic)",

  sidebar = sidebar(
    title = "Deployment Parameters",
    numericInput("num1", "Sensor Array Alpha:", value = 0, min = 0),
    numericInput("num2", "Sensor Array Beta:", value = 0, min = 0),
    actionButton("calculate", "Deploy Calculation", class = "btn-success", icon = icon("leaf")),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
  ),

  card(
    card_header("Deployment Result"),
    h3(textOutput("result"))
  )
)

server <- function(input, output, session) {

  result <- reactiveVal(0)

  observeEvent(input$calculate, {
    total <- input$num1 + input$num2
    result(total)
  })

  output$result <- renderText({
    paste("Total Deployed Sensors:", result())
  })
}

shinyApp(ui = ui, server = server)
