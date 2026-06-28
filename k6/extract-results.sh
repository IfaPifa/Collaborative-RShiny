#!/usr/bin/env bash
# ==========================================================================
#  extract-results.sh — Turn raw k6 suite output into tidy CSVs for plotting
#
#  Reads the per-run output produced by run-suite.sh:
#     results/<arch>/run-<N>/<test>-summary.json   (aggregated, tags flattened)
#     results/<arch>/run-<N>/<test>.json.gz        (raw time-series, WITH tags)
#
#  Produces three plot-ready CSVs in results/<arch>/:
#     summary-long.csv    — one row per (run, test, metric, stat)
#                           columns: run,test,metric,avg,med,min,max,p90,p95
#     per-app-long.csv    — one row per (run, test, metric, app_name)
#                           columns: run,test,metric,app_name,count,avg,med,p95
#     per-bucket-long.csv — one row per (run, test, metric, vu_bucket[, app_name])
#                           columns: run,test,metric,vu_bucket,app_name,count,avg,med,p95
#                           (for tests 04/09 that tag the concurrent-user level)
#
#  Both are "long/tidy" format — drop straight into pandas, ggplot, or Excel
#  pivot tables. Plot mean±std across the 5 runs, or facet by app_name.
#
#  Usage:
#     ./k6/extract-results.sh <arch>
#     ./k6/extract-results.sh rest-remote
#
#  Requires: jq
# ==========================================================================
set -euo pipefail

ARCH="${1:?Usage: $0 <arch>   (e.g. rest-remote)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIR="${SCRIPT_DIR}/results/${ARCH}"

[[ -d "$DIR" ]] || { echo "ERROR: $DIR not found"; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 1; }

SUMMARY_CSV="${DIR}/summary-long.csv"
PERAPP_CSV="${DIR}/per-app-long.csv"
PERBUCKET_CSV="${DIR}/per-bucket-long.csv"

echo "run,test,metric,avg,med,min,max,p90,p95" > "$SUMMARY_CSV"
echo "run,test,metric,app_name,count,avg,med,p95" > "$PERAPP_CSV"
echo "run,test,metric,vu_bucket,app_name,count,avg,med,p95" > "$PERBUCKET_CSV"

# ---- 1. Aggregated summary (overall, across all apps) --------------------
for SUMMARY in "$DIR"/run-*/*-summary.json; do
  [[ -e "$SUMMARY" ]] || continue
  RUN=$(basename "$(dirname "$SUMMARY")" | sed 's/run-//')
  TEST=$(basename "$SUMMARY" -summary.json)

  jq -r --arg run "$RUN" --arg test "$TEST" '
    .metrics
    | to_entries[]
    | select(.value.avg != null or .value.p95 != null or .value.count != null)
    | [ $run, $test, .key,
        (.value.avg // ""), (.value.med // ""),
        (.value.min // ""), (.value.max // ""),
        (.value["p(90)"] // ""), (.value["p(95)"] // "") ]
    | @csv
  ' "$SUMMARY" >> "$SUMMARY_CSV"
done

# ---- 2. Per-app breakdown (from raw tagged time-series) ------------------
# k6 raw json is newline-delimited: {"type":"Point","metric":..,"data":{"value":..,"tags":{"app_name":..}}}
# We group Points by (metric, app_name) and compute count/avg/med/p95.
for RAW in "$DIR"/run-*/*.json.gz; do
  [[ -e "$RAW" ]] || continue
  RUN=$(basename "$(dirname "$RAW")" | sed 's/run-//')
  TEST=$(basename "$RAW" .json.gz)

  gzip -dc "$RAW" | jq -rn --arg run "$RUN" --arg test "$TEST" '
    [ inputs
      | select(.type=="Point" and (.data.tags.app_name // "") != "")
      | { metric: .metric, app: .data.tags.app_name, v: .data.value } ]
    | group_by(.metric + "\u0000" + .app)[]
    | ( [ .[].v ] | sort ) as $vals
    | ($vals | length) as $n
    | {
        metric: .[0].metric,
        app:    .[0].app,
        count:  $n,
        avg:    ( ($vals | add) / $n ),
        med:    ( $vals[ (($n-1)/2) | floor ] ),
        p95:    ( $vals[ (($n-1)*0.95) | floor ] )
      }
    | [ $run, $test, .metric, .app, .count, .avg, .med, .p95 ]
    | @csv
  ' >> "$PERAPP_CSV" 2>/dev/null || echo "  [warn] no tagged points in $TEST run $RUN"
done

# ---- 3. Per-VU-bucket breakdown (load-level, optionally per app) ----------
# Only tests that set vu_bucket (04 throughput, 09 websocket) contribute rows.
# Grouped by (metric, vu_bucket, app_name) so you can plot latency vs load,
# faceted by app — e.g. spot the ~20-user breakdown per backend.
for RAW in "$DIR"/run-*/*.json.gz; do
  [[ -e "$RAW" ]] || continue
  RUN=$(basename "$(dirname "$RAW")" | sed 's/run-//')
  TEST=$(basename "$RAW" .json.gz)

  gzip -dc "$RAW" | jq -rn --arg run "$RUN" --arg test "$TEST" '
    [ inputs
      | select(.type=="Point" and (.data.tags.vu_bucket // "") != "")
      | { metric: .metric,
          bucket: .data.tags.vu_bucket,
          app:    (.data.tags.app_name // "ALL"),
          v:      .data.value } ]
    | group_by(.metric + "\u0000" + .bucket + "\u0000" + .app)[]
    | ( [ .[].v ] | sort ) as $vals
    | ($vals | length) as $n
    | {
        metric: .[0].metric,
        bucket: .[0].bucket,
        app:    .[0].app,
        count:  $n,
        avg:    ( ($vals | add) / $n ),
        med:    ( $vals[ (($n-1)/2) | floor ] ),
        p95:    ( $vals[ (($n-1)*0.95) | floor ] )
      }
    | [ $run, $test, .metric, .bucket, .app, .count, .avg, .med, .p95 ]
    | @csv
  ' >> "$PERBUCKET_CSV" 2>/dev/null || true
done

echo ""
echo "=============================================="
echo "  Extraction complete for: ${ARCH}"
echo "  Overall    : ${SUMMARY_CSV}"
echo "               ($(($(wc -l < "$SUMMARY_CSV") - 1)) rows)"
echo "  Per-app    : ${PERAPP_CSV}"
echo "               ($(($(wc -l < "$PERAPP_CSV") - 1)) rows)"
echo "  Per-bucket : ${PERBUCKET_CSV}"
echo "               ($(($(wc -l < "$PERBUCKET_CSV") - 1)) rows)"
echo "=============================================="
echo ""
echo "Plot examples:"
echo "  import pandas as pd"
echo ""
echo "  # (a) relay p95 per app, averaged over runs"
echo "  df = pd.read_csv('${PERAPP_CSV}')"
echo "  r = df[(df.test=='01-state-relay-latency') & (df.metric=='relay_total_ms')]"
echo "  r.groupby('app_name').p95.agg(['mean','std']).plot.bar(y='mean', yerr='std')"
echo ""
echo "  # (b) latency vs concurrent users (the breakdown curve)"
echo "  b = pd.read_csv('${PERBUCKET_CSV}')"
echo "  t = b[(b.test=='04-throughput') & (b.metric=='throughput_response_ms') & (b.app_name=='ALL')]"
echo "  t.groupby('vu_bucket').p95.mean().plot(marker='o')  # x sorts naturally"
echo ""
echo "  # (c) 'X times slower' — divide two buckets"
echo "  piv = t.groupby('vu_bucket').p95.mean()"
echo "  print('20-user p95 / 5-user p95 =', piv['16-20'] / piv['01-05'])"
