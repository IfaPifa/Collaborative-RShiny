#' Type-hinted state wrappers
#'
#' These wrappers tell [capture_state()] how to handle a piece of state that
#' cannot be serialised as plain JSON. They carry no logic themselves -- they
#' only attach a class that `capture_state()` dispatches on. The output of
#' `capture_state()` is always a single JSON string; the wrappers control what
#' goes \emph{inside} that JSON.
#'
#' @name state-wrappers
NULL

#' Capture a file from disk
#'
#' Marks a path so that [capture_state()] reads the file and embeds its
#' contents (base64-encoded) in the checkpoint JSON. On restore the file is
#' written back to disk.
#'
#' @param path Path to the file to embed.
#' @return An object of class `statesnap_file`.
#' @export
#' @examples
#' state_file("/tmp/data.csv")
state_file <- function(path) {
  if (!is.character(path) || length(path) != 1L) {
    stop("state_file() requires a single file path", call. = FALSE)
  }
  structure(list(path = path), class = "statesnap_file")
}

#' Capture an arbitrary R object
#'
#' Marks an R object (e.g. a trained model) so that [capture_state()]
#' serialises it with [base::serialize()] and embeds it (base64-encoded) in the
#' checkpoint JSON. On restore the object is reconstructed with
#' [base::unserialize()].
#'
#' @param obj Any R object.
#' @return An object of class `statesnap_rds`.
#' @export
#' @examples
#' state_rds(lm(mpg ~ wt, data = mtcars))
state_rds <- function(obj) {
  structure(list(obj = obj), class = "statesnap_rds")
}
