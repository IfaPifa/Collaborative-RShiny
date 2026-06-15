# Vendored: BioDT `biodt-shiny`

This directory is a **vendored copy** of the BioDT Shiny application, included so
the honeybee proof-of-concept in `whole_apps/honeybee_poc/` is self-contained and
reproducible from a single `git clone` (no submodule init, no network fetch of a
third-party repo).

## Provenance

| | |
|---|---|
| **Source repository** | https://github.com/BioDT/biodt-shiny |
| **Upstream commit** | `14f5be960bac879cfd80019244867a72d9eb2231` |
| **Commit date** | 2026-04-28 (`Rename forest DT in texts`) |
| **Upstream branch** | `main` |
| **Date vendored** | 2026-06-15 |
| **Licence** | MIT — see `LICENSE` / `LICENSE.md` (Copyright (c) 2023 BioDT) |

The original BioDT MIT licence files (`LICENSE`, `LICENSE.md`) are retained
unmodified in this directory, as required by the licence.

## Local modifications for the PoC

The vendored tree is **not** pristine: it carries a small, focused set of changes
that wire the honeybee module to the ShinySwarm `statesnap` backend over
HTTP. Every change is additive and marked inline with `# PoC:` comments so it can
be told apart from upstream code. Nothing in the original honeybee compute path
(map, parameters, lookup, plot modules) was removed.

### New files (2)

- `app/logic/honeybee/statesnap_adapter.R` — composes the BioDT *model*
  (coordinates + parameters + lookup) into a `statesnap` checkpoint, ships it to
  the Plumber backend, and writes the returned result table to the BioDT output
  path. Capturing the model (not namespaced inputs) is the core PoC idea.
- `app/view/honeybee/beekeeper_checkpoint.R` — a `box` UI module adding
  Save/Restore controls for a reproducible, shareable run checkpoint.

### Modified files (3)

- `config.yml` — adds a `poc` config profile (`executor: "plumber"`,
  `backend_url`) activated with `R_CONFIG_ACTIVE=poc`.
- `app/view/honeybee/beekeeper_runsimulation.R` — adds a `"plumber"` executor
  branch alongside the existing `docker` / `k8s` executors.
- `app/view/honeybee/honeybee_beekeeper.R` — wires the checkpoint module into the
  parent and surfaces coordinate/lookup restore.

To see the exact delta against upstream, diff this tree against
`biodt-shiny@14f5be9` from https://github.com/BioDT/biodt-shiny, or grep for
`# PoC:` markers.

## Attribution

The BioDT honeybee pollinators use case originates from the LTER LIFE / BioDT
project and is used here under its MIT licence for academic research (the
ShinySwarm Master's thesis, University of Amsterdam). See the PoC `README.md` for
how the vendored app is run dockerised against the simulated BEEHAVE backend.
