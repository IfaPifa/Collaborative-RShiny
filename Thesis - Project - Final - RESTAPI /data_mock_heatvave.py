import pandas as pd
import numpy as np
import os
from datetime import datetime, timedelta

print("Generating 500,000 rows of LTER-LIFE sensor data...")

# Parameters
num_rows = 500000
sites = ['Site_A', 'Site_B', 'Site_C', 'Site_D', 'Site_E']
rows_per_site = num_rows // len(sites)

# Generate timestamps (15-minute intervals starting Jan 1, 2020)
start_date = datetime(2020, 1, 1)
timestamps = [start_date + timedelta(minutes=15 * i) for i in range(rows_per_site)]

dfs = []

for site in sites:
    # Days elapsed array for calculating sine waves
    days_passed = np.array([i / (24 * 4) for i in range(rows_per_site)])
    
    # 1. Simulate Temperature: Yearly seasonality + daily cycle + random noise
    seasonal_temp = 15 + 10 * np.sin(2 * np.pi * (days_passed - 100) / 365.25) 
    daily_temp = 5 * np.sin(2 * np.pi * days_passed)
    noise = np.random.normal(0, 2, rows_per_site)
    
    temperature = seasonal_temp + daily_temp + noise
    
    # 2. Inject Heatwaves: Randomly spike temperatures by 12-15°C to trigger your Shiny app's anomaly logic
    heatwave_spikes = np.random.choice([0, 12, 15], size=rows_per_site, p=[0.99, 0.005, 0.005])
    temperature += heatwave_spikes
    
    # 3. Simulate Soil Moisture: Inversely correlated to temperature (hotter = drier)
    soil_moisture = 60 - (temperature * 1.2) + np.random.normal(0, 5, rows_per_site)
    soil_moisture = np.clip(soil_moisture, 10, 80) # Keep within realistic % bounds
    
    # Create DataFrame for this site
    site_df = pd.DataFrame({
        'Timestamp': timestamps,
        'SiteID': site,
        'Temperature': np.round(temperature, 2),
        'SoilMoisture': np.round(soil_moisture, 2)
    })
    dfs.append(site_df)

# Combine all sites into one massive dataframe
final_df = pd.concat(dfs, ignore_index=True)

# Sort by timestamp so the file simulates a continuous chronological sensor log
final_df = final_df.sort_values(by='Timestamp').reset_index(drop=True)

# Save to CSV
output_filename = "lter_sensor_data_500k.csv"
final_df.to_csv(output_filename, index=False)

file_mb = os.path.getsize(output_filename) / (1024 * 1024)
print(f"Success! Saved {len(final_df)} rows to '{output_filename}'.")
print(f"File size: {file_mb:.2f} MB")