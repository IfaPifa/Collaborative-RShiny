install.packages('rkafka')
library(rkafka)

# Function to add two numbers
add_up <- function(a, b) {return(a + b)}

# Define the Kafka broker and topic
broker <- "broker:29092"  # Use the appropriate address and port
topic <- "test"  # Replace with your topic name

# Create a JSON message
json_message <- '{"key": "value", "another_key": "another_value"}'

# Create a Kafka producer
producer <- rkafka.createProducer(broker)

# Send the JSON message to the specified topic
rkafka.send(producer, topic, "localhost:9092", json_message)

rkafka.closeProducer(producer)



