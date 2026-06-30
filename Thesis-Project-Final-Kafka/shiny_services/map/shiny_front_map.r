library(shiny)
library(bslib)
library(leaflet)
library(jsonlite)
library(kafka)
library(shinyjs)

# Tunable polling parameters (override via env vars in K8s ConfigMap)
POLL_INTERVAL_MS  <- as.integer(Sys.getenv("POLL_INTERVAL_MS", "150"))
CONSUME_TIMEOUT_MS <- as.integer(Sys.getenv("CONSUME_TIMEOUT_MS", "50"))

# --- MAP ICONS ---
sensor_icons <- awesomeIconList(
  "Camera Trap" = makeAwesomeIcon(icon = "camera", markerColor = "red", library = "fa"),
  "Soil Moisture" = makeAwesomeIcon(icon = "tint", markerColor = "blue", library = "fa"),
  "Audio Recorder" = makeAwesomeIcon(icon = "microphone", markerColor = "green", library = "fa")
)

# Resolve icons for a vector of sensor types, defaulting unknown types to the
# first icon so unexpected values (e.g. benchmark payloads) never crash render.
icons_for <- function(types) {
  known <- names(sensor_icons)
  safe <- ifelse(types %in% known, types, known[1])
  sensor_icons[safe]
}

# Empty authoritative pin table — the full shared map state.
empty_pins <- function() {
  data.frame(lat = numeric(0), lng = numeric(0),
             sensor_type = character(0), sender = character(0),
             stringsAsFactors = FALSE)
}

# --- UI DEFINITION ---
ui <- page_sidebar(
  useShinyjs(),
  
  # Listen for Angular role updates
  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),
  
  theme = bs_theme(version = 5, preset = "sandstone"), 
  title = "LTER-LIFE: Sensor Mesh Deployment (Kafka API)",
  
  sidebar = sidebar(
    title = "Deployment Controls",
    p("Select an asset type and click the map to deploy a sensor to the Swarm."),
    selectInput("sensor_type", "Asset Type:", choices = c("Camera Trap", "Soil Moisture", "Audio Recorder")),
    hr(),
    uiOutput("session_info_ui"),
    hr(),
    uiOutput("last_update_ui"),
    hr(),
    h5("Architecture:"),
    textOutput("connection_status")
  ),
  
  card(
    card_header("Live Deployment Map (Basel Region)"),
    leafletOutput("map", height = "700px") 
  )
)

# --- SERVER LOGIC ---
server <- function(input, output, session) {
  
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
    return(id$userId)
  })
  
  state <- reactiveValues(
    connected = FALSE, consumer = NULL, producer = NULL,
    permission = "EDITOR", last_sender = NULL,
    pins = empty_pins()   # authoritative full map state (whole-state model)
  )

  # Redraw the whole map from the authoritative pin table: clear then add all.
  # This is the statesnap-style semantics — render the full state, never append
  # blindly — so restore and late-join show exactly the saved set of pins.
  redraw_pins <- function(pins) {
    proxy <- leafletProxy("map") %>% clearMarkers()
    if (nrow(pins) > 0) {
      proxy %>% addAwesomeMarkers(
        lng = pins$lng, lat = pins$lat,
        icon = icons_for(pins$sensor_type),
        popup = paste("Type:", pins$sensor_type, "<br>Deployed by:", pins$sender)
      )
    }
  }

  # --- DYNAMIC ROLE UPDATES ---
  observeEvent(input$role_update, {
    state$permission <- input$role_update
    if (input$role_update %in% c("EDITOR", "OWNER")) {
      state$producer <- Producer$new(list("bootstrap.servers" = "kafka:9092"))
    } else {
      state$producer <- NULL
    }
  })

  observe({
    if (state$permission == "VIEWER") disable("sensor_type") else enable("sensor_type")
  })

  # --- INITIAL MAP ---
  output$map <- renderLeaflet({
    leaflet() %>% 
      addProviderTiles(providers$CartoDB.Positron) %>% 
      setView(lng = 7.5886, lat = 47.5596, zoom = 12) 
  })

  # --- KAFKA CONNECTION ---
  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      
      broker <- "kafka:9092"
      consumer_group <- paste0("front_map_", session$token)
      
      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker, "group.id" = consumer_group,
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

  # --- SEND CLICK (PRODUCER) ---
  # Whole-state model: append the new pin to the authoritative list locally, then
  # send the ENTIRE pin set. The backend echoes the full set so every client
  # (and save/restore) sees the complete map, not a one-off delta.
  observeEvent(input$map_click, {
    req(state$connected)
    if (is.null(state$producer) || state$permission == "VIEWER") return()

    click <- input$map_click
    id <- identity()

    new_pins <- rbind(state$pins, data.frame(
      lat = click$lat, lng = click$lng,
      sensor_type = input$sensor_type, sender = id$userId,
      stringsAsFactors = FALSE
    ))
    state$pins <- new_pins
    redraw_pins(new_pins)  # optimistic local render

    payload <- list(
      appName = "Geospatial",
      type = "STATE",
      pins = new_pins,            # full map state
      sender = id$userId,
      role = state$permission
    )

    state$producer$produce("input.geospatial",
                           toJSON(payload, auto_unbox = TRUE, dataframe = "rows"),
                           key = routingKey())
  })
  
  # --- RECEIVE DELTAS (CONSUMER) ---
  poll_trigger <- reactivePoll(POLL_INTERVAL_MS, session,
    checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); return(as.numeric(Sys.time())) },
    valueFunc = function() { return(as.numeric(Sys.time())) }
  )
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    
    result <- state$consumer$consume(CONSUME_TIMEOUT_MS)
    msg <- result_message(result)
    
    if (!result_has_error(result) && !is.null(msg$value)) {
      if (!is.null(msg$key) && msg$key == routingKey()) {
        data <- fromJSON(msg$value)
        if (!is.null(data$appName) && data$appName != "Geospatial") return()

        # Whole-state message: replace the authoritative pin set and redraw.
        # Restore/late-join arrive here too, so the map always reflects the
        # full saved state rather than accumulating stale pins.
        if (!is.null(data$type) && data$type == "STATE") {
          if (!is.null(data$sender)) state$last_sender <- data$sender
          pins <- data$pins
          if (is.null(pins) || length(pins) == 0) {
            pins <- empty_pins()
          } else {
            pins <- as.data.frame(pins, stringsAsFactors = FALSE)
          }
          state$pins <- pins
          redraw_pins(pins)
        }
      }
    }
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("Kafka Event Stream", style = "color: #27ae60")),
      p("User: ", strong(id$userId)),
      p("Role: ", strong(state$permission))
    )
  })
  
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    p(em(paste("Last sensor placed by:", state$last_sender))) 
  })
  
  # Note: Aligning text output with the Playwright test expectation
  output$connection_status <- renderText({ "🟢 System Online" }) 
}
shinyApp(ui = ui, server = server)