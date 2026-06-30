library(plumber)
library(jsonlite)

#* @apiTitle Geospatial Sensor Deployment Backend (REST)

#* Process a new sensor placement or return current state
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) { body_text <- rawToChar(raw_body) } else if (is.character(raw_body)) { body_text <- raw_body } else { body_text <- NULL }
  if (!is.null(body_text)) { body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE) } else { body <- raw_body }

  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  action_type <- if (!is.null(body$type)) body$type else "UNKNOWN"

  # Whole-state model: the frontend sends the full pin set; the backend is a
  # stateless relay that echoes the complete state, so Redis (and save/restore)
  # always holds the entire map rather than a single delta.
  if (action_type %in% c("STATE", "NEW_SENSOR")) {
    pins <- body$pins
    if (is.null(pins)) pins <- list()
    res <- list(
      appName = "Geospatial",
      type = "STATE",
      pins = pins,
      sender = sender,
      status = "success",
      timestamp = as.numeric(Sys.time())
    )
    if (!is.null(body[["_marker"]])) res[["_marker"]] <- body[["_marker"]]
    return(res)
  }

  res <- list(
    status = "ignored",
    message = "Unknown action type",
    timestamp = as.numeric(Sys.time())
  )
  if (!is.null(body[["_marker"]])) res[["_marker"]] <- body[["_marker"]]
  return(res)
}