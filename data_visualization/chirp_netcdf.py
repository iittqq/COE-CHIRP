"""NetCDF (CF-1.8 / ACDD-1.3) export of one processed scan.

Writes the same "chirp-bathymetry-netcdf/1.0" layout as the web app
(chirp-control-web/src/utils/exportScanNetcdf.ts). test_chirp_netcdf.py checks
that this module reproduces the web app's golden file
(test-fixtures/netcdf/header.nc) variable for variable and attribute for
attribute. The layout is specified in docs/data-dictionary.md, section 7.

Example:
    import chirp_bathymetry as cb, chirp_netcdf as cn
    scan = cb.read_bathymetry("scans/scan_data_7_deg_12_cm/bathymetry.csv")
    cn.write_scan_netcdf("scan.nc", scan, title="7 deg 12 cm", scan_id="lab-12",
                         folder_name="scan_data_7_deg_12_cm",
                         acquisition={"scanAngleDeg": 7},
                         sonar_csv="scans/scan_data_7_deg_12_cm/sonar.csv")
"""

from __future__ import annotations

import csv
import re
from datetime import datetime, timezone

import numpy as np
from netCDF4 import Dataset

import chirp_bathymetry as cb

NETCDF_FORMAT = "chirp-bathymetry-netcdf/1.0"
FILL_DOUBLE = -9999.0
FILL_ECHO = -1
ECHO_CELL_SIZE_M = 0.010407008
REPOSITORY = "https://github.com/iittqq/COE-CHIRP"
SOFTWARE_VERSION = "1.0.0"

# Same keys and order as chirp-control-web/src/utils/acquisition.ts.
ACQUISITION_KEYS = [
    "sonarModel", "sonarFirmware", "companionAppVersion", "frequencyMode", "scanAngleDeg",
    "transducerElevationM", "datum", "mountingHeightM", "blindSpotOffsetCm",
]


def _snake(key: str) -> str:
    return re.sub(r"[A-Z]", lambda m: "_" + m.group(0).lower(), key)


def _iso_ms(dt: datetime) -> str:
    dt = dt.astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def _iso_seconds(ms: float) -> str:
    return datetime.fromtimestamp(int(ms) // 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_echo_profiles(path):
    """sonar.csv -> (times_ms, cells, values[ping][cell]) or None."""
    profiles = []
    with open(path, newline="") as f:
        for row in csv.reader(f):
            if not row:
                continue
            t = cb._num(row[0])
            if t is None or t < cb.MIN_EPOCH_MS:
                continue
            cells = row[1:]
            while cells and cells[-1].strip() == "":
                cells.pop()
            values = []
            for c in cells:
                v = cb._num(c)
                values.append(int(round(v)) if v is not None else FILL_ECHO)
            profiles.append((t, values))
    if not profiles:
        return None
    profiles.sort(key=lambda p: p[0])
    n_cells = max(len(v) for _, v in profiles)
    if n_cells == 0:
        return None
    grid = np.full((len(profiles), n_cells), FILL_ECHO, dtype="i2")
    for i, (_, v) in enumerate(profiles):
        grid[i, : len(v)] = v
    return [t for t, _ in profiles], n_cells, grid


def write_scan_netcdf(path, scan: cb.Scan, *, title: str, scan_id: str, folder_name: str,
                      acquisition: dict | None = None, sonar_csv=None,
                      software: str | None = None, exported_at: datetime | None = None):
    acquisition = {k: v for k, v in (acquisition or {}).items() if v not in (None, "")}
    if scan.n == 0:
        raise ValueError("Scan has no samples to export")
    software = software or f"chirp_bathymetry (Python) {SOFTWARE_VERSION}"
    exported_at = exported_at or datetime.now(timezone.utc)
    stats = cb.depth_stats(scan)
    settled, settled_n = cb.settled_depth(scan)
    elevation = acquisition.get("transducerElevationM")
    datum = acquisition.get("datum", "")
    start, end = scan.times_ms[0], scan.times_ms[-1]

    g = {
        "Conventions": "CF-1.8, ACDD-1.3",
        "chirp_format": NETCDF_FORMAT,
        "title": f"CHIRP sonar bathymetry: {title}",
        "summary": (
            "Depth readings from a commercial CHIRP sonar (distance from the transducer face down to the "
            "detected bottom/mudline), after the documented COE-CHIRP processing: rows without depth or time "
            "skipped, samples sorted by time, isolated leading/trailing time islands removed, blind-spot "
            "offset applied to depth_corrected. Raw echo profiles from sonar.csv are included when available."
        ),
        "keywords": "CHIRP sonar, bathymetry, mudline, dredging, marsh creation, settlement plate",
        "institution": "Louisiana State University",
        "source": f"Deeper CHIRP sonar via the Fish Deeper companion app; export folder {folder_name}",
        "references": f"{REPOSITORY} (software, data dictionary: docs/data-dictionary.md section 7)",
        "history": f"{_iso_ms(exported_at)} {software}: converted from vendor bathymetry.csv/sonar.csv",
        "comment": (
            "depth is positive downward from the transducer face. depth_corrected = depth + blind_spot_offset. "
            "mudline_elevation = transducer_elevation - depth_corrected, relative to vertical_datum."
        ),
        "date_created": _iso_ms(exported_at),
        "product_version": NETCDF_FORMAT,
        "software": software,
        "scan_title": title,
        "scan_id": scan_id,
        "time_coverage_start": _iso_seconds(start),
        "time_coverage_end": _iso_seconds(end),
        "time_coverage_duration": f"PT{(end - start) / 1000:.3f}S",
        "project": "COE-CHIRP",
        "processing_level": "Vendor depth readings, cleaned (time-sorted, incomplete rows skipped, time islands trimmed)",
        "standard_name_vocabulary": "CF Standard Name Table v84",
        "processing_rows_total": scan.total_rows,
        "processing_rows_missing_depth_or_time": scan.incomplete_rows,
        "processing_rows_trimmed_leading": scan.dropped_leading,
        "processing_rows_trimmed_trailing": scan.dropped_trailing,
        "processing_rows_used": scan.n,
        "processing_trim_rule": (
            f"drop leading/trailing group if gap >= max({cb.ISLAND_GAP_MEDIAN_MULTIPLE:g} x median spacing, "
            f"{cb.ISLAND_GAP_SPAN_FRACTION:g} x span) and group <= {cb.ISLAND_MAX_FRACTION * 100:g}% of samples"
        ),
        "summary_depth_corrected_mean_cm": stats.mean_cm,
        "summary_depth_corrected_sd_cm": stats.sd_cm if stats.sd_cm is not None else FILL_DOUBLE,
        "summary_depth_corrected_n": stats.n,
        "summary_settled_window_s": cb.SETTLED_WINDOW_S,
        "summary_settled_depth_corrected_cm": settled if settled is not None else FILL_DOUBLE,
        "summary_settled_n": settled_n,
    }
    lats = [v for v in scan.latitudes if v is not None]
    lons = [v for v in scan.longitudes if v is not None]
    if lats and lons:
        g.update(geospatial_lat_min=min(lats), geospatial_lat_max=max(lats),
                 geospatial_lon_min=min(lons), geospatial_lon_max=max(lons),
                 geospatial_lat_units="degrees_north", geospatial_lon_units="degrees_east")
    for key in ACQUISITION_KEYS:
        if key in acquisition:
            g[f"acquisition_{_snake(key)}"] = acquisition[key]

    fill = lambda values: [FILL_DOUBLE if v is None else v for v in values]  # noqa: E731
    echo = read_echo_profiles(sonar_csv) if sonar_csv else None

    with Dataset(path, "w", format="NETCDF3_CLASSIC") as ds:
        # The web writer stores every numeric global attribute as a double.
        for k, v in g.items():
            ds.setncattr(k, v if isinstance(v, str) else np.float64(v))
        ds.createDimension("obs", scan.n)

        def var(name, dims, data, attrs, dtype="f8", fill_value=None):
            v = ds.createVariable(name, dtype, dims, fill_value=fill_value)
            for k, a in attrs.items():
                v.setncattr(k, a if isinstance(a, (str, np.ndarray)) else np.float64(a))
            v[:] = data
            return v

        var("time", ("obs",), scan.times_ms, {
            "standard_name": "time", "long_name": "time of depth reading",
            "units": "milliseconds since 1970-01-01 00:00:00", "calendar": "standard",
            "coverage_content_type": "coordinate",
            "comment": ("Auxiliary coordinate, not a dimension: about 1-5% of vendor readings share a timestamp "
                        "with a neighbour, so time is not strictly monotonic. Values are kept as reported."),
        })
        var("depth", ("obs",), scan.depths_m, {
            "long_name": "distance from transducer face down to detected bottom, as reported by the sonar",
            "units": "m", "coordinates": "time", "coverage_content_type": "physicalMeasurement",
            "comment": "Uncorrected. The vendor's bottom-detection algorithm is not published.",
        })
        var("depth_corrected", ("obs",), [d / 100 for d in scan.depths_cm], {
            "long_name": "distance from transducer face down to detected bottom, with blind-spot offset",
            "units": "m", "coordinates": "time", "coverage_content_type": "physicalMeasurement",
            "comment": "depth + blind_spot_offset",
        })
        var("temperature", ("obs",), fill(scan.temperatures_c), {
            "long_name": "water temperature at the transducer", "units": "degree_C",
            "coordinates": "time", "coverage_content_type": "physicalMeasurement",
        }, fill_value=FILL_DOUBLE)
        for axis, unit, values in (("latitude", "degrees_north", scan.latitudes),
                                   ("longitude", "degrees_east", scan.longitudes)):
            var(axis, ("obs",), fill(values), {
                "standard_name": axis, "long_name": f"{axis} of the sonar", "units": unit,
                "coordinates": "time", "coverage_content_type": "coordinate",
                "comment": "Missing when the sonar had no GPS fix (the vendor writes 0,0 or blank).",
            }, fill_value=FILL_DOUBLE)
        var("blind_spot_offset", (), scan.blind_spot_offset_cm, {
            "long_name": "blind-spot offset added to every reported depth", "units": "cm",
            "coverage_content_type": "auxiliaryInformation", "comment": "0 = no correction applied",
        })
        if elevation is not None:
            var("transducer_elevation", (), elevation, {
                "long_name": "elevation of the transducer face while scanning", "units": "m",
                "coverage_content_type": "auxiliaryInformation",
                "vertical_datum": datum or "not recorded",
            })
            var("mudline_elevation", ("obs",), [elevation - d / 100 for d in scan.depths_cm], {
                "long_name": "elevation of the detected bottom (mudline)", "units": "m",
                "coordinates": "time", "coverage_content_type": "physicalMeasurement",
                "vertical_datum": datum or "not recorded",
                "comment": "transducer_elevation - depth_corrected",
            })
        if echo:
            times, n_cells, grid = echo
            ds.createDimension("ping", len(times))
            ds.createDimension("range_bin", n_cells)
            var("ping_time", ("ping",), times, {
                "standard_name": "time", "long_name": "time of sonar pulse (sonar.csv column 0)",
                "coverage_content_type": "coordinate",
                "units": "milliseconds since 1970-01-01 00:00:00", "calendar": "standard",
            })
            var("range", ("range_bin",), [i * ECHO_CELL_SIZE_M for i in range(n_cells)], {
                "long_name": "nominal distance below the transducer face of the echo cell", "units": "m",
                "coverage_content_type": "coordinate",
                "comment": (f"cell index x {ECHO_CELL_SIZE_M!r} m, the vendor's cell size for Deeper CHIRP series "
                            "and PRO+ 2 (0.02738 m for PRO series, 0.03705 m for START). The origin of cell 0 is "
                            "not documented by the vendor."),
            })
            v = ds.createVariable("echo_strength", "i2", ("ping", "range_bin"), fill_value=np.int16(FILL_ECHO))
            v.set_auto_maskandscale(False)
            for k, a in {
                "long_name": "echo strength per depth cell, as exported by the vendor (sonar.csv columns 1..n)",
                "units": "1", "coordinates": "ping_time range",
                "coverage_content_type": "physicalMeasurement",
                "valid_range": np.array([0, 4096], dtype="i2"),
                "comment": "Vendor scale, 0-4096 for CHIRP series and PRO+ 2. Not calibrated to acoustic units.",
            }.items():
                v.setncattr(k, a)
            v[:] = grid
    return path
