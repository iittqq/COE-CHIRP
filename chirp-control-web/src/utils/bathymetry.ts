// Bathymetry processing: the single place that turns a vendor bathymetry.csv
// into the numbers the app shows. Every rule here is documented in the root
// README ("Data processing") and in docs/data-dictionary.md; keep the three in
// sync. The mobile app mirrors this file in
// chirp_control/lib/utils/depth_processing.dart, and both are covered by unit
// tests against the same fixtures.

import type { CsvRow } from "./csv";

// ---------------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------------

export type BathymetryField = "latitude" | "longitude" | "depth" | "temperature" | "time";

// Column order of the Deeper export as it actually appears in the files.
// NOTE: the README the vendor ships inside each export lists column 3 as the
// timestamp and column 4 as temperature. The files themselves have them the
// other way round (verified against every export used in this project), so
// the order below follows the data, not the vendor README.
export const HEADERLESS_COLUMN_ORDER: BathymetryField[] = [
  "latitude",
  "longitude",
  "depth",
  "temperature",
  "time",
];

// Accepted header names, compared after normalizeHeader(). Includes the
// vendor's own spelling ("longtitude") and the names this app writes in its
// annotated CSV export (see exportScanCsv.ts), so an export round-trips.
const HEADER_ALIASES: Record<BathymetryField, string[]> = {
  latitude: ["latitude", "lat", "latitudedeg"],
  longitude: ["longitude", "longtitude", "lon", "lng", "longitudedeg"],
  depth: ["depth", "depthm"],
  temperature: ["temperature", "temp", "temperaturec"],
  time: ["time", "timestamp", "timems", "timestampms", "timeunixms"],
};

const REQUIRED_FIELDS: BathymetryField[] = ["depth", "time"];

// Plausibility limits used to reject files that don't match the schema
// rather than silently plotting the wrong column.
const MIN_EPOCH_MS = 1_000_000_000_000; // 2001-09-09 UTC
const MAX_EPOCH_MS = 10_000_000_000_000; // 2286-11-20 UTC
const MAX_DEPTH_M = 1000;

export class BathymetryFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BathymetryFormatError";
  }
}

function normalizeHeader(cell: string): string {
  return cell
    .toLowerCase()
    .replace(/\(.*?\)|\[.*?\]/g, "")
    .replace(/[^a-z0-9]/g, "");
}

function toNumber(value: CsvRow[number] | undefined): number | null {
  if (value === undefined || value === null) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  // Number("") is 0 - treat a blank cell as missing, not as a 0 reading.
  if (value.trim() === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function isHeaderRow(row: CsvRow): boolean {
  return row.some((cell) => typeof cell === "string" && cell.trim() !== "" && toNumber(cell) === null);
}

function looksLikeEpochMs(value: number | null): boolean {
  return value !== null && value >= MIN_EPOCH_MS && value <= MAX_EPOCH_MS;
}

export interface BathymetrySample {
  timeMs: number; // Unix epoch milliseconds (UTC)
  depthM: number; // as reported by the sonar, metres below the transducer face
  temperatureC: number | null;
  latitude: number | null; // null when the export has no GPS fix (0 or blank)
  longitude: number | null;
}

export interface ParsedBathymetry {
  samples: BathymetrySample[]; // in file order
  hasHeader: boolean;
  totalRows: number; // data rows, excluding the header
  incompleteRows: number; // rows skipped because depth or time was missing
}

function columnMapFromHeader(header: CsvRow): Record<BathymetryField, number> {
  const normalized = header.map((cell) => normalizeHeader(String(cell)));
  const map = {} as Record<BathymetryField, number>;
  for (const field of Object.keys(HEADER_ALIASES) as BathymetryField[]) {
    const index = normalized.findIndex((name) => HEADER_ALIASES[field].includes(name));
    if (index !== -1) map[field] = index;
  }
  const missing = REQUIRED_FIELDS.filter((f) => map[f] === undefined);
  if (missing.length > 0) {
    throw new BathymetryFormatError(
      `bathymetry.csv header is missing required column(s): ${missing.join(", ")}. ` +
        `Found: ${header.map(String).join(", ")}.`,
    );
  }
  return map;
}

function positionalColumnMap(dataRows: CsvRow[]): Record<BathymetryField, number> {
  const map = Object.fromEntries(HEADERLESS_COLUMN_ORDER.map((f, i) => [f, i])) as Record<
    BathymetryField,
    number
  >;

  // Fail loudly if the time column doesn't hold epoch-ms timestamps. Also
  // catch the specific case where the file follows the order the vendor README
  // documents (time in column 3) instead of the order seen in real exports.
  for (const row of dataRows) {
    if (row.length < HEADERLESS_COLUMN_ORDER.length) continue;
    const time = toNumber(row[map.time]);
    if (time === null) continue;
    if (looksLikeEpochMs(time)) break; // first usable row is consistent
    if (looksLikeEpochMs(toNumber(row[map.temperature]))) {
      throw new BathymetryFormatError(
        "bathymetry.csv has its timestamp in column 4 and temperature in column 5. " +
          "This app expects latitude, longitude, depth (m), temperature (°C), time (Unix ms). " +
          "Add a header row (latitude,longitude,depth,temperature,time) to import this file.",
      );
    }
    throw new BathymetryFormatError(
      `bathymetry.csv column 5 (${time}) is not a Unix timestamp in milliseconds. ` +
        "The vendor export format may have changed; see docs/data-dictionary.md.",
    );
  }
  return map;
}

// Parses bathymetry rows by header name when the file has a header row, and by
// the documented column order when it doesn't. Throws BathymetryFormatError if
// the file doesn't match either form.
export function parseBathymetryRows(rows: CsvRow[]): ParsedBathymetry {
  const nonEmpty = rows.filter((row) => row.some((cell) => String(cell).trim() !== ""));
  if (nonEmpty.length === 0) {
    return { samples: [], hasHeader: false, totalRows: 0, incompleteRows: 0 };
  }

  const hasHeader = isHeaderRow(nonEmpty[0]);
  const dataRows = hasHeader ? nonEmpty.slice(1) : nonEmpty;
  const map = hasHeader ? columnMapFromHeader(nonEmpty[0]) : positionalColumnMap(dataRows);

  const samples: BathymetrySample[] = [];
  let incompleteRows = 0;
  for (const row of dataRows) {
    const depthM = toNumber(row[map.depth]);
    const timeMs = toNumber(row[map.time]);
    if (depthM === null || timeMs === null) {
      incompleteRows++;
      continue;
    }
    if (!looksLikeEpochMs(timeMs)) {
      throw new BathymetryFormatError(
        `bathymetry.csv has a time value (${timeMs}) that is not a Unix timestamp in milliseconds.`,
      );
    }
    if (depthM < 0 || depthM > MAX_DEPTH_M) {
      throw new BathymetryFormatError(
        `bathymetry.csv has a depth of ${depthM}, which is not a plausible depth in metres.`,
      );
    }
    const lat = map.latitude !== undefined ? toNumber(row[map.latitude]) : null;
    const lon = map.longitude !== undefined ? toNumber(row[map.longitude]) : null;
    // The vendor writes 0,0 when there is no GPS fix for a sample.
    const hasFix = lat !== null && lon !== null && !(lat === 0 && lon === 0);
    samples.push({
      timeMs,
      depthM,
      temperatureC: map.temperature !== undefined ? toNumber(row[map.temperature]) : null,
      latitude: hasFix ? lat : null,
      longitude: hasFix ? lon : null,
    });
  }

  return { samples, hasHeader, totalRows: dataRows.length, incompleteRows };
}

// ---------------------------------------------------------------------------
// Cleaning: time-island trimming
// ---------------------------------------------------------------------------

// A gap must be at least this many times the median sample spacing...
export const ISLAND_GAP_MEDIAN_MULTIPLE = 20;
// ...and at least this fraction of the whole scan's time span...
export const ISLAND_GAP_SPAN_FRACTION = 0.15;
// ...and the group cut off by it must hold at most this fraction of samples.
export const ISLAND_MAX_FRACTION = 0.15;
// Scans shorter than this many samples are never trimmed.
export const ISLAND_MIN_SAMPLES = 10;

export interface TrimResult<T> {
  kept: T[];
  droppedLeading: number;
  droppedTrailing: number;
}

// Some scans log a few samples before the device clock syncs (or after it
// drifts on reconnect), leaving them stranded seconds-to-minutes away from the
// main run. Drop a leading or trailing group of samples when it is separated
// from the rest by a gap >= max(20 x median spacing, 0.15 x total span) and
// holds <= 15% of the samples. Input must be sorted by time.
export function trimOutlyingTimeIslands<T>(sorted: T[], timeOf: (s: T) => number): TrimResult<T> {
  const untouched = { kept: sorted, droppedLeading: 0, droppedTrailing: 0 };
  if (sorted.length < ISLAND_MIN_SAMPLES) return untouched;

  const totalSpan = timeOf(sorted[sorted.length - 1]) - timeOf(sorted[0]);
  if (totalSpan <= 0) return untouched;

  const deltas: number[] = [];
  for (let i = 1; i < sorted.length; i++) deltas.push(timeOf(sorted[i]) - timeOf(sorted[i - 1]));
  const sortedDeltas = [...deltas].sort((a, b) => a - b);
  const median = sortedDeltas[Math.floor(sortedDeltas.length / 2)] || 0;

  const gapThreshold = Math.max(
    median * ISLAND_GAP_MEDIAN_MULTIPLE,
    totalSpan * ISLAND_GAP_SPAN_FRACTION,
  );

  let start = 0;
  let end = sorted.length; // exclusive
  for (let i = 1; i < sorted.length; i++) {
    if (i / sorted.length > ISLAND_MAX_FRACTION) break;
    if (deltas[i - 1] >= gapThreshold) start = i;
  }
  for (let i = sorted.length - 1; i >= 1; i--) {
    if ((sorted.length - i) / sorted.length > ISLAND_MAX_FRACTION) break;
    if (deltas[i - 1] >= gapThreshold) end = i;
  }

  if (end - start < 2) return untouched;
  return {
    kept: sorted.slice(start, end),
    droppedLeading: start,
    droppedTrailing: sorted.length - end,
  };
}

// ---------------------------------------------------------------------------
// Processed scan and derived quantities
// ---------------------------------------------------------------------------

export interface ProcessingCounts {
  totalRows: number; // data rows in bathymetry.csv
  incompleteRows: number; // skipped: depth or time missing
  droppedLeading: number; // removed by time-island trimming
  droppedTrailing: number;
  used: number; // samples behind every chart and statistic
}

export interface ProcessedScan {
  samples: BathymetrySample[]; // sorted by time, trimmed
  startMs: number | null; // time of the first used sample
  endMs: number | null;
  blindSpotOffsetCm: number; // added to every reported depth (0 = no correction)
  counts: ProcessingCounts;
}

export function processBathymetry(
  rows: CsvRow[],
  options: { blindSpotOffsetCm?: number | null } = {},
): ProcessedScan {
  const parsed = parseBathymetryRows(rows);
  const sorted = [...parsed.samples].sort((a, b) => a.timeMs - b.timeMs);
  const trim = trimOutlyingTimeIslands(sorted, (s) => s.timeMs);
  const samples = trim.kept;
  return {
    samples,
    startMs: samples.length ? samples[0].timeMs : null,
    endMs: samples.length ? samples[samples.length - 1].timeMs : null,
    blindSpotOffsetCm: options.blindSpotOffsetCm ?? 0,
    counts: {
      totalRows: parsed.totalRows,
      incompleteRows: parsed.incompleteRows,
      droppedLeading: trim.droppedLeading,
      droppedTrailing: trim.droppedTrailing,
      used: samples.length,
    },
  };
}

// Depth in cm below the transducer face, with the scan's blind-spot offset.
export function depthCm(scan: ProcessedScan, sample: BathymetrySample): number {
  return sample.depthM * 100 + scan.blindSpotOffsetCm;
}

export interface DepthStatistics {
  avgCm: number;
  minCm: number;
  maxCm: number;
  stdCm: number | null; // sample standard deviation (n - 1); null when n < 2
  n: number;
}

export function depthStatistics(scan: ProcessedScan): DepthStatistics | null {
  const values = scan.samples.map((s) => depthCm(scan, s));
  const n = values.length;
  if (n === 0) return null;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = n > 1 ? values.reduce((a, v) => a + (v - mean) ** 2, 0) / (n - 1) : null;
  return {
    avgCm: mean,
    minCm: Math.min(...values),
    maxCm: Math.max(...values),
    stdCm: variance === null ? null : Math.sqrt(variance),
    n,
  };
}

// Settled depth = mean depth over the final SETTLED_WINDOW_S seconds of the
// scan (by timestamp, after trimming). A fixed time window gives the same
// meaning at any sampling rate, unlike the previous "last 20 rows".
export const SETTLED_WINDOW_S = 30;

export interface SettledDepth {
  depthCm: number;
  n: number; // samples inside the window
  windowS: number;
}

export function settledDepth(scan: ProcessedScan, windowS = SETTLED_WINDOW_S): SettledDepth | null {
  if (scan.endMs === null) return null;
  const cutoff = scan.endMs - windowS * 1000;
  const values = scan.samples.filter((s) => s.timeMs >= cutoff).map((s) => depthCm(scan, s));
  if (values.length === 0) return null;
  return { depthCm: values.reduce((a, b) => a + b, 0) / values.length, n: values.length, windowS };
}

export interface DepthChange {
  changeCm: number; // settled(latest) - settled(earliest); negative = mudline rose
  earliestIndex: number;
  latestIndex: number;
}

// Signed change between the earliest and the latest scan (ordered by each
// scan's first timestamp, not by the order they were selected in).
// Depth is measured downward from the transducer, so a negative change means
// the mudline moved up toward the sonar (deposition) and a positive change
// means it moved down (consolidation, settlement or erosion).
export function depthChange(scans: ProcessedScan[]): DepthChange | null {
  const candidates = scans
    .map((scan, index) => ({ index, start: scan.startMs, settled: settledDepth(scan) }))
    .filter(
      (c): c is { index: number; start: number; settled: SettledDepth } =>
        c.start !== null && c.settled !== null,
    )
    .sort((a, b) => a.start - b.start);
  if (candidates.length < 2) return null;
  const earliest = candidates[0];
  const latest = candidates[candidates.length - 1];
  return {
    changeCm: latest.settled.depthCm - earliest.settled.depthCm,
    earliestIndex: earliest.index,
    latestIndex: latest.index,
  };
}

export function describeDepthChange(changeCm: number): string {
  if (Math.abs(changeCm) < 0.005) return "no change";
  return changeCm < 0 ? "mudline rose" : "mudline fell";
}

// Mudline elevation relative to the scan's datum, when the transducer face
// elevation is known: elevation = transducer elevation - corrected depth.
export function mudlineElevationM(
  transducerElevationM: number | null | undefined,
  depthCmValue: number | null | undefined,
): number | null {
  if (transducerElevationM === null || transducerElevationM === undefined) return null;
  if (depthCmValue === null || depthCmValue === undefined) return null;
  return transducerElevationM - depthCmValue / 100;
}

export function processingSummary(counts: ProcessingCounts): string {
  const trimmed = counts.droppedLeading + counts.droppedTrailing;
  const parts = [`${counts.used} of ${counts.totalRows} rows used`];
  if (counts.incompleteRows > 0) parts.push(`${counts.incompleteRows} missing depth or time`);
  if (trimmed > 0) {
    parts.push(
      `${trimmed} removed as isolated time islands (${counts.droppedLeading} leading, ${counts.droppedTrailing} trailing)`,
    );
  }
  return parts.join("; ");
}

// Screen-friendly wrapper: never throws, returns the format error instead so
// the UI can show it rather than plotting a partially-read file.
export function tryProcessBathymetry(
  rows: CsvRow[],
  options: { blindSpotOffsetCm?: number | null } = {},
): { scan: ProcessedScan | null; error: string | null } {
  try {
    return { scan: processBathymetry(rows, options), error: null };
  } catch (err) {
    if (err instanceof BathymetryFormatError) return { scan: null, error: err.message };
    throw err;
  }
}
