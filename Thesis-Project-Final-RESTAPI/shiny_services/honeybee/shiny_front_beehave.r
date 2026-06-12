# =============================================================================
# ATTRIBUTION / DISCLAIMER
# -----------------------------------------------------------------------------
# The honeybee (Beekeeper pDT) application this UI is adapted from originates
# with the LTER LIFE project (BioDT use case, repo BioDT/biodt-shiny). It is
# used here with the permission of the LTER LIFE project for the purpose of this
# Master's thesis. All credit for the original honeybee/BEEHAVE application,
# its scientific model, and its UI design belongs to the LTER LIFE / BioDT
# authors. This file is a re-engineered adaptation for the ShinySwarm
# architecture, not the original work.
# =============================================================================

library(shiny)
library(bslib)
library(leaflet)
library(leaflet.extras)
library(DT)
library(plotly)
library(httr)
library(jsonlite)
library(shinyjs)
library(promises)
library(future)
library(statesnap)

plan(multisession)

# =============================================================================
# BioDT Honeybee (Beekeeper pDT) -- ShinySwarm REST front end
# -----------------------------------------------------------------------------
# This UI is adapted from the REAL BioDT honeybee module in BioDT/biodt-shiny
# (app/view/honeybee/*). That app is a Rhino/box, deeply-modular, per-session
# ShinyProxy application with NO cross-user collaboration. Here the same UI
# surface -- input map, simulation parameters, editable habitat lookup table,
# run button, output plot -- is flattened into one plain-Shiny file and wired
# into ShinySwarm's collaboration layer:
#   * inputs (coordinates, parameters, lookup edits) are shared across users via
#     the Spring/Redis state relay (POST + 500 ms poll), exactly like the
#     map/ and monte_carlo/ benchmark apps;
#   * the BEEHAVE compute is driven through the relay -> simulated backend
#     (shiny_back_beehave.r), preserving BioDT's CSV-in / result-table-out
#     contract;
#   * statesnap captures the *computed, non-deterministic* result so a colleague
#     can restore the exact run -- which input-only Shiny bookmarking cannot do.
# The provenance comment matters for the thesis: the front is BioDT's app, the
# collaboration + reproducibility are ShinySwarm's contribution.
# =============================================================================

# Default habitat -> forage lookup table (stand-in for BioDT's lookup_table.csv).
default_lookup <- data.frame(
  Habitat = c("Oilseed rape", "Maize", "Meadow", "Forest", "Grassland", "Urban"),
  Area_m2 = c(120000, 90000, 60000, 200000, 75000, 30000),
  Nectar  = c(0.9, 0.1, 0.6, 0.3, 0.5, 0.2),
  Pollen  = c(0.8, 0.4, 0.5, 0.3, 0.4, 0.2),
  stringsAsFactors = FALSE
)

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "minty"),
  title = "BioDT Honeybee - Beekeeper pDT (ShinySwarm REST)",

  # Listen for Angular role updates (same bridge as map/mc apps).
  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),

  sidebar = sidebar(
    title = "Simulation parameters",
    width = 360,
    # --- BioDT beekeeper_param.R parameters, verbatim names/ranges ---
    sliderInput("N_INITIAL_BEES", "Adult bees at start",
                min = 0, max = 30000, value = 10000, step = 100),
    sliderInput("N_INITIAL_MITES_HEALTHY", "Mites at start",
                min = 0, max = 100, value = 100, step = 1),
    sliderInput("N_INITIAL_MITES_INFECTED", "Infected mites at start",
                min = 0, max = 100, value = 50, step = 1),
    checkboxInput("HoneyHarvesting", "Honey harvest", value = TRUE),
    checkboxInput("VarroaTreatment", "Varroa treatment (arcaricide)", value = FALSE),
    checkboxInput("DroneBroodRemoval", "Drone brood removal", value = TRUE),
    sliderInput("SimulationYearStart", "Start year",
                min = 2016L, max = 2023L, value = 2016L, step = 1, sep = ""),
    sliderInput("DaysLimit", "For how many days",
                min = 365, max = 1095, value = 365, step = 30),
    actionButton("run_simulation", "Run simulation", class = "btn-success",
                 icon = icon("play")),
    hr(),
    h6("Reproducible checkpoint (statesnap)"),
    actionButton("save_ckpt", "Save run", class = "btn-outline-primary btn-sm"),
    actionButton("restore_ckpt", "Restore run", class = "btn-outline-secondary btn-sm"),
    hr(),
    uiOutput("session_info_ui"),
    textOutput("connection_status")
  ),

  layout_columns(
    col_widths = c(7, 5),
    card(
      card_header("Input Map - click the marker tool, place the apiary"),
      leafletOutput("map_plot", height = "460px"),
      card_footer(uiOutput("map_coordinates"))
    ),
    card(
      card_header("Lookup Table (habitat -> forage) - double-click to edit"),
      DTOutput("lookup_table")
    )
  ),
  card(
    card_header("Output - colony trajectory (BEEHAVE result table)"),
    plotlyOutput("bee_plot", height = "420px"),
    card_footer(uiOutput("kpi_footer"))
  )
)

server <- function(input, output, session) {

  spring_api_base <- "http://spring-backend:8085/api/collab"
  CHECKPOINT <- file.path(tempdir(), "honeybee-checkpoint.json")

  permission_state <- reactiveVal("EDITOR")
  observeEvent(input$role_update, { permission_state(input$role_update) })

  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    if (!is.null(query$permission) && permission_state() == "EDITOR") {
      permission_state(query$permission)
    }
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })

  # Shared/collaborative reactive state.
  coordinates  <- reactiveVal(NULL)          # data.frame(lat, lon)
  lookup       <- reactiveVal(default_lookup)
  results      <- reactiveVal(NULL)          # last BEEHAVE result
  status       <- reactiveVal("IDLE")
  state        <- reactiveValues(last_timestamp = 0)

  output$connection_status <- renderText({ "\U0001F7E2 System Online" })

  observe({
    if (permission_state() == "VIEWER") {
      disable("run_simulation"); disable("N_INITIAL_BEES"); disable("lookup_table")
    } else {
      enable("run_simulation"); enable("N_INITIAL_BEES")
    }
  })

  # --- MAP (BioDT uses a land-use raster; here a plain basemap + draw tool) ---
  output$map_plot <- renderLeaflet({
    leaflet() |>
      addTiles() |>
      setView(lng = 4.90, lat = 52.37, zoom = 7) |>   # Netherlands, like BioDT
      addDrawToolbar(
        targetGroup = "apiary",
        markerOptions = drawMarkerOptions(),
        polylineOptions = FALSE, polygonOptions = FALSE,
        circleOptions = FALSE, rectangleOptions = FALSE, circleMarkerOptions = FALSE,
        editOptions = NULL
      )
  })

  # Apiary placement -> share coordinates through the relay.
  observeEvent(input$map_plot_draw_new_feature, {
    if (permission_state() == "VIEWER") {
      showNotification("Viewer role: cannot place the apiary.", type = "warning"); return()
    }
    f <- input$map_plot_draw_new_feature
    lng <- f$geometry$coordinates[[1]]
    lat <- f$geometry$coordinates[[2]]
    coordinates(data.frame(lat = lat, lon = lng))

    id <- identity()
    payload <- list(type = "COORDS", lat = lat, lng = lng,
                    sender = id$userId, appName = "Honeybee")
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    future_promise({
      httr::POST(post_url, body = toJSON(payload, auto_unbox = TRUE),
                 encode = "raw", httr::content_type_json(), httr::timeout(10))
    })
  })

  output$map_coordinates <- renderUI({
    c <- coordinates()
    if (is.null(c)) return(em("No location selected."))
    HTML(sprintf("Apiary at <b>lat</b> %.4f, <b>lon</b> %.4f", c$lat, c$lon))
  })

  # --- LOOKUP TABLE (BioDT beekeeper_lookup.R: editable DT) ---
  output$lookup_table <- renderDT(
    lookup(),
    editable = list(target = "cell", disable = list(columns = c(0, 1))),
    selection = "none", rownames = FALSE,
    options = list(paging = FALSE, searching = FALSE, info = FALSE, scrollX = TRUE)
  )
  observeEvent(input$lookup_table_cell_edit, {
    if (permission_state() == "VIEWER") return()
    info <- input$lookup_table_cell_edit
    tbl  <- lookup()
    tbl[info$row, info$col + 1] <- DT::coerceValue(info$value, tbl[info$row, info$col + 1])
    lookup(tbl)
    # Share the edited lookup table across the session.
    id <- identity()
    payload <- list(type = "LOOKUP", lookup = tbl, sender = id$userId, appName = "Honeybee")
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    future_promise({
      httr::POST(post_url, body = toJSON(payload, auto_unbox = TRUE),
                 encode = "raw", httr::content_type_json(), httr::timeout(10))
    })
  })

  # --- BUILD BioDT-shaped parameter payload (beekeeper_param.R) ---
  build_params <- reactive({
    list(
      N_INITIAL_BEES = input$N_INITIAL_BEES,
      N_INITIAL_MITES_HEALTHY = input$N_INITIAL_MITES_HEALTHY,
      N_INITIAL_MITES_INFECTED = input$N_INITIAL_MITES_INFECTED,
      HoneyHarvesting = input$HoneyHarvesting,
      VarroaTreatment = input$VarroaTreatment,
      DroneBroodRemoval = input$DroneBroodRemoval
    )
  })
  build_sim <- reactive({
    list(sim_days = input$DaysLimit,
         start_day = paste0(input$SimulationYearStart, "-01-01"))
  })

  # --- RUN SIMULATION (BioDT runsimulation -> here through the relay) ---
  observeEvent(input$run_simulation, {
    if (permission_state() == "VIEWER") return()
    c <- coordinates()
    if (is.null(c)) { showNotification("Place the apiary on the map first.", type = "error"); return() }

    id <- identity()
    status("RUNNING"); disable("run_simulation")

    payload <- list(
      command = "RUN_SIMULATION",
      lat = c$lat, lng = c$lon,
      params = build_params(),
      lookup = lookup(),
      simulation = build_sim(),
      sender = id$userId,
      appName = "Honeybee"
    )
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")

    future_promise({
      httr::POST(post_url, body = toJSON(payload, auto_unbox = TRUE),
                 encode = "raw", httr::content_type_json(), httr::timeout(120))
    }) %...>% (function(res) {
      if (httr::status_code(res) == 200) {
        data <- fromJSON(httr::content(res, "text", encoding = "UTF-8"))
        if (!is.null(data$type) && data$type == "RESULT") {
          results(data); state$last_timestamp <- data$timestamp; status("COMPLETE")
        }
      } else { status("ERROR") }
      enable("run_simulation")
    }) %...!% (function(e) { status("ERROR"); enable("run_simulation"); print(e$message) })
  })

  # --- POLL relay for collaborators' updates (coords/lookup/results) ---
  poll <- reactiveTimer(500)
  observe({
    poll()
    id <- identity()
    get_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    tryCatch({
      res <- httr::GET(get_url, httr::timeout(2))
      if (httr::status_code(res) == 200) {
        raw_text <- httr::content(res, "text", encoding = "UTF-8")
        if (nchar(raw_text) > 2) {
          data <- fromJSON(raw_text)
          if (!is.null(data$timestamp) && data$timestamp > state$last_timestamp) {
            state$last_timestamp <- data$timestamp
            if (!is.null(data$type)) {
              if (data$type == "COORDS") {
                coordinates(data.frame(lat = data$lat, lon = data$lng))
                leafletProxy("map_plot") |>
                  clearGroup("apiary") |>
                  addMarkers(lng = data$lng, lat = data$lat, group = "apiary")
              } else if (data$type == "LOOKUP" && !is.null(data$lookup)) {
                lookup(as.data.frame(data$lookup))
              } else if (data$type == "RESULT") {
                results(data); status("COMPLETE")
              }
            }
          }
        }
      }
    }, error = function(e) {})
  })

  # --- OUTPUT PLOT (BioDT plots honey + bees over date; mirrored here) ---
  output$bee_plot <- renderPlotly({
    r <- results(); req(r)
    plot_ly(x = ~r$date) |>
      add_bars(y = ~r$weather, name = "Collection hours", yaxis = "y2",
               marker = list(color = "rgba(0,158,115,0.3)")) |>
      add_lines(y = ~r$bees, name = "Bees count",
                line = list(color = "#0072B2", width = 3)) |>
      add_lines(y = ~r$honey_kg, name = "Honey (kg)", yaxis = "y3",
                line = list(color = "#E69F00", width = 3)) |>
      layout(
        xaxis = list(title = "Date"),
        yaxis = list(title = "Bees count"),
        yaxis2 = list(overlaying = "y", side = "right", showgrid = FALSE,
                      title = "", range = c(0, 24)),
        yaxis3 = list(overlaying = "y", side = "right", showgrid = FALSE,
                      title = "Honey (kg)", position = 0.97),
        hovermode = "x unified", legend = list(orientation = "h")
      )
  })

  output$kpi_footer <- renderUI({
    r <- results(); req(r)
    badge <- if (isTRUE(r$collapsed)) "bg-danger" else "bg-success"
    label <- if (isTRUE(r$collapsed)) "COLONY COLLAPSE" else "Colony viable"
    HTML(sprintf(
      "<span class='badge %s'>%s</span> &nbsp; Peak bees: <b>%s</b> &nbsp; Final bees: <b>%s</b> &nbsp; Honey: <b>%.2f kg</b>",
      badge, label, format(r$peak_bees, big.mark = ","),
      format(r$final_bees, big.mark = ","), r$total_honey))
  })

  # --- STATESNAP: reproducible capture of the COMPUTED result ---
  # Input-only bookmarking cannot reproduce a colleague's exact run because the
  # BEEHAVE model is non-deterministic. statesnap captures the computed result
  # table itself, so restore reproduces the exact trajectory.
  observeEvent(input$save_ckpt, {
    json <- capture_state(
      input,
      coordinates = coordinates,
      lookup = state_rds(lookup()),
      results = state_rds(results())
    )
    writeLines(json, CHECKPOINT)
    showNotification("Run checkpoint saved (inputs + computed result).", type = "message")
  })
  observeEvent(input$restore_ckpt, {
    if (!file.exists(CHECKPOINT)) { showNotification("No checkpoint yet.", type = "warning"); return() }
    json <- paste(readLines(CHECKPOINT), collapse = "\n")
    restored <- restore_state(session, json,
                              coordinates = coordinates,
                              lookup = lookup,
                              results = results,
                              allow_rds = TRUE)  # trusted: checkpoint from this session
    showNotification("Run restored - exact trajectory reproduced.", type = "message")
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color:#e67e22")),
      p("Session: ", code(substr(id$sessionId, 1, 8))),
      p("Role: ", strong(permission_state())),
      p("Status: ", strong(status()))
    )
  })
}

shinyApp(ui, server)
