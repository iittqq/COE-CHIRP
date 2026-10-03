import JSZip from "jszip";
import { addScan, type ScanData } from "./scanRepo";
import { getSession } from "./auth";

const CSV_NAMES = ["sonar.csv", "bathymetry.csv"];

// Spread onto an <input type="file"> to make it pick a whole folder instead
// of files. React's types don't know these attributes.
export const FOLDER_INPUT_PROPS = { webkitdirectory: "", directory: "" };

function baseName(path: string): string {
  return path.toLowerCase().split("/").pop() ?? "";
}

function isZip(file: File): boolean {
  return /\.zip$/i.test(file.name);
}

function findEntry(zip: JSZip, lowerName: string) {
  return Object.values(zip.files).find(
    (file) => !file.dir && baseName(file.name) === lowerName,
  );
}

// Loose CSVs are matched by suffix so exports like "scan1_sonar.csv" work
// alongside plain "sonar.csv".
function findLooseCsv(files: File[], kind: string): File | undefined {
  return files.find((f) => f.name.toLowerCase().endsWith(kind));
}

// Same identifying name a re-import of the same files would produce, so it
// can be checked against existing scans (via scanRepo's
// findScanByFolderName) before actually reading/importing. A zip is named
// after the zip and a picked folder after the folder. Loose CSVs fall back
// to whatever prefix their filenames share ("scan1_sonar.csv" -> "scan1"),
// or a timestamp when they're plain "sonar.csv" / "bathymetry.csv".
export function deriveFolderName(files: File[]): string {
  const zip = files.find(isZip);
  if (zip) return zip.name.replace(/\.zip$/i, "") || `scan_${Date.now()}`;

  // Picked folders: webkitRelativePath is "<folder>/<...>/<file>".
  const folder = files
    .map((f) => f.webkitRelativePath.split("/")[0])
    .find((name) => name);
  if (folder) return folder;

  for (const file of files) {
    const prefix = file.name
      .replace(/\.csv$/i, "")
      .replace(/[_\-. ]*(sonar|bathymetry)$/i, "");
    if (prefix) return prefix;
  }
  return `scan_${Date.now()}`;
}

export async function importScanFiles(
  files: File[],
  options?: { overwriteId?: string },
): Promise<ScanData> {
  let sonarCsv = "";
  let bathymetryCsv = "";

  const zipFile = files.find(isZip);
  if (zipFile) {
    const zip = await JSZip.loadAsync(zipFile);
    const sonarEntry = findEntry(zip, "sonar.csv");
    const bathymetryEntry = findEntry(zip, "bathymetry.csv");
    if (!sonarEntry && !bathymetryEntry) {
      throw new Error("Zip did not contain sonar.csv or bathymetry.csv");
    }
    sonarCsv = sonarEntry ? await sonarEntry.async("string") : "";
    bathymetryCsv = bathymetryEntry ? await bathymetryEntry.async("string") : "";
  } else {
    const sonarFile = findLooseCsv(files, CSV_NAMES[0]);
    const bathymetryFile = findLooseCsv(files, CSV_NAMES[1]);
    if (!sonarFile && !bathymetryFile) {
      throw new Error("Folder did not contain sonar.csv or bathymetry.csv");
    }
    sonarCsv = sonarFile ? await sonarFile.text() : "";
    bathymetryCsv = bathymetryFile ? await bathymetryFile.text() : "";
  }

  return addScan({
    folderName: deriveFolderName(files),
    sonarCsv,
    bathymetryCsv,
    userId: getSession()?.user_id,
    overwriteId: options?.overwriteId,
  });
}
