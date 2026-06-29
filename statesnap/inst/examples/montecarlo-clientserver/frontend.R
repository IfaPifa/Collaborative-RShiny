# Monte Carlo frontend logic, mirroring shiny_front_mc.r from the REST
# architecture, but using statesnap to apply the backend's result.
#
# The two transport-facing functions are kept free of Shiny so they can be
# driven directly in tests:
#   mc_frontend_request() -- POST the simulation parameters (the "run" action)
#   mc_frontend_apply()   -- GET the result checkpoint and restore it into a
#                            reactive-value-like setter via restore_state()

# Send a START_SIMULATION request for this session.
mc_frontend_request <- function(transport, session_id, params) {
  payload <- c(list(command = "START_SIMULATION"), params)
  transport$post(session_id, "request", payload)
  invisible(TRUE)
}

# Look for a result checkpoint and, if present, restore it into `results_setter`
# (a reactiveVal-style accessor: results_setter(value) sets, results_setter()
# gets). Returns TRUE if a result was applied, FALSE if none was waiting.
#
# This is the statesnap counterpart to the real frontend's
# `state$results <- fromJSON(...)`: instead of parsing a bespoke payload, it
# hands the checkpoint to restore_state(), which writes the computed result back
# through the supplied setter.
mc_frontend_apply <- function(transport, session_id, results_setter) {
  checkpoint <- transport$get(session_id, "result")
  if (is.null(checkpoint)) return(FALSE)
  statesnap::restore_state(NULL, checkpoint, results = results_setter)
  TRUE
}
