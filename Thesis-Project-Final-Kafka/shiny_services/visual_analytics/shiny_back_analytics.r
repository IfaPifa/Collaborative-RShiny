library(jsonlite)
library(kafka)
library(dplyr)

broker <- "kafka:9092"
topic_input <- "input"
topic_output <- "output"

print("Visual Analytics Backend Starting...")
print("⏳ Giving Kafka 15 seconds to fully boot and create topic partitions...")
Sys.sleep(15)

# --- 1. ROBUST CONNECTION LOOP ---
consumer <- NULL
connected <- FALSE

while (!connected) {
  tryCatch({
    consumer <- Consumer$new(list(
      "bootstrap.servers" = broker,
      "group.id" = "backend_analytics_v1", 
      "auto.offset.reset" = "latest",
      "enable.auto.commit" = "true"
    ))
    consumer$subscribe(topic_input)
    test_msg <- consumer$consume(100)
    connected <- TRUE
    print("✅ Successfully subscribed and verified topic! Waiting for messages...")
  }, error = function(e) {
    Sys.sleep(5)
  })
}

producer <- Producer$new(list("bootstrap.servers" = broker))
df <- mtcars

# --- 2. LOGIC LOOP ---
repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) {
        if (!is.list(mess) || is.null(mess$value)) next
        
        incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
        payload <- tryCatch(fromJSON(mess$value), error = function(e) NULL)
        if (!is.list(payload)) next
        
        if (!is.null(payload$role) && payload$role == "VIEWER") next
        
        # 🚨 CROSS-APP HIJACK PREVENTION 🚨
        if (is.null(payload$min_hp) && is.null(payload$cyl)) next
        
        min_hp <- as.numeric(payload$min_hp)
        cyl_filter <- as.numeric(payload$cyl)
        sender <- if (!is.null(payload$sender)) payload$sender else "unknown"
        
        filtered_df <- df %>% filter(hp >= min_hp, cyl %in% cyl_filter)
        
        response_payload <- list(
          data = filtered_df,
          min_hp = min_hp,
          cyl = cyl_filter,
          sender = sender,
          timestamp = as.numeric(Sys.time())
        )
        
        json_response <- toJSON(response_payload, auto_unbox = TRUE)
        producer$produce(topic_output, json_response, key = incoming_key)
      }
    }
  }, error = function(e) { 
    print(paste("Consumer loop error:", e$message))
    Sys.sleep(1) 
  })
}