library(plumber)
library(jsonlite)

#* @apiTitle Eco Deployment Calculator Backend (REST)

#* Calculate the sum of deployed sensors
#* @post /calculate
#* @serializer unboxedJSON
function(req) {
  # Handle both raw vector and string body formats
  raw_body <- req$body
  if (is.raw(raw_body)) {
    body_text <- rawToChar(raw_body)
  } else if (is.character(raw_body)) {
    body_text <- raw_body
  } else {
    # Plumber may have already parsed it into a list
    body_text <- NULL
  }

  if (!is.null(body_text)) {
    body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE)
  } else {
    body <- raw_body
  }

  n1 <- as.numeric(body$num1)
  n2 <- as.numeric(body$num2)
  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  result <- n1 + n2

  print(paste("REST API Calculated:", n1, "+", n2, "=", result, "for", sender))

  return(list(
    result = result,
    num1 = n1,
    num2 = n2,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}