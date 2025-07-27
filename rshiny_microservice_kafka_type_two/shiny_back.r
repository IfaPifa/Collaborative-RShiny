install.packages("jsonlite")
library(jsonlite)
library(kafka)

# Define the Kafka broker and topic
topic <- "output"  # Replace with your topic name
# Function to add two numbers
add_up <- function(a, b) {return(a + b)}

config <- list(
  "bootstrap.servers" = "kafka:9092"
)

# Function to consume messages
consume_messages <- function(consumer, timeout = 1000) {
  # Poll for messages
  mess <- result_message(consumer$consume(5000))
  # Check if any messages were received
  if (!is.null(mess$value)) {
    print(typeof(mess))
    print(mess)
    new_df <- fromJSON(mess$value)
    num1 <- subset(new_df, key == "num1")$value
    num2 <- subset(new_df, key == "num2")$value
    out_num <- add_up(num1,num2)
    #Create Message
    json_df <- data.frame(key = c("output","num1","num2"), 
                          value = c(out_num, num1, num2), 
                          stringsAsFactors = FALSE)
    json_message <- toJSON(json_df, pretty=FALSE)
    #Create a Kafka producer
    producer <- Producer$new(config)
    # Send the JSON message to the specified topic
    producer$produce(topic, json_message)
    } else {
    cat("No messages received.\n")
  }
}

consumer <- Consumer$new(list(
  "bootstrap.servers" = "kafka:9092",
  "auto.offset.reset" = "earliest",
  "group.id" = paste(sample(letters, 10), collapse = ""),
  "enable.auto.commit" = "True"
))


consumer$subscribe("input")

repeat {
  print('Checking messages')
  # Your code to do file manipulation
  consume_messages(consumer)
}
# Consume messages

consumer$close()

