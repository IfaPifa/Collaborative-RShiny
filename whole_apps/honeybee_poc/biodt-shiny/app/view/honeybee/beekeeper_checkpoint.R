# =============================================================================
# beekeeper_checkpoint -- statesnap save/restore UI for the honeybee pDT (PoC)
# -----------------------------------------------------------------------------
# A small box module added on top of the unchanged BioDT honeybee modules. It
# demonstrates reproducible checkpoints at the MODEL level:
#   * Save: capture the composed model (coordinates + parameters + lookup) AND
#     the last computed result as one statesnap JSON file. Because we capture
#     the model, module namespaces are irrelevant -- no flattening.
#   * Restore: read the checkpoint and push the model fragments back into the
#     module reactives via the setters the parent supplies.
#
# This is the same statesnap JSON format the backend speaks, so a checkpoint is
# both a "reopen my run" artifact and a portable, shareable record of a
# non-deterministic simulation.
# =============================================================================

box::use(
  shiny[
    NS, moduleServer, tagList, tags, actionButton, downloadButton,
    downloadHandler, fileInput, observeEvent, reactiveVal, req, showNotification
  ],
  bslib[card, card_header, card_body],
  statesnap[capture_state, restore_state],
)

box::use(
  app / logic / honeybee / statesnap_adapter[build_model, model_from_json],
)

#' @export
beekeeper_checkpoint_ui <- function(id, i18n) {
  ns <- NS(id)
  card(
    class = "mt-2 mx-md-3 card-shadow overflow-hidden",
    card_header(tags$h2(class = "card_title", i18n$t("Reproducible run (statesnap)"))),
    card_body(
      tags$p(i18n$t(
        "Save the full model and the computed result as one checkpoint, or restore a saved run. Because the simulation is non-deterministic, restoring reproduces the exact run that re-running cannot."
      )),
      tags$div(
        class = "d-flex flex-row gap-2 align-items-center flex-wrap",
        downloadButton(ns("save"), label = i18n$t("Save run"), class = "btn-primary"),
        fileInput(ns("restore_file"), label = NULL, accept = ".json",
                  buttonLabel = i18n$t("Restore run"), placeholder = "checkpoint.json")
      )
    )
  )
}

#' @export
#' @param coordinates,parameters,lookup  reactive GETTERS (model fragments)
#' @param set_coordinates,set_lookup      setter functions (reactiveVal) for restore
#' @param result_reply                     reactive returning the last backend reply (or NULL)
beekeeper_checkpoint_server <- function(
  id, coordinates, parameters, lookup,
  set_coordinates = NULL, set_lookup = NULL, result_reply = NULL, i18n
) {
  moduleServer(id, function(input, output, session) {

    # --- SAVE: model + computed result -> statesnap JSON ---------------------
    output$save <- downloadHandler(
      filename = function() {
        sprintf("honeybee-run-%s.json", format(Sys.time(), "%Y%m%d-%H%M%S"))
      },
      content = function(file) {
        model <- build_model(coordinates(), parameters(), lookup())
        reply <- if (!is.null(result_reply)) result_reply() else NULL
        # Capture model + result together. input=list(): model-level capture,
        # so module namespaces never enter statesnap.
        json <- capture_state(
          input  = list(),
          model  = model,
          result = if (!is.null(reply)) reply$result else NULL
        )
        writeLines(as.character(json), file)
        showNotification(i18n$t("Run saved as statesnap checkpoint."), type = "message")
      }
    )

    # --- RESTORE: statesnap JSON -> model fragments back into reactives ------
    observeEvent(input$restore_file, {
      req(input$restore_file)
      json <- paste(readLines(input$restore_file$datapath), collapse = "\n")
      model <- model_from_json(json)
      # Push fragments back through the setters the parent owns. Each setter
      # writes a namespace-free reactiveVal that the child modules observe.
      if (!is.null(set_coordinates) && !is.null(model$coordinates)) {
        set_coordinates(model$coordinates)
      }
      if (!is.null(set_lookup) && !is.null(model$lookup)) {
        set_lookup(model$lookup)
      }
      showNotification(i18n$t("Run restored from checkpoint."), type = "message")
    })
  })
}
