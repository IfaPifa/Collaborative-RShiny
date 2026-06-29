# Shared Monte Carlo simulation for the file hand-off demo (producer + consumer).
# Stochastic (rnorm, NO set.seed()): every run differs, which is exactly why the
# computed result -- not the inputs -- must be the thing that is shared.

mc_simulate <- function(n0 = 500, growth_rate = 0.02, env_var = 0.15,
                        paths = 2000, years = 30) {
  K <- n0 * 10
  all_paths <- matrix(0, nrow = years + 1, ncol = paths)
  all_paths[1, ] <- n0
  for (t in 2:(years + 1)) {
    noise <- rnorm(paths, mean = 0, sd = env_var)   # stochastic: no set.seed()
    all_paths[t, ] <- all_paths[t - 1, ] * exp(growth_rate - (env_var^2) / 2 + noise)
  }
  list(
    years           = 0:years,
    mean_path       = apply(all_paths, 1, mean),
    lower_95        = apply(all_paths, 1, quantile, probs = 0.025),
    upper_95        = apply(all_paths, 1, quantile, probs = 0.975),
    extinction_prob = sum(all_paths[years + 1, ] < 1) / paths
  )
}

# Draw a forecast (mean path + 95% band) into the current device.
mc_plot <- function(results, title) {
  res   <- results
  yrs   <- as.numeric(unlist(res$years))
  mean_path <- as.numeric(unlist(res$mean_path))
  lower <- as.numeric(unlist(res$lower_95))
  upper <- as.numeric(unlist(res$upper_95))

  plot(yrs, mean_path, type = "n", ylim = range(c(lower, upper)),
       xlab = "Years from present", ylab = "Population size", main = title)
  polygon(c(yrs, rev(yrs)), c(upper, rev(lower)),
          col = rgb(0.18, 0.80, 0.44, 0.25), border = NA)
  lines(yrs, mean_path, col = "#27ae60", lwd = 3)
}

# Where the producer writes and the consumer reads. Override with the
# STATESNAP_CHECKPOINT env var (e.g. a mounted folder when running in Docker).
mc_checkpoint_path <- function() {
  p <- Sys.getenv("STATESNAP_CHECKPOINT", "")
  if (nzchar(p)) p else file.path(tempdir(), "mc-handoff-checkpoint.json")
}
