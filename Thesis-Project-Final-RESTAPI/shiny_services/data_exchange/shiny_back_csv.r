library(plumber)
library(jsonlite)

#* @apiTitle Data Exchange Backend (REST)

#* Clean string columns in a dataset
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) { body_text <- rawToChar(raw_body) } else if (is.character(raw_body)) { body_text <- raw_body } else { body_text <- NULL }
  if (!is.null(body_text)) { body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE) } else { body <- raw_body }

  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  df <- as.data.frame(body$dataset)

  # String manipulation: capitalize, trim, remove special chars
  if (nrow(df) > 0) {
    for (col in names(df)) {
      if (is.character(df[[col]])) {
        df[[col]] <- toupper(trimws(df[[col]]))
        df[[col]] <- gsub("[^A-Z0-9 ]", "", df[[col]])
      }
    }
  }

  return(list(
    dataset = df,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}
