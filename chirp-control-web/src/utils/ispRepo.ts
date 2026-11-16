import { createStore, get, set, del, keys } from "idb-keyval";

// ISP (Instrumented Settlement Plate) datasets, imported from spreadsheets.
// Kept in a separate IndexedDB store from scans since they're a different
// kind of record (tabular spreadsheet data rather than sonar CSV logs).
const ispStore = createStore("chirp-control-isp", "isp");

export type IspCell = string | number | null;

interface StoredIspRecord {
  id: string;
  fileName: string;
  title: string;
  location: string;
  notes: string;
  uploadedAt: number;
  sheetName: string;
  headers: string[];
  rows: IspCell[][];
  userId?: string;
}

export type IspRecord = StoredIspRecord;

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

export function formatIspUploadedTime(record: IspRecord): string {
  return formatTime(record.uploadedAt);
}

function stripExtension(fileName: string): string {
  return fileName.replace(/\.[^./]+$/, "");
}

function toRecord(stored: StoredIspRecord): IspRecord {
  return {
    ...stored,
    title: stored.title.trim() || stripExtension(stored.fileName).replaceAll("_", " "),
    location: stored.location.trim() || "SITE A",
  };
}

export async function loadIspRecords(): Promise<IspRecord[]> {
  const allKeys = await keys(ispStore);
  const stored = await Promise.all(
    allKeys.map((key) => get<StoredIspRecord>(key, ispStore)),
  );
  return stored
    .filter((r): r is StoredIspRecord => !!r)
    .map(toRecord)
    .sort((a, b) => b.uploadedAt - a.uploadedAt);
}

export async function findIspRecordByFileName(
  fileName: string,
): Promise<IspRecord | undefined> {
  const records = await loadIspRecords();
  return records.find((record) => record.fileName === fileName);
}

export async function addIspRecord(params: {
  fileName: string;
  sheetName: string;
  headers: string[];
  rows: IspCell[][];
  userId?: string;
  // Pass an existing record's id to overwrite that record in place instead
  // of creating a new one (used by the duplicate-import confirmation flow).
  overwriteId?: string;
}): Promise<IspRecord> {
  const stored: StoredIspRecord = {
    id: params.overwriteId ?? crypto.randomUUID(),
    fileName: params.fileName,
    title: "",
    location: "",
    notes: "",
    uploadedAt: Date.now(),
    sheetName: params.sheetName,
    headers: params.headers,
    rows: params.rows,
    userId: params.userId,
  };
  await set(stored.id, stored, ispStore);
  return toRecord(stored);
}

export async function renameIspRecord(
  record: IspRecord,
  newTitle: string,
): Promise<void> {
  const trimmed = newTitle.trim();
  if (!trimmed) return;

  const stored = await get<StoredIspRecord>(record.id, ispStore);
  if (!stored) return;
  await set(record.id, { ...stored, title: trimmed }, ispStore);
}

export async function saveIspNotes(record: IspRecord, notes: string): Promise<void> {
  const stored = await get<StoredIspRecord>(record.id, ispStore);
  if (!stored) return;
  await set(record.id, { ...stored, notes }, ispStore);
}

export async function deleteIspRecord(record: IspRecord): Promise<void> {
  await del(record.id, ispStore);
}

// ISP records live only in this browser's IndexedDB (they are not sent to the
// backend), so they are lost if site data is cleared and other users cannot
// see them. This export is the way to keep or share them: one JSON file with
// every record's original sheet (headers + rows), title, location and notes.
// See docs/data-dictionary.md, "ISP export".
export const ISP_EXPORT_FORMAT = "chirp-isp-export/1.0";

export function buildIspExport(records: IspRecord[], exportedAt = new Date()): string {
  return JSON.stringify(
    {
      format: ISP_EXPORT_FORMAT,
      software: `chirp-control-web ${__APP_VERSION__}`,
      exportedUtc: exportedAt.toISOString(),
      note: "Instrumented Settlement Plate records as imported from their source spreadsheets; values are unmodified.",
      records: records.map((r) => ({
        id: r.id,
        title: r.title,
        location: r.location,
        notes: r.notes,
        sourceFileName: r.fileName,
        sheetName: r.sheetName,
        importedUtc: new Date(r.uploadedAt).toISOString(),
        headers: r.headers,
        rows: r.rows,
      })),
    },
    null,
    2,
  );
}
