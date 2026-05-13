library(jsonlite)
library(kafka)

broker <- "kafka:9092"
topic_input <- "input"
topic_output <- "output"

print("Geospatial Editor Backend Starting (Kafka DELTA mode)...")
print("⏳ Giving Kafka 15 seconds to fully boot and create topic partitions...")
Sys.sleep(15)

# --- 1. ROBUST CONNECTION LOOP ---
consumer_config <- list(
  "bootstrap.servers" = broker, 
  "group.id" = "backend_map", 
  "auto.offset.reset" = "latest", 
  "enable.auto.commit" = "true"
)

consumer <- NULL
connected <- FALSE

while (!connected) {
  tryCatch({
    print(paste("Attempting to subscribe to topic:", topic_input, "..."))
    consumer <- Consumer$new(consumer_config)
    consumer$subscribe(topic_input)
    
    # THE SECRET SAUCE: A "Test Consume"
    # If the topic is not fully initialized by Kafka yet, this will fail 
    # and safely trigger the retry instead of breaking the main loop later!
    test_msg <- consumer$consume(100)
    
    connected <- TRUE
    print("✅ Successfully subscribed and verified topic! Waiting for messages...")
  }, error = function(e) {
    print(paste("⚠️ Kafka topic not ready yet:", e$message))
    Sys.sleep(5) # Wait and retry
  })
}

producer <- Producer$new(list("bootstrap.servers" = broker))

# --- 2. LOGIC LOOP ---
repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) {
        
        # BULLETPROOF CHECK: Ignore raw error strings from Kafka
        if (!is.list(mess) || is.null(mess$value)) next
        
        incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
        
        # Safe JSON parsing
        payload <- tryCatch(fromJSON(mess$value), error = function(e) NULL)
        if (!is.list(payload)) next
        
        # Security Guardrail
        if (!is.null(payload$role) && payload$role == "VIEWER") {
          print(paste("Dropped illegal write from Viewer on key:", incoming_key))
          next 
        }
        
        # TIME MACHINE FIX: Allow both NEW_SENSOR and DELTA
        if (!is.null(payload$type) && payload$type %in% c("NEW_SENSOR", "DELTA")) {
          response_payload <- list(
            type = "DELTA",
            lat = as.numeric(payload$lat),
            lng = as.numeric(payload$lng),
            sensor_type = payload$sensor_type,
            sender = payload$sender, 
            status = "success",
            timestamp = as.numeric(Sys.time())
          )
          
          json_response <- toJSON(response_payload, auto_unbox = TRUE)
          producer$produce(topic_output, json_response, key = incoming_key)
        }
      }
    }
  }, error = function(e) { 
    print(paste("Consumer loop error:", e$message))
    Sys.sleep(1) 
  })
}