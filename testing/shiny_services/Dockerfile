# Base R Shiny image (Ubuntu 22.04 Jammy based)
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

# Set CRAN repository to Posit Public Package Manager (Ubuntu Jammy Binaries)
# This completely bypasses the massive C++ compilation times!
ENV R_REPOS="https://packagemanager.posit.co/cran/__linux__/jammy/latest"

# Install R packages including Arrow and DuckDB for CSV Advanced features 
# ---> ADDED: 'shinyWidgets' and 'randomForest'
RUN R -e "install.packages(c('Rcpp', 'jsonlite', 'rJava', 'rkafkajars', 'remotes', 'shinyjs', 'ggplot2', 'dplyr', 'leaflet', 'arrow', 'duckdb', 'bslib', 'plotly', 'shinyWidgets', 'randomForest'), repos=Sys.getenv('R_REPOS'), Ncpus=4)"

# Install the kafka package from GitHub
RUN R -e "remotes::install_github('INWTlab/r-kafka')"

# Bulletproof Check: Force Docker to fail if core packages are missing
RUN R -e "if (!requireNamespace('leaflet', quietly = TRUE)) stop('FATAL: Leaflet failed to install!')"
RUN R -e "if (!requireNamespace('arrow', quietly = TRUE)) stop('FATAL: Arrow failed to install!')"
RUN R -e "if (!requireNamespace('randomForest', quietly = TRUE)) stop('FATAL: randomForest failed to install!')"

EXPOSE 3838