#!/usr/bin/env Rscript
# ==========================================================================
#  mock-data.R — Generate synthetic benchmark CSVs for testing make-plots.R
#
#  Produces the same three tidy CSVs as k6/extract-results.sh, for both
#  'rest' and 'kafka', with realistic shapes:
#    - Kafka slower than REST on relay/collaboration (consumer lag)
#    - MLTrainer slowest everywhere (compute-bound)
#    - latency rises with VU bucket (backend saturation)
#  Use ONLY to exercise the plotting pipeline before real data exists.
#
#  Usage:  Rscript analysis/mock-data.R [out_dir]
#  Default out_dir = /tmp/mock-results
# ==========================================================================
suppressMessages({ library(dplyr); library(readr); library(tidyr) })

args <- commandArgs(trailingOnly = TRUE)
OUT  <- if (length(args) >= 1) args[1] else "/tmp/mock-results"

set.seed(42)
apps    <- c("Calculator","Analytics","Geospatial","DataExchange",
             "Advanced","ClimateAnomaly","MonteCarlo","MLTrainer")
# relative compute weight per app (Calculator light -> MLTrainer heavy)
weight  <- c(1, 1.4, 1.6, 1.5, 2.0, 3.5, 5.0, 12.0); names(weight) <- apps
buckets <- sprintf("%02d-%02d", seq(1,96,5), seq(5,100,5))
runs    <- 1:5

# arch penalty: kafka adds relay/propagation lag
arch_relay_mult <- c(rest = 1.0, kafka = 2.4)

jitter <- function(x, frac = 0.12) x * runif(length(x), 1 - frac, 1 + frac)

# ---- per-app-long.csv ------------------------------------------------------
gen_per_app <- function(arch) {
  bind_rows(lapply(runs, function(r) {
    # relay
    relay <- tibble(
      run = r, test = "01-state-relay-latency", metric = "relay_total_ms",
      app_name = apps,
      base = jitter(80 * weight * arch_relay_mult[[arch]])
    )
    # throughput (heavier; MLTrainer compute dominates)
    thru <- tibble(
      run = r, test = "04-throughput", metric = "throughput_response_ms",
      app_name = apps,
      base = jitter(900 * weight)
    )
    # save/restore (arch-independent, DB-bound)
    save <- tibble(
      run = r, test = "03-save-restore-latency", metric = "save_to_db_ms",
      app_name = apps, base = jitter(40 + 6 * weight))
    rest <- tibble(
      run = r, test = "03-save-restore-latency", metric = "restore_from_db_ms",
      app_name = apps, base = jitter(45 + 5 * weight))
    bind_rows(relay, thru, save, rest)
  })) %>%
    mutate(count = 60,
           avg = base, med = base * 0.7, p95 = base * 1.8) %>%
    select(run, test, metric, app_name, count, avg, med, p95)
}

# ---- per-bucket-long.csv ---------------------------------------------------
gen_per_bucket <- function(arch) {
  bench <- expand_grid(run = runs, app_name = apps, vu_bucket = buckets) %>%
    mutate(
      bidx   = match(vu_bucket, buckets),
      # latency grows ~quadratically past ~bucket 4 (the ~20-user knee)
      growth = 1 + pmax(0, bidx - 4)^1.8 * 0.18,
      base   = jitter(120 * weight[app_name] * growth),
      test = "04-throughput", metric = "throughput_response_ms",
      count = 30, avg = base, med = base * 0.7, p95 = base * 1.7
    ) %>%
    select(run, test, metric, vu_bucket, app_name, count, avg, med, p95)
  # also an ALL aggregate row per bucket (mean across apps)
  allrows <- bench %>%
    group_by(run, test, metric, vu_bucket) %>%
    summarise(count = sum(count), avg = mean(avg), med = mean(med),
              p95 = mean(p95), .groups = "drop") %>%
    mutate(app_name = "ALL") %>%
    select(run, test, metric, vu_bucket, app_name, count, avg, med, p95)
  bind_rows(bench, allrows)
}

# ---- summary-long.csv ------------------------------------------------------
gen_summary <- function(arch) {
  mk <- function(test, metric, val)
    tibble(run = runs, test = test, metric = metric,
           avg = jitter(rep(val, length(runs))),
           med = jitter(rep(val*0.7, length(runs))),
           min = val*0.1, max = val*4,
           p90 = val*1.5, p95 = val*1.9)
  bind_rows(
    mk("01-state-relay-latency",  "relay_total_ms",        320 * arch_relay_mult[[arch]]),
    mk("02-collaboration-latency","collab_propagation_ms", 600 * arch_relay_mult[[arch]]),
    mk("03-save-restore-latency", "restore_from_db_ms",    46),
    mk("04-throughput",           "throughput_response_ms",1500),
    mk("07-session-lifecycle",    "http_req_duration",     800),
    mk("08-multi-user-collab",    "propagation_all_ms",    1200 * arch_relay_mult[[arch]]),
    mk("09-websocket-presence",   "ws_join_roundtrip_ms",  140),
    # reliability metrics (rates)
    tibble(run = runs, test = "04-throughput", metric = "throughput_errors",
           avg = jitter(rep(if (arch=="kafka") 0.03 else 0.005, length(runs))),
           med = NA, min = NA, max = NA, p90 = NA, p95 = NA),
    tibble(run = runs, test = "07-session-lifecycle", metric = "http_req_failed",
           avg = jitter(rep(if (arch=="kafka") 0.02 else 0.004, length(runs))),
           med = NA, min = NA, max = NA, p90 = NA, p95 = NA)
  )
}

write_arch <- function(arch) {
  d <- file.path(OUT, arch); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  write_csv(gen_summary(arch),    file.path(d, "summary-long.csv"))
  write_csv(gen_per_app(arch),    file.path(d, "per-app-long.csv"))
  write_csv(gen_per_bucket(arch), file.path(d, "per-bucket-long.csv"))
  message("  wrote mock CSVs for ", arch, " -> ", d)
}

invisible(lapply(c("rest","kafka"), write_arch))
message("Mock data ready in: ", OUT)
