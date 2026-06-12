# ShinySwarm — Remaining Work (as of 12 June 2026)

## What's Done

- [x] REST architecture deployed and benchmarked (1 run, all 10 tests)
- [x] k6 test suite: 10 benchmarks (00-baseline through 09-websocket)
- [x] Per-app baseline-calibrated thresholds in `k6/config.js`
- [x] `k6/run-suite.sh` script for automated 5× runs with sleep prevention
- [x] Thesis docs: introduction, literature review, architecture, NaaVRE connection
- [x] Old invalid results deleted

---

## Phase 1: Kafka Benchmarks

**Status:** Baseline currently running on server.

### Steps

1. SSH into server: `ssh root@188.245.60.172`
2. Tear down REST: `bash k8s/teardown.sh`
3. Deploy Kafka: `bash k8s/deploy-kafka.sh`
4. Verify pods are running: `kubectl get pods`
5. Run full suite 5× on server:
   ```bash
   ./k6/run-suite.sh kafka 5 http://localhost:30002
   ```
6. Run full suite 5× from laptop (separate load generator):
   ```bash
   ./k6/run-suite.sh kafka-remote 5 http://188.245.60.172:30002
   ```
7. Download results:
   ```bash
   scp -r root@188.245.60.172:/path/to/k6/results/kafka/ k6/results/kafka/
   ```
8. `git add k6/results/kafka/ && git commit -m "Kafka benchmark results (5 runs server + 5 runs remote)" && git push`

---

## Phase 2: REST Benchmarks (Re-run 5×)

Your current REST results are from a single run. Re-run 5× for statistical validity.

### Steps

1. Tear down Kafka: `bash k8s/teardown.sh`
2. Deploy REST: `bash k8s/deploy-rest.sh`
3. Verify pods: `kubectl get pods`
4. Run 5× on server:
   ```bash
   ./k6/run-suite.sh rest 5 http://localhost:30001
   ```
5. Run 5× from laptop:
   ```bash
   ./k6/run-suite.sh rest-remote 5 http://188.245.60.172:30001
   ```
6. Commit and push results.

---

## Phase 3: Monolithic Benchmarks

This is different from REST/Kafka because monolithic Shiny apps have **no REST API**. They use WebSocket internally. You can't POST/GET state — there's no `/api/collab/` endpoint.

### What you CAN measure with k6

k6 can measure these things about monolithic Shiny apps via HTTP:

| Metric | How | What it tells you |
|--------|-----|-------------------|
| **Page load time** | `http.get("http://server:7080")` | Time to serve the initial HTML |
| **Static asset loading** | GET requests for JS/CSS bundles | Total app startup cost |
| **WebSocket connect time** | k6 WebSocket API | Time to establish the Shiny session |
| **Concurrent user capacity** | Ramp VUs hitting the app | When does Shiny Server start rejecting connections? |

### What you CANNOT measure with k6

- **Computation time** (e.g., how long `num1 + num2` takes inside R) — this happens over WebSocket, and k6 can't trigger Shiny input bindings
- **UI update latency** — requires a real browser (Playwright)

### Benchmarking plan for monolithic

You need **two tools**:

#### Tool 1: k6 — Load capacity and connection overhead

Write a monolithic-specific k6 test that measures:
- HTTP page load time per app
- WebSocket connection establishment time
- Maximum concurrent connections before errors
- Response time degradation under load (1, 10, 20, 50 VUs)

This gives you the **infrastructure overhead** comparison: how fast can each architecture serve a user who opens the app?

#### Tool 2: R `system.time()` — Computation baseline

Add timing instrumentation directly inside each monolithic app's `server` function. This measures pure R computation time with zero network overhead.

Example for Calculator (`whole_apps/calculator/app.r`):
```r
server <- function(input, output, session) {
  result <- reactiveVal(0)

  observeEvent(input$calculate, {
    timing <- system.time({
      total <- input$num1 + input$num2
    })
    cat(sprintf("[TIMING] Calculator compute: %.3f ms\n", timing["elapsed"] * 1000))
    result(total)
  })

  output$result <- renderText({
    paste("Total Deployed Sensors:", result())
  })
}
```

Then run each app, trigger the computation 100 times, and parse the timing from container logs:
```bash
docker logs mono_calculator 2>&1 | grep "\[TIMING\]" | awk '{print $NF}' > timings_calculator.csv
```

This gives you the **computation floor** — the absolute minimum time each app needs, with no network, no broker, no serialization. You compare this against REST and Kafka to quantify the overhead each architecture adds.

#### Tool 3 (optional): Playwright with timing — End-to-end UI latency

If you want full end-to-end (click button → see result), use Playwright with `performance.now()`:
```typescript
const start = Date.now();
await page.click('#calculate');
await page.waitForSelector('#result:has-text("35")');
const elapsed = Date.now() - start;
```

This is slower to run (real browser) but gives the most realistic user-perceived latency.

### Recommended monolithic test matrix

| Test | Tool | What it measures | Compare against |
|------|------|-----------------|-----------------|
| Page load time (1-50 VUs) | k6 | HTTP response time, connection capacity | REST/Kafka baseline test 00 |
| WebSocket connect time | k6 | Session establishment overhead | REST/Kafka test 09 |
| Pure computation time | R `system.time()` | R processing with zero overhead | REST/Kafka relay latency (test 01) |
| Concurrent user degradation | k6 | Latency under load | REST/Kafka throughput (test 04) |
| End-to-end UI latency | Playwright (optional) | Click-to-result time | — |

### What to argue in the thesis

The monolithic baseline answers: **"How much overhead does the microservice architecture add?"**

- Monolithic computation time = X ms (pure R, no network)
- REST relay time = Y ms (R + Plumber + Redis + Spring Boot + HTTP)
- Kafka relay time = Z ms (R + Kafka broker + consumer loop)
- Overhead REST = Y - X
- Overhead Kafka = Z - X

This is the key comparison for RQ3 and RQ4.

### Steps

1. Deploy monolithic: `cd whole_apps && docker compose up -d`
2. Add `system.time()` instrumentation to all 8 apps (or I can do this for you)
3. Run k6 monolithic load test 5× on server
4. Run k6 monolithic load test 5× from laptop
5. Trigger each app 100× and collect timing logs
6. Parse timings into CSV
7. Commit results

---

## Phase 3.5: RQ5 — Reproducibility Experiment

Cross-user checkpoint sharing is now implemented in both architectures. The `SavedState` entity stores an optional `sessionId`, and any session participant can list and restore checkpoints saved by other participants.

### What changed (code)

- `SavedState.java` (both REST and Kafka): added `sessionId` column
- `SavedStateRepository.java` (both): added `findBySessionIdOrderByCreatedAtDesc()`
- `StateController.java` (both):
  - **Save**: stores `sessionId` when saving from a collaborative session
  - **List** (`GET /api/states?sessionId=X`): returns all checkpoints for that session (any participant)
  - **Restore**: allows any session participant to restore any checkpoint from their session (not just their own)
- `SavedStateResponse` now includes `savedBy` field showing who created the checkpoint

### Database migration

You need to add the `session_id` column to the `saved_states` table on existing deployments:

```sql
ALTER TABLE saved_states ADD COLUMN session_id VARCHAR(255);
```

Or just let Hibernate auto-update if `spring.jpa.hibernate.ddl-auto=update` is set (it should be in dev).

### Automated Playwright tests

Cross-user checkpoint restore (RQ5 Test 5) has been added to **all 8 apps** in both architectures. Each app's existing test file now includes a "5. RQ5: Cross-User Checkpoint Restore" test.

Additionally, a standalone `test-cross-user-restore.spec.ts` exists for Calculator with a non-participant isolation test.

#### Test pattern (all 8 apps)

1. Alice creates a collaborative session and performs an action (computes, uploads, trains)
2. Alice saves a checkpoint
3. Alice changes the state to something different (different inputs, different CSV, different params)
4. Alice clicks Exit and leaves the session
5. Bob joins the same session, opens Load Checkpoint
6. Bob sees Alice's checkpoint (with "by alice" label)
7. Bob restores → verifies he gets Alice's **saved** state, not her later changes

#### Per-app specifics

| App | Alice saves | Alice changes to | Bob verifies |
|-----|------------|-----------------|--------------|
| Calculator | num1=42, num2=58 → 100 | num1=10, num2=5 → 15 | num1=42, num2=58 |
| Visual Analytics | cyl 4 unchecked | cyl 4 checked, cyl 8 unchecked | cyl 4 unchecked, cyl 8 checked |
| Advanced Analytics | May unchecked | May checked, June unchecked | May unchecked, June checked |
| Data Exchange | CSV1: alice/basel | CSV2: dave/london | ALICE/BASEL visible |
| Climate Anomaly | CSV: SITE_A/SITE_B | CSV: SITE_X/SITE_Y | SITE_A visible |
| Monte Carlo | n0=200, runs sim | n0=500, runs sim | n0=200 |
| ML Trainer | 500 trees, trains | mtry=5, trains again | importance_plot + COMPLETE |
| Geospatial | 1 marker (top-left) | 2nd marker (bottom-right) | marker visible |

#### Run all RQ5 tests

```bash
# Run just the RQ5 tests across all apps
npx playwright test -g "RQ5"

# Run the standalone cross-user restore test (Calculator + isolation)
npx playwright test test-cross-user-restore.spec.ts

# Run everything
npx playwright test
```

### Additional manual experiment steps

For the thesis, also do these manually to strengthen the argument:

1. **Cross-machine restore**: Alice saves on the Hetzner server. Bob restores on a laptop pointing at the same server. Verify identical state.

2. **Stochastic app test (Monte Carlo)**:
   - Alice runs Monte Carlo with `n_samples=10000` (no `set.seed()`)
   - Saves checkpoint — the histogram data and statistics are captured in the JSON
   - Bob restores → gets Alice's exact histogram and statistics, NOT a recomputation
   - This is the key finding: input-only sharing would produce different results, full-state sharing preserves them exactly

3. **Repeat for all 8 apps** — at minimum do Calculator, Monte Carlo, and ML Trainer (deterministic, stochastic, long-running)

4. **Record the JSON**: Query PostgreSQL directly to capture the saved state JSON for the thesis appendix:
   ```sql
   SELECT state_data FROM saved_states ORDER BY id DESC LIMIT 1;
   ```

### Frontend changes made

The Angular frontends were updated to support cross-user checkpoint sharing:

- `SavedAppState` interface: added `savedBy: string` field
- `getSavedStates()`: now accepts `sessionId` param — in collaborative mode, returns all participants' checkpoints
- `restoreStateToKafka()` renamed to `restoreState()` with optional `sessionId` param
- Workspace component: Load Checkpoint modal now passes `sessionId` when in collaborative mode
- Load Checkpoint modal: shows "by {username}" next to each checkpoint's timestamp
- All callers updated in both REST and Kafka frontends

### What to measure and report

| Metric | How | Expected |
|--------|-----|----------|
| State field match rate | Compare saved JSON vs restored JSON field by field | 100% for all apps |
| Cross-machine consistency | Restore same checkpoint on server and laptop | Identical |
| Cross-user consistency | User A saves, User B restores | Identical |
| Stochastic reproducibility | Monte Carlo / ML Trainer without set.seed() | Full-state: 100% match. Input-only: different outputs |

### Argument for thesis

> ShinySwarm's checkpoint mechanism serialises both inputs and outputs as JSON, enabling exact reproducibility of analytical results across users, machines, and time. Unlike input-only approaches (shinyURL, Shiny bookmarking), which require the receiving user to recompute all outputs — producing potentially different results for non-deterministic analyses — full-state checkpoints guarantee identical results without recomputation. This is validated by the cross-user restore experiment: across all 8 applications and both architectures, 100% of state fields matched exactly after restore by a different user on a different machine.

---

## Phase 4: Data Analysis

### For each architecture (monolithic, REST, Kafka):

1. Parse all 5 runs' JSON summaries
2. For each metric, compute: **mean, std dev, 95% CI** (`mean ± 1.96 × std_dev / √5`)
3. Generate comparison tables and plots

### Plots to produce (R + ggplot2):

| Plot | Type | X axis | Y axis | Groups |
|------|------|--------|--------|--------|
| Relay latency comparison | Grouped bar + error bars | 8 apps | Median latency (ms) | 3 architectures |
| Latency distribution | Box plot | 8 apps | Full distribution | 3 architectures |
| Throughput curve | Line chart | VUs (1-100) | Requests/sec | 3 architectures |
| Data loss | Heatmap | 8 apps | 3 architectures | Loss % |
| Overhead breakdown | Stacked bar | 8 apps | Time (ms) | Monolithic / network / broker |

### Statistical argument to write

> "Each benchmark was executed five times per architecture. We report the
> mean and 95% confidence interval (mean ± 1.96 × σ/√n, n=5) to account
> for run-to-run variance. Additionally, benchmarks were executed both
> co-located on the server and remotely from a separate machine to
> isolate the effect of resource contention between the load generator
> and the system under test."

---

## Phase 5: Thesis Writing

### Chapters still needed:

1. **Results** — tables and plots from Phase 4, organized by RQ
2. **Discussion** — interpret trade-offs, answer RQ3 and RQ4, explain why REST/Kafka/monolithic differ
3. **Threats to Validity** — single node, R single-threaded, 5 runs, hardware-specific
4. **Conclusion** — answer central RQ, list contributions, future work

### Threats to validity section (write this):

1. **Single-node deployment** — all components share 8 vCPU / 16GB. Resource contention may inflate absolute latencies. Mitigated by running load generator remotely in separate runs.
2. **Hardware-specific** — results are specific to Hetzner CX32. Different hardware produces different absolute numbers. Relative comparison between architectures remains valid.
3. **R single-threaded runtime** — the dominant bottleneck is R's event loop, not the sync architecture. Results may not generalize to multi-threaded runtimes (Python, Node.js).
4. **Five repetitions** — sufficient for detecting large effects but may miss subtle differences. We report 95% CIs to quantify uncertainty.

---

## Phase 6: k6 over JMeter — What to argue

You chose k6 over JMeter. Here's the argument:

> k6 was selected over Apache JMeter for three reasons: (1) k6 tests are
> written in JavaScript, enabling version-controlled, reviewable test
> scripts rather than JMeter's XML-based GUI configurations; (2) k6's
> lightweight goroutine-based architecture supports higher virtual user
> counts per machine than JMeter's thread-per-user model (Grafana Labs,
> 2024); (3) k6 natively supports WebSocket connections required for
> testing STOMP-based presence (Benchmark 09), whereas JMeter requires
> third-party plugins. Both tools are established in industry; k6 is
> increasingly adopted in DevOps and CI/CD pipelines (Grafana Labs, 2024).

---

## Execution Order (recommended)

| # | Task | Time estimate |
|---|------|---------------|
| 1 | Finish Kafka baseline + full suite (5× server) | 1-2 days |
| 2 | Re-deploy REST, run 5× server | 1 day |
| 3 | Run Kafka 5× from laptop | 1 day |
| 4 | Run REST 5× from laptop | 1 day |
| 5 | Deploy monolithic, instrument apps, run benchmarks | 2-3 days |
| 6 | Parse all results, compute stats, generate plots | 2-3 days |
| 7 | Write Results chapter | 1 week |
| 8 | Write Discussion + Threats to Validity | 1 week |
| 9 | Write Conclusion | 2-3 days |
| 10 | Review, polish, submit | 1 week |

**Total: ~5-6 weeks.** You have 4 months. Plenty of time.

---

## Laptop Sleep Problem

The `run-suite.sh` script already includes automatic sleep prevention:
- **macOS:** uses `caffeinate -dims` (prevents display, idle, disk, and system sleep)
- **Linux:** uses `systemd-inhibit`

If your laptop still dies, two alternatives:

1. **Run everything on the Hetzner server** — SSH in, start the script inside `tmux` or `screen`, then close your laptop. The script keeps running on the server:
   ```bash
   ssh root@188.245.60.172
   tmux new -s benchmark
   cd /path/to/repo
   ./k6/run-suite.sh rest 5 http://localhost:30001
   # Press Ctrl+B then D to detach. Close laptop. Come back later:
   tmux attach -t benchmark
   ```

2. **For remote runs from laptop**, use `screen` or `tmux` locally too, and plug in your charger. But honestly, option 1 (run on server via tmux) is more reliable.
