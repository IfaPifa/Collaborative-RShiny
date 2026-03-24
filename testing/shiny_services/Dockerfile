# Base R Shiny image
FROM rocker/shiny:4.4.0

# Install system dependencies
RUN apt-get -y update && apt-get install -y \
   default-jdk \
   cmake \
   r-cran-rjava \
   librdkafka-dev \
   libcurl4-openssl-dev \
   libssl-dev \
   libxml2-dev \
   libgdal-dev \
   libproj-dev \
   libgeos-dev \
   libudunits2-dev \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/*

# Configure Java for R so rJava compiles cleanly
RUN R CMD javareconf

# Update Rcpp first (Required by 'units' and 'terra')
RUN R -e "install.packages('Rcpp', repos='https://cloud.r-project.org')"

# Install R packages
RUN R -e "install.packages(c('jsonlite', 'rJava', 'rkafkajars', 'remotes', 'shinyjs', 'ggplot2', 'dplyr', 'leaflet'), repos='https://cloud.r-project.org', Ncpus=4)"

# Install the kafka package
RUN R -e "remotes::install_github('INWTlab/r-kafka')"

# Bulletproof Check: Force Docker to fail if Leaflet is missing
RUN R -e "if (!requireNamespace('leaflet', quietly = TRUE)) stop('FATAL: Leaflet failed to install!')"

EXPOSE 3838