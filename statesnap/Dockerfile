# Dockerised runner for the statesnap package: runs the tests by default, and
# can also serve the client/server Monte Carlo example app.
#
# Build (from the statesnap/ directory):
#   docker build -t statesnap-tests .
#
# Run the test suite (default):
#   docker run --rm statesnap-tests
#
# Serve the Monte Carlo app, then open http://127.0.0.1:8100 :
#   docker run --rm -p 8100:8100 statesnap-tests app
#
# File hand-off demo (two windows for a video): producer saves a checkpoint to
# a file, consumer loads it. Open http://127.0.0.1:8100 and :8200 :
#   docker run --rm -p 8100:8100 -p 8200:8200 statesnap-tests handoff
#
# The rocker/r-ver image ships R plus the Posit binary package repo, so the
# R dependencies install as prebuilt binaries (fast, no compilation, no apt key
# juggling on the host).

FROM rocker/r-ver:4.4.1

# System libraries some R packages link against (shiny/httpuv etc.).
RUN apt-get update && apt-get install -y --no-install-recommends \
      libxml2-dev \
      libcurl4-openssl-dev \
      libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install the package dependencies (Imports + Suggests used by the test suite).
RUN install2.r --error --skipinstalled \
      jsonlite \
      base64enc \
      shiny \
      testthat \
      pkgload

WORKDIR /pkg
COPY . /pkg

# Install the package itself so the demo apps (which library(statesnap)) work.
RUN R CMD INSTALL --no-multiarch --with-keep.source .

RUN chmod +x docker-entrypoint.sh

# Ports: 8100 (app / producer), 8200 (consumer in the hand-off demo).
EXPOSE 8100 8200

# Default to running the tests; pass `app` to serve the example instead.
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["test"]
