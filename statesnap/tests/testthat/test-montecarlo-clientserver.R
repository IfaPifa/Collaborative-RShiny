# End-to-end tests for the client/server Monte Carlo example, exercising the
# backend, the in-process transport, and the frontend together. They prove the
# two halves communicate through statesnap checkpoints and that the frontend
# reproduces exactly what the backend computed -- without recomputing it and
# without a fixed seed.

# Load the example modules (they live under inst/examples, not in R/). Resolve
# the directory for both an installed package (system.file) and a source-tree
# run via pkgload::load_all() (test_path fallback). Source into this file's
# environment so the functions are visible to every test below.
.mc_ex_dir <- system.file("examples", "montecarlo-clientserver",
                          package = "statesnap")
if (!nzchar(.mc_ex_dir) || !file.exists(file.path(.mc_ex_dir, "transport.R"))) {
  .mc_ex_dir <- testthat::test_path("..", "..", "inst", "examples",
                                    "montecarlo-clientserver")
}
source(file.path(.mc_ex_dir, "transport.R"), local = environment())
source(file.path(.mc_ex_dir, "backend.R"), local = environment())
source(file.path(.mc_ex_dir, "frontend.R"), local = environment())

# Helper: a reactiveVal-style setter backed by a local variable.
make_setter <- function() {
  v <- NULL
  function(x) if (missing(x)) v else v <<- x
}

as_num <- function(x) as.numeric(unlist(x))

PARAMS <- list(n0 = 500, growth_rate = 0.02, env_var = 0.15,
               paths = 1500, years = 25)

test_that("backend posts a result only after a request exists", {
  tr <- mc_transport()
  # No request yet -> backend does nothing, no result channel.
  expect_null(mc_backend_handle(tr, "s1"))
  expect_null(tr$get("s1", "result"))

  # After a request, the backend posts a checkpoint.
  mc_frontend_request(tr, "s1", PARAMS)
  checkpoint <- mc_backend_handle(tr, "s1")
  expect_type(checkpoint, "character")
  expect_false(is.null(tr$get("s1", "result")))
})

test_that("frontend restores exactly what the backend computed", {
  tr <- mc_transport()

  # Frontend requests; backend computes and we capture its ground-truth result
  # by reading the checkpoint it emitted.
  mc_frontend_request(tr, "s1", PARAMS)
  checkpoint <- mc_backend_handle(tr, "s1")
  truth <- jsonlite::fromJSON(checkpoint, simplifyVector = FALSE)
  truth_mean <- as_num(truth$reactives$results$content$mean_path)

  # Frontend applies the checkpoint into its state.
  setter <- make_setter()
  applied <- mc_frontend_apply(tr, "s1", setter)
  expect_true(applied)

  got <- setter()
  expect_equal(as_num(got$mean_path), truth_mean)
  expect_equal(length(as_num(got$years)), PARAMS$years + 1)
  expect_true(is.numeric(as_num(got$extinction_prob)))
})

test_that("frontend apply is a no-op when no result is waiting", {
  tr <- mc_transport()
  setter <- make_setter()
  expect_false(mc_frontend_apply(tr, "nobody", setter))
  expect_null(setter())
})

test_that("restored result matches the run, but a fresh run differs (no seed)", {
  tr <- mc_transport()

  mc_frontend_request(tr, "s1", PARAMS)
  mc_backend_handle(tr, "s1")
  setter <- make_setter()
  mc_frontend_apply(tr, "s1", setter)
  restored <- as_num(setter()$mean_path)

  # A second backend run with identical params draws fresh randomness.
  mc_frontend_request(tr, "s1", PARAMS)
  rerun_checkpoint <- mc_backend_handle(tr, "s1")
  rerun <- as_num(
    jsonlite::fromJSON(rerun_checkpoint, simplifyVector = FALSE)$reactives$results$content$mean_path
  )

  # The restored value still equals the first run; the rerun diverges.
  setter2 <- make_setter()
  mc_frontend_apply(tr, "s1", setter2)  # latest result == rerun
  expect_equal(as_num(setter2()$mean_path), rerun)
  expect_false(isTRUE(all.equal(restored, rerun)))
})

test_that("sessions are isolated on the shared transport", {
  tr <- mc_transport()

  mc_frontend_request(tr, "alice", PARAMS)
  mc_frontend_request(tr, "bob", modifyList(PARAMS, list(n0 = 100)))
  mc_backend_handle(tr, "alice")
  mc_backend_handle(tr, "bob")

  a <- make_setter(); b <- make_setter()
  mc_frontend_apply(tr, "alice", a)
  mc_frontend_apply(tr, "bob", b)

  # Different starting populations -> different first value of the mean path.
  expect_equal(as_num(a()$mean_path)[1], 500)
  expect_equal(as_num(b()$mean_path)[1], 100)
})

test_that("client/server round-trip works through a real Shiny server", {
  skip_if_not_installed("shiny")
  library(shiny)

  # Inline the wiring the app uses, exercised via testServer().
  server <- function(input, output, session) {
    transport <- mc_transport()
    state <- reactiveValues(results = NULL)
    results_setter <- function(x) {
      if (missing(x)) state$results else state$results <- x
    }

    observeEvent(input$run_sim, {
      mc_frontend_request(transport, "t", list(
        n0 = input$n0, growth_rate = input$growth_rate, env_var = input$env_var,
        paths = input$paths, years = input$years
      ))
      mc_backend_handle(transport, "t")
      mc_frontend_apply(transport, "t", results_setter)
    })

    exportTestValues(
      mean_path = state$results$mean_path,
      n_years   = length(state$results$years)
    )
  }

  testServer(server, {
    session$setInputs(n0 = 500, growth_rate = 0.02, env_var = 0.15,
                      paths = 1500, years = 25)
    session$setInputs(run_sim = 1)

    expect_false(is.null(state$results))
    expect_equal(length(as_num(state$results$years)), 26)
    expect_true(all(is.finite(as_num(state$results$mean_path))))
  })
})
