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

RUN chmod +x docker-entrypoint.sh

# The app listens here; published with `-p 8100:8100` when serving.
EXPOSE 8100

# Default to running the tests; pass `app` to serve the example instead.
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["test"]
