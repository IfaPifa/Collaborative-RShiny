# Use the official RStudio Shiny image
FROM rocker/shiny:latest

# Install required R packages (bslib for the UI)
RUN R -e "install.packages(c('bslib'), repos='https://cloud.r-project.org/')"

# Copy the monolithic app into the container
COPY app.R /srv/shiny-server/app.R

# Expose the standard Shiny port
EXPOSE 3838

# Run the app bound to 0.0.0.0 so it can be reached outside the container
CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/app.R', host = '0.0.0.0', port = 3838)"]