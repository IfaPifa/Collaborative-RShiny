# =============================================================================
# ATTRIBUTION / DISCLAIMER
# -----------------------------------------------------------------------------
# The honeybee (Beekeeper pDT) use case this backend serves originates with the
# LTER LIFE project (BioDT use case, repos BioDT/biodt-shiny and
# BioDT/uc-pollinators). It is used here with the permission of the LTER LIFE
# project for the purpose of this Master's thesis. All credit for the original
# honeybee/BEEHAVE application and its scientific model belongs to the
# LTER LIFE / BioDT authors. This file is a SIMULATED stand-in that honours the
# real I/O contract; it is not the real BEEHAVE compute and not the original work.
# =============================================================================

library(plumber)
library(jsonlite)

#* @apiTitle BioDT Honeybee (BEEHAVE) Backend (REST)
#* @apiDescription Simulated stand-in for the BioDT uc-pollinators BEEHAVE
#* compute container (ghcr.io/biodt/beehave:0.3.13). It honours the SAME
#* input/output contract as the real NetLogo job:
#*   IN  -- apiary coordinates + the colony parameters BioDT's beekeeper_param
#*          module collects (N_INITIAL_BEES, mites, treatments, DaysLimit) +
#*          the editable habitat->forage lookup table.
#*   OUT -- the same daily result table BioDT's plot module reads, with columns
#*          `date`, `weather`, `TotalIHbees + TotalForagers`, and
#*          `(honeyEnergyStore / ( ENERGY_HONEY_per_g * 1000 ))`.
#* The trajectory is generated with a stochastic colony model instead of
#* NetLogo. In ShinySwarm terms the compute already lives behind a service, so
#* swapping this simulated executor for the real container is a one-line route
#* change (point APP_ROUTES at the real Plumber/job endpoint).

# --- Simulated BEEHAVE colony model -------------------------------------------
# NOT a scientific model. It only needs to (a) consume the same inputs the real
# BEEHAVE job consumes and (b) produce a plausible, run-to-run-varying daily
# trajectory in BioDT's column layout, so statesnap's "capture the computed,
# non-deterministic result" story is genuine.
run_beehave_sim <- function(lat, lng, params, lookup, sim) {
  # BioDT parameter names (from app/view/honeybee/beekeeper_param.R).
  getp <- function(name, default) {
    v <- params[[name]]
    if (is.null(v) || length(v) == 0 || is.na(v)) default else v
  }
  n_bees      <- as.numeric(getp("N_INITIAL_BEES", 10000))
  mites_h     <- as.numeric(getp("N_INITIAL_MITES_HEALTHY", 100))
  mites_i     <- as.numeric(getp("N_INITIAL_MITES_INFECTED", 50))
  honey_harv  <- isTRUE(as.logical(getp("HoneyHarvesting", TRUE)))
  varroa_trt  <- isTRUE(as.logical(getp("VarroaTreatment", FALSE)))
  drone_rem   <- isTRUE(as.logical(getp("DroneBroodRemoval", TRUE)))

  days        <- as.numeric(if (!is.null(sim$sim_days)) sim$sim_days else 365)
  start_day   <- if (!is.null(sim$start_day)) as.Date(sim$start_day) else as.Date("2016-01-01")

  # Habitat quality from the editable lookup table (the collaborative input the
  # beekeepers tune together). Mean of any numeric forage columns.
  forage_score <- 0.5
  if (!is.null(lookup) && length(lookup) > 0) {
    vals <- suppressWarnings(as.numeric(unlist(lookup)))
    vals <- vals[is.finite(vals)]
    if (length(vals) > 0) {
      mx <- max(vals)
      forage_score <- mean(vals)
      if (mx > 1) forage_score <- forage_score / mx  # normalise to 0..1
    }
  }

  season_strength <- cos((abs(lat) / 90) * (pi / 3))  # toy latitude effect

  dates  <- start_day + (0:(days))
  doy    <- as.integer(format(dates, "%j"))

  bees   <- numeric(days + 1)
  honey  <- numeric(days + 1)
  mites  <- numeric(days + 1)
  hours  <- numeric(days + 1)   # weather / daily collection hours
  bees[1]  <- n_bees
  honey[1] <- 0
  mites[1] <- mites_h + mites_i

  for (d in 2:(days + 1)) {
    season <- max(0, sin(pi * doy[d] / 365)) * season_strength
    weather_noise <- runif(1, 0.6, 1.0)
    hours[d] <- round(season * 14 * weather_noise, 1)   # 0..~14 foraging hours
    food <- (hours[d] / 14) * forage_score

    births <- 1600 * (0.4 + 0.6 * food)
    deaths <- bees[d - 1] * (0.02 + 0.04 * (1 - food)) + mites[d - 1] * 0.4
    if (drone_rem) deaths <- deaths * 0.97
    noise  <- rnorm(1, 0, bees[d - 1] * 0.01)
    bees[d] <- max(0, bees[d - 1] + births - deaths + noise)

    mite_rate <- if (varroa_trt && doy[d] %in% 210:240) 0.5 else 1.02
    mites[d]  <- max(0, mites[d - 1] * mite_rate - food * 3)

    gain <- food * bees[d - 1] * 1.5e-4
    harv <- if (honey_harv && doy[d] %% 200 == 0) honey[d - 1] * 0.6 else 0
    honey[d] <- max(0, honey[d - 1] + gain - harv - 0.0005 * bees[d - 1] * 1e-3)
  }

  # BioDT result-table column layout (see honeybee_beekeeper_plot.R).
  data.frame(
    date = as.character(dates),
    weather = hours,
    `TotalIHbees + TotalForagers` = round(bees),
    `(honeyEnergyStore / ( ENERGY_HONEY_per_g * 1000 ))` = round(honey, 3),
    check.names = FALSE
  )
}

#* Run a honeybee colony simulation (BEEHAVE-compatible contract)
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) { body_text <- rawToChar(raw_body) } else if (is.character(raw_body)) { body_text <- raw_body } else { body_text <- NULL }
  if (!is.null(body_text)) { body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE) } else { body <- raw_body }

  command <- if (!is.null(body$command)) body$command else ""
  if (command != "RUN_SIMULATION") {
    return(list(status = "ignored", message = "Unknown command"))
  }

  lat    <- if (!is.null(body$lat)) as.numeric(body$lat) else 52.37
  lng    <- if (!is.null(body$lng)) as.numeric(body$lng) else 4.90
  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  params <- if (!is.null(body$params)) body$params else list()
  lookup <- if (!is.null(body$lookup)) body$lookup else list()
  sim    <- if (!is.null(body$simulation)) body$simulation else list()

  result_table <- run_beehave_sim(lat, lng, params, lookup, sim)

  final_bees <- tail(result_table[["TotalIHbees + TotalForagers"]], 1)
  peak_bees  <- max(result_table[["TotalIHbees + TotalForagers"]])
  total_hon  <- max(result_table[["(honeyEnergyStore / ( ENERGY_HONEY_per_g * 1000 ))"]])
  collapsed  <- final_bees < 2000  # colony-collapse threshold (toy)

  res <- list(
    type        = "RESULT",
    appName     = "Honeybee",
    sender      = sender,
    lat         = lat,
    lng         = lng,
    # Full daily result table in BioDT's column layout (column-oriented for JSON).
    date        = result_table$date,
    weather     = result_table$weather,
    bees        = result_table[["TotalIHbees + TotalForagers"]],
    honey_kg    = result_table[["(honeyEnergyStore / ( ENERGY_HONEY_per_g * 1000 ))"]],
    final_bees  = final_bees,
    peak_bees   = peak_bees,
    total_honey = total_hon,
    collapsed   = collapsed,
    status      = "success",
    timestamp   = as.numeric(Sys.time())
  )
  if (!is.null(body[["_marker"]])) res[["_marker"]] <- body[["_marker"]]
  return(res)
}
