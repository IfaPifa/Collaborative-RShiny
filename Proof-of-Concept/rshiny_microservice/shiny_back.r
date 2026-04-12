install.packages("rkafka")
install.packages("jsonlite")
library(jsonlite)
library(rkafka)

# Define the Kafka broker and topic
broker <- "broker:29092"  # Use the appropriate address and port
topic <- "output"  # Replace with your topic name
# Function to add two numbers
add_up <- function(a, b) {return(a + b)}

# Function to consume messages
consume_messages <- function(consumer, timeout = 1000) {
  # Poll for messages
  messages <- rkafka.readPoll(consumer)
  # Check if any messages were received
  if (length(messages) > 0) {
    cat(messages)
    for (x in messages){
        new_df <- fromJSON(x)
        num1 <- subset(new_df, key == "num1")$value
        num2 <- subset(new_df, key == "num2")$value
        out_num <- add_up(num1,num2)
        #Create Message
        json_df <- data.frame(key = c("output"), 
                            value = c(out_num), 
                            stringsAsFactors = FALSE)
        json_message <- toJSON(json_df, pretty=TRUE)
        #Create a Kafka producer
        producer <- rkafka.createProducer(broker)
        # Send the JSON message to the specified topic
        rkafka.send(producer, topic, "localhost:9092", json_message)
        #Close a Kafka producer
        rkafka.closeProducer(producer)
    }
  } else {
    cat("No messages received.\n")
  }
}

consumer <- rkafka.createConsumer("zookeeper:2181", "input")
repeat {
  print('Checking messages')
  # Your code to do file manipulation
  consume_messages(consumer)
}
# Consume messages

# Close the consumer
rkafka.closeConsumer(consumer)

