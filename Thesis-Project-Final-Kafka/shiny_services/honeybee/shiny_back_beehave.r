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

library(jsonlite)
library(kafka)

# =============================================================================
# BioDT Honeybee (BEEHAVE) Backend -- ShinySwarm Kafka variant
# -----------------------------------------------------------------------------
# Event-driven analogue of shiny_back_beehave.r (REST). Consumes "RUN_SIMULATION"
# events from the `input` topic, runs the simulated BEEHAVE colony model, and
# produces a "RESULT" event to the `output` topic keyed by the session/user.
# This async pattern matches BEEHAVE's real 2-4 min job nature far better than a
# synchronous REST request -- see biodt_feasibility.tex, which argues the
# event-driven architecture is the stronger fit for this use case.
# The model itself is identical to the REST backend (BioDT input/output contract).
# =============================================================================

broker <- "kafka:9092"
topic_input <- "input"
topic_output <- "output"

run_beehave_sim <- function(lat, lng, params, lookup, sim) {
  getp <- function(name, default) {
    v <- params[[name]]
    if (is.null(v) || length(v) == 0 || is.na(v)) default else v
  }
  n_bees     <- as.numeric(getp("N_INITIAL_BEES", 10000))
  mites_h    <- as.numeric(getp("N_INITIAL_MITES_HEALTHY", 100))
  mites_i    <- as.numeric(getp("N_INITIAL_MITES_INFECTED", 50))
  honey_harv <- isTRUE(as.logical(getp("HoneyHarvesting", TRUE)))
  varroa_trt <- isTRUE(as.logical(getp("VarroaTreatment", FALSE)))
  drone_rem  <- isTRUE(as.logical(getp("DroneBroodRemoval", TRUE)))

  days      <- as.numeric(if (!is.null(sim$sim_days)) sim$sim_days else 365)
  start_day <- if (!is.null(sim$start_day)) as.Date(sim$start_day) else as.Date("2016-01-01")

  forage_score <- 0.5
  if (!is.null(lookup) && length(lookup) > 0) {
    vals <- suppressWarnings(as.numeric(unlist(lookup)))
    vals <- vals[is.finite(vals)]
    if (length(vals) > 0) {
      mx <- max(vals); forage_score <- mean(vals)
      if (mx > 1) forage_score <- forage_score / mx
    }
  }

  season_strength <- cos((abs(lat) / 90) * (pi / 3))
  dates <- start_day + (0:(days))
  doy   <- as.integer(format(dates, "%j"))

  bees <- numeric(days + 1); honey <- numeric(days + 1)
  mites <- numeric(days + 1); hours <- numeric(days + 1)
  bees[1] <- n_bees; honey[1] <- 0; mites[1] <- mites_h + mites_i

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

  list(date = as.character(dates), weather = hours,
       bees = round(bees), honey_kg = round(honey, 3))
}

print("Honeybee BEEHAVE Backend Starting (Kafka mode)...")
print("Giving Kafka 15 seconds to boot and create topic partitions...")
Sys.sleep(15)

consumer_config <- list(
  "bootstrap.servers" = broker,
  "group.id" = "backend_honeybee",
  "auto.offset.reset" = "latest",
  "enable.auto.commit" = "true"
)

consumer <- NULL
connected <- FALSE
while (!connected) {
  tryCatch({
    print(paste("Subscribing to topic:", topic_input, "..."))
    consumer <- Consumer$new(consumer_config)
    consumer$subscribe(topic_input)
    test_msg <- consumer$consume(100)  # verify topic is initialised
    connected <- TRUE
    print("Subscribed and verified. Waiting for simulation requests...")
  }, error = function(e) {
    print(paste("Kafka topic not ready yet:", e$message)); Sys.sleep(5)
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
    if (is.null(payload$appName) || payload$appName != "Honeybee") next
    if (is.null(payload$command) || payload$command != "RUN_SIMULATION") next

    lat    <- if (!is.null(payload$lat)) as.numeric(payload$lat) else 52.37
    lng    <- if (!is.null(payload$lng)) as.numeric(payload$lng) else 4.90
    params <- if (!is.null(payload$params)) payload$params else list()
    lookup <- if (!is.null(payload$lookup)) payload$lookup else list()
    sim    <- if (!is.null(payload$simulation)) payload$simulation else list()

    tbl <- run_beehave_sim(lat, lng, params, lookup, sim)
    final_bees <- tail(tbl$bees, 1); peak_bees <- max(tbl$bees)
    total_hon <- max(tbl$honey_kg)

    response <- list(
      appName = "Honeybee", type = "RESULT",
      sender = payload$sender, lat = lat, lng = lng,
      date = tbl$date, weather = tbl$weather,
      bees = tbl$bees, honey_kg = tbl$honey_kg,
      final_bees = final_bees, peak_bees = peak_bees,
      total_honey = total_hon, collapsed = final_bees < 2000,
      status = "success", timestamp = as.numeric(Sys.time())
    )
    if (!is.null(payload[["_marker"]])) response[["_marker"]] <- payload[["_marker"]]
    producer$produce(topic_output, toJSON(response, auto_unbox = TRUE), key = incoming_key)
    print(paste("Simulation done for", payload$sender, "- final bees:", final_bees))
  }, error = function(e) {
    print(paste("Consumer loop error:", e$message)); Sys.sleep(1)
  })
}
