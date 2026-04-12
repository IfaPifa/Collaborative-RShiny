install.packages('rkafka')
library(rkafka)

# Function to consume messages
consume_messages <- function(consumer, timeout = 1000) {
  # Poll for messages
  messages <- rkafka.readPoll(consumer)
  
  # Check if any messages were received
  if (length(messages) > 0) {
    cat(messages)
  } else {
    cat("No messages received.\n")
  }
}

consumer <- rkafka.createConsumer("zookeeper:2181", "test")
repeat {
  print('Checking messages')
  # Your code to do file manipulation
  consume_messages(consumer)
  
  Sys.sleep(time=5)  # to stop execution for 5 sec
}
# Consume messages

# Close the consumer
rkafka.closeConsumer(consumer)
