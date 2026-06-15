# Honeybee PoC — statesnap between a modular Shiny frontend and a Plumber backend

A minimal proof of concept showing **frontend ↔ backend communication via
[statesnap](../../statesnap) JSON over HTTP**, using the **real, unflattened**
BioDT honeybee app as the frontend.

The point of this PoC (for the thesis): statesnap can be applied to a deeply
**modular** Shiny app (Rhino/`box`) **without flattening it**, by binding to the
app's *model* rather than to namespaced `input` widgets.

## Attribution

The honeybee (Beekeeper pDT) application is from the **LTER LIFE** project
(BioDT, `github.com/BioDT/biodt-shiny`) and is used here with their permission
for a Master's thesis. All credit for the original app and its scientific model
belongs to the LTER LIFE / BioDT authors. The compute backend in this PoC is a
**simulated** stand-in for `ghcr.io/biodt/beehave`, not the real NetLogo model.

## Layout

```
honeybee_poc/
├── biodt-shiny/                 # the REAL BioDT app (cloned), lightly patched:
│   ├── app/logic/honeybee/statesnap_adapter.R     # NEW: model<->JSON<->HTTP
│   ├── app/view/honeybee/beekeeper_checkpoint.R   # NEW: save/restore run UI
│   ├── app/view/honeybee/beekeeper_runsimulation.R# PATCHED: "plumber" executor
│   ├── app/view/honeybee/honeybee_beekeeper.R     # PATCHED: wires checkpoint
│   └── config.yml                                 # PATCHED: "poc" profile
├── backend/
│   ├── plumber.R                # simulated BEEHAVE; speaks statesnap JSON
│   ├── run_backend.R            # entrypoint (:8000)
│   └── Dockerfile
├── frontend.Dockerfile
└── docker-compose.yml
```

Only **5 files** of the upstream app are touched (2 new, 3 patched). Everything
else — map, param, lookup, plot modules — runs unchanged.

`biodt-shiny/` is a **vendored** copy (plain files, no nested git repo) so this
PoC is reproducible from a single clone. Its provenance — source URL, exact
upstream commit (`14f5be9`), date, MIT licence, and the full list of local
patches — is recorded in
[`biodt-shiny/VENDORED.md`](biodt-shiny/VENDORED.md).

## How it works

1. The BioDT parent module already composes its children into namespace-free
   model fragments: `coordinates()`, `parameters()`, `lookup()`.
2. On **Run simulation**, the patched `runsimulation` module (executor
   `"plumber"`) composes those into a `model`, captures it with
   `statesnap::capture_state(input = list(), model = model)`, and POSTs the JSON
   to the backend.
3. The backend restores the model from JSON, runs the simulated BEEHAVE, and
   returns the result **as a statesnap checkpoint** whose payload is BioDT's
   result table.
4. The frontend writes that table to BioDT's expected output path, so the
   **unchanged** plot module renders it.
5. The checkpoint card can save the model + result to one `.json` and restore it
   later — reproducing a *non-deterministic* run that re-running cannot.

`capture_state(input = list(), ...)` is the key: by never reading `names(input)`,
module namespaces are irrelevant. statesnap operates on the **model**, not widgets.

## Run it (Docker, on your laptop)

```bash
cd whole_apps/honeybee_poc
docker compose up --build
# open http://localhost:7860  -> choose the Honeybee / Beekeeper pDT
# backend health: http://localhost:8000/health
```

The frontend runs with `R_CONFIG_ACTIVE=poc` and reaches the backend at
`http://backend:8000` (compose network).

## Swap in the real BEEHAVE later

Point the backend at `ghcr.io/biodt/beehave:0.3.13` (or set the frontend back to
`executor: docker`). The frontend, adapter, and checkpoint code are unchanged —
the statesnap contract is the same.
