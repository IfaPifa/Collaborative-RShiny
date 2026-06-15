# =============================================================================
# Headless end-to-end demo of the single-cell S3 claim-check.
#
# Simulates two users without a browser:
#   User A  - runs the PBMC 3k Seurat pipeline and "shares" the result. The
#             heavy object goes to S3; only a small reference is produced.
#   (bus)   - the reference is what would travel through Kafka/Redis. We print
#             its size to show it is kilobytes, not the hundreds of megabytes of
#             the object.
#   User B  - receives only the reference and restores the exact object from S3.
#
# Asserts the MVP acceptance criteria and prints a before/after summary.
#
# Run (from this directory), with MinIO running:
#   AWS_ACCESS_KEY_ID=minio AWS_SECRET_ACCESS_KEY=minio123 \
#   STATESNAP_S3_ENDPOINT=http://127.0.0.1:9000 \
#   Rscript demo-claimcheck.R
# =============================================================================

suppressPackageStartupMessages({
  library(Seurat)
  library(statesnap)
})

source("pipeline.R", local = TRUE)

DATA_DIR <- file.path("data", "filtered_gene_bc_matrices", "hg19")
PROCESSED <- file.path("data", "pbmc3k_processed.rds")

s3 <- s3_config(
  bucket     = Sys.getenv("STATESNAP_S3_BUCKET", "shinyswarm-state"),
  endpoint   = Sys.getenv("STATESNAP_S3_ENDPOINT", "http://127.0.0.1:9000"),
  access_key = Sys.getenv("AWS_ACCESS_KEY_ID", "minio"),
  secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY", "minio123")
)

rule <- function(s) cat("\n", strrep("=", 70), "\n", s, "\n",
                        strrep("=", 70), "\n", sep = "")

# ---------------------------------------------------------------------------
rule("USER A: compute the single-cell analysis")
if (file.exists(PROCESSED)) {
  cat("Loading cached processed object...\n")
  obj_a <- readRDS(PROCESSED)
} else {
  cat("Running Seurat PBMC 3k pipeline...\n")
  obj_a <- run_pbmc_pipeline(data_dir = DATA_DIR)
}
obj_mb <- as.numeric(object.size(obj_a)) / 1024 / 1024
cat(sprintf("Cells: %d | Genes: %d | Clusters: %d | Object: %.0f MB\n",
            ncol(obj_a), nrow(obj_a), length(levels(Idents(obj_a))), obj_mb))

# ---------------------------------------------------------------------------
rule("USER A: share state (object -> S3, reference -> bus)")
t0 <- Sys.time()
ref_json <- capture_state(
  list(gene = "MS4A1", resolution = 0.5),
  seurat = state_rds(obj_a),
  s3 = s3
)
share_secs <- as.numeric(Sys.time() - t0, units = "secs")
bus_bytes <- nchar(ref_json)
cat(sprintf("Capture + upload: %.1f s\n", share_secs))
cat(sprintf("BUS PAYLOAD (the only thing on Kafka/Redis): %d bytes\n", bus_bytes))
cat("Reference content:\n")
cat(ref_json, "\n")

# ---------------------------------------------------------------------------
rule("USER B: restore state (reference -> fetch object from S3)")
obj_b <- NULL
t1 <- Sys.time()
restore_state(NULL, ref_json,
              seurat = function(v) obj_b <<- v,
              s3 = s3, allow_rds = TRUE)
restore_secs <- as.numeric(Sys.time() - t1, units = "secs")
cat(sprintf("Fetch + restore: %.1f s\n", restore_secs))
cat(sprintf("Restored object: %d cells, %d clusters\n",
            ncol(obj_b), length(levels(Idents(obj_b)))))

# ---------------------------------------------------------------------------
rule("ACCEPTANCE CRITERIA")
check <- function(label, ok) {
  cat(sprintf("[%s] %s\n", if (ok) "PASS" else "FAIL", label))
  if (!ok) stop("acceptance criterion failed: ", label, call. = FALSE)
  invisible(ok)
}

check(sprintf("Object > 100 MB shared and restored (%.0f MB)", obj_mb),
      obj_mb > 100)
check(sprintf("Bus payload stays in the kilobyte range (%d bytes)", bus_bytes),
      bus_bytes < 10 * 1024)
check("Restored clusters match User A",
      identical(levels(Idents(obj_a)), levels(Idents(obj_b))))
check("Restored UMAP embedding matches User A",
      identical(Embeddings(obj_a, "umap"), Embeddings(obj_b, "umap")))
check("Full object is byte-identical", identical(obj_a, obj_b))

# Small (non-single-cell) state still uses the inline path unchanged.
inline_json <- capture_state(list(a = 1, b = "x"), result = 42)
check("Small state keeps using the inline path (no claim-check)",
      !grepl("claim-check", inline_json, fixed = TRUE))

# The decisive control: prove the pipeline is genuinely non-deterministic, so
# that a byte-identical restore can ONLY come from state sharing, never from a
# lucky recomputation. A fresh re-run of the exact same pipeline must diverge.
rule("CONTROL: recomputation diverges (no hidden seeds)")
obj_recompute <- run_pbmc_pipeline(data_dir = DATA_DIR)
umap_diff <- max(abs(Embeddings(obj_a, "umap") - Embeddings(obj_recompute, "umap")))
cat(sprintf("Max UMAP coordinate difference vs a fresh recompute: %.2f\n", umap_diff))
check("A fresh recompute DIVERGES from A (pipeline is non-deterministic)",
      umap_diff > 0)
check("Yet the S3 restore is byte-identical to A (state, not recompute)",
      identical(Embeddings(obj_a, "umap"), Embeddings(obj_b, "umap")))

rule("BEFORE / AFTER")
cat(sprintf("Inline (before): bus would carry ~%.0f MB (object as base64 JSON)\n",
            obj_mb * 1.37))
cat(sprintf("Claim-check (after): bus carries %d bytes  ->  %.0fx smaller\n",
            bus_bytes, (obj_mb * 1.37 * 1024 * 1024) / bus_bytes))

rule("DEMO COMPLETE - all acceptance criteria passed")
