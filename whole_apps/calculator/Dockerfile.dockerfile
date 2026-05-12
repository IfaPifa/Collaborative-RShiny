FROM rocker/shiny:latest

# Install required R packages
RUN R -e "install.packages(c('bslib'), repos='https://cloud.r-project.org/')"

# Copy the app
COPY app.R /srv/shiny-server/app.R

# Expose the standard Shiny port
EXPOSE 3838

# Run the app
CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/app.R', host = '0.0.0.0', port = 3838)"]