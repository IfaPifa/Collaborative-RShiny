library(plumber)
library(jsonlite)
library(dplyr)

# Pre-load dataset
df <- mtcars

#* @apiTitle Visual Analytics Backend (REST)

#* Process filter parameters and return filtered data
#* @post /state
#* @serializer unboxedJSON
function(req) {
  # Manually parse the JSON body to handle arrays correctly
  body <- jsonlite::fromJSON(req$body, simplifyVector = TRUE)

  min_hp <- if (!is.null(body$min_hp)) as.numeric(body$min_hp) else 50
  cyl_filter <- if (!is.null(body$cyl)) as.numeric(body$cyl) else c(4, 6, 8)
  sender <- if (!is.null(body$sender)) body$sender else "unknown"

  # Data manipulation
  filtered_df <- df %>%
    filter(hp >= min_hp, cyl %in% cyl_filter)

  return(list(
    data = filtered_df,
    min_hp = min_hp,
    cyl = cyl_filter,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}
