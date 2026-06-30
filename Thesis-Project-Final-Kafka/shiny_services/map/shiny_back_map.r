library(jsonlite)
library(kafka)

broker <- "kafka:9092"
topic_input <- "input.geospatial"
topic_output <- "output"

print("Geospatial Editor Backend Starting (Kafka whole-state mode)...")
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
    result <- consumer$consume(100)
    if (result_has_error(result)) next
    mess <- result_message(result)
    if (is.null(mess) || is.null(mess$value)) next
    
    incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
    
    payload <- tryCatch(fromJSON(mess$value), error = function(e) NULL)
    if (!is.list(payload)) next
    
    if (!is.null(payload$role) && payload$role == "VIEWER") next

    if (is.null(payload$appName) || payload$appName != "Geospatial") next

    # Whole-state model: the frontend (or Spring on restore) sends the full pin
    # set; the backend is a stateless relay that echoes the complete state to
    # output, exactly like the other apps. This makes getLatestState() capture
    # the entire map, so save/restore and late-join work uniformly.
    if (!is.null(payload$type) && payload$type %in% c("STATE", "NEW_SENSOR", "DELTA")) {
      pins <- payload$pins
      if (is.null(pins)) pins <- list()  # tolerate empty / malformed
      response_payload <- list(
        appName = "Geospatial",
        type = "STATE",
        pins = pins,
        sender = payload$sender,
        status = "success",
        timestamp = as.numeric(Sys.time())
      )
      if (!is.null(payload[["_marker"]])) response_payload[["_marker"]] <- payload[["_marker"]]
      json_response <- toJSON(response_payload, auto_unbox = TRUE, dataframe = "rows")
      producer$produce(topic_output, json_response, key = incoming_key)
    }
  }, error = function(e) { 
    print(paste("Consumer loop error:", e$message))
    Sys.sleep(1) 
  })
}