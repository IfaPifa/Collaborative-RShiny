library(plumber)
library(jsonlite)

#* @apiTitle Advanced Visual Analytics Backend (REST)

#* Relay state parameters (state-only sync, no data transformation)
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) { body_text <- rawToChar(raw_body) } else if (is.character(raw_body)) { body_text <- raw_body } else { body_text <- NULL }
  if (!is.null(body_text)) { body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE) } else { body <- raw_body }

  min_temp <- if (!is.null(body$min_temp)) as.numeric(body$min_temp) else 50
  months_filter <- if (!is.null(body$months)) as.numeric(body$months) else c(5, 6, 7, 8, 9)
  sender <- if (!is.null(body$sender)) body$sender else "unknown"

  return(list(
    type = "STATE_UPDATE",
    min_temp = min_temp,
    months = months_filter,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}
