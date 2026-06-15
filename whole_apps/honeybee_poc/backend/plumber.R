# =============================================================================
# Honeybee PoC -- Plumber backend (simulated BEEHAVE)
# -----------------------------------------------------------------------------
# Receives a statesnap JSON checkpoint of the BioDT honeybee MODEL (coordinates,
# parameters, lookup) over HTTP, runs a simulated BEEHAVE colony model, and
# returns the result as a statesnap JSON checkpoint whose payload is the BioDT
# result table (same columns the real beekeeper_plot module reads).
#
# This is the "backend" half of the PoC: a headless process that speaks
# statesnap JSON over Plumber HTTP. No Docker/Spring/Kafka needed for the
# transport -- statesnap *is* the wire format.
#
# The compute is a stochastic R stand-in for ghcr.io/biodt/beehave (NetLogo).
# It is NON-DETERMINISTIC by design: re-running cannot reproduce a colleague's
# run, but restoring the returned statesnap checkpoint can -- which is the whole
# point of capturing computed state rather than inputs.
#
# ATTRIBUTION: the honeybee/BEEHAVE use case originates with the LTER LIFE
# project (BioDT) and is used here with permission for this Master's thesis.
# This file is a simulated stand-in, not the original scientific compute.
# =============================================================================

library(plumber)
library(jsonlite)
library(statesnap)

# --- Simulated BEEHAVE colony model ------------------------------------------
# Consumes the BioDT model contract and emits BioDT's result-table columns.
run_beehave_sim <- function(model) {
  coords <- model$coordinates
  params <- model$parameters$parameters   # BioDT param df (named columns)
  sim    <- model$parameters$simulation   # BioDT simulation df
  lookup <- model$lookup

  lat <- tryCatch(as.numeric(coords$lat[[1]]), error = function(e) 52.37)
  if (length(lat) == 0 || is.na(lat)) lat <- 52.37

  getp <- function(df, col, default) {
    if (is.null(df) || is.null(df[[col]])) return(default)
    v <- df[[col]][[1]]
    if (is.null(v) || is.na(v)) default else as.numeric(v)
  }
  n_bees     <- getp(params, "N_INITIAL_BEES", 10000)
  mites_h    <- getp(params, "N_INITIAL_MITES_HEALTHY", 100)
  mites_i    <- getp(params, "N_INITIAL_MITES_INFECTED", 50)
  drone_rem  <- getp(params, "DroneBroodRemoval", 1) > 0
  varroa_trt <- getp(params, "VarroaTreatment", 0) > 0
  honey_harv <- getp(params, "HoneyHarvesting", 1) > 0
  days       <- getp(sim, "DaysLimit", 365)
  if (is.na(days) || days < 30) days <- 365

  # Editable habitat lookup is the collaborative input; mean nectar drives forage.
  forage_score <- 0.5
  if (!is.null(lookup)) {
    nectar <- NULL
    for (cand in c("Nectar", "nectar", "Quantity_Nectar_per_m2")) {
      if (!is.null(lookup[[cand]])) { nectar <- lookup[[cand]]; break }
    }
    vals <- suppressWarnings(as.numeric(unlist(nectar)))
    vals <- vals[is.finite(vals)]
    if (length(vals) > 0) {
      mx <- max(vals); forage_score <- mean(vals)
      if (mx > 1) forage_score <- forage_score / mx
    }
  }

  season_strength <- cos((abs(lat) / 90) * (pi / 3))
  start_day <- as.Date("2016-01-01")
  dates <- start_day + (0:days)
  doy   <- as.integer(format(dates, "%j"))

  bees <- numeric(days + 1); honey <- numeric(days + 1)
  mites <- numeric(days + 1); hours <- numeric(days + 1)
  bees[1] <- n_bees; mites[1] <- mites_h + mites_i

  for (d in 2:(days + 1)) {
    season <- max(0, sin(pi * doy[d] / 365)) * season_strength
    hours[d] <- round(season * 14 * runif(1, 0.6, 1.0), 1)
    food <- (hours[d] / 14) * forage_score
    births <- 1600 * (0.4 + 0.6 * food)
    deaths <- bees[d - 1] * (0.02 + 0.04 * (1 - food)) + mites[d - 1] * 0.4
    if (drone_rem) deaths <- deaths * 0.97
    bees[d] <- max(0, bees[d - 1] + births - deaths + rnorm(1, 0, bees[d - 1] * 0.01))
    mite_rate <- if (varroa_trt && doy[d] %in% 210:240) 0.5 else 1.02
    mites[d] <- max(0, mites[d - 1] * mite_rate - food * 3)
    gain <- food * bees[d - 1] * 1.5e-4
    harv <- if (honey_harv && doy[d] %% 200 == 0) honey[d - 1] * 0.6 else 0
    honey[d] <- max(0, honey[d - 1] + gain - harv - 0.0005 * bees[d - 1] * 1e-3)
  }

  # Exact BioDT result-table column layout (see honeybee_beekeeper_plot.R).
  data.frame(
    date = as.character(dates),
    weather = hours,
    `TotalIHbees + TotalForagers` = round(bees),
    `(honeyEnergyStore / ( ENERGY_HONEY_per_g * 1000 ))` = round(honey, 3),
    check.names = FALSE
  )
}

#* @apiTitle Honeybee PoC Backend (simulated BEEHAVE over statesnap/HTTP)

#* Health check
#* @get /health
function() {
  list(status = "ok", model = "simulated-beehave", contract = "biodt-result-table")
}

#* Run a simulation from a statesnap model checkpoint, return a statesnap result
#* @post /run
#* @serializer text
function(req) {
  # 1. Receive the statesnap JSON checkpoint of the MODEL (not raw inputs).
  body_text <- if (is.raw(req$body)) rawToChar(req$body) else req$bodyRaw
  if (is.null(body_text) || !nzchar(body_text)) {
    body_text <- req$postBody
  }

  # statesnap restore (no live Shiny session): pull the model back from JSON.
  # The model was captured under the single registered name "model".
  model_holder <- local({
    val <- NULL
    setter <- function(x) val <<- x
    restore_state(NULL, body_text, model = setter)
    val
  })

  # 2. Run the (simulated) BEEHAVE compute.
  result_table <- run_beehave_sim(model_holder)

  # 3. Return the result AS a statesnap checkpoint. The payload is the BioDT
  #    result table; capturing it (not the inputs) is what makes the
  #    non-deterministic run reproducible on restore.
  capture_state(
    input  = list(),                 # headless: no Shiny inputs
    result = result_table,           # plain data.frame -> JSON-serialisable
    final_bees  = tail(result_table[["TotalIHbees + TotalForagers"]], 1),
    peak_bees   = max(result_table[["TotalIHbees + TotalForagers"]]),
    total_honey = max(result_table[["(honeyEnergyStore / ( ENERGY_HONEY_per_g * 1000 ))"]])
  )
}
