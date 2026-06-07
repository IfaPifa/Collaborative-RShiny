library(jsonlite)
library(kafka)

broker <- "kafka:9092"
print("Data Exchange Backend Starting...")

consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = "backend_csv", "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
consumer$subscribe("input")
producer <- Producer$new(list("bootstrap.servers" = broker))

repeat {
  tryCatch({
    result <- consumer$consume(500)
    if (result_has_error(result)) next
    mess <- result_message(result)
    if (is.null(mess) || is.null(mess$value)) next
    incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
    
    payload <- fromJSON(mess$value)

    if (!is.null(payload$role) && payload$role == "VIEWER") next 

    if (is.null(payload$dataset)) next

    # 1. PARSE DATA
    df <- as.data.frame(payload$dataset)
    
    # 2. STRING MANIPULATION (Clean the Data)
    if (nrow(df) > 0) {
      for (col in names(df)) {
        if (is.character(df[[col]])) {
          df[[col]] <- toupper(trimws(df[[col]]))
          df[[col]] <- gsub("[^A-Z0-9 ]", "", df[[col]])
        }
      }
    }
    
    response_payload <- list(
      dataset = df,
      sender = payload$sender,
      timestamp = as.numeric(Sys.time())
    )
    producer$produce("output", toJSON(response_payload, auto_unbox = TRUE), key = incoming_key)
  }, error = function(e) { Sys.sleep(1) })
}