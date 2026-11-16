import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { parseCsv } from "./csv";
import { processBathymetry } from "./bathymetry";
import { encodeNetcdf } from "./netcdf";
import { buildScanNetcdf, encodeScanNetcdf, FILL_ECHO, parseEchoProfiles } from "./exportScanNetcdf";

const FIXTURES = new URL("../../../test-fixtures/", import.meta.url);
const read = (path: string) => readFileSync(new URL(path, FIXTURES), "utf-8");
const GOLDEN = new URL("netcdf/header.nc", FIXTURES);

// The exact parameters are repeated in data_visualization/test_chirp_netcdf.py,
// which checks that the Python exporter writes the same dataset as this file.
function goldenBytes(): Uint8Array {
  return encodeScanNetcdf({
    title: "header fixture",
    scanId: "fixture-0001",
    folderName: "header",
    scan: processBathymetry(parseCsv(read("bathymetry/header.csv")), { blindSpotOffsetCm: 2 }),
    acquisition: {
      sonarModel: "Deeper CHIRP+ 2",
      scanAngleDeg: 7,
      transducerElevationM: 1.25,
      datum: "NAVD88 (GEOID18)",
      blindSpotOffsetCm: 2,
    },
    sonarRows: parseCsv(read("bathymetry/header_sonar.csv")),
    software: "chirp-control-web golden",
    exportedAt: new Date(Date.UTC(2026, 0, 1)),
  });
}

describe("NetCDF export", () => {
  it("matches the golden file shared with the Python exporter", () => {
    const bytes = goldenBytes();
    // Regenerate after an intentional format change with:
    //   UPDATE_GOLDEN=1 pnpm test
    if (process.env.UPDATE_GOLDEN === "1") {
      mkdirSync(new URL("netcdf/", FIXTURES), { recursive: true });
      writeFileSync(GOLDEN, bytes);
    }
    if (!existsSync(GOLDEN)) {
      throw new Error("test-fixtures/netcdf/header.nc is missing; run UPDATE_GOLDEN=1 pnpm test and commit it");
    }
    expect(Buffer.from(bytes).equals(readFileSync(GOLDEN))).toBe(true);
  });

  it("writes a NetCDF classic header", () => {
    const bytes = goldenBytes();
    expect(Array.from(bytes.slice(0, 4))).toEqual([0x43, 0x44, 0x46, 0x01]); // "CDF\x01"
  });

  it("pads ragged echo rows and skips rows without a timestamp", () => {
    const echo = parseEchoProfiles(parseCsv(read("bathymetry/header_sonar.csv")))!;
    expect(echo.timesMs).toHaveLength(12);
    expect(echo.cells).toBe(7);
    expect(echo.values.slice(0, 7)).toEqual([0, 11, 22, 33, 44, FILL_ECHO, FILL_ECHO]);
    expect(echo.values[4 * 7 + 2]).toBe(FILL_ECHO); // blank cell
  });

  it("adds mudline elevation only when the transducer elevation is known", () => {
    const scan = processBathymetry(parseCsv(read("bathymetry/header.csv")));
    const base = { title: "t", scanId: "s", folderName: "f", scan, software: "x" };
    const without = buildScanNetcdf({ ...base, acquisition: {} });
    expect(without.vars.map((v) => v.name)).not.toContain("mudline_elevation");
    const withElev = buildScanNetcdf({ ...base, acquisition: { transducerElevationM: 1 } });
    const mud = withElev.vars.find((v) => v.name === "mudline_elevation")!;
    expect(mud.data[0]).toBeCloseTo(1 - scan.samples[0].depthM, 12);
  });

  it("refuses empty scans and zero-length dimensions", () => {
    const empty = processBathymetry([]);
    expect(() =>
      buildScanNetcdf({ title: "t", scanId: "s", folderName: "f", scan: empty, acquisition: {}, software: "x" }),
    ).toThrow();
    expect(() => encodeNetcdf({ dims: [{ name: "obs", size: 0 }], attrs: {}, vars: [] })).toThrow();
  });
});
