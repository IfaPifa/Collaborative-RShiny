# Use Rocker's shiny image as a baseline
FROM rocker/shiny:4.3.2

# Install system dependencies required for spatial packages and leaflet
RUN apt-get update && apt-get install -y \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages
RUN R -e "install.packages(c('bslib', 'leaflet', 'shinyjs', 'jsonlite'), repos='http://cran.rstudio.com/')"

# Set working directory
WORKDIR /app

# Copy the monolithic app
COPY app.r /app/app.r

# Expose Shiny's default port
EXPOSE 3838

# Run the application
CMD ["R", "-e", "shiny::runApp('/app', host = '0.0.0.0', port = 3838)"]