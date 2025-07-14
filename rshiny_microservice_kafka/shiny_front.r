# Load the shiny package
install.packages("jsonlite")
library(jsonlite)
library(shiny)
library(kafka)

# Define the Kafka broker and topic
broker <- "kafka:9092"  # Use the appropriate address and port
topic_input <- "input"  # Replace with your topic name
topic_output <- "output"  # Replace with your topic name

config <- list(
  "bootstrap.servers" = broker
)

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
  
  consumer <- Consumer$new(list(
    "bootstrap.servers" = "kafka:9092",
    "auto.offset.reset" = "earliest",
    "group.id" = paste(sample(letters, 10), collapse = ""),
    "enable.auto.commit" = "True"
  ))
  
  consumer$subscribe("output")

  # Observe the calculate button
  observeEvent(input$calculate, {
    # Get the input values
    num1 <- input$num1
    num2 <- input$num2

    json_df <- data.frame(key = c("num1","num2"), 
                          value = c(num1,num2), 
                          stringsAsFactors = FALSE)
    json_message <- toJSON(json_df, pretty=FALSE)

    # Create a Kafka producer
    producer <- Producer$new(config)
    # Send the JSON message to the specified topic
    producer$produce(topic_input, json_message)

    # Check if any messages were received
    repeat{
      mess <- result_message(consumer$consume(5000))
      if (!is.null(mess$value)) {
          print(mess)
          new_df <- fromJSON(mess$value)
          sum_num <- subset(new_df, key == "output")$value
          break
      } else {
        cat("No messages received.\n")
      }
    }
    #consumer$close()
    
    # Display the result
    output$result <- renderText({
      paste("The product of the sum is:", sum_num)
    })
  })
}

# Run the application
shinyApp(ui = ui, server = server)
