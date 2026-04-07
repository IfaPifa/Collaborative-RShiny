library(jsonlite)
library(kafka)

broker <- "kafka:9092"
print("LTER-LIFE Geospatial Delta-Worker Starting...")

consumer <- Consumer$new(list(
  "bootstrap.servers" = broker,
  "group.id" = "backend_map_eco", 
  "auto.offset.reset" = "latest",
  "enable.auto.commit" = "true"
))
consumer$subscribe("input")
producer <- Producer$new(list("bootstrap.servers" = broker))

process_message <- function(mess) {
  if (is.null(mess) || is.null(mess$value)) return()
  incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
  
  tryCatch({
    payload <- fromJSON(mess$value)
    
    # 1. Ignore viewer clicks
    if (!is.null(payload$role) && payload$role == "VIEWER") return()
    
    # 2. Process Delta Sync (New Sensor Deployment)
    if (!is.null(payload$type) && payload$type == "NEW_SENSOR") {
      
      # In a real enterprise app, you could add geospatial validation here 
      # (e.g., checking if the coordinate falls within a specific ecological zone).
      # For now, we act as a lightweight, stateless event router.
      
      response_payload <- list(
        type = "DELTA",
        lat = as.numeric(payload$lat),
        lng = as.numeric(payload$lng),
        sensor_type = payload$sensor_type,
        sender = payload$sender,
        timestamp = as.numeric(Sys.time())
      )
      
      # Broadcast the single new sensor to the mesh
      producer$produce("output", toJSON(response_payload, auto_unbox = TRUE), key = incoming_key)
    }
  }, error = function(e) {
    print(paste("Error:", e$message))
  })
}

repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) process_message(mess)
    }
  }, error = function(e) { Sys.sleep(1) })
}