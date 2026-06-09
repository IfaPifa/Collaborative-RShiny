library(jsonlite)
library(kafka)

broker <- "kafka:9092"
topic_input <- "input"
topic_output <- "output"

print("Monte Carlo Backend Starting...")
Sys.sleep(15)

consumer <- NULL
connected <- FALSE

while (!connected) {
  tryCatch({
    consumer <- Consumer$new(list(
      "bootstrap.servers" = broker,
      "group.id" = "backend_mc_v2",
      "auto.offset.reset" = "latest",
      "enable.auto.commit" = "true"
    ))
    consumer$subscribe(topic_input)
    test_msg <- consumer$consume(100)
    connected <- TRUE
    print("Successfully subscribed! Waiting for simulation requests...")
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

    if (is.null(payload$appName) || payload$appName != "MonteCarlo") next

    command <- if (!is.null(payload$command)) payload$command else ""
    if (command != "START_SIMULATION") next

    n_paths <- if (!is.null(payload$paths)) as.numeric(payload$paths) else 1000
    years <- if (!is.null(payload$years)) as.numeric(payload$years) else 50
    n0 <- if (!is.null(payload$n0)) as.numeric(payload$n0) else 100
    r <- if (!is.null(payload$growth_rate)) as.numeric(payload$growth_rate) else 0.02
    env_var <- if (!is.null(payload$env_var)) as.numeric(payload$env_var) else 0.1
    sender <- if (!is.null(payload$sender)) payload$sender else "unknown"

    print(paste("Running simulation with N0=", n0, "paths=", n_paths, "for", sender))

    # Pre-allocate matrix for paths
    all_paths <- matrix(0, nrow = years + 1, ncol = n_paths)
    all_paths[1, ] <- n0

    # Simulate stochastic population growth
    for (t in 2:(years + 1)) {
      noise <- rnorm(n_paths, mean = 0, sd = env_var)
      all_paths[t, ] <- all_paths[t - 1, ] * exp(r - (env_var^2) / 2 + noise)
    }

    # Summary statistics
    mean_path <- apply(all_paths, 1, mean)
    lower_95 <- apply(all_paths, 1, quantile, probs = 0.025)
    upper_95 <- apply(all_paths, 1, quantile, probs = 0.975)

    # 3 random sample trajectories
    sample_indices <- sample(1:n_paths, 3)
    samples <- all_paths[, sample_indices]

    response_payload <- list(
      appName = "MonteCarlo",
      type = "RESULT",
      sender = sender,
      years = 0:years,
      mean_path = mean_path,
      lower_95 = lower_95,
      upper_95 = upper_95,
      sample_1 = samples[, 1],
      sample_2 = samples[, 2],
      sample_3 = samples[, 3],
      extinction_prob = sum(all_paths[years + 1, ] < 1) / n_paths,
      status = "success",
      timestamp = as.numeric(Sys.time())
    )
    if (!is.null(payload[["_marker"]])) response_payload[["_marker"]] <- payload[["_marker"]]
    json_response <- toJSON(response_payload, auto_unbox = TRUE)
    producer$produce(topic_output, json_response, key = incoming_key)
    print(paste("Simulation complete, results sent for", sender))
  }, error = function(e) {
    print(paste("Consumer loop error:", e$message))
    Sys.sleep(1)
  })
}
