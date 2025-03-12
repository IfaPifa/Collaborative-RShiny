# Load the shiny package
install.packages("rkafka")
install.packages("jsonlite")
library(jsonlite)
library(shiny)
library(rkafka)

# Function to add two numbers
add_up <- function(a, b) {return(a + b)}

# Define the UI
ui <- fluidPage(
  titlePanel("Add and Multiply"),
  sidebarLayout(
    sidebarPanel(
      numericInput("num1", "Enter first integer:", value = 0),
      numericInput("num2", "Enter second integer:", value = 0),
      actionButton("calculate", "Calculate")
    ),
    mainPanel(
      textOutput("result")
    )
  )
)

# Define the server logic
server <- function(input, output) {

  # Observe the calculate button
  observeEvent(input$calculate, {
    # Get the input values
    num1 <- input$num1
    num2 <- input$num2
    
    # Calculate the sum
    sum_result <- add_up(num1, num2)
    
    # Display the result
    output$result <- renderText({
      paste("The product of the sum is:", sum_result)
    })
  })
}

# Run the application
shinyApp(ui = ui, server = server)