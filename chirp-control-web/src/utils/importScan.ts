import JSZip from "jszip";
import { addScan, type ScanData } from "./scanRepo";

function findEntry(zip: JSZip, lowerName: string) {
  return Object.values(zip.files).find(
    (file) => !file.dir && file.name.toLowerCase().split("/").pop() === lowerName,
  );
}

export async function importScanZip(file: File): Promise<ScanData> {
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

  const folderName = file.name.replace(/\.zip$/i, "") || `scan_${Date.now()}`;

  return addScan({ folderName, sonarCsv, bathymetryCsv });
}
