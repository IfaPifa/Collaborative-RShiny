FROM rocker/shiny:latest

RUN R -e "install.packages(c('bslib', 'dplyr', 'ggplot2', 'leaflet', 'plotly', 'randomForest', 'shinyjs'), repos='https://cloud.r-project.org/')"

# Copy all 8 app directories into the image
COPY calculator/app.r        /apps/calculator/app.r
COPY analytics/app.r         /apps/analytics/app.r
COPY analytics_advanced/app.r /apps/analytics_advanced/app.r
COPY data_exchange/app.r     /apps/data_exchange/app.r
COPY montecarlo/app.r        /apps/montecarlo/app.r
COPY map/app.r               /apps/map/app.r
COPY anomaly_detector/app.r  /apps/anomaly_detector/app.r
COPY ml_trainer/app.r        /apps/ml_trainer/app.r

# Default to calculator; override APP_NAME env var to select app
ENV APP_NAME=calculator

EXPOSE 3838

CMD ["sh", "-c", "R -e \"shiny::runApp('/apps/${APP_NAME}/app.r', host='0.0.0.0', port=3838)\""]
