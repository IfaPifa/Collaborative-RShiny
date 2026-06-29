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
# Pin to a dated Posit PPM snapshot for reproducible builds. "latest" is not
# reproducible: a newer terra (pulled transitively by leaflet -> raster) began
# requiring the GDAL >=3.5 multidimensional API, which the base image's GDAL
# 3.4.1 (Jammy) does not provide, breaking the build. This snapshot predates
# that release and matches the known-good benchmark image.
ENV R_REPOS="https://packagemanager.posit.co/cran/__linux__/jammy/2026-06-16"

# Install R packages
# (leaflet.extras, DT and base64enc are required by the BioDT Honeybee app and
#  the statesnap package it loads.)
RUN R -e "install.packages(c('Rcpp', 'jsonlite', 'rJava', 'rkafkajars', 'remotes', 'shinyjs', 'ggplot2', 'dplyr', 'leaflet', 'leaflet.extras', 'DT', 'base64enc', 'arrow', 'duckdb', 'bslib', 'plotly', 'shinyWidgets', 'randomForest', 'plumber', 'httr', 'promises', 'future'), repos=Sys.getenv('R_REPOS'), Ncpus=4)"


# Bulletproof Checks
RUN R -e "if (!requireNamespace('leaflet', quietly = TRUE)) stop('FATAL: Leaflet failed to install!')"
RUN R -e "if (!requireNamespace('arrow', quietly = TRUE)) stop('FATAL: Arrow failed to install!')"
RUN R -e "if (!requireNamespace('randomForest', quietly = TRUE)) stop('FATAL: randomForest failed to install!')"
RUN R -e "if (!requireNamespace('httr', quietly = TRUE)) stop('FATAL: httr failed to install! (Check libssl-dev / libcurl4-openssl-dev)')"
RUN R -e "if (!requireNamespace('plumber', quietly = TRUE)) stop('FATAL: plumber failed to install! (Check libsodium-dev)')"
# Bulletproof Checks
RUN R -e "if (!requireNamespace('promises', quietly = TRUE)) stop('FATAL: promises failed to install!')"
RUN R -e "if (!requireNamespace('future', quietly = TRUE)) stop('FATAL: future failed to install!')"
RUN R -e "if (!requireNamespace('leaflet.extras', quietly = TRUE)) stop('FATAL: leaflet.extras failed to install!')"
RUN R -e "if (!requireNamespace('DT', quietly = TRUE)) stop('FATAL: DT failed to install!')"

# Install the local statesnap package (used by the BioDT Honeybee app for
# reproducible checkpoint capture/restore). Build context is the repo root so
# the package source at ./statesnap is available to COPY.
COPY statesnap /tmp/statesnap
RUN R CMD INSTALL --no-multiarch --with-keep.source /tmp/statesnap \
    && R -e "if (!requireNamespace('statesnap', quietly = TRUE)) stop('FATAL: statesnap failed to install!')"

EXPOSE 3838