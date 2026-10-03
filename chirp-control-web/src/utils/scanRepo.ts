import { createStore, get, del, keys } from "idb-keyval";
import { getSession } from "./auth";
import { API_BASE_URL as BASE_URL } from "./config";

// Scans live in the backend (see lambda/scan_handler.py): metadata in
// DynamoDB, raw CSVs in S3. The raw CSV text is kept (not pre-parsed) so
// re-parsing on load matches the original app's behavior of reading straight
// from the CSV files each time.

// Scans used to be stored only in this browser's IndexedDB. That store is
// only read now, to upload leftovers to the backend on first load (see
// migrateLocalScans). Don't remove it until old installs have had a chance
// to migrate.
const legacyScansStore = createStore("chirp-control-scans", "scans");

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
  userId?: string;
}

interface ApiScan {
  id: string;
  folderName: string;
  title: string;
  location: string;
  notes: string;
  sonarCsvUrl: string;
  bathymetryCsvUrl: string;
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
  userId?: string;
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
    userId: stored.userId,
  };
}

function requireUserId(): string {
  const session = getSession();
  if (!session) {
    throw new Error("Scans require a logged-in account.");
  }
  return session.user_id;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${BASE_URL}${path}`, init);
  if (!response.ok) {
    throw new Error(`Scan request failed (${response.status}): ${await response.text()}`);
  }
  return (await response.json()) as T;
}

async function fetchCsv(url: string): Promise<string> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download scan data (${response.status})`);
  }
  return response.text();
}

async function apiToScanData(scan: ApiScan, userId: string): Promise<ScanData> {
  const [sonarCsv, bathymetryCsv] = await Promise.all([
    fetchCsv(scan.sonarCsvUrl),
    fetchCsv(scan.bathymetryCsvUrl),
  ]);
  return toScanData({
    id: scan.id,
    folderName: scan.folderName,
    sonarCsv,
    bathymetryCsv,
    title: scan.title,
    location: scan.location,
    notes: scan.notes,
    userId,
  });
}

async function postScan(params: {
  userId: string;
  scanId?: string;
  folderName: string;
  sonarCsv: string;
  bathymetryCsv: string;
}): Promise<ApiScan> {
  const { scan } = await request<{ scan: ApiScan }>("/scans", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      user_id: params.userId,
      scan_id: params.scanId,
      folder_name: params.folderName,
      sonar_csv: params.sonarCsv,
      bathymetry_csv: params.bathymetryCsv,
    }),
  });
  return scan;
}

async function updateScan(
  scanId: string,
  fields: { title?: string; notes?: string },
): Promise<void> {
  await request("/scans", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user_id: requireUserId(), scan_id: scanId, ...fields }),
  });
}

// Uploads any scans still sitting in this browser's old IndexedDB store to
// the logged-in account, then removes each local copy only after its upload
// succeeded, so a failure (offline, API error) loses nothing and retries on
// the next load.
async function migrateLocalScans(userId: string): Promise<void> {
  const localKeys = await keys(legacyScansStore);
  for (const key of localKeys) {
    const stored = await get<StoredScan>(key, legacyScansStore);
    if (!stored) continue;
    const scan = await postScan({
      userId,
      scanId: stored.id,
      folderName: stored.folderName,
      sonarCsv: stored.sonarCsv,
      bathymetryCsv: stored.bathymetryCsv,
    });
    if (stored.title || stored.notes) {
      await updateScan(scan.id, { title: stored.title, notes: stored.notes });
    }
    await del(key, legacyScansStore);
  }
}

export async function loadScans(): Promise<ScanData[]> {
  const userId = requireUserId();
  try {
    await migrateLocalScans(userId);
  } catch {
    // Leave local scans in place; migration retries on the next load.
  }
  const { scans } = await request<{ scans: ApiScan[] }>(
    `/scans?user_id=${encodeURIComponent(userId)}`,
  );
  const loaded = await Promise.all(scans.map((s) => apiToScanData(s, userId)));
  return loaded.sort((a, b) => a.folderName.localeCompare(b.folderName));
}

export async function findScanByFolderName(
  folderName: string,
): Promise<ScanData | undefined> {
  const scans = await loadScans();
  return scans.find((scan) => scan.folderName === folderName);
}

export async function addScan(params: {
  folderName: string;
  sonarCsv: string;
  bathymetryCsv: string;
  userId?: string;
  // Pass an existing scan's id to overwrite that record in place instead of
  // creating a new one (used by the duplicate-import confirmation flow).
  overwriteId?: string;
}): Promise<ScanData> {
  const userId = params.userId ?? requireUserId();
  const scan = await postScan({
    userId,
    scanId: params.overwriteId,
    folderName: params.folderName,
    sonarCsv: params.sonarCsv,
    bathymetryCsv: params.bathymetryCsv,
  });
  return toScanData({
    id: scan.id,
    folderName: scan.folderName,
    sonarCsv: params.sonarCsv,
    bathymetryCsv: params.bathymetryCsv,
    title: scan.title,
    location: scan.location,
    notes: scan.notes,
    userId,
  });
}

export async function renameScan(
  scan: ScanData,
  newTitle: string,
): Promise<void> {
  const trimmed = newTitle.trim();
  if (!trimmed) return;
  await updateScan(scan.id, { title: trimmed });
}

export async function saveNotes(scan: ScanData, notes: string): Promise<void> {
  await updateScan(scan.id, { notes });
}

export async function deleteScan(scan: ScanData): Promise<void> {
  await request(
    `/scans?user_id=${encodeURIComponent(requireUserId())}&scan_id=${encodeURIComponent(scan.id)}`,
    { method: "DELETE" },
  );
}
