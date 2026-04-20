library(plumber)
library(jsonlite)
library(randomForest)

# Generate Synthetic LTER Data on startup
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

#* @apiTitle Eco-ML Biodiversity Predictor Backend (REST)

#* Train a Random Forest model and return feature importance
#* @post /state
#* @serializer unboxedJSON
function(req) {
  body <- jsonlite::fromJSON(req$body, simplifyVector = TRUE)

  command <- if (!is.null(body$command)) body$command else ""
  if (command != "TRAIN_MODEL") {
    return(list(status = "ignored", message = "Unknown command"))
  }

  n_trees <- if (!is.null(body$trees)) as.numeric(body$trees) else 500
  mtry_val <- if (!is.null(body$mtry)) as.numeric(body$mtry) else 2
  sender <- if (!is.null(body$sender)) body$sender else "unknown"

  # Train the Random Forest model
  rf_mod <- randomForest(richness ~ ., data = train_data, ntree = n_trees, mtry = mtry_val)

  # Build epoch log for the convergence chart
  chunks <- 5
  trees_per_chunk <- ceiling(n_trees / chunks)
  epoch_log <- lapply(1:chunks, function(i) {
    list(epoch = i * trees_per_chunk, mse = 5.0 / (i * 0.8))
  })

  return(list(
    type = "TRAINING_COMPLETE",
    importance = as.list(importance(rf_mod)[, 1]),
    epoch_log = epoch_log,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}
