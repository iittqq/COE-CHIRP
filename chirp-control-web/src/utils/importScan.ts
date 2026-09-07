import JSZip from "jszip";
import { addScan, type ScanData } from "./scanRepo";
import { getSession } from "./auth";

function findEntry(zip: JSZip, lowerName: string) {
  return Object.values(zip.files).find(
    (file) => !file.dir && file.name.toLowerCase().split("/").pop() === lowerName,
  );
}

// Same identifying name a re-import of the same file would produce, so it
// can be checked against existing scans (via scanRepo's
// findScanByFolderName) before actually reading/importing the zip.
export function deriveFolderName(fileName: string): string {
  return fileName.replace(/\.zip$/i, "") || `scan_${Date.now()}`;
}

export async function importScanZip(
  file: File,
  options?: { overwriteId?: string },
): Promise<ScanData> {
  const zip = await JSZip.loadAsync(file);

  const sonarEntry = findEntry(zip, "sonar.csv");
  const bathymetryEntry = findEntry(zip, "bathymetry.csv");

  if (!sonarEntry && !bathymetryEntry) {
    throw new Error("Zip did not contain sonar.csv or bathymetry.csv");
  }

  const sonarCsv = sonarEntry ? await sonarEntry.async("string") : "";
  const bathymetryCsv = bathymetryEntry
    ? await bathymetryEntry.async("string")
    : "";

  const folderName = deriveFolderName(file.name);

  return addScan({
    folderName,
    sonarCsv,
    bathymetryCsv,
    userId: getSession()?.user_id,
    overwriteId: options?.overwriteId,
  });
}
