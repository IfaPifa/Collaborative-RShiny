library(plumber)
library(jsonlite)

#* @apiTitle Geospatial Sensor Deployment Backend (REST)

#* Process a new sensor placement or return current state
#* @post /state
#* @serializer unboxedJSON
function(req) {
  body <- jsonlite::fromJSON(req$body, simplifyVector = TRUE)

  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  action_type <- if (!is.null(body$type)) body$type else "UNKNOWN"

  if (action_type == "NEW_SENSOR") {
    # Validate and relay the sensor placement
    return(list(
      type = "DELTA",
      lat = as.numeric(body$lat),
      lng = as.numeric(body$lng),
      sensor_type = body$sensor_type,
      sender = sender,
      status = "success",
      timestamp = as.numeric(Sys.time())
    ))
  }

  return(list(
    status = "ignored",
    message = "Unknown action type",
    timestamp = as.numeric(Sys.time())
  ))
}
