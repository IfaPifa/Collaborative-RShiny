library(shiny)
library(bslib)
library(leaflet)
library(httr)
library(jsonlite)
library(shinyjs)
library(promises)
library(future)

plan(multisession)

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
  
  # Listen for Angular sending the "ROLE_UPDATE" WebSocket message into the iframe
  tags$head(tags$script(HTML("
    window.addEventListener('message', function(event) {
      if (event.data && event.data.type === 'ROLE_UPDATE') {
        Shiny.setInputValue('role_update', event.data.permission, {priority: 'event'});
      }
    });
  "))),
  
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
  
  permission_state <- reactiveVal("EDITOR")
  
  observeEvent(input$role_update, {
    permission_state(input$role_update)
  })
  
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
  
  state <- reactiveValues(last_timestamp = 0, last_sender = NULL)
  
  observe({
    if (permission_state() == "VIEWER") {
      disable("sensor_type")
    } else {
      enable("sensor_type")
    }
  })

  # --- INITIAL MAP RENDER ---
  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = 7.5886, lat = 47.5596, zoom = 13) # Basel Coordinates
  })

  # --- SEND CLICK EVENTS (POST) ---
  observeEvent(input$map_click, {
    if (permission_state() == "VIEWER") {
      showNotification("You only have Viewer permissions in this session.", type = "warning")
      return()
    }
    
    click <- input$map_click
    id <- identity()
    
    payload <- list(
      type = "NEW_SENSOR",
      lat = click$lat,
      lng = click$lng,
      sensor_type = input$sensor_type,
      sender = id$userId,
      appName = "Geospatial"
    )
    
    post_url <- paste0(spring_api_base, "/", id$sessionId, "/state")
    
    future_promise({
      httr::POST(url = post_url, body = toJSON(payload, auto_unbox = TRUE), encode = "raw", httr::content_type_json(), httr::timeout(10))
    }) %...>% (function(res) {
      if (httr::status_code(res) == 200) {
        print("✅ Deployment signal sent.")
        
        # --- THE FIX: Eager UI Update ---
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
      } else {
        print(paste("❌ Deployment failed with status:", httr::status_code(res)))
      }
    })
  })

  # --- POLLING LOOP: 500ms ---
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
      # Fail silently to avoid console spam
    })
  })

  output$session_info_ui <- renderUI({
    id <- identity()
    tagList(
      p(strong("Mode: "), span("REST Polling", style = "color: #e67e22")),
      p("Session Key: ", code(substr(id$sessionId, 1, 8), "...")),
      p("Role: ", strong(permission_state()))
    )
  })

  output$last_update_ui <- renderUI({
    req(state$last_sender)
    span(class = "badge bg-success", paste("Last sensor placed by", state$last_sender))
  })
  
  output$connection_status <- renderText({ "🟢 System Online" })
}

shinyApp(ui, server)