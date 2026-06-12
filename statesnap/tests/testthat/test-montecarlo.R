# Tests modelled on the ShinySwarm Monte Carlo simulator. They demonstrate the
# library's defining property: a stochastic result computed WITHOUT set.seed()
# is reproduced exactly on restore, because the computed output -- not the
# recipe to recompute it -- is what gets shared.

# Run one unseeded population-viability simulation and return its summary, the
# same shape the Monte Carlo service produces (mean path, confidence bands,
# extinction probability).
run_sim <- function(n0 = 500, r = 0.02, sigma = 0.15,
                    n_paths = 2000, years = 30) {
  K <- n0 * 10
  paths <- matrix(0, nrow = n_paths, ncol = years + 1)
  paths[, 1] <- n0
  for (t in 2:(years + 1)) {
    noise <- rnorm(n_paths, mean = 0, sd = sigma)   # no set.seed(): stochastic
    growth <- r * paths[, t - 1] * (1 - paths[, t - 1] / K)
    paths[, t] <- pmax(0, paths[, t - 1] + growth + noise * paths[, t - 1])
  }
  list(
    years           = 0:years,
    mean_path       = colMeans(paths),
    lower_95        = apply(paths, 2, quantile, probs = 0.025),
    upper_95        = apply(paths, 2, quantile, probs = 0.975),
    extinction_prob = mean(paths[, years + 1] < 1)
  )
}

test_that("unseeded simulation is genuinely non-deterministic", {
  # Guards the premise: without set.seed(), two runs differ. If this ever
  # passed by accident, the reproducibility test below would prove nothing.
  a <- run_sim()
  b <- run_sim()
  expect_false(isTRUE(all.equal(a$mean_path, b$mean_path)))
})

# restore_state() parses with simplifyVector = FALSE, so a captured numeric
# vector comes back as a list of numbers. This helper recovers the numeric
# vector for value comparison.
as_num <- function(x) as.numeric(unlist(x))

test_that("captured stochastic result restores with no seed", {
  result <- run_sim()

  # Capture the COMPUTED result (as a plain value, the way the MC service
  # stores it before transmitting).
  json <- capture_state(list(), results = result)

  # Restore into a fresh accessor.
  sink <- fake_reactiveval()
  restore_state(NULL, json, results = sink)
  restored <- sink()

  expect_equal(as_num(restored$mean_path), result$mean_path)
  expect_equal(as_num(restored$lower_95), result$lower_95)
  expect_equal(as_num(restored$upper_95), result$upper_95)
  expect_equal(as_num(restored$extinction_prob), result$extinction_prob)
})

test_that("JSON round-trip preserves high numeric precision", {
  # digits = NA serialises doubles with full precision. JSON stores numbers as
  # decimal text, so the round-trip is not bit-identical, but it is accurate to
  # well within floating-point tolerance -- far tighter than the default
  # 4-decimal rounding, which would visibly corrupt simulation output.
  result <- run_sim()
  json <- capture_state(list(), results = result)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  restored_mean <- as_num(parsed$reactives$results$content$mean_path)

  expect_equal(restored_mean, result$mean_path)               # within tolerance
  expect_lt(max(abs(restored_mean - result$mean_path)), 1e-9) # tight bound
})

test_that("restored result matches original but differs from a fresh rerun", {
  # The core contrast: restore reproduces the original, whereas a
  # recompute-from-inputs strategy (no seed) would diverge.
  original <- run_sim()
  json <- capture_state(list(), results = original)

  sink <- fake_reactiveval()
  restore_state(NULL, json, results = sink)
  restored <- as_num(sink()$mean_path)

  rerun <- run_sim()   # same inputs, fresh randomness

  expect_equal(restored, original$mean_path)                       # reproduced
  expect_false(isTRUE(all.equal(restored, rerun$mean_path)))       # not a rerun
})

test_that("Monte Carlo save/restore round-trips through a real Shiny server", {
  skip_if_not_installed("shiny")
  library(shiny)

  checkpoint <- tempfile(fileext = ".json")

  server <- function(input, output, session) {
    state <- reactiveValues(results = NULL)

    observeEvent(input$run_sim, {
      state$results <- run_sim(
        n0 = input$n0, r = input$growth_rate, sigma = input$env_var,
        n_paths = input$paths, years = input$years
      )
    })

    observeEvent(input$save_btn, {
      json <- capture_state(input, results = state)
      writeLines(json, checkpoint)
    })

    observeEvent(input$restore_btn, {
      json <- paste(readLines(checkpoint), collapse = "\n")
      restore_state(session, json, results = state)
    })

    exportTestValues(mean_path = state$results$mean_path)
  }

  testServer(server, {
    session$setInputs(n0 = 500, growth_rate = 0.02, env_var = 0.15,
                      paths = 2000, years = 30)

    session$setInputs(run_sim = 1)
    first <- state$results$mean_path
    expect_false(is.null(first))

    session$setInputs(save_btn = 1)
    expect_true(file.exists(checkpoint))

    # Re-run with identical inputs: unseeded, so the live result changes.
    session$setInputs(run_sim = 2)
    expect_false(isTRUE(all.equal(state$results$mean_path, first)))

    # Restore: the original computed trajectory comes back. The reactiveValues
    # branch stores the list under content; values match the original run.
    session$setInputs(restore_btn = 1)
    expect_equal(as.numeric(unlist(state$results$mean_path)), first)
  })
})
