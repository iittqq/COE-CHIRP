"""Bathymetry loading and statistics for the analysis notebook.

Implements the same documented rules as the web app
(chirp-control-web/src/utils/bathymetry.ts) and the mobile app
(chirp_control/lib/utils/depth_processing.dart), and is tested against the
same fixtures (test-fixtures/bathymetry/) in test_chirp_bathymetry.py. The
rules are described in the root README, section "Data processing".

Summary:
  * Columns are read by header name when the file has a header row
    (the vendor's 2026 exports: latitude,longtitude,depth,temperature,time)
    and by position otherwise (2025 exports: lat, lon, depth_m, temp_C,
    time_ms). Files that match neither raise BathymetryFormatError.
  * Samples are sorted by time; rows with a blank depth or time are skipped.
  * Small leading/trailing groups of samples separated from the scan by a
    large time gap are removed (time-island trimming).
  * Depth is metres below the transducer face; a blind-spot offset (cm) is
    added only when given explicitly. The default is 0 (no correction).
"""

from __future__ import annotations

import csv
import math
import re
from dataclasses import dataclass, field
from pathlib import Path

HEADERLESS_COLUMN_ORDER = ["latitude", "longitude", "depth", "temperature", "time"]

HEADER_ALIASES = {
    "latitude": ["latitude", "lat", "latitudedeg"],
    "longitude": ["longitude", "longtitude", "lon", "lng", "longitudedeg"],
    "depth": ["depth", "depthm"],
    "temperature": ["temperature", "temp", "temperaturec"],
    "time": ["time", "timestamp", "timems", "timestampms", "timeunixms"],
}
REQUIRED = ["depth", "time"]

MIN_EPOCH_MS = 1_000_000_000_000
MAX_EPOCH_MS = 10_000_000_000_000
MAX_DEPTH_M = 1000

ISLAND_GAP_MEDIAN_MULTIPLE = 20
ISLAND_GAP_SPAN_FRACTION = 0.15
ISLAND_MAX_FRACTION = 0.15
ISLAND_MIN_SAMPLES = 10

SETTLED_WINDOW_S = 30


class BathymetryFormatError(ValueError):
    """The file does not match the documented bathymetry.csv schema."""


def _normalize(cell: str) -> str:
    cell = re.sub(r"\(.*?\)|\[.*?\]", "", cell.lower())
    return re.sub(r"[^a-z0-9]", "", cell)


def _num(cell):
    if cell is None:
        return None
    text = str(cell).strip()
    if not text:
        return None
    try:
        value = float(text)
    except ValueError:
        return None
    return value if math.isfinite(value) else None


def _is_epoch_ms(value) -> bool:
    return value is not None and MIN_EPOCH_MS <= value <= MAX_EPOCH_MS


@dataclass
class Scan:
    times_ms: list[float]  # sorted, trimmed
    depths_m: list[float]  # as reported (uncorrected)
    total_rows: int
    incomplete_rows: int
    dropped_leading: int
    dropped_trailing: int
    blind_spot_offset_cm: float = 0.0
    source: str = ""
    has_header: bool = False
    temperatures_c: list = field(default_factory=list)  # None where missing
    latitudes: list = field(default_factory=list)  # None where no GPS fix
    longitudes: list = field(default_factory=list)

    @property
    def n(self) -> int:
        return len(self.depths_m)

    @property
    def depths_cm(self) -> list[float]:
        return [d * 100 + self.blind_spot_offset_cm for d in self.depths_m]

    @property
    def elapsed_s(self) -> list[float]:
        return [(t - self.times_ms[0]) / 1000 for t in self.times_ms] if self.times_ms else []


def _column_map(rows):
    first = rows[0]
    has_header = any(c.strip() and _num(c) is None for c in first)
    if has_header:
        names = [_normalize(c) for c in first]
        cmap = {}
        for fld, aliases in HEADER_ALIASES.items():
            for i, name in enumerate(names):
                if name in aliases:
                    cmap[fld] = i
                    break
        missing = [f for f in REQUIRED if f not in cmap]
        if missing:
            raise BathymetryFormatError(
                f"bathymetry.csv header is missing required column(s): {', '.join(missing)}. "
                f"Found: {', '.join(first)}."
            )
        return True, cmap, rows[1:]

    cmap = {f: i for i, f in enumerate(HEADERLESS_COLUMN_ORDER)}
    for row in rows:
        if len(row) < len(HEADERLESS_COLUMN_ORDER):
            continue
        t = _num(row[cmap["time"]])
        if t is None:
            continue
        if _is_epoch_ms(t):
            break
        if _is_epoch_ms(_num(row[cmap["temperature"]])):
            raise BathymetryFormatError(
                "bathymetry.csv has its timestamp in column 4 and temperature in column 5. "
                "Expected latitude, longitude, depth (m), temperature (C), time (Unix ms). "
                "Add a header row (latitude,longitude,depth,temperature,time)."
            )
        raise BathymetryFormatError(
            f"bathymetry.csv column 5 ({t:g}) is not a Unix timestamp in milliseconds."
        )
    return False, cmap, rows


def trim_time_islands(times):
    """Return (start, end) indices of the samples to keep (end exclusive)."""
    n = len(times)
    if n < ISLAND_MIN_SAMPLES:
        return 0, n
    span = times[-1] - times[0]
    if span <= 0:
        return 0, n
    deltas = [b - a for a, b in zip(times, times[1:])]
    median = sorted(deltas)[len(deltas) // 2]
    threshold = max(median * ISLAND_GAP_MEDIAN_MULTIPLE, span * ISLAND_GAP_SPAN_FRACTION)
    start, end = 0, n
    for i in range(1, n):
        if i / n > ISLAND_MAX_FRACTION:
            break
        if deltas[i - 1] >= threshold:
            start = i
    for i in range(n - 1, 0, -1):
        if (n - i) / n > ISLAND_MAX_FRACTION:
            break
        if deltas[i - 1] >= threshold:
            end = i
    return (start, end) if end - start >= 2 else (0, n)


def read_bathymetry(path, blind_spot_offset_cm: float = 0.0) -> Scan:
    """Read, validate, sort and trim one bathymetry.csv."""
    with open(path, newline="") as f:
        rows = [r for r in csv.reader(f) if any(c.strip() for c in r) and not r[0].lstrip().startswith("#")]
    if not rows:
        return Scan([], [], 0, 0, 0, 0, blind_spot_offset_cm, str(path))

    has_header, cmap, data = _column_map(rows)

    def cell(row, fld):
        i = cmap.get(fld)
        return row[i] if i is not None and i < len(row) else None

    samples, incomplete = [], 0
    for row in data:
        depth, t = _num(cell(row, "depth")), _num(cell(row, "time"))
        if depth is None or t is None:
            incomplete += 1
            continue
        if not _is_epoch_ms(t):
            raise BathymetryFormatError(
                f"bathymetry.csv has a time value ({t:g}) that is not a Unix timestamp in milliseconds."
            )
        if depth < 0 or depth > MAX_DEPTH_M:
            raise BathymetryFormatError(f"bathymetry.csv has an implausible depth of {depth} m.")
        lat, lon = _num(cell(row, "latitude")), _num(cell(row, "longitude"))
        has_fix = lat is not None and lon is not None and not (lat == 0 and lon == 0)
        samples.append((t, depth, _num(cell(row, "temperature")),
                        lat if has_fix else None, lon if has_fix else None))

    samples.sort(key=lambda s: s[0])
    start, end = trim_time_islands([s[0] for s in samples])
    kept = samples[start:end]
    return Scan(
        times_ms=[s[0] for s in kept],
        depths_m=[s[1] for s in kept],
        total_rows=len(data),
        incomplete_rows=incomplete,
        dropped_leading=start,
        dropped_trailing=len(samples) - end,
        blind_spot_offset_cm=blind_spot_offset_cm,
        source=str(path),
        has_header=has_header,
        temperatures_c=[s[2] for s in kept],
        latitudes=[s[3] for s in kept],
        longitudes=[s[4] for s in kept],
    )


@dataclass
class Stats:
    mean_cm: float
    sd_cm: float | None  # sample standard deviation (ddof=1)
    min_cm: float
    max_cm: float
    n: int


def depth_stats(scan: Scan) -> Stats | None:
    values = scan.depths_cm
    n = len(values)
    if n == 0:
        return None
    mean = sum(values) / n
    sd = math.sqrt(sum((v - mean) ** 2 for v in values) / (n - 1)) if n > 1 else None
    return Stats(mean, sd, min(values), max(values), n)


def settled_depth(scan: Scan, window_s: float = SETTLED_WINDOW_S):
    """Mean corrected depth (cm) over the last `window_s` seconds, and its n."""
    if not scan.times_ms:
        return None, 0
    cutoff = scan.times_ms[-1] - window_s * 1000
    values = [d for t, d in zip(scan.times_ms, scan.depths_cm) if t >= cutoff]
    return (sum(values) / len(values), len(values)) if values else (None, 0)


def processing_summary(scan: Scan) -> str:
    parts = [f"{scan.n} of {scan.total_rows} rows used"]
    if scan.incomplete_rows:
        parts.append(f"{scan.incomplete_rows} missing depth or time")
    trimmed = scan.dropped_leading + scan.dropped_trailing
    if trimmed:
        parts.append(
            f"{trimmed} removed as isolated time islands "
            f"({scan.dropped_leading} leading, {scan.dropped_trailing} trailing)"
        )
    return "; ".join(parts)


FOLDER_PATTERN = re.compile(r"_(?P<deg>[0-9]+(?:\.[0-9]+)?)_deg_(?P<cm>[0-9]+(?:\.[0-9]+)?)_cm")


def parse_folder_name(name: str):
    """scan_data_{scan_degree}_deg_{sediment_height}_cm -> (degree, height_cm)."""
    m = FOLDER_PATTERN.search(name)
    if not m:
        return None, None
    return float(m.group("deg")), float(m.group("cm"))


def load_settling_column_scans(base_dir, blind_spot_offset_cm: float = 0.0):
    """Load every scans/<scan_data_X_deg_Y_cm>/bathymetry.csv, keyed by sediment height."""
    results = {}
    for csv_path in sorted(Path(base_dir).glob("*/bathymetry.csv")):
        degree, height = parse_folder_name(csv_path.parent.name)
        if height is None:
            print(f"skipping {csv_path.parent.name}: name does not match scan_data_<deg>_deg_<cm>_cm")
            continue
        if height in results:
            raise ValueError(f"two scan folders have sediment height {height} cm")
        results[height] = (degree, read_bathymetry(csv_path, blind_spot_offset_cm))
    return dict(sorted(results.items()))
