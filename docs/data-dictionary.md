# Data dictionary

This document specifies every data file the COE-CHIRP software reads or writes:
the raw sonar exports, the scan records stored by the backend and the mobile
app, the acquisition metadata kept with each scan, and the two export formats.
How the numbers are *processed* (cleaning, corrections, derived quantities) is
described in the root [README, "Data processing"](../README.md#data-processing).

All times are **Unix epoch milliseconds, UTC** unless stated otherwise. All
depths are measured **downward from the transducer face**.

- [1. Raw sonar export](#1-raw-sonar-export)
  - [1.1 bathymetry.csv](#11-bathymetrycsv)
  - [1.2 sonar.csv](#12-sonarcsv)
  - [1.3 Validation](#13-validation-what-the-software-rejects)
- [2. Settling-column folder naming](#2-settling-column-folder-naming-notebook)
- [3. Scan records](#3-scan-records)
- [4. Acquisition metadata](#4-acquisition-metadata)
- [5. Annotated CSV export](#5-annotated-csv-export-chirp-bathymetry-csv10)
- [6. ISP export](#6-isp-export-chirp-isp-export10)
- [7. NetCDF export](#7-netcdf-export-chirp-bathymetry-netcdf10)

---

## 1. Raw sonar export

The sonar used in this project is a Deeper CHIRP sonar. Its data are recorded
by the vendor's companion app (Fish Deeper, `eu.deeper.fishdeeper`) and
downloaded from the vendor's cloud service (<https://maps.fishdeeper.com>) as a
zip file holding one folder per scanning session:

| File | Content |
| ---- | ------- |
| `bathymetry.csv` | One row per depth reading. **This is the file the apps and the notebook analyse.** |
| `sonar.csv` | One row per sonar pulse: the raw echo-strength profile. Stored, not analysed. |
| `README` | Vendor's description of the two files (see the warning in 1.1). |

The vendor controls this format and has already changed it once (see the two
variants below). The software therefore validates every file instead of
assuming column positions (section 1.3).

### 1.1 `bathymetry.csv`

Two variants have been seen:

| Variant | Seen in | Header row | Example first line |
| ------- | ------- | ---------- | ------------------ |
| A | exports downloaded in 2025 | none | `0.0,0.0,0.561,22.4,1760032255069` |
| B | exports downloaded in 2026 | `latitude,longtitude,depth,temperature,time` (the vendor's spelling) | `,,0.19,23.0,1776055378226` |

Columns (variant A by position, variant B by header name):

| # | Header name (B) | Quantity | Unit | Notes |
| - | --------------- | -------- | ---- | ----- |
| 0 | `latitude` | Latitude of the sonar | decimal degrees, presumably WGS 84 (the vendor does not say) | `0` (A) or blank (B) when there was no GPS fix. GPS updates about once a second while depth updates up to 15 times a second, so most rows have no position. Treated as missing. |
| 1 | `longtitude` | Longitude | decimal degrees | as above |
| 2 | `depth` | Distance from the transducer face down to the bottom detected by the sonar | **metres** | The vendor's bottom-detection algorithm is not public. No correction is applied by the vendor or by this software unless a blind-spot offset is recorded (section 4). |
| 3 | `temperature` | Water temperature at the transducer | °C | |
| 4 | `time` | Time of the reading | **Unix epoch milliseconds, UTC** | Readings are about 70 ms apart (about 14 Hz) in the settling-column tests. The rate falls with depth (vendor: about 3 Hz at 100 m). |

> **Warning: the vendor README is wrong about the column order.** The
> `README` inside each export says column 3 is the timestamp and column 4 is
> temperature. In every export used in this project the file has them the
> other way round (column 3 is about 22.4, column 4 is about 1.76 × 10¹²). The
> table above follows the files. If a future export really does follow the
> vendor README, the software rejects it with an explanatory message rather
> than plotting temperatures as times (section 1.3).

Header names are matched case-insensitively after removing spaces,
punctuation and any unit in brackets. Accepted aliases:

| Field | Accepted header names |
| ----- | --------------------- |
| latitude | `latitude`, `lat`, `latitude_deg` |
| longitude | `longitude`, `longtitude`, `lon`, `lng`, `longitude_deg` |
| depth | `depth`, `depth_m`, `depth (m)` |
| temperature | `temperature`, `temp`, `temperature_c` |
| time | `time`, `timestamp`, `time_ms`, `timestamp_ms`, `time_unix_ms` |

Only `depth` and `time` are required.

### 1.2 `sonar.csv`

| Column | Quantity | Unit / range |
| ------ | -------- | ------------ |
| 0 | Time of the pulse | Unix epoch milliseconds, UTC |
| 1 … n | Echo strength in successive depth cells, from the transducer downward | dimensionless; 0–4096 for Deeper CHIRP series and PRO+ 2, 0–1600 for PRO series and START |

Cell size (vertical resolution), according to the vendor: 0.010407008 m (CHIRP
series and PRO+ 2), 0.02738 m (PRO series), 0.03705 m (START). The number of
cells varies by row: the vendor scans 10 m beyond the bottom it detects, so
n = (detected depth + 10 m) / cell size. The apps store this file but do not
analyse it. They read only its timestamps, to date a scan that has no
bathymetry rows.

### 1.3 Validation (what the software rejects)

The web app, the mobile app and the notebook apply the same checks, and a file
that fails one is not imported:

| Check | Failure message (abridged) |
| ----- | -------------------------- |
| Header present but no `depth` or `time` column | `header is missing required column(s): time` |
| No header, and column 4 is a timestamp while column 5 is not (the vendor-README order) | `has its timestamp in column 4 and temperature in column 5` |
| No header, and column 5 is not between 1 × 10¹² and 1 × 10¹³ (for example seconds rather than milliseconds) | `column 5 (…) is not a Unix timestamp in milliseconds` |
| Any depth below 0 or above 1000 m | `not a plausible depth in metres` |

Rows with a blank depth or time are skipped, not rejected, and are counted
(section "Cleaning" in the README).

---

## 2. Settling-column folder naming (notebook)

`data_visualization/data_processing.ipynb` takes the test conditions from the
folder name:

```
scan_data_{scan_degree}_deg_{sediment_height}_cm/
├── bathymetry.csv
├── sonar.csv
└── README
```

| Token | Meaning | Unit |
| ----- | ------- | ---- |
| `scan_degree` | Beam (cone) angle selected in the companion app for this run | degrees |
| `sediment_height` | Sediment height in the column measured by hand at the end of the run | cm |

The water height above the column floor (`OBSERVED_WATER_HEIGHT_CM` in the
notebook) is not in the file name. Set it in the notebook. The expected depth
is water height minus sediment height.

---

## 3. Scan records

### Web app and backend

Each scan is one item in the DynamoDB table `ChirpScans` plus two objects in
S3 (see [`chirp_control/lambda/README.md`](../chirp_control/lambda/README.md)):

| Attribute | Type | Meaning |
| --------- | ---- | ------- |
| `user_id` (partition key) | string | Account that owns the scan |
| `scan_id` (sort key) | string (UUID) | |
| `folder_name` | string | Name of the imported zip, folder or file prefix |
| `title` | string | User-editable display name (empty = derived from `folder_name`) |
| `location` | string | Site label (empty = "SITE A") |
| `notes` | string | Free-text notes |
| `acquisition` | map | Acquisition settings, section 4 |
| S3 `<user_id>/<scan_id>/bathymetry.csv` | text | Raw vendor file, byte for byte as imported |
| S3 `<user_id>/<scan_id>/sonar.csv` | text | Raw vendor file, byte for byte as imported |

Raw files are never modified. All processing happens when a scan is
displayed, so a change to the processing rules applies to old scans as well.

### Mobile app

The mobile app keeps scans **on the device only**, in
`<app documents>/scans/<folder>/` with the raw `bathymetry.csv`, `sonar.csv`,
the vendor `README`, and a `metadata.json`:

```json
{ "title": "…", "notes": "…", "user_id": "…", "acquisition": { … } }
```

Scans are not synchronised between the mobile app and the backend.

### ISP records

ISP (Instrumented Settlement Plate) spreadsheets are stored only where they
were imported: in the browser's IndexedDB (`chirp-control-isp`) for the web
app, or in `<app documents>/isp/` for the mobile app. They are not sent to the
backend, other users cannot see them, and clearing the browser's site data
deletes them. Use the export in section 6 to keep or share them.

---

## 4. Acquisition metadata

Stored with every scan (the `acquisition` map above; `metadata.json` →
`acquisition` on mobile), editable on the scan analysis screen, and printed in
the PDF report and the CSV export. All fields are optional, but a scan cannot
be converted to a mudline elevation, or compared reliably with another scan,
without them.

| Key | Type | Unit | Meaning |
| --- | ---- | ---- | ------- |
| `sonarModel` | string | | e.g. `Deeper CHIRP+ 2`, `Deeper PRO+ 2` |
| `sonarFirmware` | string | | Sonar firmware version (shown in the companion app) |
| `companionAppVersion` | string | | Version of the Fish Deeper app on the on-site phone |
| `frequencyMode` | string | | Beam / frequency mode selected in the companion app |
| `scanAngleDeg` | number | degrees | Beam cone angle used (the `scan_degree` of section 2) |
| `transducerElevationM` | number | m | Elevation of the transducer face **while scanning** (step motor lowered), relative to `datum` |
| `datum` | string | | Vertical datum of `transducerElevationM`, e.g. `NAVD88 (GEOID18)` |
| `mountingHeightM` | number | m | Height of the transducer face above the settlement plate or original ground at installation, when no surveyed elevation exists |
| `blindSpotOffsetCm` | number | cm | Signed offset **added** to every reported depth. Empty or 0 = no correction. See README "Instrument corrections" |

---

## 5. Annotated CSV export (`chirp-bathymetry-csv/1.0`)

Written by the web app's scan analysis screen (download button). It is a plain
CSV that documents itself, so the data can be used without this software:

1. A metadata block of lines starting with `# `, each `key: value`:
   - `format`, `specification`, `software` (name and version), `exported_utc`
   - `scan_title`, `scan_id`, `source_folder`, `scan_start_utc`, `scan_end_utc`
   - `depth_reference` (always `transducer face, positive downward`)
   - `acquisition.*`: every field of section 4 (in snake_case)
   - `blind_spot_offset_cm_applied`
   - `processing.*`: row counts (total, missing depth or time, trimmed leading or trailing, used) and the trimming rule
   - `summary.*`: mean, sample SD, min, max, n, settled window, settled depth and its n
   - `column.<name>`: one description line per data column
2. One header row and one row per sample used (time-sorted and trimmed):

| Column | Unit | Meaning |
| ------ | ---- | ------- |
| `time_unix_ms` | ms | Unix epoch milliseconds, UTC |
| `elapsed_s` | s | Seconds since the first used sample |
| `latitude_deg` | degrees | Empty when the sonar had no GPS fix |
| `longitude_deg` | degrees | Empty when the sonar had no GPS fix |
| `depth_m` | m | Depth as reported by the sonar (uncorrected) |
| `depth_corrected_m` | m | `depth_m + blind_spot_offset_cm / 100` |
| `temperature_c` | °C | |
| `mudline_elevation_m` | m | `transducer_elevation_m − depth_corrected_m` relative to the datum; empty if the elevation is unknown |

The header names are accepted by the importer, so an export can be imported
again. Most CSV readers can skip the comment lines, e.g.
`pandas.read_csv(path, comment="#")`.

---

## 6. ISP export (`chirp-isp-export/1.0`)

Written by the web app's ISP Data screen (download button): the selected
records, or all of them, as one JSON file:

```json
{
  "format": "chirp-isp-export/1.0",
  "software": "chirp-control-web 1.0.0",
  "exportedUtc": "2026-11-16T12:00:00.000Z",
  "records": [
    {
      "id": "…", "title": "…", "location": "…", "notes": "…",
      "sourceFileName": "plate-3.xlsx", "sheetName": "Sheet1",
      "importedUtc": "…",
      "headers": ["…"],
      "rows": [["…"]]
    }
  ]
}
```

`headers` and `rows` are the source spreadsheet's cells, unmodified. Their
meaning (instrument, units) is defined by the spreadsheet itself.

---

## 7. NetCDF export (`chirp-bathymetry-netcdf/1.0`)

A NetCDF-3 classic file following the
[CF Metadata Conventions 1.8](https://cfconventions.org/Data/cf-conventions/cf-conventions-1.8/cf-conventions.html)
and the [Attribute Convention for Data Discovery 1.3](https://wiki.esipfed.org/Attribute_Convention_for_Data_Discovery_1-3).
It can be read by netCDF4-python, xarray, MATLAB, R (ncdf4), Panoply and GIS
tools. It is written by:

- the web app: scan analysis → download → *NetCDF, CF-1.8*
  ([`exportScanNetcdf.ts`](../chirp-control-web/src/utils/exportScanNetcdf.ts),
  with its own dependency-free writer [`netcdf.ts`](../chirp-control-web/src/utils/netcdf.ts));
- Python: [`data_visualization/chirp_netcdf.py`](../data_visualization/chirp_netcdf.py),
  used by the sample-dataset builder.

The two produce the same dataset. `test-fixtures/netcdf/header.nc` is written
by the web app and checked byte for byte by its tests. The Python tests read it
with netCDF4 and compare it, variable by variable and attribute by attribute,
with the Python exporter's output. CI also checks it against CF-1.8 at the
strict level with the IOOS compliance checker.

**Dimensions:** `obs` (depth readings used), and when `sonar.csv` is available,
`ping` (sonar pulses) and `range_bin` (echo cells).

| Variable | Dimensions | Type | Units | Meaning |
| -------- | ---------- | ---- | ----- | ------- |
| `time` | obs | double | ms since 1970-01-01 UTC | Time of each reading. An *auxiliary* coordinate rather than a dimension, because about 1–5 % of vendor readings share a timestamp with a neighbour, so `time` is not strictly monotonic. |
| `depth` | obs | double | m | As reported by the sonar (uncorrected) |
| `depth_corrected` | obs | double | m | `depth` + blind-spot offset |
| `temperature` | obs | double | degree_C | Fill −9999 when missing |
| `latitude`, `longitude` | obs | double | degrees_north/east | Fill −9999 when the sonar had no GPS fix |
| `blind_spot_offset` | scalar | double | cm | 0 = no correction |
| `transducer_elevation` | scalar | double | m | Only when recorded; attribute `vertical_datum` |
| `mudline_elevation` | obs | double | m | `transducer_elevation − depth_corrected`, only when the elevation is recorded |
| `ping_time` | ping | double | ms since 1970-01-01 UTC | `sonar.csv` column 0 |
| `range` | range_bin | double | m | Cell index × 0.010407008 m (vendor cell size for CHIRP series and PRO+ 2) |
| `echo_strength` | ping, range_bin | short | 1 | `sonar.csv` columns 1…n, vendor scale 0–4096. Fill −1 where a row has fewer cells. |

**Global attributes** record discovery metadata (`title`, `summary`,
`keywords`, `institution`, `references`, `history`, `date_created`,
`time_coverage_*`, `geospatial_*` when GPS positions exist), the software and
format version, the processing (`processing_rows_*`, `processing_trim_rule`),
summary statistics (`summary_*`), and every recorded acquisition setting
(`acquisition_<snake_case key>`, section 4).

Variables without an exact CF standard name (for example the
transducer-to-bottom distance) have a `long_name` but deliberately no
`standard_name`, rather than a near miss that would mislabel the quantity.

```python
import xarray as xr
ds = xr.open_dataset("scan-bathymetry.nc")
ds.depth_corrected.to_series()          # indexed by obs; ds.time gives the timestamps
ds.echo_strength.plot(x="ping_time", y="range", yincrease=False)
```
