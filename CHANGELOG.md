# Changelog

All notable changes to this project are recorded here. Versions follow
[Semantic Versioning](https://semver.org). The web app (`package.json`), the
mobile app (`pubspec.yaml`), `CITATION.cff` and the git tag carry the same
version number.

## [1.0.0] — unreleased

First public release, prepared for archiving on Zenodo. The changes follow the
FAIR documentation review of 2 November 2026.

### Changed: results

These change numbers the apps or the notebook report. See
[README → Data processing](README.md#data-processing) for the current
definitions.

- **Settled depth** is now the mean of the samples in the **last 30 seconds**
  of the scan, by timestamp. Previously it was the mean of the last 20 rows in
  *file* order, which covered about 1.4 s at the usual sampling rate and could
  pick the wrong rows if the file was not in time order. On the four
  settling-column scans the settled depth changes by at most 0.21 cm. On
  short, noisy field scans the change can be several cm.
- **Depth change** (Compare scans) is now **signed**: the settled depth of the
  chronologically latest scan minus that of the earliest. A negative change
  means the mudline rose. Previously it was max − min of the settled depths,
  which hid the direction.
- **Statistics use the same samples as the chart.** Average, min and max now
  exclude the leading and trailing time islands the chart already removed.
  Averages of the settling-column scans are unchanged.
- **Mobile app** now applies the same time-island trimming as the web app, so
  both apps report the same statistics for the same scan.
- **Notebook error bars** are now ±1 sample standard deviation (`ddof=1`), and
  the number of readings is reported. Previously they were 0.9 σ below and
  1.15 σ above the mean, with the population σ and no justification. The
  README figures were regenerated.

### Added

- Bathymetry files are read **by header name** when they have a header row
  (the vendor's 2026 format) and validated by position when they don't (2025
  format). Files that match neither, including the column order printed in the
  vendor's own README, are **rejected with an explanatory message** instead of
  being plotted from the wrong column.
- **Acquisition settings** stored with every scan: sonar model, firmware,
  companion-app version, beam mode, scan angle, transducer elevation and
  datum, mounting height, blind-spot offset. Editable on the analysis screens
  (web and mobile), stored in DynamoDB (web) or `metadata.json` (mobile), and
  printed in the PDF report.
- **Blind-spot offset**: an explicit per-scan correction, off by default and
  always shown when applied.
- **Mudline elevation** (transducer elevation − corrected depth) when a
  transducer elevation is recorded.
- **Processing transparency**: the analysis screen and the PDF report state
  how many rows were used, skipped (missing depth or time) and trimmed, and
  whether a correction was applied. Reports and exports record the software
  version.
- **Annotated CSV export** (`chirp-bathymetry-csv/1.0`) of a processed scan,
  with a self-describing metadata block. It can be imported again.
- **NetCDF export** (`chirp-bathymetry-netcdf/1.0`, CF-1.8 and ACDD-1.3) of a
  processed scan, including acquisition metadata, the processing record and
  the raw echo profiles from `sonar.csv`. Available in the web app (a
  dependency-free NetCDF writer) and in Python (`chirp_netcdf.py`). Both
  produce the same dataset, which tests check against a shared golden file.
  It passes the IOOS compliance checker for CF-1.8 at the strict level.
- **Sample-dataset builder** (`data_visualization/build_sample_dataset.py`
  with `sample_dataset.json`) for the separate Zenodo dataset record.
- **ISP export**: download ISP records as JSON (`chirp-isp-export/1.0`). ISP
  records are still stored only in the browser or on the device.
- **Tests**: unit tests for the web app (Vitest), mobile app (`flutter test`)
  and notebook module (pytest), all against one set of fixtures with expected
  values from an independent reference implementation
  (`test-fixtures/bathymetry/`). GitHub Actions runs them on every push.
- `CITATION.cff`, `docs/data-dictionary.md`, `RELEASING.md`, this changelog,
  `data_visualization/requirements.txt`, and a "Data processing" section in
  the root README.

### Removed

- The Flutter counter-template test, which did not test this app.
- Stray files: a UI dump of the vendor app (`chirp_control/launch_screen.xml`),
  notebook checkpoints, and a committed Android build report.
- The CPRA logo from the web app and its screenshots, pending permission to
  publish it.
- The hard-coded deployment-site coordinates. The weather card now defaults
  to Baton Rouge, LA, and the site is set in the app. The coordinate label was
  also removed from the Home screenshots.
- GPS location and camera EXIF metadata from the field photographs.

### Fixed (documentation)

- Repository layout no longer lists the gitignored `FishDeeperCsvLogs/`.
- Mobile README: backend section now covers all handlers, project layout
  includes the ISP screens, and it states that mobile scans stay on the
  device.
- `pubspec.yaml` description, `data_visualization/README.md` title, folder
  diagram and typos.
- Version strings aligned at 1.0.0 (web app was 0.0.0).
