# Seurat PBMC 3k pipeline.
#
# Encapsulates the standard single-cell workflow (load 10x matrix, QC filter,
# normalise, find variable features, scale, PCA, neighbours, clustering, UMAP)
# so both the Shiny app and the headless demo run the exact same analysis.
#
# The returned Seurat object is the heavy shared state: it is what one user
# computes and another restores via the statesnap S3 claim-check.

suppressPackageStartupMessages({
  library(Seurat)
})

# Path to the extracted 10x matrix directory (genes/barcodes/matrix).
pbmc_data_dir <- function() {
  here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
  base <- if (!is.na(here)) here else getwd()
  file.path(base, "data", "filtered_gene_bc_matrices", "hg19")
}

#' Run the PBMC 3k Seurat pipeline end to end.
#'
#' @param data_dir Directory holding the 10x matrix files.
#' @param resolution Louvain clustering resolution.
#' @param n_dims Number of PCA dimensions used for neighbours/UMAP/clustering.
#' @param verbose Whether Seurat prints progress.
#' @return A processed Seurat object (clusters + UMAP embedding present).
run_pbmc_pipeline <- function(data_dir = pbmc_data_dir(),
                              resolution = 0.5,
                              n_dims = 10,
                              verbose = FALSE) {
  counts <- Read10X(data.dir = data_dir)
  obj <- CreateSeuratObject(counts = counts, project = "pbmc3k",
                            min.cells = 3, min.features = 200)

  obj[["percent.mt"]] <- PercentageFeatureSet(obj, pattern = "^MT-")
  obj <- subset(obj, subset = nFeature_RNA > 200 &
                  nFeature_RNA < 2500 & percent.mt < 5)

  # A positive seed drawn from OS entropy (/dev/urandom), independent of R's
  # global RNG. We need this because FindClusters internally calls
  # set.seed(random.seed), which would pin R's RNG and make any seed we then
  # draw via sample() a deterministic function of it -- collapsing the very
  # non-determinism we want. /dev/urandom side-steps that entirely. Falls back
  # to a clock+PID mix on platforms without /dev/urandom.
  entropy_seed <- function() {
    s <- tryCatch(
      readBin("/dev/urandom", what = "integer", n = 1L, size = 4L),
      error = function(e) NA_integer_
    )
    if (is.na(s)) {
      s <- as.integer((as.numeric(Sys.time()) * 1000) %% .Machine$integer.max) +
        Sys.getpid()
    }
    abs(s) %% .Machine$integer.max + 1L
  }

  obj <- NormalizeData(obj, verbose = verbose)
  obj <- FindVariableFeatures(obj, selection.method = "vst",
                              nfeatures = 2000, verbose = verbose)
  obj <- ScaleData(obj, features = rownames(obj), verbose = verbose)

  # Deliberately non-deterministic. Seurat's stochastic steps default to fixed
  # internal seeds (RunPCA/RunUMAP seed.use = 42, FindClusters random.seed = 0),
  # which would make every recomputation identical and hide what is actually
  # being demonstrated. We defeat that by feeding each stochastic step a fresh
  # entropy-derived seed. No set.seed() appears anywhere in the project.
  #
  # This is the point of the demo: a fresh re-run diverges (different UMAP,
  # possibly different cluster labels), so if User B's analysis matches User A's
  # it can only be because the computed state was restored from the store --
  # never because a recomputation happened to land on the same seed.
  obj <- RunPCA(obj, features = VariableFeatures(obj), verbose = verbose,
                seed.use = entropy_seed())
  obj <- FindNeighbors(obj, dims = 1:n_dims, verbose = verbose)
  obj <- FindClusters(obj, resolution = resolution, verbose = verbose,
                      random.seed = entropy_seed())
  obj <- RunUMAP(obj, dims = 1:n_dims, verbose = verbose,
                 seed.use = entropy_seed())
  obj
}
