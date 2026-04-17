library(jsonlite)
library(kafka)
library(dplyr)

topic_input <- "input"
topic_output <- "output"
broker <- "kafka:9092"

print("Visual Analytics Backend Starting...")

consumer <- Consumer$new(list(
  "bootstrap.servers" = broker,
  "group.id" = "backend_analytics_v1", 
  "auto.offset.reset" = "latest",
  "enable.auto.commit" = "true"
))
consumer$subscribe(topic_input)
producer <- Producer$new(list("bootstrap.servers" = broker))

# Pre-load dataset
df <- mtcars

process_message <- function(mess) {
  if (is.null(mess) || is.null(mess$value)) return()
  incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
  
  tryCatch({
    payload <- fromJSON(mess$value)
    
    # Consistency Check
    if (!is.null(payload$role) && payload$role == "VIEWER") return()
    
    # 1. Extract parameters from UI
    min_hp <- if (!is.null(payload$min_hp)) as.numeric(payload$min_hp) else 50
    cyl_filter <- if (!is.null(payload$cyl)) as.numeric(payload$cyl) else c(4, 6, 8)
    sender <- if (!is.null(payload$sender)) payload$sender else "unknown"
    
    # 2. Data Manipulation (dplyr)
    filtered_df <- df %>%
      filter(hp >= min_hp, cyl %in% cyl_filter)
    
    # 3. Package the data back to the frontend
    response_payload <- list(
      data = filtered_df,
      min_hp = min_hp,
      cyl = cyl_filter,
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