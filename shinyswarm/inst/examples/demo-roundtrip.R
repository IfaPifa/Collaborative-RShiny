# Standalone, headless demo of shinyswarm capture/restore.
# No Shiny server or browser required.
#
# If the package is installed:   Rscript demo-roundtrip.R
# From a source checkout:        run from the package root; the block below
#                                sources R/ directly when the package is not
#                                installed.

if (requireNamespace("shinyswarm", quietly = TRUE)) {
  library(shinyswarm)
} else if (dir.exists("R")) {
  message("shinyswarm not installed; sourcing R/ from the source tree")
  invisible(lapply(list.files("R", pattern = "[.]R$", full.names = TRUE), source))
} else {
  stop("Install shinyswarm, or run this script from the package root.")
}

cat("== shinyswarm round-trip demo ==\n\n")

# A reactiveVal is just a function; emulate one with a closure so this script
# needs no running Shiny session.
make_val <- function(initial = NULL) {
  v <- initial
  function(x) if (missing(x)) v else v <<- x
}

# ---------------------------------------------------------------------------
# 1. Basic inputs + a computed reactive value
# ---------------------------------------------------------------------------
result <- make_val(100)
json <- capture_state(list(num1 = 42, num2 = 58), result = result)

cat("Captured JSON:\n", json, "\n\n")

# Simulate the value drifting after the checkpoint, then restore.
result(999)
cat("Before restore, result =", result(), "\n")
restore_state(NULL, json, result = result)
cat("After  restore, result =", result(), "  (back to the saved 100)\n\n")

# ---------------------------------------------------------------------------
# 2. Non-deterministic output is preserved, not recomputed
# ---------------------------------------------------------------------------
draw <- make_val(mean(runif(1000)))   # no set.seed()
saved <- draw()
json2 <- capture_state(list(n = 1000), draw = draw)

draw(mean(runif(1000)))               # a different "run" => different value
cat("Saved Monte Carlo mean :", saved, "\n")
cat("Recomputed (different) :", draw(), "\n")
restore_state(NULL, json2, draw = draw)
cat("After restore          :", draw(), "  (exact saved value)\n\n")

# ---------------------------------------------------------------------------
# 3. Embedding a file (gzip + base64), restored to a directory
# ---------------------------------------------------------------------------
csv <- tempfile(fileext = ".csv")
writeLines(c("site,temp", "A,21.5", "B,19.2"), csv)

json3 <- capture_state(list(), data = state_file(csv))
out_dir <- tempfile("restored_")
holder <- make_val(NULL)
restore_state(NULL, json3, data = holder, file_dir = out_dir)

cat("File restored to:", holder(), "\n")
cat("Contents:\n"); cat(readLines(holder()), sep = "\n"); cat("\n\n")

# ---------------------------------------------------------------------------
# 4. Security: a malicious filename cannot escape the target directory
# ---------------------------------------------------------------------------
evil <- jsonlite::toJSON(list(
  inputs = list(), compressed = FALSE,
  reactives = list(f = list(
    type = "file", filename = "../ESCAPED.txt",
    content = base64enc::base64encode(charToRaw("pwned"))
  ))
), auto_unbox = TRUE)

res <- tryCatch(
  restore_state(NULL, evil, f = make_val(NULL), file_dir = tempfile()),
  error = function(e) conditionMessage(e)
)
cat("Path-traversal attempt rejected with:\n  ", res, "\n\n")

cat("== demo complete ==\n")
