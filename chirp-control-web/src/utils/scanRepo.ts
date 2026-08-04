import { createStore, get, set, del, keys } from "idb-keyval";

// Browsers have no equivalent to the Flutter app's per-scan folder on the
// local filesystem, so each scan is a single IndexedDB record instead. The
// raw CSV text is kept (not pre-parsed) so re-parsing on load matches the
// original app's behavior of reading straight from the CSV files each time.
const scansStore = createStore("chirp-control-scans", "scans");

export type CsvCell = string | number;
export type CsvRow = CsvCell[];

export function parseCsv(text: string): CsvRow[] {
  return text
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line) =>
      line.split(",").map((cell) => {
        const trimmed = cell.trim();
        if (trimmed === "") return trimmed;
        const num = Number(trimmed);
        return Number.isNaN(num) ? trimmed : num;
      }),
    );
}

interface StoredScan {
  id: string;
  folderName: string;
  sonarCsv: string;
  bathymetryCsv: string;
  title: string;
  location: string;
  notes: string;
}

export interface ScanData {
  id: string;
  folderName: string;
  sonarRows: CsvRow[];
  bathymetryRows: CsvRow[];
  title: string;
  location: string;
  time: string;
  duration: string;
  notes: string;
}

function asNumber(value: CsvCell | undefined): number | null {
  if (value === undefined) return null;
  if (typeof value === "number") return value;
  const parsed = Number(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function extractFirstTimestamp(
  sonarRows: CsvRow[],
  bathymetryRows: CsvRow[],
): number | null {
  if (bathymetryRows.length > 0) {
    for (const row of bathymetryRows) {
      if (row.length > 4) {
        const ts = asNumber(row[4]);
        if (ts !== null) return Math.round(ts);
      }
    }
  }

  if (sonarRows.length > 0) {
    for (const row of sonarRows) {
      if (row.length > 0) {
        const ts = asNumber(row[0]);
        if (ts !== null && ts > 1_000_000_000_000) return Math.round(ts);
      }
    }
  }

  return null;
}

function extractDurationSeconds(
  sonarRows: CsvRow[],
  bathymetryRows: CsvRow[],
): number {
  let firstTs: number | null = null;
  let lastTs: number | null = null;

  if (bathymetryRows.length > 0) {
    for (const row of bathymetryRows) {
      if (row.length > 4) {
        const ts = asNumber(row[4]);
        if (ts === null) continue;
        firstTs ??= ts;
        lastTs = ts;
      }
    }
  } else if (sonarRows.length > 0) {
    for (const row of sonarRows) {
      if (row.length === 0) continue;
      const ts = asNumber(row[0]);
      if (ts === null || ts < 1_000_000_000_000) continue;
      firstTs ??= ts;
      lastTs = ts;
    }
  }

  if (firstTs === null || lastTs === null) return 0;

  const seconds = Math.round((lastTs - firstTs) / 1000);
  return seconds < 0 ? 0 : seconds;
}

function formatDurationFromSeconds(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}m ${String(seconds).padStart(2, "0")}s`;
}

function formatTime(timestampMs: number): string {
  const date = new Date(timestampMs);
  const datePart = new Intl.DateTimeFormat("en-US", {
    month: "numeric",
    day: "numeric",
    year: "numeric",
  }).format(date);
  const timePart = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(date);
  return `${datePart}, ${timePart}`;
}

function toScanData(stored: StoredScan): ScanData {
  const sonarRows = stored.sonarCsv ? parseCsv(stored.sonarCsv) : [];
  const bathymetryRows = stored.bathymetryCsv
    ? parseCsv(stored.bathymetryCsv)
    : [];

  const firstTimestamp = extractFirstTimestamp(sonarRows, bathymetryRows);
  const durationSeconds = extractDurationSeconds(sonarRows, bathymetryRows);

  return {
    id: stored.id,
    folderName: stored.folderName,
    sonarRows,
    bathymetryRows,
    title: stored.title.trim() || stored.folderName.replaceAll("_", " "),
    location: stored.location.trim() || "SITE A",
    time: firstTimestamp !== null ? formatTime(firstTimestamp) : "Unknown time",
    duration: formatDurationFromSeconds(durationSeconds),
    notes: stored.notes,
  };
}

export async function loadScans(): Promise<ScanData[]> {
  const allKeys = await keys(scansStore);
  const stored = await Promise.all(
    allKeys.map((key) => get<StoredScan>(key, scansStore)),
  );
  return stored
    .filter((s): s is StoredScan => !!s)
    .map(toScanData)
    .sort((a, b) => a.folderName.localeCompare(b.folderName));
}

export async function addScan(params: {
  folderName: string;
  sonarCsv: string;
  bathymetryCsv: string;
}): Promise<ScanData> {
  const stored: StoredScan = {
    id: crypto.randomUUID(),
    folderName: params.folderName,
    sonarCsv: params.sonarCsv,
    bathymetryCsv: params.bathymetryCsv,
    title: "",
    location: "",
    notes: "",
  };
  await set(stored.id, stored, scansStore);
  return toScanData(stored);
}

export async function renameScan(
  scan: ScanData,
  newTitle: string,
): Promise<void> {
  const trimmed = newTitle.trim();
  if (!trimmed) return;

  const stored = await get<StoredScan>(scan.id, scansStore);
  if (!stored) return;
  await set(scan.id, { ...stored, title: trimmed }, scansStore);
}

export async function saveNotes(scan: ScanData, notes: string): Promise<void> {
  const stored = await get<StoredScan>(scan.id, scansStore);
  if (!stored) return;
  await set(scan.id, { ...stored, notes }, scansStore);
}

export async function deleteScan(scan: ScanData): Promise<void> {
  await del(scan.id, scansStore);
}
