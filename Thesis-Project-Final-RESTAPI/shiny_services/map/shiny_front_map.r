library(shiny)
library(bslib)
library(leaflet)
library(httr)
library(jsonlite)
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
  title = "LTER-LIFE: Sensor Mesh Deployment (REST API)",
  
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

server <- function(input, output, session) {
  
  spring_api_base <- "http://spring-backend:8085/api/collab"
  
  identity <- reactive({
    query <- parseQueryString(session$clientData$url_search)
    list(
      userId = if (!is.null(query$userId)) query$userId else "anonymous",
      sessionId = if (!is.null(query$sessionId)) query$sessionId else "solo",
      permission = if (!is.null(query$permission)) query$permission else "EDITOR"
    )
  })
  
  state <- reactiveValues(last_timestamp = 0, last_sender = NULL, known_sensors = list())

  observe({
    if (identity()$permission == "VIEWER") {
      disable("sensor_type")
    } else {
      enable("sensor_type")
    }
  })

  output$connection_status <- renderText({ "HTTP GET/POST" })

  output$map <- renderLeaflet({
    leaflet() %>% 
      addProviderTiles(providers$CartoDB.Positron) %>% 
      setView(lng = 7.5886, lat = 47.5596, zoom = 12) 
  })

  # --- POST new sensor on map click ---
  observeEvent(input$map_click, {
    id <- identity()
    if (id$permission == "VIEWER") return()
    
    click <- input$map_click
    
    payload <- list(
      type = "NEW_SENSOR",
      lat = click$lat,
      lng = click$lng,
      sensor_type = input$sensor_type,
      sender = id$userId,
      appName = "Geospatial"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    tryCatch({
      httr::POST(
        url = post_url,
        body = toJSON(payload, auto_unbox = TRUE),
        encode = "raw",
        httr::content_type_json(),
        httr::timeout(5)
      )
    }, error = function(e) {
      print(paste("POST Error:", e$message))
    })
  })
  
  # --- Poll Spring Boot for state every 500ms ---
  poll_trigger <- reactiveTimer(500)
  
  observe({
    poll_trigger()
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
            state$last_sender <- data$sender
            
            if (!is.null(data$type) && data$type == "DELTA") {
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
    }, error = function(e) {
      # Fail silently
    })
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("User: ", strong(id$userId)),
      p("Role: ", strong(id$permission))
    )
  })
  
  output$last_update_ui <- renderUI({ 
    req(state$last_sender)
    p(em(paste("Last sensor placed by:", state$last_sender))) 
  })
}
shinyApp(ui = ui, server = server)

