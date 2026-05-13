library(plumber)
library(jsonlite)
library(dplyr)

df <- mtcars

#* @apiTitle Visual Analytics Backend (REST)

#* Process filter parameters and return filtered data
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) { body_text <- rawToChar(raw_body) } else if (is.character(raw_body)) { body_text <- raw_body } else { body_text <- NULL }
  if (!is.null(body_text)) { body <- jsonlite::fromJSON(body_text, simplifyVector = TRUE) } else { body <- raw_body }

  min_hp <- if (!is.null(body$min_hp)) as.numeric(body$min_hp) else 50
  cyl_filter <- if (!is.null(body$cyl)) as.numeric(body$cyl) else c(4, 6, 8)
  sender <- if (!is.null(body$sender)) body$sender else "unknown"

  filtered_df <- df %>% filter(hp >= min_hp, cyl %in% cyl_filter)

  return(list(
    data = filtered_df,
    min_hp = min_hp,
    cyl = cyl_filter,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}
