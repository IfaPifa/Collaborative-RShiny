library(plumber)
library(jsonlite)

#* @apiTitle Data Exchange Backend (REST)

#* Clean string columns in a dataset
#* @post /state
#* @serializer unboxedJSON
function(req) {
  body <- jsonlite::fromJSON(req$body, simplifyVector = TRUE)

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
