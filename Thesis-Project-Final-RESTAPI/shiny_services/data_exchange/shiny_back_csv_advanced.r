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
  body <- jsonlite::fromJSON(req$body, simplifyVector = TRUE)

  sender <- if (!is.null(body$sender)) body$sender else "unknown"
  action <- if (!is.null(body$action)) body$action else ""

  if (action != "ANALYZE_CLIMATE") {
    return(list(status = "ignored", message = "Unknown action"))
  }

  raw_file_path <- file.path(shared_dir, body$file)
  threshold <- if (!is.null(body$threshold)) as.numeric(body$threshold) else 28.5

  if (!file.exists(raw_file_path)) {
    return(list(status = "error", message = "File not found on shared volume"))
  }

  # Read and process the raw sensor data
  df <- read.csv(raw_file_path, stringsAsFactors = FALSE)
  df$Date <- as.Date(df$Timestamp)

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

  return(list(
    action = "CLIMATE_READY",
    file = summary_file_name,
    sender = sender,
    rows_processed = nrow(summary_df),
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}
