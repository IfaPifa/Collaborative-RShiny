# Honeybee PoC backend: Plumber + statesnap.
# Build context is the REPO ROOT (see docker-compose.yml) so we can copy both
# the backend code and the statesnap package source.
# Reuse the BioDT shiny-base image (R + system libs already present).
FROM ghcr.io/biodt/shiny-base:latest

WORKDIR /srv

# R deps for the backend.
RUN R -q -e "install.packages(c('plumber','jsonlite','base64enc','httr'), repos='https://cloud.r-project.org')"

# Install statesnap from local source.
COPY statesnap /tmp/statesnap
RUN R -q -e "install.packages('/tmp/statesnap', repos=NULL, type='source')"

# Backend code
COPY whole_apps/honeybee_poc/backend /srv/backend

EXPOSE 8000
CMD ["Rscript", "backend/run_backend.R"]
