install.packages("jsonlite")
library(shiny)
library(jsonlite)
library(kafka)

# Define the Kafka broker and topic
broker <- "kafka:9092"  # Use the appropriate address and port
topic_input <- "input"  # Replace with your topic name
topic_output <- "output"  # Replace with your topic name

config <- list(
  "bootstrap.servers" = broker
)

consumer <- Consumer$new(list(
  "bootstrap.servers" = "kafka:9092",
  "auto.offset.reset" = "earliest",
  "group.id" = paste(sample(letters, 10), collapse = ""),
  "enable.auto.commit" = "True"
))

consumer$subscribe("output")

sum_num <- 0
current_values <- list(num1 = 0, num2 = 0)

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
server <- function(input, output, session) {
  
  # Observe the calculate button
  observeEvent(input$calculate, {
    current_values$num1 <<- input$num1
    current_values$num2 <<- input$num2
    
    json_df <- data.frame(key = c("num1","num2"), 
                          value = c(current_values$num1, current_values$num2), 
                          stringsAsFactors = FALSE)
    json_message <- toJSON(json_df, pretty=FALSE)
    
    # Create a Kafka producer
    producer <- Producer$new(config)
    # Send the JSON message to the specified topic
    producer$produce(topic_input, json_message)
    
    repeat{
      mess <- result_message(consumer$consume(5000))
      if (!is.null(mess$value)) {
        print(mess)
        new_df <- fromJSON(mess$value)
        sum_num <<- subset(new_df, key == "output")$value
        break
      } else {
        cat("No messages received.\n")
      }
    }
    
  })
  
  # Reactive polling for global values
  reactive_data <- reactivePoll(1000, session,
                                checkFunc = function() {
                                  sum_num
                                },
                                valueFunc = function() {
                                  list(sum = sum_num, num1 = current_values$num1, num2 = current_values$num2)
                                }
  )
  
  # Update the inputs and output based on the global state
  observe({
    
    data <- reactive_data()
    
    updateNumericInput(session, "num1", value = data$num1)
    updateNumericInput(session, "num2", value = data$num2)
    
    output$result <- renderText({
      result <- data$sum
      paste("The product of the sum is:", result)
    })
  })
}

# Run the application
shinyApp(ui = ui, server = server)
