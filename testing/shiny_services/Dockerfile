# Base R Shiny image (not RStudio)
FROM rocker/shiny:4.4.0

# Install system dependencies needed for R packages
RUN apt-get -y update && apt-get install -y \
   r-cran-rjava \
   librdkafka-dev \
   libcurl4-openssl-dev \
   libssl-dev \
   libxml2-dev \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/*

# Install the R packages needed by your scripts
RUN R -e "install.packages(c('jsonlite', 'rJava', 'rkafkajars', 'remotes'), repos='https://cloud.r-project.org')"

# Install the kafka package from INWTlab GitHub
RUN R -e "remotes::install_github('INWTlab/r-kafka')"

# Expose the default Shiny port
EXPOSE 3838

