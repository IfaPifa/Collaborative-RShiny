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

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "sandstone"), 
  title = "LTER-LIFE: Sensor Mesh Deployment",
  
  sidebar = sidebar(
    title = "Deployment Controls",
    p("Select an asset type and click the map to deploy a sensor to the Swarm."),
    selectInput("sensor_type", "Asset Type:", choices = c("Camera Trap", "Soil Moisture", "Audio Recorder")),
    hr(),
    uiOutput("session_info_ui"),
    hr(),
    uiOutput("last_update_ui")
  ),
  
  card(
    card_header("Live Deployment Map (Basel Region)"),
    leafletOutput("map", height = "700px") 
  )
)

server <- function(input, output, session) {
  
  # FIX: Restore dynamic identity parsing from the Angular URL
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else NULL
    )
  })
  
  routingKey <- reactive({
    id <- identity()
    if (!is.null(id$sessionId)) return(id$sessionId)
    return(id$userId)
  })
  
  state <- reactiveValues(connected = FALSE, consumer = NULL, producer = NULL, permission = "EDITOR", last_sender = NULL)

  output$map <- renderLeaflet({
    leaflet() %>% 
      addProviderTiles(providers$CartoDB.Positron) %>% 
      setView(lng = 7.5886, lat = 47.5596, zoom = 12) 
  })

  # FIX: Restore dynamic permission parsing and Kafka connection
  observe({
    if (state$connected) return()
    tryCatch({
      query <- parseQueryString(session$clientData$url_search)
      state$permission <- if (!is.null(query$permission)) query$permission else "EDITOR"
      
      broker <- "kafka:9092"
      state$consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = paste0("front_map_", sample(10000:99999, 1)), "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
      state$consumer$subscribe("output")
      
      if (state$permission %in% c("EDITOR", "OWNER")) {
        state$producer <- Producer$new(list("bootstrap.servers" = broker))
      }
      state$connected <- TRUE
    }, error = function(e) { print(e$message) })
  })

  observeEvent(input$map_click, {
    req(state$connected)
    click <- input$map_click 
    
    payload <- list(
      type = "NEW_SENSOR",
      lat = click$lat, 
      lng = click$lng, 
      sensor_type = input$sensor_type,
      sender = identity()$userId, 
      role = state$permission
    )
    # Only produce if user has write access
    if (!is.null(state$producer)) {
       state$producer$produce("input", toJSON(payload, auto_unbox = TRUE), key = routingKey())
    }
  })
  
  poll_trigger <- reactivePoll(200, session, checkFunc = function() as.numeric(Sys.time()), valueFunc = function() as.numeric(Sys.time()))
  
  observe({
    poll_trigger()
    req(state$connected, !is.null(state$consumer))
    messages <- state$consumer$consume(100)
    if (length(messages) > 0) {
      for (m in messages) {
        if (!is.null(m$key) && m$key == routingKey()) {
          data <- fromJSON(m$value)
          
          if (!is.null(data$type) && data$type == "RESTORE_STATE") {
             if (!is.null(data$sensors) && nrow(data$sensors) > 0) {
                for (i in 1:nrow(data$sensors)) {
                   sensor <- data$sensors[i, ]
                   leafletProxy("map") %>% 
                     addAwesomeMarkers(
                       lng = sensor$lng, lat = sensor$lat, 
                       icon = sensor_icons[[sensor$sensor_type]],
                       popup = paste("Type:", sensor$sensor_type, "<br>Deployed by:", sensor$sender)
                     )
                }
             }
          }
          else if (!is.null(data$type) && data$type == "DELTA") {
            state$last_sender <- data$sender
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

  output$session_info_ui <- renderUI({ tagList(p("User: ", strong(identity()$userId)), p("Role: ", strong(state$permission))) })
  output$last_update_ui <- renderUI({ req(state$last_sender); p(em(paste("Last sensor placed by:", state$last_sender))) })
}
shinyApp(ui = ui, server = server)