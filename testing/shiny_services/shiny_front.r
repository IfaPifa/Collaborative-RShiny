library(shiny)
library(jsonlite)
library(kafka)

# Define the UI
ui <- fluidPage(
  titlePanel("Add Numbers"),
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
  message_temp <- data.frame(key = c("output","num1","num2"), 
                             value = c(sum_num, 0, 0), 
                             stringsAsFactors = FALSE)
  
  # Observe the calculate button
  observeEvent(input$calculate, {
    num1 <- input$num1
    num2 <- input$num2
    
    json_df <- data.frame(key = c("num1","num2"), 
                          value = c(num1, num2), 
                          stringsAsFactors = FALSE)
    json_message <- toJSON(json_df, pretty=FALSE)
    
    # Create a Kafka producer
    producer <- Producer$new(config)
    # Send the JSON message to the specified topic
    producer$produce(topic_input, json_message)
    
  })
  
  kafkaMessage <- reactivePoll(1000, session,
                               checkFunc = function() {
                                 mess <- result_message(consumer$consume(5000))
                                 print(mess$value)
                                 if (!is.null(mess$value)) {
                                   temp <- fromJSON(mess$value)
                                   message_temp$value <<- temp$value
                                   print("Message was consumed")
                                   return(temp)
                                 }
                                 print("No Messages")
                                 return(message_temp)
                               },
                               valueFunc = function() {
                                 print("Returning message temp")
                                 return(message_temp)
                               }
  )
  
  observe({
    
    kmess <- kafkaMessage()
    print("Kmess is:")
    print(kmess)
    sum_num <<- subset(kmess, key == "output")$value
    input_number_one <- subset(kmess, key == "num1")$value
    input_number_two <- subset(kmess, key == "num2")$value
    print("Sum num is:")
    print(sum_num)
    
    updateNumericInput(session, "num1", value = input_number_one)
    updateNumericInput(session, "num2", value = input_number_two)
    
    output$result <- renderText({
      result <- sum_num
      paste("The product of the sum is:", result)
    })
  })
}

# Run the application
shinyApp(ui = ui, server = server)
