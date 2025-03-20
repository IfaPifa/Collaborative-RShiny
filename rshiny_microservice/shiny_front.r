# Load the shiny package
install.packages("rkafka")
install.packages("jsonlite")
library(jsonlite)
library(shiny)
library(rkafka)

# Define the Kafka broker and topic
broker <- "broker:29092"  # Use the appropriate address and port
topic_input <- "input"  # Replace with your topic name
topic_output <- "output"  # Replace with your topic name

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

    json_df <- data.frame(key = c("num1","num2"), 
                          value = c(num1,num2), 
                          stringsAsFactors = FALSE)
    json_message <- toJSON(json_df, pretty=TRUE)

    # Create a Kafka producer
    producer <- rkafka.createProducer(broker)
    # Send the JSON message to the specified topic
    rkafka.send(producer, topic_input, "localhost:9092", json_message)
    #Close a Kafka producer
    rkafka.closeProducer(producer)

    consumer <- rkafka.createConsumer("zookeeper:2181", topic_output)

    # Check if any messages were received
    repeat{
      # Poll for messages
      messages <- rkafka.readPoll(consumer)
      if (length(messages) > 0) {
        cat(messages)
        for (x in messages){
          new_df <- fromJSON(x)
          sum_num <- subset(new_df, key == "output")$value
        }
        break
      } else {
        cat("No messages received.\n")
      }
    }
    rkafka.closeConsumer(consumer)
    
    # Display the result
    output$result <- renderText({
      paste("The product of the sum is:", sum_num)
    })
  })
}

# Run the application
shinyApp(ui = ui, server = server)
