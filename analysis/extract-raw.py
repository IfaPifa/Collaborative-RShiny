#!/usr/bin/env python3
# ==========================================================================
#  extract-raw.py - parse k6 raw .json.gz into tidy per-metric CSVs that
#  PRESERVE per-point detail the summary CSVs drop: timestamp, app_name,
#  operation, group_size, vu_bucket. Output feeds the detailed figures.
#
#  Usage: python3 analysis/extract-raw.py [results_dir] [arch1 arch2 ...]
#  Writes: <results_dir>/<arch>/raw-points.csv.gz  (one row per data point
#          for the metrics we care about) and a small derived
#          <arch>/baseline-ops.csv for test 00.
# ==========================================================================
import sys, os, gzip, json, glob, csv

RESULTS = sys.argv[1] if len(sys.argv) > 1 else "k6/results"
ARCHS   = sys.argv[2:] if len(sys.argv) > 2 else ["rest", "kafka"]

# metrics we keep (all the *_ms latency trends + a few counters/rates)
KEEP_PREFIX = (
    "baseline_", "relay_total_ms", "relay_post_ms", "relay_poll_ms",
    "collab_propagation_ms", "collab_host_post_ms",
    "save_to_db_ms", "restore_from_db_ms", "list_states_ms", "restore_verify_ms",
    "throughput_response_ms", "throughput_ops", "throughput_errors",
    "dataloss_pct", "contamination_events",
    "lifecycle_op_ms",
    "multi_propagation_all_ms", "multi_propagation_first_ms",
    "ws_connect_ms", "ws_join_roundtrip_ms",
    "http_reqs", "http_req_duration",
)

def keep(metric):
    return any(metric == p or metric.startswith(p) for p in KEEP_PREFIX)

TAGS = ("app_name", "operation", "group_size", "vu_bucket", "scenario", "status")

def test_name_from_path(p):
    base = os.path.basename(p)
    return base[:-len(".json.gz")]

for arch in ARCHS:
    adir = os.path.join(RESULTS, arch)
    if not os.path.isdir(adir):
        print(f"skip {arch}: no dir"); continue
    out_path = os.path.join(adir, "raw-points.csv.gz")
    n_in = n_out = 0
    with gzip.open(out_path, "wt", newline="") as fo:
        w = csv.writer(fo)
        w.writerow(["run", "test", "metric", "time", "value"] + list(TAGS))
        for gzf in sorted(glob.glob(os.path.join(adir, "run-*", "*.json.gz"))):
            run = os.path.basename(os.path.dirname(gzf)).replace("run-", "")
            test = test_name_from_path(gzf)
            try:
                with gzip.open(gzf, "rt") as fi:
                    for line in fi:
                        line = line.strip()
                        if not line or '"type":"Point"' not in line:
                            continue
                        n_in += 1
                        try:
                            o = json.loads(line)
                        except Exception:
                            continue
                        m = o.get("metric", "")
                        if not keep(m):
                            continue
                        d = o.get("data", {})
                        tags = d.get("tags", {}) or {}
                        w.writerow([run, test, m, d.get("time", ""), d.get("value", "")]
                                   + [tags.get(t, "") for t in TAGS])
                        n_out += 1
            except Exception as e:
                print(f"  warn {gzf}: {e}")
    print(f"{arch}: scanned {n_in:,} points -> kept {n_out:,} -> {out_path}")
