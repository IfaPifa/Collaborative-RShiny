library(shiny)
library(bslib)
library(leaflet)
library(shinyjs)

sensor_icons <- awesomeIconList(
  "Camera Trap" = makeAwesomeIcon(icon = "camera", markerColor = "red", library = "fa"),
  "Soil Moisture" = makeAwesomeIcon(icon = "tint", markerColor = "blue", library = "fa"),
  "Audio Recorder" = makeAwesomeIcon(icon = "microphone", markerColor = "green", library = "fa")
)

ui <- page_sidebar(
  useShinyjs(),
  theme = bs_theme(version = 5, preset = "sandstone"),
  title = "LTER-LIFE: Sensor Mesh Deployment (Monolithic)",

  sidebar = sidebar(
    title = "Deployment Controls",
    p("Select an asset type and click the map to deploy a sensor."),
    selectInput("sensor_type", "Asset Type:",
                choices = c("Camera Trap", "Soil Moisture", "Audio Recorder")),
    hr(),
    h5("Sensors Deployed:"),
    textOutput("sensor_count"),
    hr(),
    h5("Architecture:"),
    p("Monolithic (Single Process)")
  ),

  card(
    card_header("Live Deployment Map (Basel Region)"),
    leafletOutput("map", height = "700px")
  )
)

server <- function(input, output, session) {

  sensors <- reactiveVal(data.frame(
    lat = numeric(), lng = numeric(), type = character(), stringsAsFactors = FALSE
  ))

  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = 7.5886, lat = 47.5596, zoom = 13)
  })

  observeEvent(input$map_click, {
    click <- input$map_click

    new_sensor <- data.frame(
      lat = click$lat, lng = click$lng, type = input$sensor_type,
      stringsAsFactors = FALSE
    )
    sensors(rbind(sensors(), new_sensor))

    leafletProxy("map") %>%
      addAwesomeMarkers(
        lng = click$lng, lat = click$lat,
        icon = sensor_icons[[input$sensor_type]],
        popup = paste("Type:", input$sensor_type)
      )
  })

  output$sensor_count <- renderText({ nrow(sensors()) })
}

shinyApp(ui = ui, server = server)
