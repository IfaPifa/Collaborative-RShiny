# =============================================================================
# ShinySwarm - Single-Cell (PBMC 3k) collaborative app with S3 claim-check.
#
# Demonstrates sharing a *large* computed object (a ~330 MB Seurat object) across
# users without passing it through the message bus. Capture writes the object to
# an S3-compatible store (MinIO) and emits a small claim-check reference via
# statesnap; restore redeems the reference and fetches the object back.
#
# Run (from this directory), pointing at a running MinIO:
#   AWS_ACCESS_KEY_ID=minio AWS_SECRET_ACCESS_KEY=minio123 \
#   STATESNAP_S3_ENDPOINT=http://127.0.0.1:9000 \
#   R -e "shiny::runApp('app.R', host='0.0.0.0', port=3838)"
#
# Two browser tabs act as User A and User B. A runs the pipeline and clicks
# "Share state"; B pastes the reference and clicks "Restore state" to see A's
# exact analysis (same clusters, same UMAP) with no recomputation.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(Seurat)
  library(ggplot2)
  library(statesnap)
})

source("pipeline.R", local = TRUE)

DATA_DIR <- file.path("data", "filtered_gene_bc_matrices", "hg19")

# Object store config from the environment, defaulting to local MinIO.
s3 <- s3_config(
  bucket     = Sys.getenv("STATESNAP_S3_BUCKET", "shinyswarm-state"),
  endpoint   = Sys.getenv("STATESNAP_S3_ENDPOINT", "http://127.0.0.1:9000"),
  access_key = Sys.getenv("AWS_ACCESS_KEY_ID", "minio"),
  secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY", "minio123")
)

ui <- page_sidebar(
  theme = bs_theme(version = 5, preset = "minty"),
  title = "ShinySwarm: Single-Cell (PBMC 3k) + S3 Claim-Check",

  sidebar = sidebar(
    width = 360,
    title = "Analysis & Collaboration",

    h5("1. Compute (User A)"),
    sliderInput("resolution", "Clustering resolution:",
                min = 0.1, max = 1.5, value = 0.5, step = 0.1),
    sliderInput("n_dims", "PCA dimensions:",
                min = 5, max = 30, value = 10, step = 1),
    actionButton("run", "Run pipeline", class = "btn-success",
                 icon = icon("dna")),
    hr(),

    h5("2. Share state -> S3"),
    textInput("gene", "Gene of interest:", value = "MS4A1"),
    actionButton("share", "Share state", class = "btn-primary",
                 icon = icon("cloud-arrow-up")),
    div(class = "mt-2",
        tags$small("Claim-check reference (this is all that rides the bus):")),
    verbatimTextOutput("ref_out"),

    hr(),
    h5("3. Restore state (User B)"),
    textAreaInput("ref_in", "Paste reference JSON:", rows = 4,
                  placeholder = "{...claim-check...}"),
    actionButton("restore", "Restore state", class = "btn-info",
                 icon = icon("cloud-arrow-down")),

    hr(),
    h5("Architecture:"),
    textOutput("store_status")
  ),

  layout_columns(
    col_widths = c(4, 4, 4),
    value_box(title = "Cells", value = textOutput("kpi_cells"),
              showcase = icon("microscope"), theme = "success"),
    value_box(title = "Clusters", value = textOutput("kpi_clusters"),
              showcase = icon("circle-nodes"), theme = "info"),
    value_box(title = "Object size", value = textOutput("kpi_size"),
              showcase = icon("weight-hanging"), theme = "secondary")
  ),

  card(
    card_header("UMAP - clusters"),
    plotOutput("umap_plot", height = "360px")
  ),
  card(
    card_header(textOutput("feature_header", inline = TRUE)),
    plotOutput("feature_plot", height = "320px")
  )
)

server <- function(input, output, session) {

  # The heavy shared state: the processed Seurat object.
  seurat <- reactiveVal(NULL)
  last_ref <- reactiveVal("")

  output$store_status <- renderText({
    paste0("S3 claim-check via ", s3$endpoint, " (bucket: ", s3$bucket, ")")
  })

  # --- 1. Compute the pipeline (User A) ---
  observeEvent(input$run, {
    withProgress(message = "Running Seurat PBMC 3k pipeline...", value = 0.3, {
      obj <- run_pbmc_pipeline(data_dir = DATA_DIR,
                               resolution = input$resolution,
                               n_dims = input$n_dims)
      incProgress(0.7)
      seurat(obj)
    })
    showNotification("Pipeline complete.", type = "message")
  })

  # --- 2. Share: upload object to S3, emit a tiny reference (User A) ---
  observeEvent(input$share, {
    obj <- seurat()
    if (is.null(obj)) {
      showNotification("Run the pipeline before sharing.", type = "warning")
      return()
    }
    withProgress(message = "Uploading object to S3 (claim-check)...",
                 value = 0.5, {
      json <- capture_state(
        list(gene = input$gene,
             resolution = input$resolution,
             n_dims = input$n_dims),
        seurat = state_rds(obj),
        s3 = s3
      )
      incProgress(0.5)
      last_ref(json)
    })
    showNotification(
      sprintf("Shared. Bus payload: %d bytes (object stays in S3).",
              nchar(last_ref())),
      type = "message", duration = 6
    )
  })

  output$ref_out <- renderText({
    r <- last_ref()
    if (!nzchar(r)) "(share to generate a reference)" else r
  })

  # --- 3. Restore: redeem the reference, fetch object from S3 (User B) ---
  observeEvent(input$restore, {
    ref <- trimws(input$ref_in)
    if (!nzchar(ref)) {
      showNotification("Paste a reference JSON first.", type = "warning")
      return()
    }
    withProgress(message = "Fetching object from S3...", value = 0.5, {
      restored <- NULL
      tryCatch({
        restore_state(session, ref,
                      seurat = function(v) restored <<- v,
                      s3 = s3, allow_rds = TRUE)
      }, error = function(e) {
        showNotification(paste("Restore failed:", conditionMessage(e)),
                         type = "error", duration = 8)
      })
      incProgress(0.5)
      if (!is.null(restored)) {
        seurat(restored)
        showNotification("Restored A's exact analysis from S3.",
                         type = "message")
      }
    })
  })

  # --- KPIs ---
  output$kpi_cells <- renderText({
    obj <- seurat(); if (is.null(obj)) "-" else format(ncol(obj), big.mark = ",")
  })
  output$kpi_clusters <- renderText({
    obj <- seurat(); if (is.null(obj)) "-" else length(levels(Idents(obj)))
  })
  output$kpi_size <- renderText({
    obj <- seurat()
    if (is.null(obj)) "-" else format(object.size(obj), units = "MB")
  })

  # --- Plots ---
  output$umap_plot <- renderPlot({
    obj <- seurat()
    validate(need(!is.null(obj), "Run the pipeline or restore a shared state."))
    DimPlot(obj, reduction = "umap", label = TRUE) + NoLegend()
  })

  output$feature_header <- renderText({
    paste0("Feature expression - ", input$gene)
  })

  output$feature_plot <- renderPlot({
    obj <- seurat()
    validate(need(!is.null(obj), "No object yet."))
    g <- input$gene
    validate(need(g %in% rownames(obj),
                  paste0("Gene '", g, "' not found in this object.")))
    FeaturePlot(obj, features = g, reduction = "umap")
  })
}

shinyApp(ui = ui, server = server)
