# Reusable prompt: integrate an existing app into ShinySwarm

Paste this to an AI coding agent working in the Collaborative-RShiny repo. Replace
the **three bracketed fields** at the top, then send. The body encodes the
workflow that produced the BioDT Honeybee integration, including the mistakes to
avoid (inventing the I/O contract; assuming structural symmetry means correct
behaviour).

---

## FILL THESE IN

- **APP TO INTEGRATE:** `[name + upstream repo/URL, e.g. BioDT grassland module @ github.com/BioDT/biodt-shiny]`
- **SHORT NAME (routing key):** `[one PascalCase word, e.g. Grassland]`
- **ARCHITECTURE(S):** `[REST | Kafka | both]`

---

## PROMPT

You are integrating an existing third-party Shiny application into the ShinySwarm
architecture in this repository. The compute backend may be **simulated** (this
environment cannot run the real scientific compute), but the integration must be
faithful in every other respect. Follow this workflow in order. Do not skip the
reading steps — they are the point.

### 1. Learn the host pattern (read, don't assume)
Read two existing ShinySwarm apps **completely** before writing anything:
`shiny_services/map/` and `shiny_services/monte_carlo/` (both front + back), plus
the Spring relay `shinyswarm/.../session/CollaborationController.java` and the
`statesnap/` package. Extract the repeated shape: front/back split, `identity()`
from the URL query string, VIEWER/EDITOR role gating, the POST-then-poll relay
(REST) or Producer/Consumer (Kafka), and how `appName` routes a message.

### 2. Acquire the real source (do NOT reconstruct from description)
Clone/read the **actual** upstream app for `[APP TO INTEGRATE]`. If it is modular,
find the leaf modules that own inputs and outputs. Inventing plausible parameter
names is a failure — the real names are non-negotiable facts.

### 3. Pin the I/O contract exactly
Write down, before coding:
- **Inputs:** where are they produced upstream? Copy every parameter name and
  type verbatim.
- **Outputs:** where are they consumed upstream (the plot/table code)? Copy the
  result schema / column names verbatim, however ugly.
State the contract explicitly in your reply so it can be checked.

### 4. Build by analogy
Clone the template app's structure into
`shiny_services/[app]/shiny_front_*.r` and `shiny_back_*.r`, swapping in the
contract from step 3. Preserve the host's cross-cutting concerns: role gating,
identity, the relay/topic conventions. The backend simulates the compute but must
emit the **exact** output schema. Integrate `statesnap` for reproducible
checkpoints; if the result is plain JSON-serialisable data, prefer capturing it
without `state_rds`/`allow_rds` so cross-user restore stays safe.

### 5. Trace one message of EACH kind end-to-end
For every distinct message/event type the front sends (e.g. a compute request AND
any state-sharing messages like coordinates or table edits), follow it through
**every hop**: front → relay → store → poll → other front (REST), or
front → topic → backend → topic → front (Kafka). Confirm the backend does not
silently drop non-compute messages — echo/re-emit them with a timestamp like the
`map` app does. Structural symmetry is NOT correctness.

### 6. Respect invariants
Before inserting into `DataInitializer.java`, grep for ordering/ID constraints
(existing app IDs are used by k6 benchmarks — append, do not reorder). Wire the
new app into both `DataInitializer.java`, `docker-compose.yml`, `nginx.conf`, and
(REST only) the `APP_ROUTES` map. Note: `Map.of` caps at 10 pairs — switch to
`Map.ofEntries` if you would exceed it.

### 7. Verify cheaply and report honestly
Install R if needed; `parse()` every R file and execute the simulation function
once to confirm it returns the correct output schema. Then state plainly:
- what you verified,
- what you did NOT verify (e.g. full Docker stack not run end-to-end),
- any contract mismatches, dropped message types, or security trade-offs.

### Deliverable
Front + back for the chosen architecture(s), all wiring, an attribution/provenance
header in each new file, and a short summary covering the contract you reproduced,
what ShinySwarm adds over the upstream app, and the honest caveats from step 7.

### Anti-patterns to avoid (these bit the honeybee integration)
1. **Plausible reconstruction** — writing code that looks like the target instead
   of reading its source. Caused invented parameter names.
2. **Symmetry-as-correctness** — matching file shapes without tracing each
   message type. Caused state-sharing messages to be silently dropped.
