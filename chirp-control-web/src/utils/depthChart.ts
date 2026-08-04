import { cmToDisplayUnit } from "./unitsRepository";
import type { CsvRow } from "./scanRepo";

export interface DepthPoint {
  x: number; // seconds since scan start
  y: number; // negated depth (so "down" reads as down on a normal y-up axis)
}

function toNumber(value: CsvRow[number] | undefined): number | null {
  if (value === undefined) return null;
  if (typeof value === "number") return value;
  const parsed = Number(value);
  return Number.isNaN(parsed) ? null : parsed;
}

export function computeDepthSpots(rows: CsvRow[], isMetric: boolean): DepthPoint[] {
  const validRows = rows.filter((row) => row.length >= 5);
  const points: DepthPoint[] = [];

  for (const row of validRows) {
    const depthMeters = toNumber(row[2]);
    const timestampMs = toNumber(row[4]);
    if (depthMeters === null || timestampMs === null) continue;

    const depthDisplay = cmToDisplayUnit(depthMeters * 100, isMetric);
    points.push({ x: timestampMs, y: depthDisplay });
  }

  if (points.length === 0) return [];

  points.sort((a, b) => a.x - b.x);
  const firstTime = points[0].x;
  return points.map((p) => ({ x: (p.x - firstTime) / 1000, y: -p.y }));
}

// Large gaps in a scan (sensor paused, reconnect, etc.) shouldn't be drawn as
// a straight interpolated line — insert a null-y breakpoint at the gap's
// midpoint so the chart's native "break on null" behavior renders it as two
// separate segments instead, without needing to split into multiple series.
export function buildGappedSeries(
  points: DepthPoint[],
): { x: number[]; y: (number | null)[] } {
  if (points.length < 3) {
    return { x: points.map((p) => p.x), y: points.map((p) => p.y) };
  }

  const deltas: number[] = [];
  for (let i = 1; i < points.length; i++) deltas.push(points[i].x - points[i - 1].x);

  const sortedDeltas = [...deltas].sort((a, b) => a - b);
  const median = sortedDeltas[Math.floor(sortedDeltas.length / 2)];
  const threshold = median * 3 < 1 ? 1 : median * 3;

  const xs: number[] = [points[0].x];
  const ys: (number | null)[] = [points[0].y];

  for (let i = 1; i < points.length; i++) {
    if (deltas[i - 1] > threshold) {
      xs.push((points[i - 1].x + points[i].x) / 2);
      ys.push(null);
    }
    xs.push(points[i].x);
    ys.push(points[i].y);
  }

  return { x: xs, y: ys };
}

export function timeLabel(secondsValue: number): string {
  const totalSeconds = Math.min(Math.max(Math.round(secondsValue), 0), 999_999);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

// MUI X Charts' line series share one xAxis positional array. Different
// scans rarely land on the same elapsed-second values, so build the union
// of every scan's x-values as the shared axis and null-fill each series
// everywhere but its own points (rendered with connectNulls so the line
// still reads as continuous, just skipping the interleaved gaps left by
// the other scans' x-values).
export function mergeSeriesForComparison(
  perScanPoints: DepthPoint[][],
): { x: number[]; seriesY: (number | null)[][] } {
  const xSet = new Set<number>();
  for (const points of perScanPoints) {
    for (const point of points) xSet.add(point.x);
  }
  const x = Array.from(xSet).sort((a, b) => a - b);
  const xIndex = new Map(x.map((value, index) => [value, index]));

  const seriesY = perScanPoints.map((points) => {
    const y = new Array<number | null>(x.length).fill(null);
    for (const point of points) {
      const index = xIndex.get(point.x);
      if (index !== undefined) y[index] = point.y;
    }
    return y;
  });

  return { x, seriesY };
}

const LEFT_STEP_CANDIDATES = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000];
const LEFT_TARGET_TICKS = 6;

// How far apart (in display units) consecutive y-axis labels should be,
// picked from a fixed candidate list so labels land on round numbers instead
// of wherever an auto-scaled axis happens to put them.
export function niceLeftStep(yRange: number): number {
  for (const step of LEFT_STEP_CANDIDATES) {
    if (yRange / step <= LEFT_TARGET_TICKS) return step;
  }
  return LEFT_STEP_CANDIDATES[LEFT_STEP_CANDIDATES.length - 1];
}

const BOTTOM_STEP_CANDIDATES = [
  5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 450, 600, 900, 1200, 1800,
  2700, 3600, 5400, 7200, 10800,
];
const BOTTOM_TARGET_PX_PER_LABEL = 65;

// Same idea for the x-axis (elapsed seconds), sized so labels land roughly
// every 65px at the chart's actual rendered width — this is what keeps tick
// spacing even instead of the axis's automatic collision-based label hiding
// dropping labels unpredictably.
export function niceBottomStep(xRange: number, fullWidthPx: number): number {
  const pxPerSecond = fullWidthPx / xRange;
  const minStepForSpacing = BOTTOM_TARGET_PX_PER_LABEL / pxPerSecond;
  for (const step of BOTTOM_STEP_CANDIDATES) {
    if (step >= minStepForSpacing) return step;
  }
  return BOTTOM_STEP_CANDIDATES[BOTTOM_STEP_CANDIDATES.length - 1];
}

export function buildTicksFromZero(max: number, interval: number): number[] {
  const ticks: number[] = [];
  let current = 0;
  while (current <= max + 1e-6) {
    ticks.push(current);
    current += interval;
  }
  return ticks;
}

export function buildTicksInRange(min: number, max: number, interval: number): number[] {
  const ticks: number[] = [];
  let current = Math.ceil(min / interval) * interval;
  while (current <= max + 1e-6) {
    ticks.push(current);
    current += interval;
  }
  return ticks;
}

export interface DepthStats {
  avg: number;
  min: number;
  max: number;
}

export function calcDepthStats(rows: CsvRow[], isMetric: boolean): DepthStats | null {
  const values: number[] = [];
  for (const row of rows) {
    if (row.length < 5) continue;
    const depthMeters = toNumber(row[2]);
    if (depthMeters === null) continue;
    values.push(cmToDisplayUnit(depthMeters * 100, isMetric));
  }
  if (values.length === 0) return null;

  const sum = values.reduce((a, b) => a + b, 0);
  return {
    avg: sum / values.length,
    min: Math.min(...values),
    max: Math.max(...values),
  };
}

export function calcSettledDepth(rows: CsvRow[], isMetric: boolean): number | null {
  const values: number[] = [];
  for (const row of rows) {
    if (row.length < 5) continue;
    const depthMeters = toNumber(row[2]);
    if (depthMeters === null) continue;
    values.push(cmToDisplayUnit(depthMeters * 100, isMetric));
  }
  if (values.length === 0) return null;

  const lastCount = Math.min(values.length, 20);
  const lastValues = values.slice(values.length - lastCount);
  return lastValues.reduce((a, b) => a + b, 0) / lastValues.length;
}
