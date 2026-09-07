import { cmToDisplayUnit } from "./unitsRepository";
import type { CsvRow } from "./scanRepo";

export interface DepthPoint {
  x: number; // seconds since scan start
  y: number; // negated depth (so "down" reads as down on a normal y-up axis)
}

function toNumber(value: CsvRow[number] | undefined): number | null {
  if (value === undefined || value === null) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  // Number("") and Number("   ") are both 0 - treat a blank cell as missing
  // rather than a real 0 reading (otherwise empty leading depth rows plot as
  // a flat line at 0 and pad the chart).
  if (value.trim() === "") return null;
  const parsed = Number(value);
  return Number.isNaN(parsed) ? null : parsed;
}

// Some scans log a handful of samples before the device's clock is synced
// (or after it drifts on reconnect), leaving one or two points stranded
// seconds-to-minutes away from the main run. Anchoring the time axis to those
// strays leaves the chart mostly empty with the real data crammed into one
// end. Drop leading/trailing islands that are both a small minority of points
// and separated from the body by a gap that's a large fraction of the whole
// span, so the axis can start where the real data does.
function trimOutlyingTimeIslands(sorted: DepthPoint[]): DepthPoint[] {
  if (sorted.length < 10) return sorted;

  const totalSpan = sorted[sorted.length - 1].x - sorted[0].x;
  if (totalSpan <= 0) return sorted;

  const deltas: number[] = [];
  for (let i = 1; i < sorted.length; i++) deltas.push(sorted[i].x - sorted[i - 1].x);
  const sortedDeltas = [...deltas].sort((a, b) => a - b);
  const median = sortedDeltas[Math.floor(sortedDeltas.length / 2)] || 0;

  // A gap only counts as an "island boundary" if it's both far bigger than the
  // normal sample spacing and a meaningful slice of the total scan length.
  const gapThreshold = Math.max(median * 20, totalSpan * 0.15);
  const maxIslandFraction = 0.15;

  let start = 0;
  let end = sorted.length; // exclusive

  for (let i = 1; i < sorted.length; i++) {
    if (i / sorted.length > maxIslandFraction) break;
    if (deltas[i - 1] >= gapThreshold) start = i;
  }
  for (let i = sorted.length - 1; i >= 1; i--) {
    if ((sorted.length - i) / sorted.length > maxIslandFraction) break;
    if (deltas[i - 1] >= gapThreshold) end = i;
  }

  const result = sorted.slice(start, end);
  return result.length >= 2 ? result : sorted;
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
  const trimmed = trimOutlyingTimeIslands(points);
  const firstTime = trimmed[0].x;
  return trimmed.map((p) => ({ x: (p.x - firstTime) / 1000, y: -p.y }));
}

// Elapsed-time gap (seconds) beyond which consecutive samples are considered a
// real break in the scan rather than normal spacing: 3x the median interval,
// floored at 1s. Returns Infinity when there aren't enough points to judge (so
// callers treat the scan as gap-free).
function gapThreshold(points: DepthPoint[]): number {
  if (points.length < 3) return Infinity;
  const deltas: number[] = [];
  for (let i = 1; i < points.length; i++) deltas.push(points[i].x - points[i - 1].x);
  const sorted = [...deltas].sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)];
  return median * 3 < 1 ? 1 : median * 3;
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

  const threshold = gapThreshold(points);

  const xs: number[] = [points[0].x];
  const ys: (number | null)[] = [points[0].y];

  for (let i = 1; i < points.length; i++) {
    if (points[i].x - points[i - 1].x > threshold) {
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

// Multi-scan counterpart of buildGappedSeries. MUI X line series must share one
// positional xAxis array, so every scan's y-values are linearly interpolated
// onto the union of all scans' elapsed-second values. A series is null (a)
// outside its own time range and (b) inside a real data gap — the same
// "> gapThreshold" gaps buildGappedSeries breaks on. Rendered with
// connectNulls:false this makes each line break at its real gaps instead of
// bridging them with a straight line, matching the single-scan chart.
export function mergeGappedSeriesForComparison(
  perScanPoints: DepthPoint[][],
): { x: number[]; seriesY: (number | null)[][] } {
  const thresholds = perScanPoints.map(gapThreshold);

  const xSet = new Set<number>();
  perScanPoints.forEach((points, s) => {
    for (const point of points) xSet.add(point.x);
    // A sample in the middle of each real gap gives this series somewhere to be
    // null even when no other scan has an x-value inside that gap, so the two
    // sides of the break don't get connected.
    for (let i = 1; i < points.length; i++) {
      if (points[i].x - points[i - 1].x > thresholds[s]) {
        xSet.add((points[i - 1].x + points[i].x) / 2);
      }
    }
  });
  const x = Array.from(xSet).sort((a, b) => a - b);

  const seriesY = perScanPoints.map((points, s) => {
    if (points.length === 0) return x.map(() => null);

    const threshold = thresholds[s];
    const first = points[0].x;
    const last = points[points.length - 1].x;

    return x.map((ux) => {
      if (ux < first || ux > last) return null;

      // Segment [points[i], points[i + 1]] that brackets ux.
      let i = 0;
      while (i < points.length - 1 && points[i + 1].x < ux) i++;
      const a = points[i];
      const b = points[i + 1] ?? a;

      if (ux === a.x) return a.y;
      if (ux === b.x) return b.y;

      const span = b.x - a.x;
      if (span <= 0) return a.y;
      if (span > threshold) return null; // inside a real gap — break the line

      return a.y + ((b.y - a.y) * (ux - a.x)) / span;
    });
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
