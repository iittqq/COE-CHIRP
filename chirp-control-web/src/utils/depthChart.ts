import { cmToDisplayUnit } from "./unitsRepository";
import { depthCm, type ProcessedScan } from "./bathymetry";

export interface DepthPoint {
  x: number; // seconds since scan start
  y: number; // negated depth (so "down" reads as down on a normal y-up axis)
}

// Chart points for one processed scan: x = seconds since the first used
// sample, y = negated depth in display units. Parsing, sorting, trimming and
// the blind-spot offset all happen in bathymetry.ts (processBathymetry), so the
// chart and the statistics are always computed from the same samples.
export function computeDepthSpots(scan: ProcessedScan, isMetric: boolean): DepthPoint[] {
  if (scan.startMs === null) return [];
  const start = scan.startMs;
  return scan.samples.map((s) => ({
    x: (s.timeMs - start) / 1000,
    y: -cmToDisplayUnit(depthCm(scan, s), isMetric),
  }));
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

// Unlabeled ticks between each pair of major ticks (major step / subdivisions
// apart), for the finer-grained axis marks/gridlines a static print chart
// needs in place of on-screen hover detail. Indexes off an absolute k*minorStep
// grid (not off buildTicksInRange's own start point) so "is this a major tick"
// is a plain k % subdivisions check, with no float-equality comparison against
// the separately-computed major tick values.
export function buildMinorTicks(
  min: number,
  max: number,
  majorStep: number,
  subdivisions: number,
): number[] {
  if (subdivisions <= 1) return [];
  const minorStep = majorStep / subdivisions;
  const startK = Math.ceil(min / minorStep - 1e-9);
  const endK = Math.floor(max / minorStep + 1e-9);
  const ticks: number[] = [];
  for (let k = startK; k <= endK; k++) {
    if (((k % subdivisions) + subdivisions) % subdivisions === 0) continue;
    ticks.push(k * minorStep);
  }
  return ticks;
}
