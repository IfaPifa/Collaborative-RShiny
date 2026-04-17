library(jsonlite)
library(kafka)
library(dplyr)

broker <- "kafka:9092"
shared_dir <- "/app/shared_data"
print("LTER-LIFE Anomaly Backend Starting...")

consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = "backend_csv", "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
consumer$subscribe("input")
producer <- Producer$new(list("bootstrap.servers" = broker))

repeat {
  tryCatch({
    messages <- consumer$consume(500)
    if (length(messages) > 0) {
      for (mess in messages) {
        if (is.null(mess) || is.null(mess$value)) next
        incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
        
        payload <- fromJSON(mess$value)
        if (!is.null(payload$role) && payload$role == "VIEWER") next 
        
        # Check if this is our new ecological action
        if (!is.null(payload$action) && payload$action == "ANALYZE_CLIMATE") {
          
          # 1. READ RAW DATA FROM VOLUME (Not from Kafka)
          raw_file_path <- file.path(shared_dir, payload$file)
          
          if (file.exists(raw_file_path)) {
            df <- read.csv(raw_file_path, stringsAsFactors = FALSE)
            
            # 2. ECOLOGICAL MATH (Aggregation & Anomaly Detection)
            # Ensure Timestamp is readable as Date
            df$Date <- as.Date(df$Timestamp)
            
            summary_df <- df %>%
              group_by(SiteID, Date) %>%
              summarize(
                Daily_Mean_Temp = mean(Temperature, na.rm = TRUE),
                Daily_Mean_Moisture = mean(SoilMoisture, na.rm = TRUE),
                .groups = 'drop'
              ) %>%
              mutate(
                Heatwave_Anomaly = ifelse(Daily_Mean_Temp > payload$threshold, "YES", "NO")
              )
            
            # 3. SAVE PROCESSED DATA TO VOLUME
            summary_file_name <- "processed_summary.csv"
            write.csv(summary_df, file.path(shared_dir, summary_file_name), row.names = FALSE)
            
            # 4. SEND "POINTER" BACK OVER KAFKA
            response_payload <- list(
              action = "CLIMATE_READY",
              file = summary_file_name,
              sender = payload$sender,
              timestamp = as.numeric(Sys.time())
            )
            
            producer$produce("output", toJSON(response_payload, auto_unbox = TRUE), key = incoming_key)
            print(paste("Processed LTER data for", payload$sender, "with threshold", payload$threshold))
          }
        }
      }
    }
  }, error = function(e) { 
    print(paste("Backend Error:", e$message))
    Sys.sleep(1) 
  })
}