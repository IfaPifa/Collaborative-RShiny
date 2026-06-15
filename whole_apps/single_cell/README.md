# Single-Cell (PBMC 3k) + S3 Claim-Check

Hobby-project branch extending ShinySwarm to collaborate on **single-cell
RNA-seq** applications. A large computed object (a ~330 MB Seurat object) is
shared between users **without passing it through the message bus**: the object
is stored in S3-compatible object storage and only a small reference (a
"claim check") rides the bus.

This is the [Claim-Check enterprise integration
pattern](https://www.enterpriseintegrationpatterns.com/patterns/messaging/StoreInLibrary.html)
applied to ShinySwarm's full-state sharing, implemented as a transport option in
the [`statesnap`](../../statesnap) library.

## Why

ShinySwarm shares full application state (inputs **and** computed outputs) so a
collaborator sees an exact, reproducible view without recomputation. A Seurat /
AnnData object routinely reaches hundreds of megabytes, which inline transport
cannot carry:

- **Kafka** defaults to ~1 MB `max.message.bytes`.
- **Redis** is in-memory; multi-hundred-MB blobs evict useful entries.
- **JSON + base64** of a dense object is slow and inflates size ~37%.

The fix: keep the bus for coordination, move the heavy bytes to object storage.

## Result (measured)

| | Inline (before) | Claim-check (after) |
|---|---|---|
| Bus payload for one share | ~462 MB (object as base64 JSON) | **431 bytes** |
| Object integrity on restore | n/a | size + ETag verified |
| Restored object vs original | identical | **byte-identical** |

A 337 MB Seurat object is shared via a 431-byte reference — over 1,000,000×
smaller — and User B reconstructs the exact analysis (same clusters, same UMAP)
with no recomputation.

### Why there are no seeds

The pipeline is **deliberately non-deterministic** — there is no `set.seed()`
anywhere, and Seurat's built-in fixed seeds (`RunPCA`/`RunUMAP` `seed.use = 42`,
`FindClusters` `random.seed = 0`) are replaced with per-run seeds drawn from OS
entropy (`/dev/urandom`). This is the whole point: a fresh re-run of the same
pipeline **diverges** (the demo measures a UMAP coordinate difference of ~7–10).
So when User B's analysis comes back byte-identical to User A's, it can only be
because `statesnap` restored the *computed state* — never because a
recomputation happened to land on the same numbers. Reproducibility here is a
property of state sharing, not of a shared seed.

## How it works

```
User A app ──1. put object──► S3 / MinIO ◄──4. get object── User B app
     │                                                          ▲
     └──────2. reference (KB)──► Kafka / Redis ──3. reference───┘
```

`statesnap` decides per blob: state below a threshold (256 KB) stays inline,
unchanged; a larger `state_rds()` / `state_file()` blob is uploaded and replaced
by a claim-check reference in the JSON. See
[`statesnap/R/s3_transport.R`](../../statesnap/R/s3_transport.R) and the
`s3` / `threshold` arguments of `capture_state()` / `restore_state()`.

The reference is small, JSON-safe and self-describing:

```json
{
  "type": "claim-check", "schema": 1, "store": "s3",
  "bucket": "shinyswarm-state",
  "key": "states/20260615T175954Z-c0398d36.rds",
  "format": "rds", "compressed": true,
  "sizeBytes": 287163623,
  "etag": "4ff6116f10ccbd526a3e7802493c6b46",
  "blobType": "rds", "ttlSeconds": 86400
}
```

`sizeBytes` + `etag` are verified on fetch; `compressed` selects decompression;
`blobType` selects the restore path; `schema` allows forward-compatible
evolution.

## Files

| File | Purpose |
|---|---|
| `pipeline.R` | Seurat PBMC 3k pipeline (load, QC, normalise, PCA, cluster, UMAP). |
| `app.R` | Shiny app: run pipeline, Share state → S3, Restore state from a reference. |
| `demo-claimcheck.R` | Headless A→bus→B demo asserting the acceptance criteria. |
| `data/` | PBMC 3k 10x matrix (downloaded, gitignored). |

## Setup

R 4.x with `Seurat`, `shiny`, `bslib`, `ggplot2`, the local `statesnap` package,
and `paws.storage` (the S3 client). System libraries: `libhdf5-dev`, `libuv1`,
plus the usual `libcurl`/`libssl`/`libxml2` dev headers.

```sh
# 1. Object store (S3-compatible). MinIO standalone binary, no Docker required:
MINIO_ROOT_USER=minio MINIO_ROOT_PASSWORD=minio123 \
  minio server ~/minio-data --address ":9000" --console-address ":9001" &
mc alias set local http://127.0.0.1:9000 minio minio123
mc mb --ignore-existing local/shinyswarm-state

# 2. PBMC 3k dataset:
mkdir -p data && cd data
curl -sSL https://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz \
  | tar xz
cd ..
```

A real AWS S3 endpoint works by changing only `STATESNAP_S3_ENDPOINT` (and
credentials) — the application code is identical.

## Run

Headless end-to-end demo (recommended — proves the claim-check):

```sh
AWS_ACCESS_KEY_ID=minio AWS_SECRET_ACCESS_KEY=minio123 \
STATESNAP_S3_ENDPOINT=http://127.0.0.1:9000 \
Rscript demo-claimcheck.R
```

Interactive app (two browser tabs = User A and User B):

```sh
AWS_ACCESS_KEY_ID=minio AWS_SECRET_ACCESS_KEY=minio123 \
STATESNAP_S3_ENDPOINT=http://127.0.0.1:9000 \
R -e "shiny::runApp('app.R', host='0.0.0.0', port=3838)"
```

In tab A: **Run pipeline** → **Share state**, copy the reference. In tab B:
paste it → **Restore state** to see A's exact analysis.

## Acceptance criteria (all met)

- [x] A single-cell object > 100 MB is shared and restored (337 MB).
- [x] The bus payload for that share stays in the kilobyte range (431 bytes).
- [x] Restored state on User B matches User A (clusters, UMAP, selection).
- [x] Small apps keep using the inline path unchanged.

## Out of scope (later iterations)

TTL-based cleanup of stale objects, spatial transcriptomics, chunked/streaming
transfer, signed URLs / auth on the store, real AWS deployment.

## Security

The claim-check reuses `statesnap`'s defences: `allow_rds` gates
`unserialize()`, decompression is bounded, and filenames are sanitised against
path traversal. Additionally, fetched objects are verified against the
reference's recorded `sizeBytes` and `etag`, so a partial or swapped object is
rejected rather than silently deserialised. The MVP uses plain bucket access on
a local network; signed URLs and auth are a later iteration.
