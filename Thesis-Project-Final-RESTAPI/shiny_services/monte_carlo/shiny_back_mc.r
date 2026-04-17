library(jsonlite)
library(kafka)

topic_input <- "input"
topic_output <- "output"
broker <- "kafka:9092"

print("LTER-LIFE Async Backend Starting...")

consumer <- Consumer$new(list(
  "bootstrap.servers" = broker,
  "group.id" = "backend_mc_eco", 
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
    if (is.null(payload$command) || payload$command != "START_SIMULATION") return()
    
    # 1. Extract Eco Parameters
    n_paths <- if (!is.null(payload$paths)) as.numeric(payload$paths) else 1000
    years <- if (!is.null(payload$years)) as.numeric(payload$years) else 50
    n0 <- if (!is.null(payload$n0)) as.numeric(payload$n0) else 100 # Initial Population
    r <- if (!is.null(payload$growth_rate)) as.numeric(payload$growth_rate) else 0.02
    env_var <- if (!is.null(payload$env_var)) as.numeric(payload$env_var) else 0.1
    sender <- payload$sender
    
    # --- ASYNC SIMULATION WITH PROGRESS ---
    chunks <- 10
    paths_per_chunk <- n_paths / chunks
    
    # Pre-allocate matrix for paths: rows = years (0 to years), cols = paths
    all_paths <- matrix(0, nrow = years + 1, ncol = n_paths)
    all_paths[1, ] <- n0
    
    for (c in 1:chunks) {
      start_col <- (c - 1) * paths_per_chunk + 1
      end_col <- c * paths_per_chunk
      
      # Simulate Stochastic Population Growth (Geometric Brownian Motion analogy)
      for (t in 2:(years + 1)) {
        noise <- rnorm(paths_per_chunk, mean = 0, sd = env_var)
        all_paths[t, start_col:end_col] <- all_paths[t-1, start_col:end_col] * exp(r - (env_var^2)/2 + noise)
      }
      
      # Broadcast Progress
      progress_payload <- list(
        type = "PROGRESS",
        percent = (c / chunks) * 100,
        sender = sender
      )
      producer$produce(topic_output, toJSON(progress_payload, auto_unbox = TRUE), key = incoming_key)
      
      # Artificial delay to simulate heavy compute for demo purposes
      Sys.sleep(0.3) 
    }
    
    # --- SMART PAYLOAD REDUCTION ---
    # Calculate summary statistics across all paths for each year
    mean_path <- apply(all_paths, 1, mean)
    lower_95 <- apply(all_paths, 1, quantile, probs = 0.025)
    upper_95 <- apply(all_paths, 1, quantile, probs = 0.975)
    
    # Select 3 random sample paths to visualize individual trajectories
    sample_indices <- sample(1:n_paths, 3)
    samples <- all_paths[, sample_indices]
    
    result_payload <- list(
      type = "RESULT",
      sender = sender,
      years = 0:years,
      mean_path = mean_path,
      lower_95 = lower_95,
      upper_95 = upper_95,
      sample_1 = samples[, 1],
      sample_2 = samples[, 2],
      sample_3 = samples[, 3],
      extinction_prob = sum(all_paths[years + 1, ] < 1) / n_paths # Probability of dropping below 1 individual
    )
    
    producer$produce(topic_output, toJSON(result_payload, auto_unbox = TRUE), key = incoming_key)
    
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