library(jsonlite)
library(kafka)

topic_input <- "input"
topic_output <- "output"
broker <- "kafka:9092"

print("Eco Visual Analytics Backend Starting...")

consumer <- Consumer$new(list(
  "bootstrap.servers" = broker,
  "group.id" = "backend_analytics_v1", 
  "auto.offset.reset" = "latest",
  "enable.auto.commit" = "true"
))
consumer$subscribe(topic_input)
producer <- Producer$new(list("bootstrap.servers" = broker))

process_message <- function(mess) {
  if (is.null(mess) || is.null(mess$value)) return()
  incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
  
  tryCatch({
    payload <- fromJSON(mess$value)
    
    # Consistency Check
    if (!is.null(payload$role) && payload$role == "VIEWER") return()
    
    # 1. Extract and validate ecological parameters
    min_temp <- if (!is.null(payload$min_temp)) as.numeric(payload$min_temp) else 50
    months_filter <- if (!is.null(payload$months)) as.numeric(payload$months) else c(5, 6, 7, 8, 9)
    sender <- if (!is.null(payload$sender)) payload$sender else "unknown"
    
    # 2. Package ONLY the state parameters back to the mesh
    response_payload <- list(
      type = "STATE_UPDATE",
      min_temp = min_temp,
      months = months_filter,
      sender = sender,
      timestamp = as.numeric(Sys.time())
    )
    
    # Convert to JSON and send
    json_response <- toJSON(response_payload, auto_unbox = TRUE)
    producer$produce(topic_output, json_response, key = incoming_key)
    
  }, error = function(e) {
    print(paste("Error:", e$message))
  })
}

# Main Loop
repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) process_message(mess)
    }
  }, error = function(e) { Sys.sleep(1) })
}