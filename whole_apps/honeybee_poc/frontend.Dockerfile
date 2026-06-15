# Honeybee PoC frontend: the REAL BioDT honeybee app + statesnap.
# Build context is the REPO ROOT (see docker-compose.yml).
# Reuse the BioDT shiny-base image (rhino/box/leaflet/terra/echarty present).
FROM ghcr.io/biodt/shiny-base:latest

WORKDIR /app

# statesnap + httr for the PoC adapter (frontend talks to the backend over HTTP).
RUN R -q -e "install.packages(c('httr','base64enc'), repos='https://cloud.r-project.org')"
COPY statesnap /tmp/statesnap
RUN R -q -e "install.packages('/tmp/statesnap', repos=NULL, type='source')"

# The (patched) BioDT app, including our statesnap_adapter + checkpoint module.
COPY whole_apps/honeybee_poc/biodt-shiny /app

EXPOSE 7860
CMD ["R", "--quiet", "-e", "shiny::runApp(host='0.0.0.0', port=7860)"]
