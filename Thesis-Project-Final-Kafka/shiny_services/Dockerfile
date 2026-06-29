# Base R Shiny image (Ubuntu 22.04 Jammy based)
FROM rocker/shiny:4.4.0

# Install system dependencies (no JDK — r-kafka uses librdkafka, not rJava)
RUN apt-get -y update && apt-get install -y \
   cmake \
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

# Pin to a dated Posit PPM snapshot for reproducible builds. "latest" is not
# reproducible: a newer terra (pulled transitively by leaflet -> raster) began
# requiring the GDAL >=3.5 multidimensional API, which the base image's GDAL
# 3.4.1 (Jammy) does not provide, breaking the build. This snapshot predates
# that release and matches the known-good benchmark image.
ENV R_REPOS="https://packagemanager.posit.co/cran/__linux__/jammy/2026-06-16"

# Install R packages
RUN R -e "install.packages(c('Rcpp', 'jsonlite', 'remotes', 'shinyjs', 'ggplot2', 'dplyr', 'leaflet', 'arrow', 'duckdb', 'bslib', 'plotly', 'shinyWidgets', 'randomForest', 'promises', 'future'), repos=Sys.getenv('R_REPOS'), Ncpus=4)"

# Install the kafka package from GitHub
RUN R -e "remotes::install_github('INWTlab/r-kafka')"

# Bulletproof Checks
RUN R -e "if (!requireNamespace('leaflet', quietly = TRUE)) stop('FATAL: Leaflet failed to install!')"
RUN R -e "if (!requireNamespace('arrow', quietly = TRUE)) stop('FATAL: Arrow failed to install!')"
RUN R -e "if (!requireNamespace('randomForest', quietly = TRUE)) stop('FATAL: randomForest failed to install!')"
RUN R -e "if (!requireNamespace('bslib', quietly = TRUE)) stop('FATAL: bslib failed to install!')"

EXPOSE 3838