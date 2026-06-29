# ==========================================================================
#  common.R — Shared helpers, theme, and constants for benchmark analysis
#
#  Sourced by the plotting scripts. Loads packages, defines a consistent
#  thesis theme, the app/metric metadata, and small data-loading helpers
#  for the three tidy CSVs produced by k6/extract-results.sh:
#     summary-long.csv     run,test,metric,avg,med,min,max,p90,p95
#     per-app-long.csv     run,test,metric,app_name,count,avg,med,p95
#     per-bucket-long.csv  run,test,metric,vu_bucket,app_name,count,avg,med,p95
# ==========================================================================

suppressMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(scales)
})

# --- Consistent thesis theme ------------------------------------------------
theme_thesis <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title    = element_text(face = "bold", size = rel(1.15)),
      plot.subtitle = element_text(colour = "grey35", size = rel(0.9)),
      axis.title    = element_text(face = "bold"),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      legend.position = "top",
      legend.title  = element_text(face = "bold"),
      strip.text    = element_text(face = "bold"),
      plot.margin   = margin(10, 14, 10, 10)
    )
}

# Architecture colours (consistent across every figure)
ARCH_COLOURS <- c(rest = "#1b6ca8", kafka = "#e07b39", monolithic = "#5a9e6f")
ARCH_LABELS  <- c(rest = "REST (polling)", kafka = "Kafka (pub/sub)",
                  monolithic = "Monolithic")

# The 8 apps, ordered by computational weight (light -> heavy), with the
# stress factor each one exercises (from the thesis RQ doc).
APP_ORDER <- c("Calculator", "Analytics", "Geospatial", "DataExchange",
               "Advanced", "ClimateAnomaly", "MonteCarlo", "MLTrainer")
APP_STRESS <- c(
  Calculator     = "baseline (trivial compute)",
  Analytics      = "moderate plotting",
  Geospatial     = "map tiles / leaflet",
  DataExchange   = "CSV file relay",
  Advanced       = "advanced analytics",
  ClimateAnomaly = "large CSV + raster",
  MonteCarlo     = "heavy simulation",
  MLTrainer      = "RandomForest training (slowest)"
)

# Human-readable test names
TEST_LABELS <- c(
  "00-baseline"             = "Baseline (1 user)",
  "01-state-relay-latency"  = "State relay latency",
  "02-collaboration-latency"= "Collaboration latency",
  "03-save-restore-latency" = "Save / restore latency",
  "04-throughput"           = "Throughput under load",
  "05-data-loss"            = "Data loss under load",
  "06-cross-contamination"  = "Session isolation",
  "07-session-lifecycle"    = "Session lifecycle",
  "08-multi-user-collab"    = "Multi-user scaling",
  "09-websocket-presence"   = "WebSocket presence"
)

# --- Data loaders -----------------------------------------------------------
# Each loader reads <results_dir>/<arch>/<file>.csv for every arch present and
# binds them with an `arch` column. Missing files are skipped with a warning.

load_csv_for_archs <- function(results_dir, archs, file) {
  rows <- lapply(archs, function(a) {
    path <- file.path(results_dir, a, file)
    if (!file.exists(path)) {
      message(sprintf("  [skip] %s (not found)", path))
      return(NULL)
    }
    df <- suppressMessages(read_csv(path, show_col_types = FALSE))
    if (nrow(df) == 0) return(NULL)
    df$arch <- a
    df
  })
  out <- bind_rows(rows)
  if (is.null(out) || nrow(out) == 0)
    stop(sprintf("No '%s' data found in %s for archs: %s",
                 file, results_dir, paste(archs, collapse = ", ")))
  out
}

load_summary  <- function(results_dir, archs)
  load_csv_for_archs(results_dir, archs, "summary-long.csv")
load_per_app  <- function(results_dir, archs)
  load_csv_for_archs(results_dir, archs, "per-app-long.csv")
load_per_bucket <- function(results_dir, archs)
  load_csv_for_archs(results_dir, archs, "per-bucket-long.csv")

# Order app_name factor by computational weight (unknown apps appended).
order_apps <- function(x) {
  lv <- c(APP_ORDER, setdiff(unique(x), APP_ORDER))
  factor(x, levels = lv)
}

# Order vu_bucket naturally ("01-05" < "06-10" < ...). They are zero-padded so
# lexical order already works; this just drops unused levels cleanly.
order_buckets <- function(x) factor(x, levels = sort(unique(x)))

# Aggregate a chosen statistic across the N runs -> mean + sd (for error bars).
# `stat` is one of: avg, med, p95, p90, min, max (column must exist).
agg_runs <- function(df, group_cols, stat = "p95") {
  stopifnot(stat %in% names(df))
  df %>%
    group_by(across(all_of(group_cols))) %>%
    summarise(
      mean = mean(.data[[stat]], na.rm = TRUE),
      sd   = sd(.data[[stat]],   na.rm = TRUE),
      n    = dplyr::n(),
      .groups = "drop"
    ) %>%
    mutate(sd = ifelse(is.na(sd), 0, sd))
}

# Save a plot at consistent size/dpi, both PNG (slides) and PDF (thesis).
save_plot <- function(plot, outdir, name, w = 9, h = 5.2) {
  if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)
  png <- file.path(outdir, paste0(name, ".png"))
  pdf <- file.path(outdir, paste0(name, ".pdf"))
  ggsave(png, plot, width = w, height = h, dpi = 150, bg = "white")
  ggsave(pdf, plot, width = w, height = h, bg = "white")
  message(sprintf("  wrote %s (+pdf)", png))
}

# Pretty ms -> human axis labels (e.g. 1500 -> "1.5 s", 40 -> "40 ms")
ms_label <- function(x) {
  ifelse(is.na(x), NA,
    ifelse(x >= 1000, paste0(formatC(x/1000, digits = 1, format = "f"), " s"),
           paste0(formatC(x, digits = 0, format = "f"), " ms")))
}
