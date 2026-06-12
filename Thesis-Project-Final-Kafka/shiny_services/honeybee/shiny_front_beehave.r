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
library(jsonlite)
library(kafka)
library(shinyjs)
library(statesnap)

# =============================================================================
# BioDT Honeybee (Beekeeper pDT) -- ShinySwarm Kafka front end
# -----------------------------------------------------------------------------
# Same BioDT honeybee UI as the REST variant (adapted from BioDT/biodt-shiny
# app/view/honeybee/*), but collaboration uses Kafka events instead of REST
# polling: inputs and run requests are produced to the `input` topic; the
# backend produces results/deltas to `output`, consumed here keyed by session.
# The event-driven path is the better fit for BEEHAVE's long-running jobs.
# =============================================================================

POLL_INTERVAL_MS  <- as.integer(Sys.getenv("POLL_INTERVAL_MS", "150"))
CONSUME_TIMEOUT_MS <- as.integer(Sys.getenv("CONSUME_TIMEOUT_MS", "50"))

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
  title = "BioDT Honeybee - Beekeeper pDT (ShinySwarm Kafka)",

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

  CHECKPOINT <- file.path(tempdir(), "honeybee-checkpoint.json")

  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo"
    )
  })
  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId) && id$sessionId != "solo") return(id$sessionId)
    id$userId
  })

  coordinates <- reactiveVal(NULL)
  lookup      <- reactiveVal(default_lookup)
  results     <- reactiveVal(NULL)
  status      <- reactiveVal("IDLE")
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL,
                          permission = "EDITOR")

  output$connection_status <- renderText({ "\U0001F7E2 System Online" })

  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
    } else {
      state$producer <- NULL
    }
  })

  observe({
    if (state$permission == "VIEWER") {
      disable("run_simulation"); disable("N_INITIAL_BEES")
    } else {
      enable("run_simulation"); enable("N_INITIAL_BEES")
    }
  })

  # --- KAFKA CONNECTION ---
  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      broker <- "kafka:9092"
      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker,
        "group.id" = paste0("front_honeybee_", session$token),
        "auto.offset.reset" = "latest", "enable.auto.commit" = "true",
        "max.poll.interval.ms" = "600000"
      ))
      state$consumer$subscribe("output")
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) { print(e$message); invalidateLater(5000, session) })
  })

  produce_event <- function(payload) {
    req(state$connected)
    if (is.null(state$producer) || state$permission == "VIEWER") return()
    payload$appName <- "Honeybee"
    payload$role <- state$permission
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  }

  # --- MAP ---
  output$map_plot <- renderLeaflet({
    leaflet() |>
      addProviderTiles(providers$CartoDB.Positron) |>
      setView(lng = 4.90, lat = 52.37, zoom = 7) |>
      addDrawToolbar(
        targetGroup = "apiary",
        markerOptions = drawMarkerOptions(),
        polylineOptions = FALSE, polygonOptions = FALSE,
        circleOptions = FALSE, rectangleOptions = FALSE, circleMarkerOptions = FALSE
      )
  })

  observeEvent(input$map_plot_draw_new_feature, {
    if (state$permission == "VIEWER") return()
    f <- input$map_plot_draw_new_feature
    lng <- f$geometry$coordinates[[1]]; lat <- f$geometry$coordinates[[2]]
    coordinates(data.frame(lat = lat, lon = lng))
    id <- identity()
    produce_event(list(type = "COORDS", lat = lat, lng = lng, sender = id$userId))
  })

  output$map_coordinates <- renderUI({
    c <- coordinates()
    if (is.null(c)) return(em("No location selected."))
    HTML(sprintf("Apiary at <b>lat</b> %.4f, <b>lon</b> %.4f", c$lat, c$lon))
  })

  # --- LOOKUP TABLE ---
  output$lookup_table <- renderDT(
    lookup(),
    editable = list(target = "cell", disable = list(columns = c(0, 1))),
    selection = "none", rownames = FALSE,
    options = list(paging = FALSE, searching = FALSE, info = FALSE, scrollX = TRUE)
  )
  observeEvent(input$lookup_table_cell_edit, {
    if (state$permission == "VIEWER") return()
    info <- input$lookup_table_cell_edit
    tbl <- lookup()
    tbl[info$row, info$col + 1] <- DT::coerceValue(info$value, tbl[info$row, info$col + 1])
    lookup(tbl)
    id <- identity()
    produce_event(list(type = "LOOKUP", lookup = tbl, sender = id$userId))
  })

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

  # --- RUN SIMULATION (produce event) ---
  observeEvent(input$run_simulation, {
    if (state$permission == "VIEWER") return()
    c <- coordinates()
    if (is.null(c)) { showNotification("Place the apiary on the map first.", type = "error"); return() }
    id <- identity()
    status("RUNNING")
    produce_event(list(
      command = "RUN_SIMULATION", lat = c$lat, lng = c$lon,
      params = build_params(), lookup = lookup(),
      simulation = build_sim(), sender = id$userId
    ))
  })

  # --- CONSUME results / collaborators' deltas ---
  poll_trigger <- reactivePoll(POLL_INTERVAL_MS, session,
    checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); as.numeric(Sys.time()) },
    valueFunc = function() { as.numeric(Sys.time()) }
  )
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    result <- state$consumer$consume(CONSUME_TIMEOUT_MS)
    msg <- result_message(result)
    if (!result_has_error(result) && !is.null(msg$value)) {
      if (!is.null(msg$key) && msg$key == routingKey()) {
        data <- fromJSON(msg$value)
        if (is.null(data$appName) || data$appName != "Honeybee") return()
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
  })

  # --- OUTPUT PLOT ---
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

  # --- STATESNAP ---
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
    restore_state(session, json,
                  coordinates = coordinates, lookup = lookup, results = results,
                  allow_rds = TRUE)  # trusted: checkpoint from this session
    showNotification("Run restored - exact trajectory reproduced.", type = "message")
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("Kafka Event Stream", style = "color:#27ae60")),
      p("User: ", strong(id$userId)),
      p("Role: ", strong(state$permission)),
      p("Status: ", strong(status()))
    )
  })
}

shinyApp(ui, server)
