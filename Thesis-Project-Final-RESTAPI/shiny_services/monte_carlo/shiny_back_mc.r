library(plumber)
library(jsonlite)

#* @apiTitle Population Viability Simulator Backend (REST)

#* Run a stochastic population simulation
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) { body_text <- rawToChar(raw_body) } else if (is.character(raw_body)) { body_text <- raw_body } else { body_text <- NULL }
  if (!is.null(body_text)) { body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE) } else { body <- raw_body }

  command <- if (!is.null(body$command)) body$command else ""
  if (command != "START_SIMULATION") {
    return(list(status = "ignored", message = "Unknown command"))
  }

  n_paths <- if (!is.null(body$paths)) as.numeric(body$paths) else 1000
  years <- if (!is.null(body$years)) as.numeric(body$years) else 50
  n0 <- if (!is.null(body$n0)) as.numeric(body$n0) else 100
  r <- if (!is.null(body$growth_rate)) as.numeric(body$growth_rate) else 0.02
  env_var <- if (!is.null(body$env_var)) as.numeric(body$env_var) else 0.1
  sender <- if (!is.null(body$sender)) body$sender else "unknown"

  # Pre-allocate matrix for paths
  all_paths <- matrix(0, nrow = years + 1, ncol = n_paths)
  all_paths[1, ] <- n0

  # Simulate Stochastic Population Growth
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

  return(list(
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
  ))
}
