library(jsonlite)
library(kafka)

broker <- "kafka:9092"
topic_input <- "input"
topic_output <- "output"

print("Advanced Visual Analytics Backend Starting...")
Sys.sleep(15)

consumer <- NULL
connected <- FALSE

while (!connected) {
  tryCatch({
    consumer <- Consumer$new(list(
      "bootstrap.servers" = broker,
      "group.id" = "backend_adv_analytics_v1",
      "auto.offset.reset" = "latest",
      "enable.auto.commit" = "true"
    ))
    consumer$subscribe(topic_input)
    test_msg <- consumer$consume(100)
    connected <- TRUE
    print("Successfully subscribed! Waiting for messages...")
  }, error = function(e) {
    Sys.sleep(5)
  })
}

producer <- Producer$new(list("bootstrap.servers" = broker))

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

    # Only process Advanced analytics messages
    if (is.null(payload$appName) || payload$appName != "Advanced") next

    min_temp <- as.numeric(payload$min_temp)
    months_filter <- if (!is.null(payload$months)) as.numeric(payload$months) else c(5, 6, 7, 8, 9)
    sender <- if (!is.null(payload$sender)) payload$sender else "unknown"

    response_payload <- list(
      appName = "Advanced",
      min_temp = min_temp,
      months = months_filter,
      sender = sender,
      status = "success",
      timestamp = as.numeric(Sys.time())
    )
    if (!is.null(payload[["_marker"]])) response_payload[["_marker"]] <- payload[["_marker"]]
    json_response <- toJSON(response_payload, auto_unbox = TRUE)
    producer$produce(topic_output, json_response, key = incoming_key)
  }, error = function(e) {
    print(paste("Consumer loop error:", e$message))
    Sys.sleep(1)
  })
}
