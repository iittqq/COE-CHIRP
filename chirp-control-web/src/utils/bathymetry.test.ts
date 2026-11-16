import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { parseCsv } from "./csv";
import {
  BathymetryFormatError,
  depthChange,
  depthStatistics,
  parseBathymetryRows,
  processBathymetry,
  settledDepth,
  SETTLED_WINDOW_S,
  trimOutlyingTimeIslands,
} from "./bathymetry";
import { buildAnnotatedCsv } from "./exportScanCsv";
import { computeDepthSpots } from "./depthChart";

// Shared with the mobile app's tests; regenerate with
// python3 test-fixtures/bathymetry/generate.py
const FIXTURES = new URL("../../../test-fixtures/bathymetry/", import.meta.url);
const read = (name: string) => readFileSync(new URL(name, FIXTURES), "utf-8");
const rows = (name: string) => parseCsv(read(name));
const expected = JSON.parse(read("expected.json"));

interface Expected {
  totalRows: number;
  incompleteRows: number;
  droppedLeading: number;
  droppedTrailing: number;
  used: number;
  startMs: number;
  endMs: number;
  avgCm: number;
  sdCm: number;
  minCm: number;
  maxCm: number;
  settledCm: number;
  settledN: number;
}

function checkAgainst(scan: ReturnType<typeof processBathymetry>, exp: Expected) {
  expect(scan.counts).toEqual({
    totalRows: exp.totalRows,
    incompleteRows: exp.incompleteRows,
    droppedLeading: exp.droppedLeading,
    droppedTrailing: exp.droppedTrailing,
    used: exp.used,
  });
  expect(scan.startMs).toBe(exp.startMs);
  expect(scan.endMs).toBe(exp.endMs);
  const stats = depthStatistics(scan)!;
  expect(stats.n).toBe(exp.used);
  expect(stats.avgCm).toBeCloseTo(exp.avgCm, 9);
  expect(stats.stdCm!).toBeCloseTo(exp.sdCm, 9);
  expect(stats.minCm).toBeCloseTo(exp.minCm, 9);
  expect(stats.maxCm).toBeCloseTo(exp.maxCm, 9);
  const settled = settledDepth(scan)!;
  expect(settled.depthCm).toBeCloseTo(exp.settledCm, 9);
  expect(settled.n).toBe(exp.settledN);
}

describe("bathymetry schema", () => {
  it("uses the shared settled window", () => {
    expect(SETTLED_WINDOW_S).toBe(expected.settledWindowS);
  });

  for (const name of Object.keys(expected.files)) {
    it(`processes ${name} as documented`, () => {
      checkAgainst(processBathymetry(rows(name)), expected.files[name]);
    });
  }

  it("reads a header row by name, including the vendor's 'longtitude' spelling", () => {
    const parsed = parseBathymetryRows(rows("header.csv"));
    expect(parsed.hasHeader).toBe(true);
    expect(parsed.samples[0].temperatureC).toBe(23);
    expect(parsed.samples[0].latitude).toBeNull();
  });

  it("treats 0,0 coordinates as no GPS fix", () => {
    const parsed = parseBathymetryRows(rows("headerless.csv"));
    expect(parsed.hasHeader).toBe(false);
    expect(parsed.samples[0].latitude).toBeNull();
    expect(parsed.samples[0].longitude).toBeNull();
  });

  for (const [name, fragment] of Object.entries(expected.errors as Record<string, string>)) {
    it(`rejects ${name}`, () => {
      expect(() => parseBathymetryRows(rows(name))).toThrow(BathymetryFormatError);
      expect(() => parseBathymetryRows(rows(name))).toThrow(fragment);
    });
  }

  it("returns an empty result for an empty file", () => {
    expect(processBathymetry([]).counts.used).toBe(0);
    expect(depthStatistics(processBathymetry([]))).toBeNull();
  });
});

describe("derived quantities", () => {
  it("applies the blind-spot offset to every statistic", () => {
    const scan = processBathymetry(rows("headerless.csv"), { blindSpotOffsetCm: 5 });
    checkAgainst(scan, expected.files["headerless.csv"].blindSpotOffset5);
  });

  it("computes the settled depth by time, not by file order", () => {
    // The deepest (latest-in-time) rows come first in unsorted.csv, so the
    // old "last 20 rows in file order" rule would return 50.0 cm.
    const settled = settledDepth(processBathymetry(rows("unsorted.csv")))!;
    expect(settled.depthCm).not.toBeCloseTo(50, 3);
  });

  it("signs the depth change from the earliest to the latest scan", () => {
    const { inputs, changeCm, earliest, latest } = expected.depthChange;
    const scans = (inputs as string[]).map((n) => processBathymetry(rows(n)));
    const result = depthChange(scans)!;
    expect(result.changeCm).toBeCloseTo(changeCm, 9);
    expect(inputs[result.earliestIndex]).toBe(earliest);
    expect(inputs[result.latestIndex]).toBe(latest);
    // Reversing the input order must not change the sign.
    expect(depthChange([...scans].reverse())!.changeCm).toBeCloseTo(changeCm, 9);
  });

  it("needs two scans for a depth change", () => {
    expect(depthChange([processBathymetry(rows("headerless.csv"))])).toBeNull();
  });

  it("does not trim short scans or scans without islands", () => {
    const pts = Array.from({ length: 9 }, (_, i) => i * (i === 1 ? 1000 : 1));
    expect(trimOutlyingTimeIslands(pts, (t) => t).kept).toHaveLength(9);
  });

  it("charts the same samples the statistics use", () => {
    const scan = processBathymetry(rows("header.csv"));
    const spots = computeDepthSpots(scan, true);
    expect(spots).toHaveLength(scan.counts.used);
    expect(spots[0].x).toBe(0);
    expect(-spots[0].y).toBeCloseTo(scan.samples[0].depthM * 100, 9);
  });
});

describe("annotated CSV export", () => {
  it("round-trips through the importer", () => {
    const scan = processBathymetry(rows("header.csv"), { blindSpotOffsetCm: 2 });
    const csv = buildAnnotatedCsv({
      title: "Test scan",
      scanId: "abc",
      folderName: "scan_test",
      scan,
      acquisition: { sonarModel: "Deeper CHIRP+ 2", transducerElevationM: 1.5, datum: "NAVD88" },
      exportedAt: new Date(0),
    });
    expect(csv).toContain("# format: chirp-bathymetry-csv/1.0");
    expect(csv).toContain("# acquisition.sonar_model: Deeper CHIRP+ 2");
    expect(csv).toContain("# processing.rows_trimmed_leading: 2");

    const reparsed = processBathymetry(parseCsv(csv));
    expect(reparsed.counts.used).toBe(scan.counts.used);
    expect(reparsed.samples.map((s) => s.depthM)).toEqual(scan.samples.map((s) => s.depthM));

    const firstData = csv.split("\n").find((l) => /^\d/.test(l))!.split(",");
    const corrected = Number(firstData[5]);
    expect(corrected).toBeCloseTo(scan.samples[0].depthM + 0.02, 6);
    expect(Number(firstData[7])).toBeCloseTo(1.5 - corrected, 4);
  });
});
