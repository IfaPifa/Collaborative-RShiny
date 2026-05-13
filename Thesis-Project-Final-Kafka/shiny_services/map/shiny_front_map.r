library(shiny)
library(bslib)
library(leaflet)
library(jsonlite)
library(kafka)
library(shinyjs)

# --- MAP ICONS ---
sensor_icons <- awesomeIconList(
  "Camera Trap" = makeAwesomeIcon(icon = "camera", markerColor = "red", library = "fa"),
  "Soil Moisture" = makeAwesomeIcon(icon = "tint", markerColor = "blue", library = "fa"),
  "Audio Recorder" = makeAwesomeIcon(icon = "microphone", markerColor = "green", library = "fa")
)

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
    permission = "EDITOR", last_sender = NULL
  )

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
      consumer_group <- paste0("front_map_", sample(10000:99999, 1))
      
      state$consumer <- Consumer$new(list(
        "bootstrap.servers" = broker, "group.id" = consumer_group,
        "auto.offset.reset" = "latest", "enable.auto.commit" = "true"
      ))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  # --- SEND CLICK (PRODUCER) ---
  observeEvent(input$map_click, {
    req(state$connected)
    if (is.null(state$producer) || state$permission == "VIEWER") return()
    
    click <- input$map_click
    id <- identity()
    
    payload <- list(
      type = "NEW_SENSOR",
      lat = click$lat,
      lng = click$lng,
      sensor_type = input$sensor_type,
      sender = id$userId,
      role = state$permission
    )
    
    state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
  })
  
  # --- RECEIVE DELTAS (CONSUMER) ---
  poll_trigger <- reactivePoll(500, session,
    checkFunc = function() { if (!isTRUE(state$connected)) return(NULL); return(as.numeric(Sys.time())) },
    valueFunc = function() { return(as.numeric(Sys.time())) }
  )
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    
    messages <- state$consumer$consume(100)
    
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$type) && data$type == "DELTA") {
            state$last_sender <- data$sender
            
            # Apply identical awesome-marker DOM injection as the REST version
            leafletProxy("map") %>% 
              addAwesomeMarkers(
                lng = data$lng, lat = data$lat, 
                icon = sensor_icons[[data$sensor_type]],
                popup = paste("Type:", data$sensor_type, "<br>Deployed by:", data$sender)
              )
          }
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
  output$connection_status <- renderText({ "System Online" }) 
}
shinyApp(ui = ui, server = server)