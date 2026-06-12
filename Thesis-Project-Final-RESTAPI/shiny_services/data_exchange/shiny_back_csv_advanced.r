library(plumber)
library(jsonlite)
library(dplyr)

shared_dir <- "/app/shared_data"
dir.create(shared_dir, showWarnings = FALSE)

#* @apiTitle LTER-LIFE Climate Anomaly Backend (REST)

#* Analyze climate sensor data from shared volume
#* @post /state
#* @serializer unboxedJSON
function(req) {
  raw_body <- req$body
  if (is.raw(raw_body)) {
    body <- jsonlite::fromJSON(rawToChar(raw_body), simplifyVector = TRUE)
  } else if (is.character(raw_body)) {
    body <- jsonlite::fromJSON(raw_body, simplifyVector = TRUE)
  } else if (is.list(raw_body)) {
    body <- raw_body
  } else {
    body <- list()
  }

  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  action <- if (!is.null(body$action)) body$action else ""

  if (action != "ANALYZE_CLIMATE") {
    return(list(status = "ignored", message = "Unknown action"))
  }

  file_name <- if (!is.null(body$file) && nchar(body$file) > 0) body$file else ""
  raw_file_path <- file.path(shared_dir, file_name)
  threshold <- if (!is.null(body$threshold)) as.numeric(body$threshold) else 28.5

  if (file_name == "" || !file.exists(raw_file_path)) {
    return(list(status = "error", message = "File not found on shared volume"))
  }

  # Read and process the raw sensor data
  df <- read.csv(raw_file_path, stringsAsFactors = FALSE)
  df$Date <- as.Date(df$Timestamp, format = "%Y-%m-%d")

  summary_df <- df %>%
    group_by(SiteID, Date) %>%
    summarize(
      Daily_Mean_Temp = mean(Temperature, na.rm = TRUE),
      Daily_Mean_Moisture = mean(SoilMoisture, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(
      Heatwave_Anomaly = ifelse(Daily_Mean_Temp > threshold, "YES", "NO")
    )

  # Save processed data with matching fingerprint
  summary_file_name <- sub("^raw_", "processed_", body$file)
  write.csv(summary_df, file.path(shared_dir, summary_file_name), row.names = FALSE)

  res <- list(
    action = "CLIMATE_READY",
    file = summary_file_name,
    sender = sender,
    rows_processed = nrow(summary_df),
    status = "success",
    timestamp = as.numeric(Sys.time())
  )
  if (!is.null(body[["_marker"]])) res[["_marker"]] <- body[["_marker"]]
  return(res)
}