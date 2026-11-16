"""Generate the shared bathymetry test fixtures and their expected results.

The web app (chirp-control-web/src/utils/bathymetry.test.ts) and the mobile
app (chirp_control/test/depth_processing_test.dart) both test their depth
processing against these files and against expected.json, so the two apps
cannot silently drift apart. expected.json is computed here by an independent
Python implementation of the rules documented in the root README
("Data processing").

Run from anywhere:  python3 test-fixtures/bathymetry/generate.py
"""

import json
import math
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent
T0 = 1_760_032_255_069  # 2025-10-09T17:50:55.069Z
SETTLED_WINDOW_S = 30


def write(name, rows, header=None):
    lines = []
    if header:
        lines.append(",".join(header))
    lines += [",".join("" if v is None else str(v) for v in r) for r in rows]
    (HERE / name).write_text("\n".join(lines) + "\n")


# --- reference implementation of the documented rules ----------------------

def trim(samples):
    n = len(samples)
    if n < 10:
        return samples, 0, 0
    times = [s[0] for s in samples]
    span = times[-1] - times[0]
    if span <= 0:
        return samples, 0, 0
    deltas = [b - a for a, b in zip(times, times[1:])]
    median = sorted(deltas)[len(deltas) // 2]
    thr = max(20 * median, 0.15 * span)
    start, end = 0, n
    for i in range(1, n):
        if i / n > 0.15:
            break
        if deltas[i - 1] >= thr:
            start = i
    for i in range(n - 1, 0, -1):
        if (n - i) / n > 0.15:
            break
        if deltas[i - 1] >= thr:
            end = i
    if end - start < 2:
        return samples, 0, 0
    return samples[start:end], start, n - end


def expected(samples, total_rows, incomplete, offset_cm=0.0):
    ordered = sorted(samples)
    kept, lead, trail = trim(ordered)
    depths = [d * 100 + offset_cm for _, d in kept]
    n = len(depths)
    mean = sum(depths) / n
    sd = math.sqrt(sum((v - mean) ** 2 for v in depths) / (n - 1)) if n > 1 else None
    end = kept[-1][0]
    window = [d * 100 + offset_cm for t, d in kept if t >= end - SETTLED_WINDOW_S * 1000]
    return {
        "totalRows": total_rows,
        "incompleteRows": incomplete,
        "droppedLeading": lead,
        "droppedTrailing": trail,
        "used": n,
        "startMs": kept[0][0],
        "endMs": end,
        "avgCm": mean,
        "sdCm": sd,
        "minCm": min(depths),
        "maxCm": max(depths),
        "settledCm": sum(window) / len(window),
        "settledN": len(window),
    }


out = {"settledWindowS": SETTLED_WINDOW_S, "files": {}, "errors": {}}

# 1. Headerless vendor export (2025 format): lat, lon, depth_m, temp_C, time_ms.
#    100 samples, 500 ms apart, depth slowly decreasing (mudline rising).
rows, samples = [], []
for i in range(100):
    t = T0 + i * 500
    d = round(0.600 - 0.0004 * i + 0.002 * ((i * 7) % 3), 3)
    rows.append([0.0, 0.0, d, 22.4, t])
    samples.append((t, d))
write("headerless.csv", rows)
out["files"]["headerless.csv"] = expected(samples, 100, 0)
out["files"]["headerless.csv"]["blindSpotOffset5"] = expected(samples, 100, 0, 5.0)

# 2. Header vendor export (2026 format, note the vendor's "longtitude"), blank
#    lat/lon, three rows with a blank depth, and two stray leading samples ten
#    minutes before the scan (clock not yet synced) that must be trimmed.
rows, samples = [], []
for k in range(2):
    t = T0 - 600_000 + k * 1000
    rows.append([None, None, 0.9, 23.0, t])
    samples.append((t, 0.9))
for i in range(40):
    t = T0 + i * 1000
    d = round(0.450 + 0.001 * (i % 4), 3)
    if i in (5, 6, 30):
        rows.append([None, None, None, 23.0, t])
        continue
    rows.append([None, None, d, 23.0, t])
    samples.append((t, d))
write("header.csv", rows, ["latitude", "longtitude", "depth", "temperature", "time"])
out["files"]["header.csv"] = expected(samples, 42, 3)

# 2b. sonar.csv companion for header.csv (NetCDF echo-profile test): column 0
#     = Unix ms, then echo strengths. Rows have different lengths (as in field
#     exports), a trailing comma, a blank cell, and one row without a timestamp.
sonar_lines = []
for i in range(12):
    t = T0 + i * 1000
    cells = [str((i * 37 + j * 11) % 4097) for j in range(5 + (i % 3))]
    if i == 4:
        cells[2] = ""
    sonar_lines.append(",".join([str(t)] + cells) + ("," if i % 2 == 0 else ""))
sonar_lines.insert(3, ",1,2,3")
(HERE / "header_sonar.csv").write_text("\n".join(sonar_lines) + "\n")

# 3. Rows out of time order. The last rows in the file are NOT the latest in
#    time, so "last N rows in file order" and "last 30 s by time" differ.
rows, samples = [], []
for i in range(80):
    t = T0 + 3_600_000 + i * 1000  # one hour after headerless.csv
    d = round(0.500 + (0.05 if i >= 60 else 0.0), 3)
    rows.append([0.0, 0.0, d, 22.0, t])
    samples.append((t, d))
random.Random(42).shuffle(rows)
rows.sort(key=lambda r: r[2] < 0.52)  # deep (latest-in-time) rows first in the file
write("unsorted.csv", rows)
out["files"]["unsorted.csv"] = expected(samples, 80, 0)

# 4. Signed depth change between headerless.csv (earlier) and unsorted.csv
#    (later), passed in the reverse order to check chronological ordering.
a = out["files"]["headerless.csv"]["settledCm"]
b = out["files"]["unsorted.csv"]["settledCm"]
out["depthChange"] = {"inputs": ["unsorted.csv", "headerless.csv"], "changeCm": b - a,
                      "earliest": "headerless.csv", "latest": "unsorted.csv"}

# 5. Files that must be rejected.
write("swapped.csv", [[0.0, 0.0, 0.5, T0 + i * 500, 22.4] for i in range(20)])
out["errors"]["swapped.csv"] = "timestamp in column 4"
write("missing_time_header.csv", [[0.0, 0.0, 0.5, 22.4] for _ in range(5)],
      ["latitude", "longitude", "depth", "temperature"])
out["errors"]["missing_time_header.csv"] = "missing required column"
write("seconds_timestamp.csv", [[0.0, 0.0, 0.5, 22.4, 1_760_032_255 + i] for i in range(5)])
out["errors"]["seconds_timestamp.csv"] = "not a Unix timestamp in milliseconds"

(HERE / "expected.json").write_text(json.dumps(out, indent=2) + "\n")
print("wrote fixtures to", HERE)
