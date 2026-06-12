# Lightweight fakes so the core capture/restore logic can be tested without a
# running Shiny server.

# A reactiveVal substitute: a closure that gets/sets a stored value.
fake_reactiveval <- function(initial = NULL) {
  value <- initial
  function(x) {
    if (missing(x)) value else value <<- x
  }
}

# A fake session that records sendInputMessage() calls into an environment so
# tests can assert which inputs were pushed back.
fake_session <- function() {
  sent <- list()
  list(
    sendInputMessage = function(name, msg) {
      sent[[name]] <<- msg$value
    },
    sent = function() sent
  )
}
