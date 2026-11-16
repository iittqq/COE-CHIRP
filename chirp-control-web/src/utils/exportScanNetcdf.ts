// NetCDF export of one processed scan, following the CF Metadata Conventions
// (CF-1.8) and the Attribute Convention for Data Discovery (ACDD-1.3). The
// layout ("chirp-bathymetry-netcdf/1.0") is specified in
// docs/data-dictionary.md, section 7, and is produced identically by the
// Python exporter (data_visualization/chirp_netcdf.py). Both are checked
// against test-fixtures/netcdf/header.nc.

import { ACQUISITION_FIELDS, type AcquisitionMetadata } from "./acquisition";
import {
  depthCm,
  depthStatistics,
  ISLAND_GAP_MEDIAN_MULTIPLE,
  ISLAND_GAP_SPAN_FRACTION,
  ISLAND_MAX_FRACTION,
  mudlineElevationM,
  settledDepth,
  SETTLED_WINDOW_S,
  type ProcessedScan,
} from "./bathymetry";
import { encodeNetcdf, type NcAttrValue, type NcFile, type NcVariable } from "./netcdf";
import type { CsvRow } from "./csv";

export const NETCDF_FORMAT = "chirp-bathymetry-netcdf/1.0";
export const FILL_DOUBLE = -9999.0;
export const FILL_ECHO = -1;
// Vertical size of one sonar.csv echo cell for the Deeper CHIRP series and
// PRO+ 2, per the vendor's export README.
export const ECHO_CELL_SIZE_M = 0.010407008;

const REPOSITORY = "https://github.com/iittqq/COE-CHIRP";

function snake(key: string): string {
  return key.replace(/[A-Z]/g, (ch) => `_${ch.toLowerCase()}`);
}

function isoSeconds(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}

export interface EchoProfiles {
  timesMs: number[];
  cells: number; // max profile length
  values: number[]; // row-major [ping][cell], FILL_ECHO where a row is shorter
}

// sonar.csv: column 0 = Unix ms, columns 1..n = echo strength per depth cell.
// Rows without a valid timestamp are skipped; short rows are padded.
export function parseEchoProfiles(rows: CsvRow[]): EchoProfiles | null {
  const profiles: { t: number; v: number[] }[] = [];
  for (const row of rows) {
    const t = typeof row[0] === "number" ? row[0] : Number(row[0]);
    if (!Number.isFinite(t) || t < 1_000_000_000_000) continue;
    const cells = row.slice(1);
    while (cells.length > 0 && String(cells[cells.length - 1]).trim() === "") cells.pop();
    profiles.push({
      t,
      v: cells.map((c) => {
        const n = typeof c === "number" ? c : Number(String(c).trim() || NaN);
        return Number.isFinite(n) ? Math.round(n) : FILL_ECHO;
      }),
    });
  }
  if (profiles.length === 0) return null;
  profiles.sort((a, b) => a.t - b.t);
  const cells = Math.max(...profiles.map((p) => p.v.length));
  if (cells === 0) return null;
  const values = new Array<number>(profiles.length * cells).fill(FILL_ECHO);
  profiles.forEach((p, i) => p.v.forEach((v, j) => (values[i * cells + j] = v)));
  return { timesMs: profiles.map((p) => p.t), cells, values };
}

export interface NetcdfExportParams {
  title: string;
  scanId: string;
  folderName: string;
  scan: ProcessedScan;
  acquisition: AcquisitionMetadata;
  sonarRows?: CsvRow[];
  software?: string;
  exportedAt?: Date;
}

export function buildScanNetcdf(params: NetcdfExportParams): NcFile {
  const { scan, acquisition } = params;
  if (scan.samples.length === 0) throw new Error("Scan has no samples to export");
  const software = params.software ?? `chirp-control-web ${__APP_VERSION__}`;
  const exportedAt = params.exportedAt ?? new Date();
  const stats = depthStatistics(scan)!;
  const settled = settledDepth(scan);
  const c = scan.counts;
  const elevation = acquisition.transducerElevationM ?? null;
  const datum = acquisition.datum ?? "";
  const n = scan.samples.length;

  const attrs: Record<string, NcAttrValue> = {
    Conventions: "CF-1.8, ACDD-1.3",
    chirp_format: NETCDF_FORMAT,
    title: `CHIRP sonar bathymetry: ${params.title}`,
    summary:
      "Depth readings from a commercial CHIRP sonar (distance from the transducer face down to the " +
      "detected bottom/mudline), after the documented COE-CHIRP processing: rows without depth or time " +
      "skipped, samples sorted by time, isolated leading/trailing time islands removed, blind-spot " +
      "offset applied to depth_corrected. Raw echo profiles from sonar.csv are included when available.",
    keywords: "CHIRP sonar, bathymetry, mudline, dredging, marsh creation, settlement plate",
    institution: "Louisiana State University",
    source: `Deeper CHIRP sonar via the Fish Deeper companion app; export folder ${params.folderName}`,
    references: `${REPOSITORY} (software, data dictionary: docs/data-dictionary.md section 7)`,
    history: `${exportedAt.toISOString()} ${software}: converted from vendor bathymetry.csv/sonar.csv`,
    comment:
      "depth is positive downward from the transducer face. depth_corrected = depth + blind_spot_offset. " +
      "mudline_elevation = transducer_elevation - depth_corrected, relative to vertical_datum.",
    date_created: exportedAt.toISOString(),
    product_version: NETCDF_FORMAT,
    software,
    scan_title: params.title,
    scan_id: params.scanId,
    time_coverage_start: isoSeconds(scan.startMs!),
    time_coverage_end: isoSeconds(scan.endMs!),
    time_coverage_duration: `PT${((scan.endMs! - scan.startMs!) / 1000).toFixed(3)}S`,
    project: "COE-CHIRP",
    processing_level: "Vendor depth readings, cleaned (time-sorted, incomplete rows skipped, time islands trimmed)",
    standard_name_vocabulary: "CF Standard Name Table v84",
    processing_rows_total: c.totalRows,
    processing_rows_missing_depth_or_time: c.incompleteRows,
    processing_rows_trimmed_leading: c.droppedLeading,
    processing_rows_trimmed_trailing: c.droppedTrailing,
    processing_rows_used: c.used,
    processing_trim_rule:
      `drop leading/trailing group if gap >= max(${ISLAND_GAP_MEDIAN_MULTIPLE} x median spacing, ` +
      `${ISLAND_GAP_SPAN_FRACTION} x span) and group <= ${ISLAND_MAX_FRACTION * 100}% of samples`,
    summary_depth_corrected_mean_cm: stats.avgCm,
    summary_depth_corrected_sd_cm: stats.stdCm ?? FILL_DOUBLE,
    summary_depth_corrected_n: stats.n,
    summary_settled_window_s: SETTLED_WINDOW_S,
    summary_settled_depth_corrected_cm: settled?.depthCm ?? FILL_DOUBLE,
    summary_settled_n: settled?.n ?? 0,
  };
  const lats = scan.samples.map((s) => s.latitude).filter((v): v is number => v !== null);
  const lons = scan.samples.map((s) => s.longitude).filter((v): v is number => v !== null);
  if (lats.length > 0 && lons.length > 0) {
    attrs.geospatial_lat_min = Math.min(...lats);
    attrs.geospatial_lat_max = Math.max(...lats);
    attrs.geospatial_lon_min = Math.min(...lons);
    attrs.geospatial_lon_max = Math.max(...lons);
    attrs.geospatial_lat_units = "degrees_north";
    attrs.geospatial_lon_units = "degrees_east";
  }
  for (const spec of ACQUISITION_FIELDS) {
    const value = acquisition[spec.key];
    if (value === undefined || value === null || value === "") continue;
    attrs[`acquisition_${snake(spec.key)}`] = value as string | number;
  }

  const fill = (v: number | null) => (v === null ? FILL_DOUBLE : v);
  const vars: NcVariable[] = [
    {
      name: "time",
      type: "double",
      dims: ["obs"],
      attrs: {
        standard_name: "time",
        long_name: "time of depth reading",
        units: "milliseconds since 1970-01-01 00:00:00",
        calendar: "standard",
        coverage_content_type: "coordinate",
        comment:
          "Auxiliary coordinate, not a dimension: about 1-5% of vendor readings share a timestamp " +
          "with a neighbour, so time is not strictly monotonic. Values are kept as reported.",
      },
      data: scan.samples.map((s) => s.timeMs),
    },
    {
      name: "depth",
      type: "double",
      dims: ["obs"],
      attrs: {
        long_name: "distance from transducer face down to detected bottom, as reported by the sonar",
        units: "m",
        coordinates: "time",
        coverage_content_type: "physicalMeasurement",
        comment: "Uncorrected. The vendor's bottom-detection algorithm is not published.",
      },
      data: scan.samples.map((s) => s.depthM),
    },
    {
      name: "depth_corrected",
      type: "double",
      dims: ["obs"],
      attrs: {
        long_name: "distance from transducer face down to detected bottom, with blind-spot offset",
        units: "m",
        coordinates: "time",
        coverage_content_type: "physicalMeasurement",
        comment: "depth + blind_spot_offset",
      },
      data: scan.samples.map((s) => depthCm(scan, s) / 100),
    },
    {
      name: "temperature",
      type: "double",
      dims: ["obs"],
      attrs: {
        long_name: "water temperature at the transducer",
        units: "degree_C",
        coordinates: "time",
        coverage_content_type: "physicalMeasurement",
        _FillValue: FILL_DOUBLE,
      },
      data: scan.samples.map((s) => fill(s.temperatureC)),
    },
    {
      name: "latitude",
      type: "double",
      dims: ["obs"],
      attrs: {
        standard_name: "latitude",
        long_name: "latitude of the sonar",
        units: "degrees_north",
        coordinates: "time",
        coverage_content_type: "coordinate",
        _FillValue: FILL_DOUBLE,
        comment: "Missing when the sonar had no GPS fix (the vendor writes 0,0 or blank).",
      },
      data: scan.samples.map((s) => fill(s.latitude)),
    },
    {
      name: "longitude",
      type: "double",
      dims: ["obs"],
      attrs: {
        standard_name: "longitude",
        long_name: "longitude of the sonar",
        units: "degrees_east",
        coordinates: "time",
        coverage_content_type: "coordinate",
        _FillValue: FILL_DOUBLE,
        comment: "Missing when the sonar had no GPS fix (the vendor writes 0,0 or blank).",
      },
      data: scan.samples.map((s) => fill(s.longitude)),
    },
    {
      name: "blind_spot_offset",
      type: "double",
      dims: [],
      attrs: {
        long_name: "blind-spot offset added to every reported depth",
        units: "cm",
        coverage_content_type: "auxiliaryInformation",
        comment: "0 = no correction applied",
      },
      data: [scan.blindSpotOffsetCm],
    },
  ];

  if (elevation !== null) {
    vars.push(
      {
        name: "transducer_elevation",
        type: "double",
        dims: [],
        attrs: {
          long_name: "elevation of the transducer face while scanning",
          units: "m",
          coverage_content_type: "auxiliaryInformation",
          vertical_datum: datum || "not recorded",
        },
        data: [elevation],
      },
      {
        name: "mudline_elevation",
        type: "double",
        dims: ["obs"],
        attrs: {
          long_name: "elevation of the detected bottom (mudline)",
          units: "m",
          coordinates: "time",
          coverage_content_type: "physicalMeasurement",
          vertical_datum: datum || "not recorded",
          comment: "transducer_elevation - depth_corrected",
        },
        data: scan.samples.map((s) => mudlineElevationM(elevation, depthCm(scan, s))!),
      },
    );
  }

  const dims = [{ name: "obs", size: n }];
  const echo = params.sonarRows ? parseEchoProfiles(params.sonarRows) : null;
  if (echo) {
    dims.push({ name: "ping", size: echo.timesMs.length }, { name: "range_bin", size: echo.cells });
    vars.push(
      {
        name: "ping_time",
        type: "double",
        dims: ["ping"],
        attrs: {
          standard_name: "time",
          long_name: "time of sonar pulse (sonar.csv column 0)",
          coverage_content_type: "coordinate",
          units: "milliseconds since 1970-01-01 00:00:00",
          calendar: "standard",
        },
        data: echo.timesMs,
      },
      {
        name: "range",
        type: "double",
        dims: ["range_bin"],
        attrs: {
          long_name: "nominal distance below the transducer face of the echo cell",
          units: "m",
          coverage_content_type: "coordinate",
          comment:
            `cell index x ${ECHO_CELL_SIZE_M} m, the vendor's cell size for Deeper CHIRP series and PRO+ 2 ` +
            "(0.02738 m for PRO series, 0.03705 m for START). The origin of cell 0 is not documented by the vendor.",
        },
        data: Array.from({ length: echo.cells }, (_, i) => i * ECHO_CELL_SIZE_M),
      },
      {
        name: "echo_strength",
        type: "short",
        dims: ["ping", "range_bin"],
        attrs: {
          long_name: "echo strength per depth cell, as exported by the vendor (sonar.csv columns 1..n)",
          units: "1",
          coordinates: "ping_time range",
          coverage_content_type: "physicalMeasurement",
          _FillValue: FILL_ECHO,
          valid_range: [0, 4096],
          comment: "Vendor scale, 0-4096 for CHIRP series and PRO+ 2. Not calibrated to acoustic units.",
        },
        data: echo.values,
      },
    );
  }

  return { dims, attrs, vars };
}

export function encodeScanNetcdf(params: NetcdfExportParams): Uint8Array {
  return encodeNetcdf(buildScanNetcdf(params));
}

export function downloadBytes(fileName: string, bytes: Uint8Array, mime: string): void {
  const blob = new Blob([bytes as BlobPart], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
