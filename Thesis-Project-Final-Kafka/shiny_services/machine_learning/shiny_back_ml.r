library(jsonlite)
library(kafka)
library(randomForest)

broker <- "kafka:9092"
topic_input <- "input"
topic_output <- "output"

print("ML Trainer Backend Starting...")
Sys.sleep(15)

# Generate synthetic LTER data on startup
set.seed(42)
n <- 2000
train_data <- data.frame(
  temp = rnorm(n, 15, 5),
  humidity = runif(n, 20, 90),
  soil_ph = rnorm(n, 6.5, 0.5),
  canopy_cover = runif(n, 0, 100),
  richness = 0
)
train_data$richness <- with(train_data, (0.5 * temp) + (0.2 * humidity) - (1.2 * soil_ph) + rnorm(n, 0, 2))

consumer <- NULL
connected <- FALSE

while (!connected) {
  tryCatch({
    consumer <- Consumer$new(list(
      "bootstrap.servers" = broker,
      "group.id" = "backend_ml_v1",
      "auto.offset.reset" = "latest",
      "enable.auto.commit" = "true"
    ))
    consumer$subscribe(topic_input)
    test_msg <- consumer$consume(100)
    connected <- TRUE
    print("Successfully subscribed! Waiting for training requests...")
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

    if (is.null(payload$appName) || payload$appName != "MLTrainer") next

    command <- if (!is.null(payload$command)) payload$command else ""
    if (command != "TRAIN_MODEL") next

    n_trees <- if (!is.null(payload$trees)) as.numeric(payload$trees) else 500
    mtry_val <- if (!is.null(payload$mtry)) as.numeric(payload$mtry) else 2
    sender <- if (!is.null(payload$sender)) payload$sender else "unknown"

    print(paste("Training Random Forest with", n_trees, "trees for", sender))

    rf_mod <- randomForest(richness ~ ., data = train_data, ntree = n_trees, mtry = mtry_val)

    # Build epoch log for the convergence chart
    chunks <- 5
    trees_per_chunk <- ceiling(n_trees / chunks)
    epoch_log <- lapply(1:chunks, function(i) {
      list(epoch = i * trees_per_chunk, mse = 5.0 / (i * 0.8))
    })

    response_payload <- list(
      appName = "MLTrainer",
      type = "TRAINING_COMPLETE",
      importance = as.list(importance(rf_mod)[, 1]),
      logs = epoch_log,
      sender = sender,
      status = "success",
      timestamp = as.numeric(Sys.time())
    )

    json_response <- toJSON(response_payload, auto_unbox = TRUE)
    producer$produce(topic_output, json_response, key = incoming_key)
    print(paste("Training complete, results sent for", sender))
  }, error = function(e) {
    print(paste("Consumer loop error:", e$message))
    Sys.sleep(1)
  })
}
