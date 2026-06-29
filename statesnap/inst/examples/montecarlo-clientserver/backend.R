# Monte Carlo backend, mirroring shiny_back_mc.r from the REST architecture.
#
# It runs the stochastic population-viability simulation (rnorm, NO set.seed())
# and returns the COMPUTED result as a statesnap checkpoint via capture_state().
# This is the key difference from the hand-rolled backend: instead of building a
# bespoke JSON payload, it emits a statesnap checkpoint that the frontend can
# apply directly with restore_state().
#
# Pure function mc_simulate() is separated from the transport-facing
# mc_backend_handle() so the simulation can be unit-tested on its own.

# Run one stochastic simulation; returns the computed summary (the unit of
# state that gets shared, never recomputed on the receiving side).
mc_simulate <- function(n0 = 500, growth_rate = 0.02, env_var = 0.15,
                        paths = 2000, years = 30) {
  K <- n0 * 10
  all_paths <- matrix(0, nrow = years + 1, ncol = paths)
  all_paths[1, ] <- n0
  for (t in 2:(years + 1)) {
    noise <- rnorm(paths, mean = 0, sd = env_var)   # stochastic: no set.seed()
    all_paths[t, ] <- all_paths[t - 1, ] * exp(growth_rate - (env_var^2) / 2 + noise)
  }
  sample_idx <- sample(seq_len(paths), min(3, paths))
  list(
    years           = 0:years,
    mean_path       = apply(all_paths, 1, mean),
    lower_95        = apply(all_paths, 1, quantile, probs = 0.025),
    upper_95        = apply(all_paths, 1, quantile, probs = 0.975),
    sample_1        = all_paths[, sample_idx[1]],
    sample_2        = all_paths[, sample_idx[min(2, length(sample_idx))]],
    sample_3        = all_paths[, sample_idx[min(3, length(sample_idx))]],
    extinction_prob = sum(all_paths[years + 1, ] < 1) / paths
  )
}

# Transport-facing handler: read a request for a session, run the simulation,
# and post back a statesnap checkpoint on the "result" channel. Returns the
# checkpoint JSON invisibly (handy for tests). No-op if there is no pending
# START_SIMULATION request.
mc_backend_handle <- function(transport, session_id) {
  req <- transport$get(session_id, "request")
  if (is.null(req) || !identical(req$command, "START_SIMULATION")) {
    return(invisible(NULL))
  }

  results <- mc_simulate(
    n0          = req$n0,
    growth_rate = req$growth_rate,
    env_var     = req$env_var,
    paths       = req$paths,
    years       = req$years
  )

  # Emit the computed result as a statesnap checkpoint. There is no live Shiny
  # input here, so the input slot is empty; the simulation result travels in the
  # registered "results" value.
  checkpoint <- statesnap::capture_state(list(), results = results)
  transport$post(session_id, "result", checkpoint)
  invisible(checkpoint)
}
