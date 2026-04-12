# Base R Shiny image
FROM rocker/rstudio:4.5.0


# Install R dependencies
# Install rJava
RUN apt-get -y update && apt-get install -y \
   r-cran-rjava \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/

RUN apt-get -y update && apt-get install -y \
   librdkafka-dev \
   libcurl4-openssl-dev \
   libssl-dev \
   libxml2-dev \
   && rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages(c('rJava','rkafkajars','shiny'))"

RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org')"

# Install the kafka package from INWTlab GitHub
RUN R -e "remotes::install_github('INWTlab/r-kafka')"

# Expose the application port
EXPOSE 8080
EXPOSE 8180


