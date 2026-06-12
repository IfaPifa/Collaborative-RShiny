# ==========================================================================
#  statesnap microbenchmarks
#
#  Measures the IN-PROCESS cost of the library: capture_state() and
#  restore_state() latency, payload size, and compression effectiveness.
#  This is deliberately separate from the k6 system benchmarks (which measure
#  HTTP + database + session round-trips). The library's cost is the
#  serialisation work; the transport's cost is measured elsewhere.
#
#  Headless: no Shiny server, no browser. Run with:
#     Rscript statesnap/inst/benchmarks/benchmark.R
#  from the repository root (or with the package installed).
#
#  Outputs (written next to this script, under results/):
#     - latency.csv              capture/restore timings by payload size
#     - sizes.csv                payload sizes + compression ratios
#     - tradeoff.csv             full-state vs input-only comparison
#     - latency-plot.png         latency vs payload size
#     - size-plot.png            raw vs gzip payload size
#     - benchmark-results.md     thesis-ready summary tables
# ==========================================================================

suppressWarnings(suppressMessages({
  if (requireNamespace("statesnap", quietly = TRUE)) {
    library(statesnap)
  } else if (dir.exists("statesnap/R")) {
    invisible(lapply(list.files("statesnap/R", "[.]R$", full.names = TRUE), source))
    library(jsonlite); library(base64enc)
  } else if (dir.exists("R")) {
    invisible(lapply(list.files("R", "[.]R$", full.names = TRUE), source))
    library(jsonlite); library(base64enc)
  } else {
    stop("Run from the repo root or install the statesnap package.")
  }
  library(microbenchmark)
  have_ggplot <- requireNamespace("ggplot2", quietly = TRUE)
}))

set.seed(42)  # reproducible synthetic payloads (not the captured values)

# Resolve an output directory next to this script when possible.
# Resolve a deterministic output directory: always <script_dir>/results,
# regardless of how the script is invoked. Resolution order:
#   1. SHINYSWARM_BENCH_OUT env var, if set (explicit override).
#   2. The directory of this script, via --file= (Rscript benchmark.R).
#   3. Known repo-relative location when sourced (Rscript -e 'source(...)').
# This guarantees a rerun updates one canonical location rather than writing
# to getwd(), which varies with the invocation.
out_dir <- local({
  override <- Sys.getenv("SHINYSWARM_BENCH_OUT", "")
  if (nzchar(override)) {
    base <- override
  } else {
    args <- commandArgs(trailingOnly = FALSE)
    fa <- sub("^--file=", "", args[grep("^--file=", args)])
    if (length(fa) == 1L && nzchar(fa)) {
      base <- dirname(normalizePath(fa))
    } else if (file.exists("statesnap/inst/benchmarks/benchmark.R")) {
      base <- "statesnap/inst/benchmarks"          # run from repo root
    } else if (file.exists("inst/benchmarks/benchmark.R")) {
      base <- "inst/benchmarks"                      # run from package root
    } else {
      base <- getwd()                                # last resort
    }
  }
  d <- file.path(base, "results")
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  normalizePath(d)
})

TIMES <- as.integer(Sys.getenv("SHINYSWARM_BENCH_TIMES", "100"))
cat(sprintf("statesnap benchmark | %d iterations/case | output: %s\n\n",
            TIMES, out_dir))

# A reactiveVal stand-in so the benchmark needs no running Shiny session.
make_val <- function(initial = NULL) {
  v <- initial
  function(x) if (missing(x)) v else v <<- x
}

# Build a synthetic data frame of approximately `target_bytes` when serialised.
make_df <- function(target_bytes) {
  # ~ each row of (double, double, short string) ~ 40 bytes serialised.
  n <- max(1L, as.integer(target_bytes / 40))
  data.frame(
    id    = seq_len(n),
    value = rnorm(n),
    label = sample(c("alpha", "beta", "gamma", "delta"), n, replace = TRUE),
    stringsAsFactors = FALSE
  )
}

ms <- function(nanoseconds) nanoseconds / 1e6

# --------------------------------------------------------------------------
# 1. Latency across payload sizes (data-frame reactive value)
# --------------------------------------------------------------------------
cat("[1/3] Latency vs payload size ...\n")

size_targets <- c(1e3, 1e4, 1e5, 1e6, 5e6, 1e7)  # 1 KB .. 10 MB
size_labels  <- c("1 KB", "10 KB", "100 KB", "1 MB", "5 MB", "10 MB")

latency_rows <- list()
for (i in seq_along(size_targets)) {
  df <- make_df(size_targets[i])
  rv <- make_val(df)
  json <- capture_state(list(n = nrow(df)), data = rv)  # warm + measured below

  cap <- microbenchmark(
    capture_state(list(n = nrow(df)), data = rv),
    times = TIMES
  )
  holder <- make_val(NULL)
  res <- microbenchmark(
    restore_state(NULL, json, data = holder),
    times = TIMES
  )

  latency_rows[[i]] <- data.frame(
    size_label   = size_labels[i],
    size_bytes   = size_targets[i],
    json_bytes   = nchar(json),
    capture_med_ms = ms(median(cap$time)),
    capture_iqr_ms = ms(IQR(cap$time)),
    restore_med_ms = ms(median(res$time)),
    restore_iqr_ms = ms(IQR(res$time))
  )
  cat(sprintf("    %-7s  capture %.2f ms  restore %.2f ms  (json %s)\n",
              size_labels[i], ms(median(cap$time)), ms(median(res$time)),
              format(nchar(json), big.mark = ",")))
}
latency <- do.call(rbind, latency_rows)
write.csv(latency, file.path(out_dir, "latency.csv"), row.names = FALSE)

# --------------------------------------------------------------------------
# 2. Payload size + compression ratio by data type
# --------------------------------------------------------------------------
cat("\n[2/3] Compression effectiveness by data type ...\n")

# (a) CSV file: highly repetitive text
csv_path <- tempfile(fileext = ".csv")
writeLines(c("site,temp,humidity",
             rep("stationA,21.5,60.2", 50000)), csv_path)

# (b) data frame: mixed numeric/text
df_big <- make_df(2e6)

# (c) binary model: low redundancy
model <- lm(value ~ id, data = df_big)

size_case <- function(label, raw_json, comp_json) {
  data.frame(
    case        = label,
    raw_bytes   = nchar(raw_json),
    gzip_bytes  = nchar(comp_json),
    ratio       = round(nchar(raw_json) / nchar(comp_json), 2),
    saved_pct   = round(100 * (1 - nchar(comp_json) / nchar(raw_json)), 1)
  )
}

size_rows <- list(
  size_case("CSV file (repetitive)",
            capture_state(list(), f = state_file(csv_path), compress = FALSE),
            capture_state(list(), f = state_file(csv_path), compress = TRUE)),
  size_case("data.frame (state_rds)",
            capture_state(list(), d = state_rds(df_big), compress = FALSE),
            capture_state(list(), d = state_rds(df_big), compress = TRUE)),
  size_case("lm model (state_rds)",
            capture_state(list(), m = state_rds(model), compress = FALSE),
            capture_state(list(), m = state_rds(model), compress = TRUE))
)
sizes <- do.call(rbind, size_rows)
write.csv(sizes, file.path(out_dir, "sizes.csv"), row.names = FALSE)
for (i in seq_len(nrow(sizes))) {
  cat(sprintf("    %-24s raw %9s  gzip %9s  ratio %.2fx (%.1f%% saved)\n",
              sizes$case[i],
              format(sizes$raw_bytes[i], big.mark = ","),
              format(sizes$gzip_bytes[i], big.mark = ","),
              sizes$ratio[i], sizes$saved_pct[i]))
}

# --------------------------------------------------------------------------
# 3. Full-state vs input-only (the RQ5 trade-off, quantified)
# --------------------------------------------------------------------------
cat("\n[3/3] Full-state vs input-only ...\n")

# A representative app: a few inputs plus a computed 1 MB result table.
inputs <- list(num1 = 42, num2 = 58, method = "monte-carlo", iterations = 1e5)
result_df <- make_df(1e6)
result <- make_val(result_df)

# Input-only: just the inputs (what shinyURL / bookmarking transfer).
input_only_json <- capture_state(inputs)
# Full-state: inputs + the computed result.
full_state_json <- capture_state(inputs, result = result)

io_cap <- microbenchmark(capture_state(inputs), times = TIMES)
fs_cap <- microbenchmark(capture_state(inputs, result = result), times = TIMES)

tradeoff <- data.frame(
  approach    = c("input-only", "full-state"),
  json_bytes  = c(nchar(input_only_json), nchar(full_state_json)),
  capture_med_ms = c(ms(median(io_cap$time)), ms(median(fs_cap$time))),
  reproduces_nondeterministic = c(FALSE, TRUE)
)
write.csv(tradeoff, file.path(out_dir, "tradeoff.csv"), row.names = FALSE)
cat(sprintf("    input-only: %s bytes, %.3f ms (recompute required)\n",
            format(nchar(input_only_json), big.mark = ","),
            ms(median(io_cap$time))))
cat(sprintf("    full-state: %s bytes, %.3f ms (exact reproduction)\n",
            format(nchar(full_state_json), big.mark = ","),
            ms(median(fs_cap$time))))

# --------------------------------------------------------------------------
# Plots
# --------------------------------------------------------------------------
if (have_ggplot) {
  library(ggplot2)
  lat_long <- rbind(
    data.frame(size_bytes = latency$size_bytes, op = "capture",
               ms = latency$capture_med_ms),
    data.frame(size_bytes = latency$size_bytes, op = "restore",
               ms = latency$restore_med_ms)
  )
  p1 <- ggplot(lat_long, aes(size_bytes, ms, colour = op)) +
    geom_line() + geom_point() +
    scale_x_log10(labels = function(x) paste0(x/1e3, "KB")) +
    scale_y_log10() +
    labs(title = "statesnap capture/restore latency",
         x = "approx. state size (log)", y = "median ms (log)",
         colour = NULL) +
    theme_minimal()
  ggsave(file.path(out_dir, "latency-plot.png"), p1, width = 7, height = 4, dpi = 120)

  sz_long <- rbind(
    data.frame(case = sizes$case, kind = "raw",  bytes = sizes$raw_bytes),
    data.frame(case = sizes$case, kind = "gzip", bytes = sizes$gzip_bytes)
  )
  p2 <- ggplot(sz_long, aes(case, bytes, fill = kind)) +
    geom_col(position = "dodge") +
    scale_y_continuous(labels = function(x) paste0(round(x/1e3), "KB")) +
    labs(title = "statesnap payload size: raw vs gzip",
         x = NULL, y = "JSON bytes", fill = NULL) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 20, hjust = 1))
  ggsave(file.path(out_dir, "size-plot.png"), p2, width = 7, height = 4, dpi = 120)
  cat("\nPlots written.\n")
} else {
  cat("\nggplot2 not available; skipping plots.\n")
}

# --------------------------------------------------------------------------
# Markdown report
# --------------------------------------------------------------------------
fmt <- function(x, d = 2) formatC(x, format = "f", digits = d)
md <- c(
  "# statesnap benchmark results",
  "",
  sprintf("_Generated %s. %d iterations per case. R %s, %s._",
          format(Sys.Date()), TIMES, getRversion(),
          R.version$platform),
  "",
  "These are **in-process** microbenchmarks of the library's serialisation",
  "cost. They are distinct from the k6 system benchmarks, which measure HTTP +",
  "database + session round-trips. Single machine, warm cache; medians with IQR",
  "are reported to absorb GC jitter.",
  "",
  "## 1. Capture / restore latency vs payload size",
  "",
  "| State size | JSON bytes | Capture (ms) | Restore (ms) |",
  "|---|---:|---:|---:|",
  paste0("| ", latency$size_label,
         " | ", format(latency$json_bytes, big.mark = ","),
         " | ", fmt(latency$capture_med_ms), " ± ", fmt(latency$capture_iqr_ms),
         " | ", fmt(latency$restore_med_ms), " ± ", fmt(latency$restore_iqr_ms),
         " |"),
  "",
  "## 2. Compression effectiveness by data type",
  "",
  "| Case | Raw bytes | Gzip bytes | Ratio | Saved |",
  "|---|---:|---:|---:|---:|",
  paste0("| ", sizes$case,
         " | ", format(sizes$raw_bytes, big.mark = ","),
         " | ", format(sizes$gzip_bytes, big.mark = ","),
         " | ", fmt(sizes$ratio), "x",
         " | ", fmt(sizes$saved_pct, 1), "% |"),
  "",
  "## 3. Full-state vs input-only",
  "",
  "| Approach | JSON bytes | Capture (ms) | Reproduces non-deterministic output |",
  "|---|---:|---:|:--:|",
  paste0("| ", tradeoff$approach,
         " | ", format(tradeoff$json_bytes, big.mark = ","),
         " | ", fmt(tradeoff$capture_med_ms, 3),
         " | ", ifelse(tradeoff$reproduces_nondeterministic, "yes", "no"), " |"),
  "",
  sprintf("Full-state capture costs %sx the bytes and %sx the time of input-only",
          fmt(tradeoff$json_bytes[2] / tradeoff$json_bytes[1], 1),
          fmt(tradeoff$capture_med_ms[2] / tradeoff$capture_med_ms[1], 1)),
  "for this case, in exchange for exact reproduction of computed results.",
  "",
  "_Plots: `latency-plot.png`, `size-plot.png`._"
)
writeLines(md, file.path(out_dir, "benchmark-results.md"))
cat(sprintf("\nReport written: %s\n", file.path(out_dir, "benchmark-results.md")))
cat("Done.\n")
