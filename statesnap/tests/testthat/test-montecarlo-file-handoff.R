# Cross-session state hand-off through a FILE transport.
#
# Two independent Shiny app instances, sharing nothing but a path on disk:
#   - App A (producer) runs the unseeded Monte Carlo simulation and saves a
#     statesnap checkpoint to a file via capture_state() + writeLines().
#   - App B (consumer) starts fresh, reads that same file, and restores the
#     state via restore_state().
# The consumer must land in exactly the producer's computed state, proving that
# a statesnap checkpoint is a self-contained, transportable artifact -- the file
# here could equally be a REST body, a Kafka message, or a database row.

# Load the example backend (for mc_simulate) from installed pkg or source tree.
.ex_dir <- system.file("examples", "montecarlo-clientserver", package = "statesnap")
if (!nzchar(.ex_dir) || !file.exists(file.path(.ex_dir, "backend.R"))) {
  .ex_dir <- testthat::test_path("..", "..", "inst", "examples",
                                 "montecarlo-clientserver")
}
source(file.path(.ex_dir, "backend.R"), local = environment())

as_num <- function(x) as.numeric(unlist(x))

PARAMS <- list(n0 = 500, growth_rate = 0.02, env_var = 0.15,
               paths = 1500, years = 25)

# A reactiveVal-style setter over state$results, matching the app.R wiring:
# setter() reads, setter(x) writes. capture_state stores the value; restore_state
# writes it back through this closure.
results_accessor <- function(state) {
  function(x) if (missing(x)) state$results else state$results <- x
}

# Producer app: computes a simulation and saves a checkpoint to `path`.
producer_server <- function(checkpoint_path) {
  function(input, output, session) {
    state <- reactiveValues(results = NULL)

    observeEvent(input$run_sim, {
      state$results <- mc_simulate(
        n0 = input$n0, growth_rate = input$growth_rate,
        env_var = input$env_var, paths = input$paths, years = input$years
      )
    })

    observeEvent(input$save_btn, {
      req(state$results)
      json <- capture_state(input, results = state$results)
      writeLines(json, checkpoint_path)   # transport = file on disk
    })

    exportTestValues(mean_path = state$results$mean_path)
  }
}

# Consumer app: a DIFFERENT instance that reads the file and restores it.
consumer_server <- function(checkpoint_path) {
  function(input, output, session) {
    state <- reactiveValues(results = NULL)
    setter <- results_accessor(state)

    observeEvent(input$load_btn, {
      req(file.exists(checkpoint_path))
      json <- paste(readLines(checkpoint_path), collapse = "\n")
      restore_state(session, json, results = setter)
    })

    exportTestValues(
      mean_path = state$results$mean_path,
      n_years   = length(state$results$years)
    )
  }
}

test_that("a second app restores the first app's state from a shared file", {
  skip_if_not_installed("shiny")
  library(shiny)

  checkpoint <- tempfile(fileext = ".json")
  on.exit(unlink(checkpoint), add = TRUE)

  # --- App A: run + save to file. Capture the ground-truth computed result. ---
  produced_mean <- NULL
  testServer(producer_server(checkpoint), {
    session$setInputs(n0 = PARAMS$n0, growth_rate = PARAMS$growth_rate,
                      env_var = PARAMS$env_var, paths = PARAMS$paths,
                      years = PARAMS$years)
    session$setInputs(run_sim = 1)
    produced_mean <<- as_num(state$results$mean_path)

    session$setInputs(save_btn = 1)
    expect_true(file.exists(checkpoint))
    expect_gt(file.info(checkpoint)$size, 0)
  })

  # The file outlives app A: it is a standalone artifact on disk.
  expect_true(file.exists(checkpoint))

  # --- App B: a fresh instance that only knows the path. ---
  testServer(consumer_server(checkpoint), {
    # Nothing loaded yet.
    expect_null(state$results)

    session$setInputs(load_btn = 1)

    # App B now holds exactly what app A computed.
    expect_false(is.null(state$results))
    expect_equal(length(as_num(state$results$years)), PARAMS$years + 1)
    expect_equal(as_num(state$results$mean_path), produced_mean)
  })
})

test_that("the checkpoint file is self-contained across a fresh restore", {
  skip_if_not_installed("shiny")
  library(shiny)

  checkpoint <- tempfile(fileext = ".json")
  on.exit(unlink(checkpoint), add = TRUE)

  # Produce and save.
  produced_mean <- NULL
  testServer(producer_server(checkpoint), {
    session$setInputs(n0 = PARAMS$n0, growth_rate = PARAMS$growth_rate,
                      env_var = PARAMS$env_var, paths = PARAMS$paths,
                      years = PARAMS$years)
    session$setInputs(run_sim = 1)
    produced_mean <<- as_num(state$results$mean_path)
    session$setInputs(save_btn = 1)
  })

  # Restore directly from the file with no live session, the way any other
  # transport consumer (REST/Kafka/DB) would: parse the bytes and apply them.
  json <- paste(readLines(checkpoint), collapse = "\n")
  sink <- NULL
  setter <- function(x) if (missing(x)) sink else sink <<- x
  restore_state(NULL, json, results = setter)

  expect_equal(as_num(setter()$mean_path), produced_mean)
})

test_that("two producers write distinct files; each consumer gets its own", {
  skip_if_not_installed("shiny")
  library(shiny)

  file_a <- tempfile(fileext = ".json")
  file_b <- tempfile(fileext = ".json")
  on.exit(unlink(c(file_a, file_b)), add = TRUE)

  mean_a <- NULL
  testServer(producer_server(file_a), {
    session$setInputs(n0 = 500, growth_rate = 0.02, env_var = 0.15,
                      paths = 1500, years = 25)
    session$setInputs(run_sim = 1); mean_a <<- as_num(state$results$mean_path)
    session$setInputs(save_btn = 1)
  })

  mean_b <- NULL
  testServer(producer_server(file_b), {
    session$setInputs(n0 = 100, growth_rate = 0.02, env_var = 0.15,
                      paths = 1500, years = 25)
    session$setInputs(run_sim = 1); mean_b <<- as_num(state$results$mean_path)
    session$setInputs(save_btn = 1)
  })

  # Consumer of A gets A's state (starts at population 500).
  testServer(consumer_server(file_a), {
    session$setInputs(load_btn = 1)
    expect_equal(as_num(state$results$mean_path), mean_a)
    expect_equal(as_num(state$results$mean_path)[1], 500)
  })

  # Consumer of B gets B's state (starts at population 100).
  testServer(consumer_server(file_b), {
    session$setInputs(load_btn = 1)
    expect_equal(as_num(state$results$mean_path), mean_b)
    expect_equal(as_num(state$results$mean_path)[1], 100)
  })
})
