library(plumber)
library(jsonlite)

#* @apiTitle Visual Analytics Backend (REST)

#* Process filter states and return current configuration
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) { body_text <- rawToChar(raw_body) } else if (is.character(raw_body)) { body_text <- raw_body } else { body_text <- NULL }
  if (!is.null(body_text)) { body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE) } else { body <- raw_body }

  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  min_hp <- if (!is.null(body$min_hp)) as.numeric(body$min_hp) else 50
  
  # --- THE FIX: Parse the incoming cylinder array safely ---
  cylinders <- c(4, 6, 8) # Default
  if (!is.null(body$cyl)) {
    # It might come in as a single string, numeric, or a list/vector
    cylinders <- as.numeric(unlist(body$cyl))
  }

  return(list(
    min_hp = min_hp,
    cylinders = cylinders, # Return the parsed array back to the frontend
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time()) * 1000 # Use ms for Java compatibility
  ))
}
