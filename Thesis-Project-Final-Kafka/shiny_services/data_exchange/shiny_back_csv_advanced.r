library(jsonlite)
library(kafka)
library(dplyr)

broker <- "kafka:9092"
shared_dir <- "/app/shared_data"
print("LTER-LIFE Anomaly Backend Starting...")

consumer <- Consumer$new(list("bootstrap.servers" = broker, "group.id" = "backend_csv_advanced", "auto.offset.reset" = "latest", "enable.auto.commit" = "true"))
consumer$subscribe("input")
producer <- Producer$new(list("bootstrap.servers" = broker))

repeat {
  tryCatch({
    result <- consumer$consume(500)
    if (result_has_error(result)) next
    mess <- result_message(result)
    if (is.null(mess) || is.null(mess$value)) next
    incoming_key <- if (!is.null(mess$key)) mess$key else "unknown"
    
    payload <- fromJSON(mess$value)
    if (!is.null(payload$role) && payload$role == "VIEWER") next 
    
    if (!is.null(payload$action)) {
      
      if (payload$action == "ANALYZE_CLIMATE") {
        
        raw_file_path <- file.path(shared_dir, payload$file)
        
        if (file.exists(raw_file_path)) {
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
              Heatwave_Anomaly = ifelse(Daily_Mean_Temp > payload$threshold, "YES", "NO")
            )
          
          summary_file_name <- "processed_summary.csv"
          write.csv(summary_df, file.path(shared_dir, summary_file_name), row.names = FALSE)
          
          response_payload <- list(
            action = "CLIMATE_READY",
            file = summary_file_name,
            sender = payload$sender,
            timestamp = as.numeric(Sys.time())
          )
          
          producer$produce("output", toJSON(response_payload, auto_unbox = TRUE), key = incoming_key)
          print(paste("Processed LTER data for", payload$sender, "with threshold", payload$threshold))
        }
        
      } else if (payload$action == "CLIMATE_READY" && !is.null(payload$sender) && payload$sender == "System Restore") {
        producer$produce("output", toJSON(payload, auto_unbox = TRUE), key = incoming_key)
        print(paste("Time Machine: Restored checkpoint for", incoming_key))
      }
    }
  }, error = function(e) { 
    print(paste("Backend Error:", e$message))
    Sys.sleep(1) 
  })
}