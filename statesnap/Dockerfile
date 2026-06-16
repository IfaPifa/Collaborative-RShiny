# Dockerised test runner for the statesnap package.
#
# Build:  docker build -t statesnap-tests statesnap
# Run:    docker run --rm statesnap-tests
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

# Default: load the package from source and run the full test suite.
CMD ["Rscript", "-e", "pkgload::load_all('.'); testthat::test_dir('tests/testthat', stop_on_failure = TRUE)"]
