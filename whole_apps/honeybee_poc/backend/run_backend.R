# Entry point for the Honeybee PoC Plumber backend.
# Run: Rscript backend/run_backend.R   (listens on :8000)
library(plumber)
port <- as.integer(Sys.getenv("PORT", "8000"))
pr <- plumber::plumb("backend/plumber.R")
cat(sprintf("Honeybee PoC backend listening on http://0.0.0.0:%d\n", port))
pr$run(host = "0.0.0.0", port = port)
