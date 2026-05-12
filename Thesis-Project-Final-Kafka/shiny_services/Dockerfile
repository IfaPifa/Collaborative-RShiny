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
   libsodium-dev \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/*

# Configure Java for R so rJava compiles cleanly
RUN R CMD javareconf

# Set CRAN repository to Posit Public Package Manager (Ubuntu Jammy Binaries)
# Bypasses massive C++ compilation times
ENV R_REPOS="https://packagemanager.posit.co/cran/__linux__/jammy/latest"

# Install R packages (Includes bslib, arrow, randomForest, etc.)
RUN R -e "install.packages(c('Rcpp', 'jsonlite', 'rJava', 'rkafkajars', 'remotes', 'shinyjs', 'ggplot2', 'dplyr', 'leaflet', 'arrow', 'duckdb', 'bslib', 'plotly', 'shinyWidgets', 'randomForest', 'promises', 'future'), repos=Sys.getenv('R_REPOS'), Ncpus=4)"

# Install the kafka package from GitHub
RUN R -e "remotes::install_github('INWTlab/r-kafka')"

# Bulletproof Checks
RUN R -e "if (!requireNamespace('leaflet', quietly = TRUE)) stop('FATAL: Leaflet failed to install!')"
RUN R -e "if (!requireNamespace('arrow', quietly = TRUE)) stop('FATAL: Arrow failed to install!')"
RUN R -e "if (!requireNamespace('randomForest', quietly = TRUE)) stop('FATAL: randomForest failed to install!')"
RUN R -e "if (!requireNamespace('bslib', quietly = TRUE)) stop('FATAL: bslib failed to install!')"

EXPOSE 3838