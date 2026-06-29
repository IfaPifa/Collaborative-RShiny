#!/usr/bin/env Rscript
# ==========================================================================
#  make-plots.R — Generate all benchmark figures from the extracted CSVs
#
#  Reads the tidy CSVs produced by k6/extract-results.sh and writes PNG+PDF
#  figures to analysis/plots/. Designed to "just work" with whatever
#  architectures are present (rest, kafka, monolithic) and to fail gracefully
#  per-figure so one missing metric never aborts the whole run.
#
#  Usage:
#    Rscript analysis/make-plots.R [results_dir] [out_dir] [arch1 arch2 ...]
#
#  Defaults:
#    results_dir = k6/results
#    out_dir     = analysis/plots
#    archs       = rest kafka   (any missing arch is skipped)
#
#  Figures produced (when the underlying metric exists):
#    fig01_relay_per_app        per-app relay latency p95, REST vs Kafka
#    fig02_throughput_vs_load   latency vs concurrent users (the breakdown)
#    fig03_throughput_per_app   per-app throughput p95, REST vs Kafka
#    fig04_save_restore         save/restore latency per app
#    fig05_overview_grid        p95 across all tests, REST vs Kafka
#    fig06_reliability          data-loss / error-rate / isolation summary
#    fig07_slowdown_factor      "X times slower at N users" per app
# ==========================================================================

# --- locate this script so common.R resolves regardless of CWD -------------
args_all <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)])
script_dir <- if (length(file_arg)) dirname(normalizePath(file_arg)) else "analysis"
source(file.path(script_dir, "common.R"))

# --- arguments --------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
RESULTS_DIR <- if (length(args) >= 1) args[1] else "k6/results"
OUT_DIR     <- if (length(args) >= 2) args[2] else file.path(script_dir, "plots")
ARCHS       <- if (length(args) >= 3) args[3:length(args)] else c("rest", "kafka")

message("Benchmark plotting")
message(sprintf("  results : %s", RESULTS_DIR))
message(sprintf("  out     : %s", OUT_DIR))
message(sprintf("  archs   : %s", paste(ARCHS, collapse = ", ")))

# Keep only archs that actually have a results folder
ARCHS <- ARCHS[dir.exists(file.path(RESULTS_DIR, ARCHS))]
if (length(ARCHS) == 0) stop("None of the requested arch folders exist under ", RESULTS_DIR)

arch_scale <- function()
  list(
    scale_fill_manual(values = ARCH_COLOURS[ARCHS], labels = ARCH_LABELS[ARCHS],
                      name = "Architecture", drop = TRUE),
    scale_colour_manual(values = ARCH_COLOURS[ARCHS], labels = ARCH_LABELS[ARCHS],
                        name = "Architecture", drop = TRUE)
  )

# Run a figure block; on error, warn and continue so one failure isn't fatal.
fig <- function(name, expr) {
  tryCatch(force(expr),
           error = function(e) message(sprintf("  [skip %s] %s", name, conditionMessage(e))))
}

# ==========================================================================
#  Load data (each is optional; figures guard on availability)
# ==========================================================================
summary_df    <- tryCatch(load_summary(RESULTS_DIR, ARCHS),    error = function(e) NULL)
per_app_df    <- tryCatch(load_per_app(RESULTS_DIR, ARCHS),    error = function(e) NULL)
per_bucket_df <- tryCatch(load_per_bucket(RESULTS_DIR, ARCHS), error = function(e) NULL)

# ==========================================================================
#  FIG 1 — Per-app state relay latency (p95), REST vs Kafka
# ==========================================================================
fig("fig01", {
  d <- per_app_df %>%
    filter(test == "01-state-relay-latency", metric == "relay_total_ms")
  if (nrow(d) == 0) stop("no relay_total_ms per-app data")
  a <- agg_runs(d, c("arch", "app_name"), "p95") %>%
    mutate(app_name = order_apps(app_name))
  p <- ggplot(a, aes(app_name, mean, fill = arch)) +
    geom_col(position = position_dodge(0.8), width = 0.72) +
    geom_errorbar(aes(ymin = pmax(mean - sd, 0), ymax = mean + sd),
                  position = position_dodge(0.8), width = 0.25, colour = "grey30") +
    arch_scale() +
    scale_y_continuous(labels = ms_label) +
    labs(title = "State relay latency by application (p95)",
         subtitle = "Round-trip POST -> backend -> GET. Lower is better. Error bars = SD across runs.",
         x = NULL, y = "p95 latency") +
    theme_thesis() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
  save_plot(p, OUT_DIR, "fig01_relay_per_app")
})

# ==========================================================================
#  FIG 2 — Latency vs concurrent users (the breakdown curve)
#  Uses per-bucket throughput data; ALL-apps line per architecture.
# ==========================================================================
fig("fig02", {
  d <- per_bucket_df %>%
    filter(test == "04-throughput", metric == "throughput_response_ms")
  if (nrow(d) == 0) stop("no per-bucket throughput data")
  # Prefer the aggregate app row if extractor emitted app_name = "ALL",
  # otherwise average across apps within each bucket.
  d2 <- if (any(d$app_name == "ALL")) filter(d, app_name == "ALL") else d
  a <- agg_runs(d2, c("arch", "vu_bucket"), "p95") %>%
    mutate(vu_bucket = order_buckets(vu_bucket))
  p <- ggplot(a, aes(vu_bucket, mean, colour = arch, group = arch)) +
    geom_line(linewidth = 1.1) +
    geom_point(size = 2.4) +
    geom_ribbon(aes(ymin = pmax(mean - sd, 0), ymax = mean + sd, fill = arch),
                alpha = 0.15, colour = NA) +
    arch_scale() +
    scale_y_continuous(labels = ms_label) +
    labs(title = "Response latency vs concurrent users (p95)",
         subtitle = "Throughput test, stepped load. The knee marks where the R backend saturates.",
         x = "Concurrent users (VU bucket)", y = "p95 response time") +
    theme_thesis() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          panel.grid.major.x = element_line(colour = "grey92"))
  save_plot(p, OUT_DIR, "fig02_throughput_vs_load")
})

# ==========================================================================
#  FIG 3 — Per-app throughput latency (p95), REST vs Kafka
# ==========================================================================
fig("fig03", {
  d <- per_app_df %>%
    filter(test == "04-throughput", metric == "throughput_response_ms")
  if (nrow(d) == 0) stop("no throughput per-app data")
  a <- agg_runs(d, c("arch", "app_name"), "p95") %>%
    mutate(app_name = order_apps(app_name))
  p <- ggplot(a, aes(app_name, mean, fill = arch)) +
    geom_col(position = position_dodge(0.8), width = 0.72) +
    geom_errorbar(aes(ymin = pmax(mean - sd, 0), ymax = mean + sd),
                  position = position_dodge(0.8), width = 0.25, colour = "grey30") +
    arch_scale() +
    scale_y_continuous(labels = ms_label) +
    labs(title = "Throughput latency under load by application (p95)",
         subtitle = "100-VU load. MLTrainer is compute-bound; others reflect backend queuing.",
         x = NULL, y = "p95 response time") +
    theme_thesis() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
  save_plot(p, OUT_DIR, "fig03_throughput_per_app")
})

# ==========================================================================
#  FIG 4 — Save / restore latency per app (DB snapshot cycle)
# ==========================================================================
fig("fig04", {
  d <- per_app_df %>%
    filter(test == "03-save-restore-latency",
           metric %in% c("save_to_db_ms", "restore_from_db_ms"))
  if (nrow(d) == 0) stop("no save/restore per-app data")
  a <- agg_runs(d, c("arch", "app_name", "metric"), "med") %>%
    mutate(app_name = order_apps(app_name),
           metric = recode(metric,
                           save_to_db_ms = "Save", restore_from_db_ms = "Restore"))
  p <- ggplot(a, aes(app_name, mean, fill = arch)) +
    geom_col(position = position_dodge(0.8), width = 0.72) +
    facet_wrap(~ metric) +
    arch_scale() +
    scale_y_continuous(labels = ms_label) +
    labs(title = "Save and restore latency by application (median)",
         subtitle = "PostgreSQL snapshot cycle. Architecture-independent (shared DB path).",
         x = NULL, y = "median latency") +
    theme_thesis() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
  save_plot(p, OUT_DIR, "fig04_save_restore", w = 10, h = 5)
})

# ==========================================================================
#  FIG 5 — Overview grid: p95 across all tests, REST vs Kafka
#  Uses the overall summary (tags flattened) -> one bar per test.
# ==========================================================================
fig("fig05", {
  # Pick the headline latency metric per test
  metric_for <- c(
    "01-state-relay-latency"  = "relay_total_ms",
    "02-collaboration-latency"= "collab_propagation_ms",
    "03-save-restore-latency" = "restore_from_db_ms",
    "04-throughput"           = "throughput_response_ms",
    "07-session-lifecycle"    = "http_req_duration",
    "08-multi-user-collab"    = "propagation_all_ms",
    "09-websocket-presence"   = "ws_join_roundtrip_ms"
  )
  d <- summary_df %>%
    inner_join(tibble(test = names(metric_for), metric = unname(metric_for)),
               by = c("test", "metric"))
  if (nrow(d) == 0) stop("no matching summary metrics")
  a <- agg_runs(d, c("arch", "test"), "p95") %>%
    mutate(test_lab = recode(test, !!!TEST_LABELS),
           test_lab = factor(test_lab, levels = unname(TEST_LABELS)))
  p <- ggplot(a, aes(test_lab, mean, fill = arch)) +
    geom_col(position = position_dodge(0.8), width = 0.72) +
    arch_scale() +
    scale_y_continuous(labels = ms_label) +
    labs(title = "Latency overview across benchmarks (p95)",
         subtitle = "Headline metric per test. Mean of per-run p95; lower is better.",
         x = NULL, y = "p95 latency") +
    theme_thesis() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1))
  save_plot(p, OUT_DIR, "fig05_overview_grid", w = 10, h = 5.5)
})

# ==========================================================================
#  FIG 6 — Reliability: data loss / error rate / isolation
#  These are pass/quality metrics, shown as a simple comparison.
# ==========================================================================
fig("fig06", {
  rel <- summary_df %>%
    filter(metric %in% c("http_req_failed", "throughput_errors",
                         "relay_failure", "ws_errors")) %>%
    mutate(value = ifelse(is.na(avg), med, avg))
  if (nrow(rel) == 0) stop("no reliability metrics")
  a <- rel %>%
    group_by(arch, metric) %>%
    summarise(mean = mean(value, na.rm = TRUE), .groups = "drop") %>%
    mutate(metric = recode(metric,
             http_req_failed   = "HTTP failures",
             throughput_errors = "Throughput errors",
             relay_failure     = "Relay failures",
             ws_errors         = "WebSocket errors"))
  p <- ggplot(a, aes(metric, mean, fill = arch)) +
    geom_col(position = position_dodge(0.8), width = 0.72) +
    arch_scale() +
    labs(title = "Reliability under load",
         subtitle = "Failure rates / counts. Lower is better; 0 is ideal.",
         x = NULL, y = "rate or count") +
    theme_thesis() +
    theme(axis.text.x = element_text(angle = 20, hjust = 1))
  save_plot(p, OUT_DIR, "fig06_reliability")
})

# ==========================================================================
#  FIG 7 — Slowdown factor: "X times slower at N users" per app
#  Normalises each app's per-bucket p95 against its lightest-load bucket.
# ==========================================================================
fig("fig07", {
  d <- per_bucket_df %>%
    filter(test == "04-throughput", metric == "throughput_response_ms",
           app_name != "ALL")
  if (nrow(d) == 0) stop("no per-bucket per-app throughput data")
  a <- agg_runs(d, c("arch", "app_name", "vu_bucket"), "p95")
  # baseline = each (arch, app)'s smallest bucket
  base <- a %>%
    group_by(arch, app_name) %>%
    slice_min(vu_bucket, n = 1, with_ties = FALSE) %>%
    select(arch, app_name, base = mean)
  s <- a %>%
    left_join(base, by = c("arch", "app_name")) %>%
    mutate(factor = mean / base,
           app_name = order_apps(app_name),
           vu_bucket = order_buckets(vu_bucket))
  p <- ggplot(s, aes(vu_bucket, factor, colour = arch, group = arch)) +
    geom_hline(yintercept = 1, linetype = "dashed", colour = "grey60") +
    geom_line(linewidth = 0.9) +
    geom_point(size = 1.8) +
    facet_wrap(~ app_name, scales = "free_y") +
    arch_scale() +
    labs(title = "Slowdown factor vs lightest load, by application",
         subtitle = "p95 normalised to each app's lowest-VU bucket (=1x). Higher = degrades more.",
         x = "Concurrent users (VU bucket)", y = "Slowdown (x)") +
    theme_thesis() +
    theme(axis.text.x = element_text(angle = 90, hjust = 1, size = 7),
          panel.grid.major.x = element_line(colour = "grey94"))
  save_plot(p, OUT_DIR, "fig07_slowdown_factor", w = 11, h = 7)
})

message("\nDone. Figures in: ", OUT_DIR)
