# Base R Shiny image
FROM rocker/rstudio:4.0.3


# Install R dependencies
# Install rJava
RUN apt-get -y update && apt-get install -y \
   r-cran-rjava \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/

RUN R -e "install.packages(c('rJava','rkafkajars','shiny'))"


# Expose the application port
EXPOSE 8080
EXPOSE 8180


