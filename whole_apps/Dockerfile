FROM rocker/shiny:latest

RUN R -e "install.packages(c('bslib', 'dplyr', 'ggplot2', 'leaflet', 'plotly', 'randomForest', 'shinyjs'), repos='https://cloud.r-project.org/')"

COPY app.r /srv/shiny-server/app.r

EXPOSE 3838

CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/app.r', host='0.0.0.0', port=3838)"]
