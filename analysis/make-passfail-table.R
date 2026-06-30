#!/usr/bin/env Rscript
# ==========================================================================
#  make-passfail-table.R - PASS/FAIL table vs calibrated thresholds.
#
#  For each app x test, compares measured p95 (mean over runs) against the
#  per-app threshold from k6/config.js (baseline x multiplier) and renders a
#  coloured PASS/FAIL table to analysis/plots/fig08_passfail_table.png.
# ==========================================================================
suppressMessages({
  library(readr); library(dplyr); library(tidyr)
  library(ggplot2); library(stringr)
})

args <- commandArgs(trailingOnly = TRUE)
RESULTS_DIR <- if (length(args) >= 1) args[1] else "k6/results"
OUT_DIR     <- if (length(args) >= 2) args[2] else "analysis/plots"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# --- per-app thresholds (from k6/config.js APP_THRESHOLDS) -----------------
TH <- tribble(
  ~app,            ~relay, ~save, ~restore, ~propagation, ~lifecycle, ~throughput,
  "Calculator",       730,    70,      40,         730,        730,        600,
  "Analytics",        830,    60,      60,         830,        830,        650,
  "Advanced",         730,    80,      50,         730,        730,        500,
  "DataExchange",     870,    80,      60,         870,        870,        550,
  "MonteCarlo",      1170,    80,      50,        1170,       1170,       2550,
  "Geospatial",       730,    60,      40,         730,        730,        550,
  "ClimateAnomaly",  1050,    80,      60,        1050,       1050,       1450,
  "MLTrainer",     143000,    80,      50,      143000,     143000,     711950
)

# --- test -> (metric, threshold key, friendly label) ----------------------
tests <- tribble(
  ~test,                        ~metric,                   ~thkey,        ~label,
  "01-state-relay-latency",     "relay_total_ms",          "relay",       "01 Relay",
  "02-collaboration-latency",   "collab_propagation_ms",   "propagation", "02 Collab",
  "03-save-restore-latency",    "save_to_db_ms",           "save",        "03 Save",
  "03-save-restore-latency",    "restore_from_db_ms",      "restore",     "03 Restore",
  "04-throughput",              "throughput_response_ms",  "throughput",  "04 Thrpt",
  "07-session-lifecycle",       "lifecycle_op_ms",         "lifecycle",   "07 Lifecycle",
  "08-multi-user-collab",       "multi_propagation_all_ms","propagation", "08 MultiCollab"
)

read_perapp <- function(arch) {
  f <- file.path(RESULTS_DIR, arch, "per-app-long.csv")
  if (!file.exists(f)) return(NULL)
  read_csv(f, show_col_types = FALSE) %>% mutate(arch = arch)
}

archs <- c("rest", "kafka")
dat <- bind_rows(lapply(archs, read_perapp))
archs <- intersect(archs, unique(dat$arch))

th_long <- TH %>% pivot_longer(-app, names_to = "thkey", values_to = "threshold")

# measured p95 per (arch, app, test/metric), averaged across runs
meas <- dat %>%
  inner_join(tests, by = c("test", "metric")) %>%
  filter(app_name %in% TH$app) %>%
  group_by(arch, label, thkey, app = app_name) %>%
  summarise(p95 = mean(p95, na.rm = TRUE), .groups = "drop") %>%
  left_join(th_long, by = c("app", "thkey")) %>%
  mutate(
    status = case_when(
      is.na(p95)              ~ "n/a",
      p95 <= threshold        ~ "PASS",
      TRUE                    ~ "FAIL"
    ),
    cell = ifelse(is.na(p95), "-", sprintf("%s\n%s / %s",
                  status,
                  ifelse(p95 >= 1000, sprintf("%.1fs", p95/1000), sprintf("%.0fms", p95)),
                  ifelse(threshold >= 1000, sprintf("%.0fs", threshold/1000), sprintf("%.0fms", threshold))))
  )

app_order <- TH$app
test_order <- unique(tests$label)

plot_one <- function(arch) {
  d <- meas %>% filter(arch == !!arch) %>%
    mutate(app = factor(app, levels = rev(app_order)),
           label = factor(label, levels = test_order))
  ggplot(d, aes(label, app, fill = status)) +
    geom_tile(colour = "white", linewidth = 1.2) +
    geom_text(aes(label = cell), size = 2.7, lineheight = 0.9) +
    scale_fill_manual(values = c(PASS = "#2e8b57", FAIL = "#c0392b", `n/a` = "grey75"),
                      name = NULL) +
    labs(title = sprintf("%s - PASS/FAIL vs calibrated thresholds", toupper(arch)),
         subtitle = "cell = status, measured p95 / threshold (threshold = baseline x 10 relay/collab/save, x50 throughput)",
         x = NULL, y = NULL) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1, face = "bold"),
          axis.text.y = element_text(face = "bold"),
          panel.grid = element_blank(),
          plot.title = element_text(face = "bold"),
          plot.subtitle = element_text(size = 8, colour = "grey30"),
          legend.position = "top")
}

for (a in archs) {
  p <- plot_one(a)
  png_path <- file.path(OUT_DIR, sprintf("fig08_passfail_%s.png", a))
  ggsave(png_path, p, width = 10, height = 5.2, dpi = 200, bg = "white")
  ggsave(sub("\\.png$", ".pdf", png_path), p, width = 10, height = 5.2)
  message("  wrote ", png_path)
}

# combined summary counts
summ <- meas %>% group_by(arch, status) %>% summarise(n = n(), .groups = "drop")
message("\nPASS/FAIL counts:")
print(as.data.frame(summ))
