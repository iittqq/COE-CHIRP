// Acquisition settings stored with every scan record (DynamoDB `acquisition`
// map, see chirp_control/lambda/scan_handler.py). Without these a scan cannot
// be interpreted later: the depth reference, any instrument correction and the
// sonar configuration all change what the numbers mean. Field meanings are
// documented in docs/data-dictionary.md.

export interface AcquisitionMetadata {
  sonarModel?: string; // e.g. "Deeper CHIRP+ 2", "Deeper PRO+ 2"
  sonarFirmware?: string;
  companionAppVersion?: string; // Fish Deeper app version on the on-site phone
  frequencyMode?: string; // e.g. "CHIRP wide (7°)", "CHIRP narrow (47°)"
  scanAngleDeg?: number | null; // beam cone angle used for this scan
  // Elevation of the transducer face, relative to `datum`, while scanning
  // (i.e. with the step motor in its lowered position).
  transducerElevationM?: number | null;
  // Height of the transducer face above the settlement plate / original
  // ground at installation, for mountings without a surveyed elevation.
  mountingHeightM?: number | null;
  datum?: string; // vertical datum of transducerElevationM, e.g. "NAVD88 (GEOID18)"
  // Signed offset in cm added to every reported depth. 0 or empty = no
  // correction applied. See README "Instrument corrections".
  blindSpotOffsetCm?: number | null;
}

export type AcquisitionKey = keyof AcquisitionMetadata;

interface FieldSpec {
  key: AcquisitionKey;
  label: string;
  kind: "text" | "number";
  unit?: string;
  help?: string;
}

export const ACQUISITION_FIELDS: FieldSpec[] = [
  { key: "sonarModel", label: "Sonar model", kind: "text", help: "e.g. Deeper CHIRP+ 2" },
  { key: "sonarFirmware", label: "Sonar firmware", kind: "text" },
  { key: "companionAppVersion", label: "Companion app version", kind: "text" },
  { key: "frequencyMode", label: "Frequency / beam mode", kind: "text" },
  { key: "scanAngleDeg", label: "Scan angle", kind: "number", unit: "°" },
  {
    key: "transducerElevationM",
    label: "Transducer elevation",
    kind: "number",
    unit: "m",
    help: "Elevation of the transducer face (lowered position) relative to the datum",
  },
  { key: "datum", label: "Vertical datum", kind: "text", help: "e.g. NAVD88 (GEOID18)" },
  {
    key: "mountingHeightM",
    label: "Mounting height",
    kind: "number",
    unit: "m",
    help: "Transducer face above the settlement plate / original ground",
  },
  {
    key: "blindSpotOffsetCm",
    label: "Blind-spot offset",
    kind: "number",
    unit: "cm",
    help: "Added to every reported depth. Leave empty for no correction.",
  },
];

export function formatAcquisitionValue(meta: AcquisitionMetadata, spec: FieldSpec): string {
  const value = meta[spec.key];
  if (value === undefined || value === null || value === "") {
    return spec.key === "blindSpotOffsetCm" ? "none applied" : "not recorded";
  }
  return spec.unit ? `${value} ${spec.unit}` : String(value);
}

// Normalizes untrusted input (API response or form state) into the typed
// shape, dropping unknown keys and blank values.
export function normalizeAcquisition(raw: unknown): AcquisitionMetadata {
  const out: AcquisitionMetadata = {};
  if (!raw || typeof raw !== "object") return out;
  const source = raw as Record<string, unknown>;
  for (const spec of ACQUISITION_FIELDS) {
    const value = source[spec.key];
    if (value === undefined || value === null || value === "") continue;
    if (spec.kind === "number") {
      const num = typeof value === "number" ? value : Number(String(value).trim());
      if (Number.isFinite(num)) (out as Record<string, unknown>)[spec.key] = num;
    } else {
      const text = String(value).trim();
      if (text) (out as Record<string, unknown>)[spec.key] = text;
    }
  }
  return out;
}
