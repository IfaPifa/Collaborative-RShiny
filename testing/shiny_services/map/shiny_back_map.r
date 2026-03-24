library(jsonlite)
library(kafka)

broker <- "kafka:9092"
print("Geospatial Editor Backend Starting...")

consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = "backend_map", "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
consumer$subscribe("input")
producer <- Producer$new(list("bootstrap.servers" = broker))

# In-memory store for session POIs (Points of Interest)
session_pois <- list()

repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) {
        if (is.null(mess) || is.null(mess$value)) next
        incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
        
        payload <- fromJSON(mess$value)
        if (!is.null(payload$role) && payload$role == "VIEWER") next 
        
        # Initialize an empty dataframe for this session if it doesn't exist
        if (is.null(session_pois[[incoming_key]])) {
          session_pois[[incoming_key]] <- data.frame(lat=numeric(), lng=numeric(), sender=character(), stringsAsFactors=FALSE)
        }
        
        # Append the new click coordinate to the session's map
        if (!is.null(payload$lat) && !is.null(payload$lng)) {
           new_row <- data.frame(
             lat = as.numeric(payload$lat), 
             lng = as.numeric(payload$lng), 
             sender = payload$sender, 
             stringsAsFactors = FALSE
           )
           session_pois[[incoming_key]] <- rbind(session_pois[[incoming_key]], new_row)
        }
        
        # Broadcast the entire list of pins back to the frontend
        response_payload <- list(
          pois = session_pois[[incoming_key]],
          sender = payload$sender,
          timestamp = as.numeric(Sys.time())
        )
        producer$produce("output", toJSON(response_payload, auto_unbox = TRUE), key = incoming_key)
      }
    }
  }, error = function(e) { Sys.sleep(1) })
}