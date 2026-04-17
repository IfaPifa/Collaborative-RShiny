library(jsonlite)
library(kafka)
library(randomForest)

broker <- "kafka:9092"
print("Eco-ML Backend Worker Starting...")

consumer <- Consumer$new(list(
  "bootstrap.servers" = broker, 
  "group.id" = "backend_ml_worker",
  "auto.offset.reset" = "latest",
  "enable.auto.commit" = "true"
))
consumer$subscribe("input")
producer <- Producer$new(list("bootstrap.servers" = broker))

# Generate Synthetic LTER Data
set.seed(42)
n <- 2000
train_data <- data.frame(
  temp = rnorm(n, 15, 5),
  humidity = runif(n, 20, 90),
  soil_ph = rnorm(n, 6.5, 0.5),
  canopy_cover = runif(n, 0, 100),
  richness = 0 # Target
)
train_data$richness <- with(train_data, (0.5*temp) + (0.2*humidity) - (1.2*soil_ph) + rnorm(n, 0, 2))

process_ml <- function(mess) {
  # FIX 1: Guard against NULL messages from Kafka
  if (is.null(mess) || is.null(mess$value)) return()
  incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
  
  tryCatch({
    payload <- fromJSON(mess$value)
    if (is.null(payload$command) || payload$command != "TRAIN_MODEL") return()
    
    n_trees <- payload$trees
    mtry_val <- payload$mtry
    
    chunks <- 5
    trees_per_chunk <- ceiling(n_trees / chunks)
    
    for (i in 1:chunks) {
      Sys.sleep(1.5) # Simulate heavy compute
      
      progress_payload <- list(
        type = "EPOCH_UPDATE",
        epoch = i * trees_per_chunk,
        mse = 5.0 / (i * 0.8), 
        percent = (i / chunks) * 100
      )
      producer$produce("output", toJSON(progress_payload, auto_unbox = TRUE), key = incoming_key)
    }
    
    rf_mod <- randomForest(richness ~ ., data = train_data, ntree = 100, mtry = mtry_val)
    
    final_payload <- list(
      type = "TRAINING_COMPLETE",
      importance = as.list(importance(rf_mod)[,1]),
      sender = "mesh_worker_01"
    )
    producer$produce("output", toJSON(final_payload, auto_unbox = TRUE), key = incoming_key)
    
  }, error = function(e) {
    print(paste("Error processing ML payload:", e$message))
  })
}

# FIX 2: Wrap the repeat loop in a tryCatch so the container doesn't halt
repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) process_ml(mess)
    }
  }, error = function(e) { Sys.sleep(1) })
}