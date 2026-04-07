library(jsonlite)
library(kafka)

# --- CONFIGURATION ---
topic_input <- "input"
topic_output <- "output"
broker <- "kafka:9092"

print("Eco Deployment Calculator Backend Starting...")

# Consumer Config
consumer_config <- list(
  "bootstrap.servers" = broker,
  "group.id" = "backend_calc_service_v2", 
  "auto.offset.reset" = "latest",
  "enable.auto.commit" = "true"
)

# --- 1. ROBUST CONNECTION LOOP ---
consumer <- NULL
connected <- FALSE

while (!connected) {
  tryCatch({
    print(paste("Attempting to subscribe to topic:", topic_input, "..."))
    consumer <- Consumer$new(consumer_config)
    consumer$subscribe(topic_input)
    connected <- TRUE
    print("✅ Successfully subscribed! Waiting for mesh events...")
  }, error = function(e) {
    print(paste("⚠️ Kafka not ready yet:", e$message))
    print("Retrying in 5 seconds...")
    Sys.sleep(5)
  })
}

producer <- Producer$new(list("bootstrap.servers" = broker))

# --- LOGIC LOOP ---
add_up <- function(a, b) { return(a + b) }

process_message <- function(mess) {
  if (is.null(mess) || is.null(mess$value)) return()

  incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
  
  tryCatch({
    payload <- fromJSON(mess$value)
    
    sender_role <- if (!is.null(payload$role)) payload$role else "UNKNOWN"
    if (sender_role == "VIEWER") {
      print(paste("⚠️ CONSISTENCY ALERT: Dropped illegal write from Viewer on key:", incoming_key))
      return() # Discard message, do not broadcast update
    }
    
    sender <- if (!is.null(payload$sender)) payload$sender else "unknown"
    print(paste("Processing sensor sync on key:", incoming_key, "from sender:", sender))
    
    num1 <- as.numeric(payload$num1)
    num2 <- as.numeric(payload$num2)
    result <- add_up(num1, num2)
    
    response_payload <- list(
      result = result,
      num1 = num1,
      num2 = num2,
      sender = sender,
      status = "success",
      timestamp = as.numeric(Sys.time())
    )
    json_response <- toJSON(response_payload, auto_unbox = TRUE)
    
    producer$produce(topic_output, json_response, key = incoming_key)
    
  }, error = function(e) {
    print(paste("Error processing message:", e$message))
  })
}

# --- MAIN LOOP ---
repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) {
        process_message(mess)
      }
    }
  }, error = function(e) {
    print(paste("Consumer loop error:", e$message))
    Sys.sleep(1)
  })
}