# statesnap — Related Work Notes (draft for thesis)

Working notes comparing `statesnap` to existing R/Shiny state-handling tools.
Not polished prose — raw material to read over and research further before
writing the thesis "Related Work" section. Verify every claim against the
linked source before citing.

---

## 1. The one-sentence contribution

`statesnap` captures the **full computed state** of an interactive R/Shiny
session (inputs + registered reactive values + computed outputs) into a single
**transport-agnostic JSON string**, and restores it later **without
recomputation**.

The differentiator no mainstream tool offers: a non-deterministic output (e.g.
an unseeded Monte Carlo result) is reproduced **exactly**, because the computed
*value* is stored — not the recipe to recompute it. No fixed seed required.

Everything else in the ecosystem is **input-only + recompute**.

---

## 2. The main competitor: Shiny native bookmarking

This is the tool to position against. It is the de-facto standard and ships in
Shiny itself (since v0.14). Your thesis MUST compare against this directly.

Docs:
- Basic: https://shiny.posit.co/r/articles/share/bookmarking-state/
- Advanced: https://shiny.posit.co/r/articles/share/advanced-bookmarking/

### How it works
- Enable with `enableBookmarking("url")` or `enableBookmarking("server")`, plus
  the UI must become a **function of `request`** (`ui <- function(request){...}`).
- Two storage modes:
  - **"url"** — entire state encoded in the URL query string.
    - Values visible in URL.
    - Breaks past ~2000 chars (browser URL limit).
    - `fileInput` NOT saved in URL mode.
  - **"server"** — state written to a directory on the host; URL is just an ID
    (`?_state_id_=...`).
    - Requires a hosting env that supports it: Shiny Server (OSS ≥1.4.7),
      Shiny Server Pro, Posit Connect (≥1.4.6). Local `runApp()` writes to
      `shiny_bookmarks/`.
    - Can save extra files.

### What it actually saves
- **Inputs only**, automatically. On restore it **re-seeds the inputs and
  recomputes the reactive graph.**
- Exceptions: `passwordInput` never saved; `fileInput` only in "server" mode.
- Exclude inputs with `setBookmarkExclude(c("x","y"))`.
- Tab/navbar position saved only if you give `tabsetPanel`/`navbarPage` an `id`.
- Action buttons are problematic (operations triggered by them aren't reliably
  reproduced).

### The crucial limitation (this is your wedge)
Quote from the official docs:

> "If the application uses randomly generated numbers somewhere between the
> inputs and outputs, then the restored state of the app may not exactly match
> the bookmarked state. However, it is possible to use `set.seed()` or
> `repeatable()` ... to make the bookmarked state and restored state
> consistent."

And:

> "if the state of the inputs at time t does not fully determine the state of
> the outputs at time t, then the application may not save and restore correctly
> unless you add additional logic."

**This is exactly the gap statesnap fills.** Bookmarking assumes
inputs → outputs is a pure function. When it isn't (stochastic sims, accumulated
state, external API calls, time-dependent computation), bookmarking either
diverges or forces the developer to hand-wire workarounds.

### The hand-wired workaround bookmarking offers: onBookmark / onRestore
For non-pure apps, bookmarking lets you manually save extra values:

```r
onBookmark(function(state)  { state$values$currentSum <- vals$sum })  # save
onRestore(function(state)   { vals$sum <- state$values$currentSum })  # restore
# plus onBookmarked / onRestored for after-the-fact hooks (e.g. update inputs)
```

**Argument for statesnap:** this is manual, per-value, per-app boilerplate. The
developer must enumerate every piece of derived state by hand and write both
directions. statesnap's `capture_state(input, result = result, ...)` registers
reactives by name in one call and round-trips them generically. (Caveat: you
still register reactives by name in statesnap too — R has no API to discover
them automatically — so be honest that statesnap reduces but does not eliminate
this. The win is full-value capture + no recompute + transport independence, not
zero registration.)

### Where bookmarking BEATS statesnap (be honest in thesis)
- Handles **Shiny modules** (namespaced IDs) out of the box. statesnap does not
  yet (documented limitation).
- **URL portability** — share a link, no transport code. statesnap gives you
  JSON and makes transport your problem (deliberate, but more work for the
  simple case).
- Built in, zero dependencies, maintained by Posit.
- `fileInput` handled in server mode (statesnap needs `state_file()` wrapper).

---

## 3. Other ecosystem tools (lesser competitors)

### shinyURL (aoles) — https://github.com/aoles/shinyURL
- Encodes **inputs** into a query URL. Predates / overlaps native bookmarking.
- Input-only. Same ~2000 char URL limit. Action buttons unreliable.
- No outputs, no files, no binary objects.
- Verdict: strictly a subset of what native bookmarking now does. Mention
  briefly as prior art for URL-encoded input sharing.

### shinyStore (trestletech) — https://github.com/trestletech/shinyStore
- Persists arbitrary key/values to the browser via **HTML5 localStorage**.
- Optional RSA encryption (tiny payloads only; needs Shiny Server Pro for the
  identity binding to be meaningful).
- Browser-bound, not transport-agnostic JSON. No reactive-graph awareness, no
  full-state semantics. Different problem (client-side persistence of settings).
- Verdict: orthogonal. Cite as "browser-side persistence" not full-state
  capture.

### shinyjs (daattali) — https://github.com/daattali/shinyjs
- `reset()` resets inputs to defaults. Opposite direction; not capture/restore.
- Not a competitor; mention only if discussing input manipulation.

### Generic serialization: saveRDS / serialize / jsonlite / qs / qs2
- `state_rds()` wrapper IS essentially `serialize()` + gzip + base64. Standard.
- **qs / qs2** (CRAN) serialize R objects much faster and smaller than base.
  - Reviewers WILL ask "why not qs?". Answer: statesnap chose **JSON** on
    purpose — human-inspectable, language-neutral, transport-agnostic (a Java
    Spring backend / Kafka / Redis can read it; an .rds/.qs blob is opaque and
    R-only). qs is faster but binary and R-locked.
  - Note in thesis: statesnap can embed binary via `state_rds()` for the cases
    that genuinely need byte-exact R objects — best of both, with the security
    `allow_rds` gate.
- Verdict: not "state capture" tools, but the obvious building blocks. Show you
  knew about them and chose JSON deliberately.

---

## 4. Comparison table (draft — verify before use)

| Capability | statesnap | Native bookmarking | shinyURL | shinyStore | qs/saveRDS |
|---|---|---|---|---|---|
| Saves inputs | yes | yes | yes | manual | n/a |
| Saves computed outputs / reactives | **yes** | no (recomputes) | no | manual | n/a |
| Non-deterministic result reproduced w/o seed | **yes** | no | no | no | n/a |
| Transport-agnostic (plain JSON out) | **yes** | no (URL/host dir) | no (URL) | no (browser) | no (binary) |
| Human-inspectable format | yes (JSON) | partial (URL) | partial | no | no |
| Files embedded | yes (`state_file`) | server mode only | no | no | manual |
| Arbitrary R objects | yes (`state_rds`) | manual | no | no | yes |
| Shiny modules supported | no (yet) | **yes** | partial | n/a | n/a |
| Treats checkpoint as untrusted input | **yes** | no | no | partial | no |
| Zero transport code for simple share | no | **yes** (URL) | yes | n/a | n/a |
| Built-in / maintained by Posit | no | **yes** | no | no | yes (qs CRAN) |

---

## 5. Security angle (a genuinely under-served gap)

In a **collaborative / cross-user** restore (the ShinySwarm scenario), a
checkpoint authored by user A is loaded by user B → it is **untrusted input**.
None of the competitors treat it that way, because they assume single-user
save/restore of your own session.

statesnap defends against:
- **Path traversal** — embedded filenames reduced to safe basename; reject
  separators, drive letters, `..`.
- **RCE via `unserialize()`** — `state_rds` restore gated behind
  `allow_rds = TRUE`; off by default. (`unserialize` can execute code while
  reconstructing certain objects.)
- **Decompression bomb / memory exhaustion** — `max_size` ceiling enforced
  *during* streaming gunzip, not after.

This is a defensible novel contribution for the collaborative setting. Research:
- OWASP deserialization cheat sheet (for the unserialize argument).
- Any CVEs / writeups on R `unserialize` RCE to cite the threat is real.

---

## 6. Honest gaps / threats to validity (pre-empt the examiner)

- statesnap still requires **manual registration** of reactives by name (R
  limitation, same as bookmarking's onBookmark). Don't overclaim "automatic".
- **Modules not supported yet** — bookmarking wins here.
- **Floating-point not bit-identical** across JSON round-trip (~1e-13); vectors
  come back as lists (`simplifyVector = FALSE`). Documented; frame as inherent
  JSON boundary, with `state_rds()` as the bit-exact escape hatch.
- **fileInput** can't be restored via `sendInputMessage` — must embed with
  `state_file()`.
- No live large-scale benchmark yet vs bookmarking (latency/size). The thesis's
  k6 / architecture benchmarks could supply this — tie it in.

---

## 7. Search status — DONE (2026-06-12)

Checked: Shiny native bookmarking (basic + advanced docs), shinyURL,
shinyStore, shinyjs, generic serialization (qs/saveRDS), CRAN task views,
GitHub repo search, cross-ecosystem (Streamlit/Dash/Jupyter), academic
(Crossref). **No mainstream package found doing transport-agnostic
full-computed-state capture for Shiny.** Details + exact queries below in §9–§11.

---

## 8. Suggested thesis framing (one paragraph, to expand)

Prior art for sharing Shiny application state falls into two camps:
input-encoding approaches (Shiny's native URL/server bookmarking, shinyURL) that
save input values and **recompute** outputs on restore, and client-side
persistence (shinyStore) that stores key/values in the browser. Both assume the
mapping from inputs to outputs is a pure, deterministic function and a
single-user trust boundary. statesnap targets the case both miss: capturing the
**computed output itself** so that non-deterministic analyses reproduce exactly
without a fixed seed, emitting a **transport-agnostic** JSON checkpoint suitable
for a distributed microservice setting, and treating that checkpoint as
**untrusted cross-user input** with explicit defences. Native bookmarking
remains superior for the simple single-user, deterministic, URL-shareable case
and for Shiny modules; statesnap is aimed at collaborative, distributed,
stochastic workloads.

---

## 9. Cross-ecosystem check (verified) — "store result vs store recipe"

The "save the recipe and recompute" vs "save the computed result" distinction is
NOT an R quirk — every interactive-compute ecosystem has the same gap. This
strengthens the thesis: statesnap addresses a general problem in a setting (R/
Shiny + distributed transport + cross-user trust) where no one has.

### Streamlit — `st.session_state`
Docs: https://docs.streamlit.io/develop/concepts/architecture/session-state
- Dict-like per-session store to survive Streamlit's top-to-bottom rerun model.
- **In-memory only. NOT persisted.** "As soon as you close the tab, everything
  ... is lost"; wiped if the server crashes. No built-in export to a portable
  artifact.
- Optional `runner.enforceSerializableSessionState=true` uses **pickle**, which
  the docs explicitly warn is **insecure**: "it is possible to construct
  malicious pickle data that will execute arbitrary code during unpickling ...
  Only load data you trust."
  → SAME threat statesnap gates with `allow_rds` (R's `unserialize` == pickle).
  Cross-ecosystem evidence the security concern is real and under-addressed.
- Cannot set state for `st.button` / `st.file_uploader` via the API
  (cf. statesnap's fileInput / actionButton limitations — universal pattern).

### Dash (Plotly) — `dcc.Store`
Docs: https://dash.plotly.com/dash-core-components/store
- Stores **JSON** in the browser: `storage_type` = memory / local / session.
- Browser-bound (window.localStorage / sessionStorage), ~2MB practical limit.
- Developer-managed per-callback store, NOT an automatic full-app-state capture.
  You hand-write what goes in each Store and wire callbacks to read it.
- Not transport-agnostic (it's a browser store, not an emit-anywhere artifact).
- Closest to statesnap in using JSON, but scope/intent differ: client-side
  caching of selected values vs server-side full-state checkpoint.

### Jupyter notebook (.ipynb)
Docs: https://jupyter-notebook.readthedocs.io/en/stable/notebook.html
- **This is the strongest conceptual analogue to statesnap.** The `.ipynb` is a
  **JSON document storing BOTH inputs (code cells) AND outputs (computed
  results)** — "a complete computational record ... interleaving executable code
  with ... rich representations of resulting objects."
  → Exactly statesnap's thesis: persist the computed result, not just the recipe.
- Has a **trust/signature mechanism**: outputs from untrusted notebooks are not
  rendered until re-executed or explicitly trusted (`jupyter trust`).
  → Direct parallel to statesnap treating a checkpoint as untrusted input +
  the `allow_rds` gate. Cite this as prior art for "computed-output artifacts
  must carry a trust boundary."
- BUT: a notebook captures *cell* outputs of a linear document; it does NOT
  capture live interactive-app / reactive-widget session state, and it is not
  transport-agnostic in the microservice sense. statesnap = the interactive-app
  analogue of what .ipynb is for linear notebooks.

Framing line for thesis: *"A Jupyter .ipynb persists code + computed outputs as
JSON for a linear document; statesnap does the analogous thing for a live,
reactive Shiny session — and adds a transport-agnostic, cross-user-hardened
checkpoint."*

---

## 10. NaaVRE connection (the project anchor — Zhiming Zhao group, UvA)

CONTEXT: supervisor = Zhiming Zhao; this thesis sits alongside the **NaaVRE**
(Notebook-as-a-VRE) line of work. NaaVRE was the starting point. statesnap /
ShinySwarm is, in effect, the **Shiny counterpart of the NaaVRE idea**: take a
private interactive artifact and make it collaborative, cloud-native,
containerized, and shareable in a Virtual Research Environment (VRE).

### Key references (verify DOIs in the actual papers before citing)
- **Zhao, Koulouzis, Bianchi, Farshidi, Shi, Xin, Wang, Li, Shi, Timmermans,
  Kissling (2022). "Notebook-as-a-VRE (NaaVRE): From private notebooks to a
  collaborative cloud virtual research environment." *Software: Practice and
  Experience*. DOI: 10.1002/spe.3098.** ← primary citation.
- Pelouze, Koulouzis, Zhao (2024/2025). "NaaVRE: From private notebooks to a
  collaborative cloud VRE." (EGU egusphere-egu24-17978) — newer iteration.
- Pelouze, Koulouzis, Greuell, Soveizi, Zhao (2025). "NaaVRE: collaborative
  virtual labs to build digital twins of ecosystems." (egusphere-egu25-10262).
- Li, Farshidi, Bianchi, Koulouzis, Zhao (2022). "Context-Aware Notebook Search
  in a Jupyter-Based VRE." IEEE e-Science. DOI: 10.1109/escience55777.2022.00054.
- Shi et al. (2023). LiDAR ecosystem data products via NaaVRE
  (egusphere-egu23-11716) — domain application example.

### How statesnap relates to NaaVRE (thesis framing)
| Dimension | NaaVRE (notebooks) | ShinySwarm / statesnap (Shiny) |
|---|---|---|
| Base artifact | Jupyter notebook cell / sub-workflow | Live Shiny reactive session |
| Goal | private → collaborative cloud VRE | private → collaborative microservice app |
| Unit of sharing | containerized notebook component | JSON full-state checkpoint |
| Reproducibility basis | code + captured outputs (.ipynb), containers | **captured computed state** (no recompute) |
| Infra | Kubernetes, containers, cloud | Kubernetes/Rancher, REST/Kafka/Redis (thesis) |
| State portability | notebook file / component registry | transport-agnostic JSON (statesnap) |

**The gap statesnap fills within the NaaVRE worldview:** NaaVRE makes the
*notebook* a collaborative, reproducible, containerized VRE citizen. But the
*interactive dashboard / Shiny app* — the thing domain scientists actually hand
to collaborators to explore results — has no equivalent mechanism to capture and
move a *live reactive session's full computed state* across a distributed system
in a transport-agnostic, trust-bounded way. statesnap is that missing primitive.
For non-deterministic analyses (the ecosystem/Monte-Carlo simulations NaaVRE's
digital-twin work runs), recompute-on-restore is actively wrong; you must move
the *result*. That is statesnap's contribution, expressed in NaaVRE's language.

Argument to make explicit: ShinySwarm extends the NaaVRE "private → collaborative
cloud VRE" thesis from the linear-notebook modality to the live-interactive-app
modality, with full-state capture as the enabling primitive.

TODO before write-up:
- Read the 2022 SPE NaaVRE paper for its exact reproducibility/state claims and
  its "containerize a notebook component" mechanism — mirror its vocabulary.
- Check whether any NaaVRE paper already discusses interactive-app / dashboard
  state (Shiny, Voila, Panel). If yes, position against it; if no, that absence
  IS your gap statement.
- Look at Voila / Panel / Bokeh server (Jupyter-dashboard bridges) — these turn
  notebooks into interactive apps and may be the nearest neighbor to ShinySwarm
  in the Jupyter world. (Not yet checked — do before final.)

---

## 11. Exact searches run (provenance — so I can re-run / cite method)

Record of WHERE I looked and WITH WHAT, on 2026-06-12. All sources are primary
(official docs / package repos / Crossref / CRAN), not blog hearsay.

### CRAN task views (read in full, grepped for state/session/serial/shiny/
### bookmark/persist/snapshot/checkpoint/reactiv/cache)
- WebTechnologies: https://cran.r-project.org/web/views/WebTechnologies.html
  → only "session/cache" hits were httr/rvest/polite (web scraping). Nothing on
    app-state capture.
- ReproducibleResearch: https://cran.r-project.org/web/views/ReproducibleResearch.html
  → only "snapshot/restore" hits were renv, dateback, containerit, liftr — all
    about PACKAGE/ENV versions, not session/reactive state. Confirms gap.

### GitHub repo search (REST API, sorted by stars)
Endpoint: api.github.com/search/repositories. Queries tried:
- `shiny session state restore language:R`        → 0
- `shiny reactiveValues persist language:R`        → 0
- `shiny state snapshot language:R`                → 0
- `reactive state serialization shiny`             → 0
- `shiny app state save restore language:R`        → 1 → **aoles/shinyURL** (*82)
- `shiny session state language:R`                 → 2 (both unrelated: legislative
                                                     dashboard, coursework)
- `shiny state in:name language:R`                 → 11, only 2 relevant:
   - **mdubel/shiny-conf-sharing-app-state** (*8) — Appsilon ShinyConf 2023 talk
     "Sharing app state between Shiny MODULES". A demo/talk, not a package; about
     modules, uses bookmarking machinery. Not transport-agnostic full-state.
   - **DrRoad/shiny_module_save_restore_state** (*0) — single demo app saving an
     RDS file. Not a package, not JSON, not transport-agnostic.
  → Conclusion: shinyURL is the only starred prior R artifact, and it's
    input-only URL encoding (subset of native bookmarking).

### Cross-ecosystem (official docs, read in full)
- Streamlit session_state (link in §9)
- Dash dcc.Store (link in §9)
- Jupyter notebook docs (link in §9)

### Academic (Crossref REST API; arXiv + Semantic Scholar were blocked/rate-
### limited from this network — retry from a normal connection)
Endpoint: api.crossref.org/works. Queries:
- `Notebook-as-a-VRE containerizing virtual research environment`
- `Notebook-as-a-VRE Zhao Koulouzis collaborative notebook research environment`
  → returned the NaaVRE corpus listed in §10.
- NOT yet done (blocked): broad "computational notebook reproducibility" survey
  search on Semantic Scholar / arXiv. Redo for a general reproducibility-lit
  paragraph. Suggested terms: "computational notebook reproducibility",
  "literate computing reproducibility", "dashboard reproducibility",
  "preserving computational results provenance".

### Search terms that returned NOTHING useful (document the absence — useful for
### a "to the best of our knowledge, no tool exists" statement)
"shiny session snapshot", "shiny full state serialization", "reactiveValues
persistence", "shiny resume session", "transport-agnostic shiny state",
"shiny computed output capture". None map to a maintained package.

---

## 12. Bottom line for the "no equivalent exists" claim

To the best of this search (CRAN task views, GitHub starred repos, cross-
ecosystem docs, Crossref), **no maintained tool — in R or any comparable
interactive-compute ecosystem — provides transport-agnostic capture and restore
of the FULL COMPUTED STATE of a live interactive/reactive session as a portable,
trust-bounded JSON artifact.** The closest neighbours each miss at least one
defining property:
- Shiny bookmarking / shinyURL: input-only, recompute, transport-coupled.
- shinyStore / Dash dcc.Store: browser-bound key-value, not full-state.
- Streamlit session_state: in-memory, not persisted, insecure pickle option.
- Jupyter .ipynb: full inputs+outputs JSON + trust model (closest in spirit) but
  for linear documents, not live reactive apps, and not transport-agnostic.
- renv/containerit etc.: environment/package state, not session state.

statesnap occupies the intersection none of them cover, and does so in exactly
the collaborative-cloud-VRE setting that the NaaVRE line of work (Zhao group)
established for notebooks — extended here to the interactive-app modality.
