#!/usr/bin/env python3
# ==========================================================================
#  make_detailed_plots.py - the Gemini-recommended per-benchmark figures.
#
#  Reads <results>/<arch>/raw-points.csv.gz (from extract-raw.py) and renders
#  one figure per benchmark in the chart type best suited to it:
#    00 baseline       grouped bar  (POST/Relay/Save/Restore per app)
#    01 relay          box plot     (latency distribution per app)
#    02 collaboration  line + VUs   (propagation vs active VUs over time)
#    03 save/restore   stacked area (db cycle over time)
#    04 throughput     hockey stick (latency + error vs VU bucket)
#    05 data loss      bar % per app (flat at 0)
#    06 contamination  big-number KPI
#    07 lifecycle      stacked bar  (per-operation latency by VU bucket)
#    08 multi-user     grouped bar  (propagation by group size per app)
#    09 websocket      line         (connect + join roundtrip over time)
#
#  Each figure overlays/compares REST vs Kafka where it makes sense.
#  Usage: python3 analysis/make_detailed_plots.py [results_dir] [out_dir]
# ==========================================================================
import sys, os, gzip
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

RESULTS = sys.argv[1] if len(sys.argv) > 1 else "k6/results"
OUT     = sys.argv[2] if len(sys.argv) > 2 else "analysis/plots"
os.makedirs(OUT, exist_ok=True)

ARCHS  = ["rest", "kafka"]
COLOR  = {"rest": "#1f77b4", "kafka": "#d62728"}
LABEL  = {"rest": "REST (polling)", "kafka": "Kafka (push)"}
APPS   = ["Calculator", "Analytics", "Advanced", "DataExchange",
          "MonteCarlo", "Geospatial", "ClimateAnomaly", "MLTrainer"]

def load(arch):
    f = os.path.join(RESULTS, arch, "raw-points.csv.gz")
    if not os.path.exists(f):
        return None
    df = pd.read_csv(f, dtype={"run": str}, low_memory=False)
    df["value"] = pd.to_numeric(df["value"], errors="coerce")
    return df

DATA = {a: load(a) for a in ARCHS}
DATA = {a: d for a, d in DATA.items() if d is not None}
ARCHS = list(DATA.keys())

def ms_fmt(x, _=None):
    if x >= 1000: return f"{x/1000:.0f}s"
    return f"{x:.0f}ms"

def save(fig, name):
    p = os.path.join(OUT, name)
    fig.savefig(p + ".png", dpi=170, bbox_inches="tight", facecolor="white")
    fig.savefig(p + ".pdf", bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("  wrote", p + ".png")

def app_order(present):
    return [a for a in APPS if a in present]

# ---------------------------------------------------------------------------
# 00 — baseline grouped bar: median POST/Relay/Save/Restore per app
# ---------------------------------------------------------------------------
def fig00():
    # POST varies 12ms..14000ms; Relay/Save/Restore ~5ms; and Kafka Analytics
    # relay is a ~60s timeout anomaly. Three panels per arch keep every bar
    # readable: [ 6 light apps (linear) | MLTrainer | Analytics(anomaly) ].
    ops = [("baseline_post_ms","POST"),("baseline_relay_ms","Relay"),
           ("baseline_save_ms","Save"),("baseline_restore_ms","Restore")]
    heavy = "MLTrainer"; anomaly = "Analytics"
    colors = plt.rcParams['axes.prop_cycle'].by_key()['color'][:len(ops)]
    fig, axes = plt.subplots(
        len(ARCHS), 3, figsize=(15, 4.2*len(ARCHS)),
        gridspec_kw={"width_ratios": [5, 1, 1]}, squeeze=False)
    for r, arch in enumerate(ARCHS):
        d = DATA[arch]
        sub = d[d["test"]=="00-baseline"]
        present = set(sub["app_name"])
        light = [a for a in app_order(present) if a not in (heavy, anomaly)]

        def med_for(app):
            return [sub[(sub.app_name==app)&(sub.metric==m)]["value"].median() for m,_ in ops]

        # --- left: light apps, linear, grouped ---
        axL = axes[r][0]
        x = np.arange(len(light)); w = 0.2
        for i,(metric,lab) in enumerate(ops):
            med = [sub[(sub.app_name==a)&(sub.metric==metric)]["value"].median() for a in light]
            bars = axL.bar(x + (i-1.5)*w, med, w, label=lab, color=colors[i])
            axL.bar_label(bars, fmt="%.0f", fontsize=6, padding=1)
        axL.set_xticks(x); axL.set_xticklabels(light, rotation=30, ha="right", fontsize=8)
        axL.set_ylabel("median latency (ms, linear)")
        axL.set_title(f"{LABEL[arch]} - light apps")
        axL.legend(fontsize=8, ncol=4, loc="upper right")
        axL.grid(axis="y", alpha=0.3)

        # --- middle: MLTrainer (POST dominates, log) ---
        axM = axes[r][1]
        if heavy in present:
            med = med_for(heavy)
            bars = axM.bar([l for _,l in ops], med, color=colors)
            axM.bar_label(bars, labels=[ms_fmt(v) for v in med], fontsize=7, padding=1)
            axM.set_yscale("log"); axM.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
            axM.set_title(f"{heavy}\n(POST = R model training)", fontsize=9)
            axM.tick_params(axis="x", labelrotation=30, labelsize=7)
            axM.grid(axis="y", alpha=0.3)

        # --- right: Analytics (relay anomaly on Kafka, log) ---
        axR = axes[r][2]
        if anomaly in present:
            med = med_for(anomaly)
            bars = axR.bar([l for _,l in ops], med, color=colors)
            axR.bar_label(bars, labels=[ms_fmt(v) for v in med], fontsize=7, padding=1)
            axR.set_yscale("log"); axR.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
            relay_med = med[1]
            note = " - RELAY ~60s\n(propagation anomaly)" if relay_med and relay_med > 5000 else ""
            axR.set_title(f"{anomaly}{note}", fontsize=9,
                          color=("#c0392b" if note else "black"))
            axR.tick_params(axis="x", labelrotation=30, labelsize=7)
            axR.grid(axis="y", alpha=0.3)
    fig.suptitle("Benchmark 00 - Single-user baseline latency per operation (control group)\n"
                 "POST = send state + backend ack (app compute) | Relay = becomes visible to others "
                 "| Save/Restore = PostgreSQL checkpoint",
                 fontweight="bold", fontsize=10)
    fig.tight_layout(rect=[0,0,1,0.94])
    save(fig, "fig00_baseline_ops")

# ---------------------------------------------------------------------------
# 01 — relay latency distribution: box plot per app, REST vs Kafka
# ---------------------------------------------------------------------------
def fig01():
    # MLTrainer (intrinsic R compute) and Kafka Analytics (propagation defect)
    # are ~1000x the others and crush the box plot. Split each to its own PNG.
    outliers = ["MLTrainer", "Analytics"]
    metric = "relay_total_ms"; test = "01-state-relay-latency"

    def boxes(ax, arch, apps, logscale):
        d = DATA[arch]
        sub = d[(d["test"]==test) & (d["metric"]==metric)]
        apps = [a for a in apps if a in set(sub["app_name"])]
        data = [sub[sub.app_name==a]["value"].dropna().values for a in apps]
        bp = ax.boxplot(data, labels=apps, showfliers=False, patch_artist=True)
        for patch in bp["boxes"]:
            patch.set_facecolor(COLOR[arch]); patch.set_alpha(0.5)
        ax.set_xticklabels(apps, rotation=35, ha="right", fontsize=8)
        if logscale: ax.set_yscale("log")
        ax.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
        ax.set_title(LABEL[arch]); ax.set_ylabel("relay round-trip")
        ax.grid(axis="y", alpha=0.3)

    # --- PNG 1: light apps (excludes MLTrainer + Analytics) ---
    light = [a for a in APPS if a not in outliers]
    fig, axes = plt.subplots(1, len(ARCHS), figsize=(7*len(ARCHS), 4.8), sharey=False)
    if len(ARCHS) == 1: axes=[axes]
    for ax, arch in zip(axes, ARCHS):
        boxes(ax, arch, light, logscale=True)
    fig.suptitle("Benchmark 01 - State relay latency distribution (light apps; MLTrainer + Analytics excluded)",
                 fontweight="bold")
    save(fig, "fig01_relay_box")

    # --- PNG 2: MLTrainer alone ---
    fig2, axes2 = plt.subplots(1, len(ARCHS), figsize=(4*len(ARCHS), 4.5), sharey=True)
    if len(ARCHS) == 1: axes2=[axes2]
    for ax, arch in zip(axes2, ARCHS):
        boxes(ax, arch, ["MLTrainer"], logscale=False)
        ax.set_xticklabels(["MLTrainer"], rotation=0)
    fig2.suptitle("Benchmark 01 - State relay latency: MLTrainer (intrinsic R compute)",
                  fontweight="bold")
    save(fig2, "fig01_relay_box_mltrainer")

    # --- PNG 3: Analytics alone ---
    fig3, axes3 = plt.subplots(1, len(ARCHS), figsize=(4*len(ARCHS), 4.5), sharey=True)
    if len(ARCHS) == 1: axes3=[axes3]
    for ax, arch in zip(axes3, ARCHS):
        boxes(ax, arch, ["Analytics"], logscale=False)
        ax.set_xticklabels(["Analytics"], rotation=0)
    fig3.suptitle("Benchmark 01 - State relay latency: Analytics (Kafka propagation defect)",
                  fontweight="bold")
    save(fig3, "fig01_relay_box_analytics")

# ---------------------------------------------------------------------------
# 01b — REST vs Kafka relay, light apps only: median vs p95 grouped bars.
#       Shows the trade-off: REST wins the median, Kafka wins the tail.
# ---------------------------------------------------------------------------
def fig01_medp95():
    outliers = ["MLTrainer", "Analytics"]
    light = [a for a in APPS if a not in outliers]
    test = "01-state-relay-latency"; metric = "relay_total_ms"

    def agg(stat):
        out = {arch: [] for arch in ARCHS}
        present = []
        for a in light:
            vals = {}
            for arch in ARCHS:
                d = DATA[arch]
                sub = d[(d["test"]==test) & (d["metric"]==metric) &
                        (d["app_name"]==a)]["value"].dropna()
                vals[arch] = (sub.median() if stat=="median"
                              else sub.quantile(0.95)) if len(sub) else None
            if all(vals[arch] is not None for arch in ARCHS):
                present.append(a)
                for arch in ARCHS: out[arch].append(vals[arch])
        return present, out

    def panel(ax, stat, title):
        apps, out = agg(stat)
        x = range(len(apps)); w = 0.8/len(ARCHS)
        for i, arch in enumerate(ARCHS):
            off = (i - (len(ARCHS)-1)/2) * w
            bars = ax.bar([p+off for p in x], out[arch], w,
                          label=LABEL[arch], color=COLOR[arch], alpha=0.85)
            ax.bar_label(bars, labels=[ms_fmt(v) for v in out[arch]],
                         fontsize=7, padding=2)
        ax.set_xticks(list(x)); ax.set_xticklabels(apps, rotation=35, ha="right", fontsize=8)
        ax.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
        ax.set_title(title); ax.set_ylabel("relay round-trip"); ax.legend()
        ax.grid(axis="y", alpha=0.3)

    # PNG 1: median
    fig, ax = plt.subplots(figsize=(10, 5))
    panel(ax, "median", "Benchmark 01 - relay latency MEDIAN (light apps)")
    fig.text(0.5, -0.02, "Typical case: REST is faster (catches update on next poll).",
             ha="center", fontsize=8, style="italic")
    save(fig, "fig01_relay_median")

    # PNG 2: p95 (tail)
    fig2, ax2 = plt.subplots(figsize=(10, 5))
    panel(ax2, "p95", "Benchmark 01 - relay latency p95 / tail (light apps)")
    fig2.text(0.5, -0.02, "Worst case: Kafka is bounded (~280ms); REST tail blows out to seconds under contention.",
              ha="center", fontsize=8, style="italic")
    save(fig2, "fig01_relay_p95")

# ---------------------------------------------------------------------------
# levels — REST vs Kafka across the 3 latency levels (POST / Collab / Save /
#          Restore), light apps only (MLTrainer + Analytics excluded).
#          Two PNGs: median and p95.
# ---------------------------------------------------------------------------
def fig_levels():
    outliers = ["MLTrainer", "Analytics"]
    light = [a for a in APPS if a not in outliers]
    levels = [("01-state-relay-latency","relay_post_ms","POST\n(send to backend)"),
              ("02-collaboration-latency","collab_propagation_ms","Collab\n(propagate to peer)"),
              ("03-save-restore-latency","save_to_db_ms","Save\n(write to DB)"),
              ("03-save-restore-latency","restore_from_db_ms","Restore\n(read from DB)")]

    def series(stat):
        out = {arch: [] for arch in ARCHS}
        for test, metric, _ in levels:
            for arch in ARCHS:
                d = DATA[arch]
                sub = d[(d["test"]==test) & (d["metric"]==metric) &
                        (d["app_name"].isin(light))]["value"].dropna()
                v = (sub.median() if stat=="median" else sub.quantile(0.95)) if len(sub) else 0
                out[arch].append(v)
        return out

    def panel(stat, title, sub, slug, logscale):
        out = series(stat)
        labs = [l[2] for l in levels]
        x = np.arange(len(levels)); w = 0.8/len(ARCHS)
        fig, ax = plt.subplots(figsize=(10, 5))
        for i, arch in enumerate(ARCHS):
            off = (i-(len(ARCHS)-1)/2)*w
            bars = ax.bar(x+off, out[arch], w, label=LABEL[arch],
                          color=COLOR[arch], alpha=0.85)
            ax.bar_label(bars, labels=[ms_fmt(v) for v in out[arch]],
                         fontsize=7, padding=2)
        ax.set_xticks(x); ax.set_xticklabels(labs, fontsize=8)
        if logscale: ax.set_yscale("log")
        ax.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
        ax.set_ylabel("latency"); ax.set_title(title, fontweight="bold")
        ax.legend(); ax.grid(axis="y", alpha=0.3)
        fig.text(0.5, -0.03, sub, ha="center", fontsize=8, style="italic")
        save(fig, slug)

    panel("median", "Latency by level - MEDIAN (light apps; MLTrainer + Analytics excluded)",
          "Three measured levels: send, propagate, persist. REST faster typically; Kafka POST near-instant.",
          "fig_levels_median", logscale=True)
    panel("p95", "Latency by level - p95 / tail (light apps; MLTrainer + Analytics excluded)",
          "Worst case: REST tail blows out on POST/Collab/Save; Kafka stays bounded.",
          "fig_levels_p95", logscale=True)

# ---------------------------------------------------------------------------
# 02 — collaboration: propagation latency vs active VUs over time (dual axis)
# ---------------------------------------------------------------------------
def fig02():
    fig, ax = plt.subplots(figsize=(11, 5))
    ax2 = ax.twinx()
    for arch in ARCHS:
        d = DATA[arch]
        sub = d[(d["test"]=="02-collaboration-latency") &
                (d["metric"]=="collab_propagation_ms")].copy()
        if sub.empty: continue
        sub["t"] = pd.to_datetime(sub["time"], errors="coerce")
        sub = sub.dropna(subset=["t"]).sort_values("t")
        # one run only for a clean time axis: pick run with most points
        run = sub["run"].value_counts().idxmax()
        sub = sub[sub["run"]==run]
        t0 = sub["t"].min()
        sub["sec"] = (sub["t"]-t0).dt.total_seconds()
        # rolling median over 5s bins
        sub["bin"] = (sub["sec"]//5)*5
        g = sub.groupby("bin")["value"].median()
        ax.plot(g.index, g.values, color=COLOR[arch], label=LABEL[arch], lw=1.8)
    ax.set_xlabel("time into test (s)")
    ax.set_ylabel("propagation latency p50 (ms)")
    ax.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
    ax.set_title("Benchmark 02 - Cross-user propagation latency over the test (per-arch, busiest run)",
                 fontweight="bold")
    ax.legend(loc="upper left"); ax.grid(alpha=0.3)
    ax2.set_ylabel("(VU ramp shape)")
    ax2.set_yticks([])
    save(fig, "fig02_collab_timeseries")

# ---------------------------------------------------------------------------
# 03 — save/restore: stacked area of db cycle over time
# ---------------------------------------------------------------------------
def fig03():
    parts = [("save_to_db_ms","save"),("list_states_ms","list"),
             ("restore_from_db_ms","restore")]
    fig, axes = plt.subplots(1, len(ARCHS), figsize=(7*len(ARCHS), 4.5), sharey=True)
    if len(ARCHS) == 1: axes=[axes]
    for ax, arch in zip(axes, ARCHS):
        d = DATA[arch]
        sub = d[d["test"]=="03-save-restore-latency"].copy()
        sub["t"] = pd.to_datetime(sub["time"], errors="coerce")
        sub = sub.dropna(subset=["t"])
        if sub.empty: continue
        run = sub["run"].value_counts().idxmax()
        sub = sub[sub["run"]==run]
        t0 = sub["t"].min(); sub["sec"]=(sub["t"]-t0).dt.total_seconds()
        sub["bin"]=(sub["sec"]//10)*10
        series = {}
        for metric,lab in parts:
            g = sub[sub.metric==metric].groupby("bin")["value"].median()
            series[lab]=g
        idx = sorted(set().union(*[set(s.index) for s in series.values()])) if series else []
        ys = [series[lab].reindex(idx).fillna(0).values for _,lab in parts]
        ax.stackplot(idx, *ys, labels=[lab for _,lab in parts], alpha=0.8)
        ax.set_xlabel("time into test (s)"); ax.set_ylabel("db cycle (ms)")
        ax.set_title(LABEL[arch]); ax.legend(loc="upper left", fontsize=8)
        ax.grid(alpha=0.3)
    fig.suptitle("Benchmark 03 - Database save/list/restore cycle over time",
                 fontweight="bold")
    save(fig, "fig03_saverestore_area")

# ---------------------------------------------------------------------------
# 04 — throughput hockey stick: latency + error vs VU bucket
# ---------------------------------------------------------------------------
def vu_sort_key(b):
    try: return int(str(b).split("-")[0])
    except: return 9999

def fig04():
    fig, ax = plt.subplots(figsize=(11, 5))
    ax2 = ax.twinx()
    for arch in ARCHS:
        d = DATA[arch]
        sub = d[(d["test"]=="04-throughput") &
                (d["metric"]=="throughput_response_ms")]
        sub = sub[sub["vu_bucket"].astype(str).str.match(r"\d+-\d+")]
        if sub.empty: continue
        g = sub.groupby("vu_bucket")["value"].quantile(0.95)
        buckets = sorted(g.index, key=vu_sort_key)
        ax.plot(range(len(buckets)), [g[b] for b in buckets],
                marker="o", color=COLOR[arch], label=LABEL[arch], lw=2)
        # error rate per bucket
        err = d[(d["test"]=="04-throughput") & (d["metric"]=="throughput_errors")]
        if not err.empty:
            eg = err.groupby("vu_bucket")["value"].mean()
            ax2.plot(range(len(buckets)), [eg.get(b,0)*100 for b in buckets],
                     marker="x", ls="--", color=COLOR[arch], alpha=0.5)
    ax.set_xticks(range(len(buckets))); ax.set_xticklabels(buckets, rotation=45, fontsize=7)
    ax.set_xlabel("concurrent users (VU bucket)")
    ax.set_ylabel("response p95"); ax.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
    ax2.set_ylabel("error rate % (dashed)")
    ax.set_title("Benchmark 04 - Throughput: latency p95 (solid) & error rate (dashed) vs load",
                 fontweight="bold")
    ax.legend(loc="upper left"); ax.grid(alpha=0.3)
    save(fig, "fig04_throughput_hockey")

# ---------------------------------------------------------------------------
# 05 — data loss bar % per app
# ---------------------------------------------------------------------------
def fig05():
    fig, ax = plt.subplots(figsize=(10, 4.5))
    x = np.arange(len(APPS)); w = 0.38
    for i,arch in enumerate(ARCHS):
        d = DATA[arch]
        sub = d[(d["test"]=="05-data-loss") & (d["metric"]=="dataloss_pct")]
        vals = []
        for a in APPS:
            v = sub[sub.app_name==a]["value"]
            vals.append(v.mean() if len(v) else (sub["value"].mean() if a==APPS[0] and sub.app_name.eq("").all() else 0))
        # if not tagged per app, show overall as flat
        if sub["app_name"].replace("", np.nan).isna().all():
            overall = sub["value"].mean() if len(sub) else 0
            vals = [overall]*len(APPS)
        ax.bar(x + (i-0.5)*w, vals, w, label=LABEL[arch], color=COLOR[arch], alpha=0.8)
    ax.set_xticks(x); ax.set_xticklabels(APPS, rotation=35, ha="right", fontsize=8)
    ax.set_ylabel("data loss %"); ax.set_ylim(0, 5)
    ax.axhline(0, color="green", lw=1)
    ax.set_title("Benchmark 05 - Data loss under load (target: 0%)", fontweight="bold")
    ax.legend(); ax.grid(axis="y", alpha=0.3)
    save(fig, "fig05_dataloss")

# ---------------------------------------------------------------------------
# 06 — contamination big-number KPI
# ---------------------------------------------------------------------------
def fig06():
    fig, axes = plt.subplots(1, len(ARCHS), figsize=(5*len(ARCHS), 3.2))
    if len(ARCHS) == 1: axes=[axes]
    for ax, arch in zip(axes, ARCHS):
        d = DATA[arch]
        sub = d[(d["test"]=="06-cross-contamination") & (d["metric"]=="contamination_events")]
        total = int(sub["value"].sum()) if len(sub) else 0
        ax.axis("off")
        color = "#2e8b57" if total==0 else "#c0392b"
        ax.text(0.5, 0.62, str(total), ha="center", va="center",
                fontsize=64, fontweight="bold", color=color)
        ax.text(0.5, 0.22, "contamination events", ha="center", fontsize=12)
        ax.text(0.5, 0.92, LABEL[arch], ha="center", fontsize=13, fontweight="bold")
    fig.suptitle("Benchmark 06 - Session isolation (target: 0 events)", fontweight="bold")
    save(fig, "fig06_contamination_kpi")

# ---------------------------------------------------------------------------
# 07 — lifecycle stacked bar: per-operation median latency by VU bucket
# ---------------------------------------------------------------------------
def fig07():
    fig, axes = plt.subplots(1, len(ARCHS), figsize=(8*len(ARCHS), 5), sharey=True)
    if len(ARCHS) == 1: axes=[axes]
    for ax, arch in zip(axes, ARCHS):
        d = DATA[arch]
        sub = d[(d["test"]=="07-session-lifecycle") & (d["metric"]=="lifecycle_op_ms")]
        sub = sub[sub["vu_bucket"].astype(str).str.match(r"\d+-\d+")]
        if sub.empty: continue
        buckets = sorted(sub["vu_bucket"].unique(), key=vu_sort_key)
        ops = sorted(sub["operation"].unique())
        bottom = np.zeros(len(buckets))
        for op in ops:
            med = [sub[(sub.vu_bucket==b)&(sub.operation==op)]["value"].median() or 0 for b in buckets]
            med = np.nan_to_num(med)
            ax.bar(range(len(buckets)), med, bottom=bottom, label=op)
            bottom += med
        ax.set_xticks(range(len(buckets))); ax.set_xticklabels(buckets, rotation=45, fontsize=7)
        ax.set_xlabel("concurrent users"); ax.set_ylabel("stacked median op latency (ms)")
        ax.set_title(LABEL[arch]); ax.legend(fontsize=6, ncol=2, loc="upper left")
        ax.grid(axis="y", alpha=0.3)
    fig.suptitle("Benchmark 07 - Lifecycle: per-operation latency by load", fontweight="bold")
    save(fig, "fig07_lifecycle_stacked")

# ---------------------------------------------------------------------------
# 08 — multi-user grouped bar: propagation by group size per app
# ---------------------------------------------------------------------------
def fig08():
    fig, axes = plt.subplots(1, len(ARCHS), figsize=(8*len(ARCHS), 4.8), sharey=True)
    if len(ARCHS) == 1: axes=[axes]
    sizes = ["3","5","10"]
    for ax, arch in zip(axes, ARCHS):
        d = DATA[arch]
        sub = d[(d["test"]=="08-multi-user-collab") & (d["metric"]=="multi_propagation_all_ms")]
        apps = app_order(set(sub["app_name"]))
        x = np.arange(len(apps)); w = 0.26
        has_size = sub["group_size"].astype(str).isin(sizes).any()
        if has_size:
            for i,s in enumerate(sizes):
                med = [sub[(sub.app_name==a)&(sub.group_size.astype(str)==s)]["value"].median() for a in apps]
                med = [0 if pd.isna(v) else v for v in med]
                ax.bar(x+(i-1)*w, med, w, label=f"group {s}")
        else:
            med = [sub[sub.app_name==a]["value"].median() for a in apps]
            med = [0 if pd.isna(v) else v for v in med]
            ax.bar(x, med, 0.6, label="all guests")
        ax.set_xticks(x); ax.set_xticklabels(apps, rotation=35, ha="right", fontsize=8)
        ax.set_ylabel("propagation to all guests (ms)")
        ax.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
        ax.set_title(LABEL[arch]); ax.legend(fontsize=8); ax.grid(axis="y", alpha=0.3)
    fig.suptitle("Benchmark 08 - Multi-user fan-out latency by group size", fontweight="bold")
    save(fig, "fig08_multiuser_grouped")

# ---------------------------------------------------------------------------
# 09 — websocket: connect + join roundtrip over time
# ---------------------------------------------------------------------------
def fig09():
    fig, ax = plt.subplots(figsize=(11, 5))
    for arch in ARCHS:
        d = DATA[arch]
        for metric, ls, lab in [("ws_connect_ms","-","connect"),
                                ("ws_join_roundtrip_ms","--","join RT")]:
            sub = d[(d["test"]=="09-websocket-presence") & (d["metric"]==metric)].copy()
            if sub.empty: continue
            sub["t"]=pd.to_datetime(sub["time"], errors="coerce")
            sub=sub.dropna(subset=["t"])
            run = sub["run"].value_counts().idxmax(); sub=sub[sub["run"]==run]
            t0=sub["t"].min(); sub["sec"]=(sub["t"]-t0).dt.total_seconds()
            sub["bin"]=(sub["sec"]//5)*5
            g=sub.groupby("bin")["value"].quantile(0.95)
            ax.plot(g.index, g.values, ls=ls, color=COLOR[arch],
                    label=f"{LABEL[arch]} - {lab}", lw=1.6)
    ax.set_xlabel("time into test (s)"); ax.set_ylabel("p95 latency")
    ax.yaxis.set_major_formatter(FuncFormatter(ms_fmt))
    ax.set_title("Benchmark 09 - WebSocket connect & JOIN roundtrip over time (p95)",
                 fontweight="bold")
    ax.legend(fontsize=8); ax.grid(alpha=0.3)
    save(fig, "fig09_websocket_timeseries")

# ---------------------------------------------------------------------------
ALL = {"00":fig00,"01":fig01,"01b":fig01_medp95,"levels":fig_levels,
       "02":fig02,"03":fig03,"04":fig04,
       "05":fig05,"06":fig06,"07":fig07,"08":fig08,"09":fig09}
want = sys.argv[3:] if len(sys.argv) > 3 else list(ALL.keys())
print(f"Detailed plots -> {OUT}  (archs: {', '.join(ARCHS)})")
for k in want:
    try:
        ALL[k]()
    except Exception as e:
        import traceback
        print(f"  [skip {k}] {e}")
        traceback.print_exc()
print("Done.")
