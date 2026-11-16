// Self-describing ("annotated") CSV export of one processed scan. The file
// carries its own metadata block (lines starting with "#"), named columns with
// units in the name, and the processing that produced each value, so it can be
// read without this app. The format is specified in docs/data-dictionary.md
// ("Annotated CSV export"). The header names are accepted by
// parseBathymetryRows, so an export can be re-imported.

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

export const ANNOTATED_CSV_FORMAT = "chirp-bathymetry-csv/1.0";

export const ANNOTATED_CSV_COLUMNS: { name: string; description: string }[] = [
  { name: "time_unix_ms", description: "Sample time, Unix epoch milliseconds, UTC" },
  { name: "elapsed_s", description: "Seconds since the first used sample" },
  { name: "latitude_deg", description: "WGS 84 latitude; empty when the sonar had no GPS fix" },
  { name: "longitude_deg", description: "WGS 84 longitude; empty when the sonar had no GPS fix" },
  { name: "depth_m", description: "Depth below the transducer face as reported by the sonar (uncorrected)" },
  { name: "depth_corrected_m", description: "depth_m + blind_spot_offset_cm / 100" },
  { name: "temperature_c", description: "Water temperature at the transducer, degrees Celsius" },
  {
    name: "mudline_elevation_m",
    description: "transducer_elevation_m - depth_corrected_m, relative to vertical_datum; empty if elevation unknown",
  },
];

function metaLine(key: string, value: string | number | null | undefined): string {
  const text = value === null || value === undefined || value === "" ? "" : String(value);
  return `# ${key}: ${text.replace(/[\r\n]+/g, " ")}`;
}

function num(value: number | null | undefined, digits: number): string {
  return value === null || value === undefined ? "" : value.toFixed(digits);
}

export function buildAnnotatedCsv(params: {
  title: string;
  scanId: string;
  folderName: string;
  scan: ProcessedScan;
  acquisition: AcquisitionMetadata;
  exportedAt?: Date;
}): string {
  const { scan, acquisition } = params;
  const stats = depthStatistics(scan);
  const settled = settledDepth(scan);
  const exportedAt = params.exportedAt ?? new Date();
  const c = scan.counts;

  const lines: string[] = [
    "# CHIRP processed bathymetry export",
    metaLine("format", ANNOTATED_CSV_FORMAT),
    metaLine("specification", "docs/data-dictionary.md in the COE-CHIRP repository"),
    metaLine("software", `chirp-control-web ${__APP_VERSION__}`),
    metaLine("exported_utc", exportedAt.toISOString()),
    metaLine("scan_title", params.title),
    metaLine("scan_id", params.scanId),
    metaLine("source_folder", params.folderName),
    metaLine("scan_start_utc", scan.startMs !== null ? new Date(scan.startMs).toISOString() : null),
    metaLine("scan_end_utc", scan.endMs !== null ? new Date(scan.endMs).toISOString() : null),
    metaLine("depth_reference", "transducer face, positive downward"),
  ];

  for (const spec of ACQUISITION_FIELDS) {
    const value = acquisition[spec.key];
    const key = spec.key.replace(/[A-Z]/g, (ch) => `_${ch.toLowerCase()}`);
    lines.push(metaLine(`acquisition.${key}`, value as string | number | null | undefined));
  }

  lines.push(
    metaLine("blind_spot_offset_cm_applied", scan.blindSpotOffsetCm),
    metaLine("processing.rows_total", c.totalRows),
    metaLine("processing.rows_missing_depth_or_time", c.incompleteRows),
    metaLine("processing.rows_trimmed_leading", c.droppedLeading),
    metaLine("processing.rows_trimmed_trailing", c.droppedTrailing),
    metaLine("processing.rows_used", c.used),
    metaLine(
      "processing.trim_rule",
      `drop leading/trailing group if gap >= max(${ISLAND_GAP_MEDIAN_MULTIPLE} x median spacing, ` +
        `${ISLAND_GAP_SPAN_FRACTION} x span) and group <= ${ISLAND_MAX_FRACTION * 100}% of samples`,
    ),
    metaLine("summary.depth_mean_cm", num(stats?.avgCm, 2)),
    metaLine("summary.depth_sd_cm", num(stats?.stdCm, 2)),
    metaLine("summary.depth_min_cm", num(stats?.minCm, 2)),
    metaLine("summary.depth_max_cm", num(stats?.maxCm, 2)),
    metaLine("summary.n", stats?.n ?? 0),
    metaLine("summary.settled_window_s", SETTLED_WINDOW_S),
    metaLine("summary.settled_depth_cm", num(settled?.depthCm, 2)),
    metaLine("summary.settled_n", settled?.n ?? 0),
  );
  for (const col of ANNOTATED_CSV_COLUMNS) {
    lines.push(metaLine(`column.${col.name}`, col.description));
  }

  lines.push(ANNOTATED_CSV_COLUMNS.map((col) => col.name).join(","));

  const start = scan.startMs ?? 0;
  for (const s of scan.samples) {
    const corrected = depthCm(scan, s);
    lines.push(
      [
        String(s.timeMs),
        ((s.timeMs - start) / 1000).toFixed(3),
        s.latitude === null ? "" : String(s.latitude),
        s.longitude === null ? "" : String(s.longitude),
        String(s.depthM),
        (corrected / 100).toFixed(4),
        s.temperatureC === null ? "" : String(s.temperatureC),
        num(mudlineElevationM(acquisition.transducerElevationM, corrected), 4),
      ].join(","),
    );
  }

  return lines.join("\n") + "\n";
}

export function downloadText(fileName: string, text: string, mime = "text/csv"): void {
  const blob = new Blob([text], { type: `${mime};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function safeFileName(name: string): string {
  return name.replace(/[^A-Za-z0-9._ -]+/g, "_").trim() || "scan";
}
