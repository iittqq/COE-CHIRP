"""Build the sample-dataset package for a separate Zenodo dataset record.

Reads the raw settling-column scans and sample_dataset.json, and writes a
self-contained, documented package ready to upload:

    build/sample-dataset/<package_name>-<version>/
    ├── README.md                 what the data are, how they were made, how to use them
    ├── data-dictionary.md        file formats, units, metadata (copy of docs/data-dictionary.md)
    ├── summary.csv               one row per scan: expected vs. measured depth, SD, n, ...
    ├── scans/<folder>/raw/       bathymetry.csv, sonar.csv exactly as exported by the vendor
    ├── scans/<folder>/<folder>.nc   CF-1.8 NetCDF: processed depths + raw echo profiles
    ├── figures/                  average depth vs. sediment height; depth over time
    ├── metadata/zenodo.json      deposit metadata for the Zenodo form or API
    ├── metadata/scans.json       per-scan metadata, processing counts and statistics
    └── manifest-sha256.txt       checksums of every file
    build/sample-dataset/<package_name>-<version>.zip

Usage (from data_visualization/):
    python build_sample_dataset.py --draft        # allowed while sample_dataset.json has TODOs
    python build_sample_dataset.py                # final package; fails on any TODO

The vendor's own README from each export is deliberately not included: it is
vendor-authored text and documents the bathymetry.csv column order wrongly
(see data-dictionary.md, section 1.1).
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import chirp_bathymetry as cb
import chirp_netcdf as cn

HERE = Path(__file__).resolve().parent
REPO = HERE.parent


def find_todos(obj, path="config"):
    if isinstance(obj, str):
        return [path] if "TODO" in obj else []
    if isinstance(obj, dict):
        return [t for k, v in obj.items() if not k.startswith("_") for t in find_todos(v, f"{path}.{k}")]
    if isinstance(obj, list):
        return [t for i, v in enumerate(obj) for t in find_todos(v, f"{path}[{i}]")]
    return []


def clean(value):
    """Config value for publication: TODO placeholders become 'not yet confirmed'."""
    return "not yet confirmed" if isinstance(value, str) and "TODO" in value else value


def check_no_coordinates(csv_path: Path):
    """Refuse to publish any scan that contains a GPS position."""
    scan = cb.read_bathymetry(csv_path)
    fixes = sum(1 for lat in scan.latitudes if lat is not None)
    if fixes:
        raise SystemExit(
            f"{csv_path} contains {fixes} GPS positions. Field-site coordinates may need permission to "
            "publish (RELEASING.md); remove this scan or strip the coordinates first."
        )


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def make_figures(rows, scans, out_dir: Path, water_cm: float, angle):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.ticker import FuncFormatter, MultipleLocator

    out_dir.mkdir(parents=True, exist_ok=True)
    h = [r["sediment_height_cm"] for r in rows]
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.plot(h, [r["mean_depth_cm"] for r in rows], "x-", color="green", label="Sonar mean depth (uncorrected)")
    ax.errorbar(h, [r["mean_depth_cm"] for r in rows], yerr=[r["sd_depth_cm"] for r in rows],
                fmt="none", ecolor="orange", capsize=5, label="±1 SD (sample)")
    ax.plot(h, [water_cm - x for x in h], "r--", label="Expected depth")
    ax.set_xlabel("Sediment height (cm)")
    ax.set_ylabel("Depth below transducer (cm)")
    ax.set_title(f"Mean depth vs. expected depth ({angle:g}° scan angle)")
    ax.set_xticks(h)
    ax.grid(True)
    ax.legend()
    fig.savefig(out_dir / "average_depth_vs_sediment_height.png", dpi=150, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(12, 5))
    for row, scan in zip(rows, scans):
        ax.plot(scan.elapsed_s, scan.depths_cm, label=f'{row["sediment_height_cm"]:g} cm sediment (n={scan.n})')
    ax.xaxis.set_major_locator(MultipleLocator(30))
    ax.xaxis.set_major_formatter(FuncFormatter(lambda s, _: f"{int(s // 60):02d}:{int(s % 60):02d}"))
    ax.set_xlabel("Elapsed time (mm:ss)")
    ax.set_ylabel("Depth below transducer (cm)")
    ax.set_title("Depth over time")
    ax.invert_yaxis()
    ax.grid(True, linestyle="--")
    ax.legend(loc="upper right")
    fig.savefig(out_dir / "depth_over_time.png", dpi=150, bbox_inches="tight")
    plt.close(fig)


def readme(cfg, rows, built_at, draft) -> str:
    exp, acq, sw = cfg["experiment"], cfg["acquisition"], cfg["software"]
    first = min(r["scan_start_utc"] for r in rows)
    table = "\n".join(
        f'| `{r["folder"]}` | {r["scan_start_utc"]} | {r["sediment_height_cm"]:g} | {r["expected_depth_cm"]:g} | '
        f'{r["mean_depth_cm"]:.2f} | {r["sd_depth_cm"]:.2f} | {r["n"]} | {r["settled_depth_cm"]:.2f} | '
        f'{r["mudline_elevation_settled_cm"]:.2f} |'
        for r in rows
    )
    banner = (
        "> **DRAFT. Not for deposit.** Values marked *not yet confirmed* must be filled in "
        "`sample_dataset.json` and the package rebuilt without `--draft`.\n\n"
        if draft else ""
    )
    creators = "; ".join(c["name"] for c in cfg["creators"])
    return f"""# {cfg["title"]}

{banner}Version {cfg["version"]} · built {built_at} · creators: {creators}

## Overview

CHIRP sonar depth readings from {len(rows)} laboratory settling-column runs
with known sediment heights ({", ".join(f'{r["sediment_height_cm"]:g}' for r in rows)} cm),
recorded on {first[:10]}. They were used to validate the COE-CHIRP system, which
tracks mudline elevation during marsh-creation dredging. Each run provides the
sonar vendor's raw export and a CF-1.8 NetCDF file with the processed depths
and the raw echo profiles.

- Software that produced the processed files: COE-CHIRP {sw["version"]}, {sw["repository"]} (DOI: {clean(sw["doi"])})
- Thesis: {cfg["thesis"]}
- License: {clean(cfg["license"])}

## Method

{exp["description"]}

| | |
|---|---|
| Column | {exp["column"]} |
| Sediment | {clean(exp["sediment"])} |
| Water height above column floor | {exp["water_height_cm"]} cm ({clean(exp["water_height_note"])}) |
| Sediment height | {exp["sediment_height_note"]} |
| Sonar | {clean(acq["sonarModel"])}, scan angle {acq["scanAngleDeg"]}° |
| Transducer face | at the water surface, about {acq["transducerElevationM"]} m above the column floor (datum: {acq["datum"]}) |
| Blind-spot correction | none ({acq["blindSpotOffsetCm"]} cm) |
| Expected depth | water height − sediment height |

## Results

| Scan | Start (UTC) | Sediment (cm) | Expected depth (cm) | Mean depth (cm) | SD (cm) | n | Settled depth, last {cb.SETTLED_WINDOW_S} s (cm) | Mudline elevation, settled (cm above floor) |
|---|---|---|---|---|---|---|---|---|
{table}

SD is the sample standard deviation of individual readings. Readings are about
70 ms apart and autocorrelated, so SD/√n understates the uncertainty of the
mean. The same table is in `summary.csv`, and the figures are in `figures/`.

## Files

| Path | Content |
|---|---|
| `scans/<run>/raw/bathymetry.csv` | Vendor export, unmodified: latitude, longitude, depth (m), temperature (°C), time (Unix ms, UTC). No header row. Latitude and longitude are 0 (no GPS indoors). |
| `scans/<run>/raw/sonar.csv` | Vendor export, unmodified: time (Unix ms, UTC), then echo strength (0–4096) in 400 depth cells of 0.010407008 m. |
| `scans/<run>/<run>.nc` | NetCDF-3 classic, CF-1.8 and ACDD-1.3: `depth` (as reported), `depth_corrected`, `mudline_elevation` (relative to the column floor), `temperature`, `time`, and the raw echo profiles `echo_strength(ping, range_bin)`. Global attributes record the acquisition settings, the processing applied and summary statistics. |
| `summary.csv` | One row per run (columns described in its header). |
| `metadata/scans.json` | Per-run metadata, processing counts and statistics. |
| `metadata/zenodo.json` | Deposit metadata used for this record. |
| `data-dictionary.md` | Full specification of every file format above. |
| `manifest-sha256.txt` | SHA-256 checksum of every file. |

The vendor's own `README` from each export is not included: it is
vendor-authored and lists the `bathymetry.csv` columns in the wrong order (see
`data-dictionary.md`, section 1.1).

## Processing

Applied only to the NetCDF files and statistics; the raw files are untouched.
Samples are sorted by time, rows without depth or time are skipped, and small
leading or trailing groups of samples separated by a large time gap are
removed. No such rows occur in these runs, so all readings are used. No
blind-spot correction is applied. About 1–5 % of readings share a timestamp
with a neighbour; they are kept as reported. Full rules: README of the
software repository, section "Data processing".

## Reading the data

```python
import xarray as xr                     # or netCDF4.Dataset
ds = xr.open_dataset("scans/scan_data_7_deg_12_cm/scan_data_7_deg_12_cm.nc")
ds.depth_corrected.mean().item() * 100   # cm
ds.attrs["acquisition_scan_angle_deg"]

import pandas as pd
raw = pd.read_csv("scans/scan_data_7_deg_12_cm/raw/bathymetry.csv", header=None,
                  names=["latitude", "longitude", "depth_m", "temperature_c", "time_ms"])
```

## Known limitations

- The sonar's bottom-detection algorithm and any sound-speed compensation are proprietary and undocumented.
- The transducer elevation is derived from the recorded water height, so the mudline elevations are approximate (± a few mm).
- Each sediment height is a single hand measurement read from a yard stick.

## How to cite

Cite this dataset by its Zenodo DOI, and the software by its DOI ({clean(sw["doi"])}).
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=HERE / "sample_dataset.json", type=Path)
    ap.add_argument("--scans-dir", default=HERE / "scans", type=Path)
    ap.add_argument("--out", default=REPO / "build" / "sample-dataset", type=Path)
    ap.add_argument("--draft", action="store_true", help="allow TODO values (package is marked DRAFT)")
    args = ap.parse_args()

    cfg = json.loads(args.config.read_text())
    todos = find_todos(cfg)
    if todos and not args.draft:
        raise SystemExit("sample_dataset.json still has TODO values:\n  " + "\n  ".join(todos) +
                         "\nFill them in, or pass --draft to build a review copy.")

    name = f'{cfg["package_name"]}-{cfg["version"]}' + ("-DRAFT" if args.draft and todos else "")
    root = args.out / name
    if root.exists():
        shutil.rmtree(root)
    (root / "metadata").mkdir(parents=True)

    built = datetime.now(timezone.utc).replace(microsecond=0)
    acq = {k: clean(v) for k, v in cfg["acquisition"].items()}
    water = cfg["experiment"]["water_height_cm"]
    rows, scans, scan_meta = [], [], []
    for entry in cfg["scans"]:
        folder = entry["folder"]
        src = args.scans_dir / folder
        bathy = src / "bathymetry.csv"
        if not bathy.exists():
            raise SystemExit(f"Missing {bathy}. Point --scans-dir at the folder holding the raw exports.")
        check_no_coordinates(bathy)

        raw = root / "scans" / folder / "raw"
        raw.mkdir(parents=True)
        shutil.copyfile(bathy, raw / "bathymetry.csv")
        sonar = src / "sonar.csv"
        if sonar.exists():
            shutil.copyfile(sonar, raw / "sonar.csv")

        scan = cb.read_bathymetry(bathy, blind_spot_offset_cm=cfg["acquisition"]["blindSpotOffsetCm"])
        nc_path = root / "scans" / folder / f"{folder}.nc"
        cn.write_scan_netcdf(
            nc_path, scan, title=f'{folder} ({entry["sediment_height_cm"]:g} cm sediment)',
            scan_id=folder, folder_name=folder,
            acquisition={k: v for k, v in acq.items() if v != "not yet confirmed"},
            sonar_csv=sonar if sonar.exists() else None,
            software=f"chirp_bathymetry (Python) {cfg['software']['version']}", exported_at=built,
        )

        st = cb.depth_stats(scan)
        settled, settled_n = cb.settled_depth(scan)
        h = entry["sediment_height_cm"]
        row = {
            "folder": folder,
            "scan_start_utc": datetime.fromtimestamp(int(scan.times_ms[0]) // 1000, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "duration_s": round((scan.times_ms[-1] - scan.times_ms[0]) / 1000, 3),
            "scan_angle_deg": cfg["acquisition"]["scanAngleDeg"],
            "water_height_cm": water,
            "sediment_height_cm": h,
            "expected_depth_cm": water - h,
            "mean_depth_cm": st.mean_cm,
            "sd_depth_cm": st.sd_cm,
            "n": st.n,
            "mean_minus_expected_cm": st.mean_cm - (water - h),
            "settled_depth_cm": settled,
            "settled_n": settled_n,
            "mudline_elevation_settled_cm": water - settled,
            "rows_total": scan.total_rows,
            "rows_used": scan.n,
        }
        rows.append(row)
        scans.append(scan)
        scan_meta.append({**row, "acquisition": acq, "processing": cb.processing_summary(scan),
                          "files": [f"scans/{folder}/raw/bathymetry.csv", f"scans/{folder}/raw/sonar.csv",
                                    f"scans/{folder}/{folder}.nc"]})

    with open(root / "summary.csv", "w", newline="") as f:
        f.write("# One row per settling-column run. Depths in cm below the transducer face, uncorrected.\n"
                "# expected_depth_cm = water_height_cm - sediment_height_cm; sd = sample SD (n-1);\n"
                f"# settled = mean of the last {cb.SETTLED_WINDOW_S} s; mudline_elevation_settled_cm = "
                "water_height_cm - settled_depth_cm (above the column floor).\n")
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        for r in rows:
            w.writerow({k: (f"{v:.4f}" if isinstance(v, float) else v) for k, v in r.items()})

    make_figures(rows, scans, root / "figures", water, cfg["acquisition"]["scanAngleDeg"])
    shutil.copyfile(REPO / "docs" / "data-dictionary.md", root / "data-dictionary.md")
    (root / "metadata" / "scans.json").write_text(json.dumps(scan_meta, indent=2) + "\n")

    sw = cfg["software"]
    related = [{"identifier": sw["repository"], "relation": "isSupplementTo", "resource_type": "software"}]
    if "TODO" not in sw["doi"]:
        related.append({"identifier": sw["doi"], "relation": "isSupplementTo", "scheme": "doi",
                        "resource_type": "software"})
    zenodo = {
        "metadata": {
            "upload_type": "dataset",
            "title": cfg["title"],
            "version": cfg["version"],
            "publication_date": built.date().isoformat(),
            "creators": [{k: v for k, v in c.items() if "TODO" not in str(v)} for c in cfg["creators"]],
            "description": (
                f"<p>CHIRP sonar depth readings from {len(rows)} laboratory settling-column runs with known "
                "sediment heights, used to validate the COE-CHIRP mudline-tracking system. Each run includes "
                "the vendor's raw bathymetry.csv and sonar.csv and a CF-1.8 NetCDF file with the processed "
                "depths, acquisition metadata and raw echo profiles. See README.md and data-dictionary.md.</p>"
            ),
            "keywords": cfg["keywords"],
            "related_identifiers": related,
            "references": [cfg["thesis"]],
            "language": "eng",
            **({"license": cfg["license"]} if "TODO" not in cfg["license"] else {}),
            **({"notes": "DRAFT metadata: license, ORCID and software DOI not yet confirmed."} if todos else {}),
        }
    }
    (root / "metadata" / "zenodo.json").write_text(json.dumps(zenodo, indent=2, ensure_ascii=False) + "\n")
    (root / "README.md").write_text(readme(cfg, rows, built.isoformat().replace("+00:00", "Z"), bool(todos)))

    files = sorted(p for p in root.rglob("*") if p.is_file())
    manifest = "".join(f"{sha256(p)}  {p.relative_to(root).as_posix()}\n" for p in files)
    (root / "manifest-sha256.txt").write_text(manifest)

    zip_path = args.out / f"{name}.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(q for q in root.rglob("*") if q.is_file()):
            z.write(p, Path(name) / p.relative_to(root))

    print(f"Built {root}\n      {zip_path} ({zip_path.stat().st_size / 1e6:.1f} MB)")
    if todos:
        print("DRAFT: still TODO in sample_dataset.json:\n  " + "\n  ".join(todos))
    for r in rows:
        print(f'  {r["folder"]}: mean {r["mean_depth_cm"]:.2f} cm, expected {r["expected_depth_cm"]:g} cm, '
              f'n={r["n"]}')


if __name__ == "__main__":
    sys.exit(main())
