library(jsonlite)
library(kafka)

broker <- "kafka:9092"
print("Monte Carlo Backend Starting...")

consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = "backend_mc", "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
consumer$subscribe("input")
producer <- Producer$new(list("bootstrap.servers" = broker))

repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) {
        if (is.null(mess) || is.null(mess$value)) next
        incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
        
        payload <- fromJSON(mess$value)
        if (!is.null(payload$role) && payload$role == "VIEWER") next 
        
        # 1. EXTRACT PARAMS
        n_iter <- as.numeric(payload$n_iter)
        mean_val <- as.numeric(payload$mean_val)
        sd_val <- as.numeric(payload$sd_val)
        
        # 2. HEAVY COMPUTATION (The Monte Carlo Simulation)
        print(paste("Running simulation with N=", n_iter, "for", payload$sender))
        sim_data <- rnorm(n_iter, mean = mean_val, sd = sd_val)
        
        # 3. AGGREGATION (Don't send 1M rows over Kafka! Send the summary)
        hist_data <- hist(sim_data, breaks = 50, plot = FALSE)
        
        response_payload <- list(
          n_iter = n_iter,
          mean_val = mean_val,
          sd_val = sd_val,
          calc_mean = mean(sim_data),
          calc_sd = sd(sim_data),
          hist_counts = hist_data$counts,
          hist_mids = hist_data$mids,
          sender = payload$sender,
          timestamp = as.numeric(Sys.time())
        )
        
        producer$produce("output", toJSON(response_payload, auto_unbox = TRUE), key = incoming_key)
      }
    }
  }, error = function(e) { Sys.sleep(1) })
}