# In-process transport standing in for the Spring Boot store in the real
# ShinySwarm REST architecture. It is a tiny keyed message store: the frontend
# POSTs a request, the backend reads it and POSTs back a result checkpoint, and
# the frontend GETs the result -- exactly the request/result round-trip of the
# real system, but without HTTP so it can be driven directly in tests.
#
# Channels are keyed by (session_id, channel) so many sessions can coexist:
#   "request" -> simulation parameters (plain JSON), written by the frontend
#   "result"  -> statesnap checkpoint, written by the backend

mc_transport <- function() {
  store <- new.env(parent = emptyenv())
  key <- function(session_id, channel) paste0(session_id, "::", channel)

  list(
    post = function(session_id, channel, payload) {
      assign(key(session_id, channel), payload, envir = store)
      invisible(TRUE)
    },
    get = function(session_id, channel) {
      k <- key(session_id, channel)
      if (exists(k, envir = store, inherits = FALSE)) {
        base::get(k, envir = store)
      } else {
        NULL
      }
    },
    clear = function() {
      rm(list = ls(store, all.names = TRUE), envir = store)
      invisible(TRUE)
    }
  )
}
