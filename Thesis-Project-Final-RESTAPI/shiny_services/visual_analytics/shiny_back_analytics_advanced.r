library(plumber)
library(jsonlite)

#* @apiTitle Eco Visual Analytics Backend (REST)

#* Process the state update for the Analytics App
#* @post /calculate
function(req, res) {
  
  # 1. Safely extract the raw JSON body sent by Java
  body <- req$body
  
  sender <- if(!is.null(body$sender)) body$sender else "unknown"
  print(paste("REST API Updating Analytics State for:", sender))
  
  # 2. Extract explicitly to prevent type-mapping crashes
  min_temp <- if(!is.null(body$min_temp)) as.numeric(body$min_temp) else 50
  
  # Safely handle the array!
  months_filter <- if(!is.null(body$months)) as.numeric(unlist(body$months)) else c(5, 6, 7, 8, 9)
  if (length(months_filter) == 0) months_filter <- c(5, 6, 7, 8, 9)
  
  # 3. Force unboxed JSON response so the Shiny frontend parses it easily
  res$body <- toJSON(list(
    type = "STATE_UPDATE",
    min_temp = min_temp,
    months = months_filter,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ), auto_unbox = TRUE)
  
  res$setHeader("Content-Type", "application/json")
  return(res)
}