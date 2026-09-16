import { forwardRef, type Ref } from "react";
import { Box, Typography } from "@mui/material";
import { LineChart } from "@mui/x-charts/LineChart";
import {
  buildMinorTicks,
  buildTicksFromZero,
  buildTicksInRange,
  niceBottomStep,
  niceLeftStep,
  timeLabel,
} from "../utils/depthChart";

const CHART_HEIGHT = 300;
const MARGIN_TOP = 16;
const MARGIN_BOTTOM = 8;
// MUI reserves space for the x-axis's own ticks/label *in addition to*
// `margin` (defaulting to 45px for a labeled axis, which is where this 45
// comes from) — set explicitly here so the fixed y-axis panel's math (which
// needs to know the real plot area height) doesn't have to guess at that
// default. Below ~45 the axis stops rendering entirely instead of clipping,
// so this isn't just a visual buffer — keep it at the real default.
const X_AXIS_HEIGHT = 45;
const Y_PANEL_WIDTH = 56;
const MIN_PX_PER_SECOND = 8;
const MIN_PX_PER_POINT = 3;
const MAX_CHART_WIDTH = 20_000;
const BASE_WIDTH = 640;
// Very flat scans (e.g. depth varying only 64.2 -> 65) otherwise collapse to a
// single y-axis tick, since the smallest nice step is 1. Force the axis to span
// at least this many display units so it stays "zoomed out" with ~5-6 integer
// ticks, matching how higher-variation scans render.
const MIN_Y_SPAN = 5;
// Each major interval gets this many minor ticks/gridlines between it and the
// next - a static print chart needs these to read values precisely since
// there's no hover tooltip to fall back on.
const MINOR_TICKS_PER_MAJOR = 5;
const MAJOR_TICK_LENGTH = 6;
const MINOR_TICK_LENGTH = 3;
const AXIS_LINE_COLOR = "#8f8e82";
const MINOR_TICK_COLOR = "#c3c2b7";

const axisLineSx = {
  "& .MuiChartsAxis-line, & .MuiChartsAxis-tick": { stroke: "#8f8e82" },
  "& .MuiChartsAxis-tickLabel": { fill: "#52514e" },
  "& .MuiChartsGrid-line": { stroke: "#e3e2d8", strokeWidth: 1 },
};

export interface DepthChartSeries {
  id: string;
  data: (number | null)[];
  color: string;
  connectNulls?: boolean;
  label?: string;
}

interface DepthLineChartProps {
  series: DepthChartSeries[];
  xValues: number[];
  unit: string;
  // Attach to capture the y-axis panel and the full (unclipped) chart body
  // separately for PDF export - see ScanAnalysis.tsx's exportPdf handler.
  yAxisPanelRef?: Ref<HTMLDivElement>;
  chartBodyRef?: Ref<HTMLDivElement>;
  // Renders at this fixed width instead of the interactive scroll-friendly
  // sizing below, and recomputes x-tick density to match - used to capture a
  // compact, single-page-friendly chart for PDF export (see PRINT_CHART_WIDTH
  // in utils/exportPdf.ts).
  printWidth?: number;
  // Overrides for a taller/more-zoomed-in rendering - defaults keep the
  // compact sizing used elsewhere (CompareScans, the PDF overview) unchanged.
  height?: number;
  pxPerSecond?: number;
}

// Hand-rolled y-axis label column (plain absolutely-positioned text, not a
// chart) — mirrors the original Flutter chart's own custom `_fixedYAxis`
// widget. A real MUI axis rendered in its own tiny chart turned out to be
// unreliable here (a dummy all-null series doesn't get its ticks rendered),
// so this sidesteps that entirely: it only needs the same height/margins/
// domain as the scrollable chart to stay pixel-aligned with it.
const FixedYAxisLabels = forwardRef<
  HTMLDivElement,
  {
    minY: number;
    maxY: number;
    ticks: number[];
    minorTicks: number[];
    label: string;
    chartHeight: number;
  }
>(function FixedYAxisLabels({ minY, maxY, ticks, minorTicks, label, chartHeight }, ref) {
  const plotHeight = chartHeight - MARGIN_TOP - MARGIN_BOTTOM - X_AXIS_HEIGHT;
  const tickCenter = (value: number) =>
    MARGIN_TOP + (1 - (value - minY) / (maxY - minY)) * plotHeight;

  return (
    <Box
      ref={ref}
      sx={{ flexShrink: 0, width: Y_PANEL_WIDTH, height: chartHeight, display: "flex" }}
    >
      <Box sx={{ width: 18, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Typography
          sx={{
            fontSize: 12,
            fontWeight: 600,
            color: "#52514e",
            whiteSpace: "nowrap",
            transform: "rotate(-90deg)",
          }}
        >
          {label}
        </Typography>
      </Box>
      <Box sx={{ position: "relative", flex: 1, height: chartHeight }}>
        {/* Axis line - the real MUI y-axis line/ticks are disabled (see the
            comment above) since this hand-rolled column stands in for them. */}
        <Box
          sx={{
            position: "absolute",
            right: 0,
            top: MARGIN_TOP,
            height: plotHeight,
            width: "1px",
            bgcolor: AXIS_LINE_COLOR,
          }}
        />
        {minorTicks.map((value) => (
          <Box
            key={`minor-${value}`}
            sx={{
              position: "absolute",
              right: 0,
              top: tickCenter(value),
              width: MINOR_TICK_LENGTH,
              height: "1px",
              bgcolor: MINOR_TICK_COLOR,
            }}
          />
        ))}
        {ticks.map((value) => {
          const center = tickCenter(value);
          const top = Math.max(0, Math.min(chartHeight - 16, center - 8));
          return (
            <Box key={value}>
              <Box
                sx={{
                  position: "absolute",
                  right: 0,
                  top: center,
                  width: MAJOR_TICK_LENGTH,
                  height: "1px",
                  bgcolor: AXIS_LINE_COLOR,
                }}
              />
              <Typography
                sx={{
                  position: "absolute",
                  top,
                  right: MAJOR_TICK_LENGTH + 2,
                  fontSize: 11,
                  fontWeight: 600,
                  color: "#52514e",
                  lineHeight: "16px",
                }}
              >
                {Math.abs(value).toFixed(0)}
              </Typography>
            </Box>
          );
        })}
      </Box>
    </Box>
  );
});

// The y-axis renders as plain fixed text (see FixedYAxisLabels) outside the
// horizontally-scrolling chart, so it never scrolls away. Tick VALUES for
// both axes are computed up front (nice-step candidates, same approach the
// original Flutter chart used) and passed in explicitly via tickInterval/
// tickLabelInterval, instead of relying on the x-axis's default
// collision-based auto-hiding, which is what caused ticks to disappear
// unpredictably at odd widths.
export default function DepthLineChart({
  series,
  xValues,
  unit,
  yAxisPanelRef,
  chartBodyRef,
  printWidth,
  height,
  pxPerSecond,
}: DepthLineChartProps) {
  const chartHeight = height ?? CHART_HEIGHT;
  const effectivePxPerSecond = pxPerSecond ?? MIN_PX_PER_SECOND;
  const allY = series.flatMap((s) => s.data.filter((v): v is number => v !== null));

  if (allY.length === 0 || xValues.length === 0) {
    return (
      <Box sx={{ height: chartHeight, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Typography>No bathymetry chart data</Typography>
      </Box>
    );
  }

  const lowY = Math.min(...allY);
  const highY = Math.max(...allY);
  const yRange = highY - lowY;
  const yPadding = yRange < 0.01 ? 1 : yRange * 0.08;
  let minY = lowY - yPadding;
  let maxY = highY + yPadding;

  if (maxY - minY < MIN_Y_SPAN) {
    const center = (minY + maxY) / 2;
    minY = center - MIN_Y_SPAN / 2;
    maxY = center + MIN_Y_SPAN / 2;
  }

  const maxX = Math.max(...xValues, 1);

  const leftStep = niceLeftStep(maxY - minY);
  // Snap the plotted range out to whole tick steps so the first and last
  // major ticks land exactly on the top/bottom edges of the chart instead of
  // leaving a partial gap above/below them.
  minY = Math.floor(minY / leftStep) * leftStep;
  maxY = Math.ceil(maxY / leftStep) * leftStep;
  if (minY === maxY) maxY = minY + leftStep;
  const yTicks = buildTicksInRange(minY, maxY, leftStep);
  const minorYTicks = buildMinorTicks(minY, maxY, leftStep, MINOR_TICKS_PER_MAJOR);

  let fullWidth = printWidth ?? BASE_WIDTH;
  if (printWidth === undefined) {
    fullWidth = Math.max(fullWidth, maxX * effectivePxPerSecond);
    fullWidth = Math.max(fullWidth, xValues.length * MIN_PX_PER_POINT);
    fullWidth = Math.min(fullWidth, MAX_CHART_WIDTH);
  }

  const bottomStep = niceBottomStep(maxX, fullWidth);
  const xTicks = buildTicksFromZero(maxX, bottomStep);
  const minorXTicks = buildMinorTicks(0, maxX, bottomStep, MINOR_TICKS_PER_MAJOR);
  const combinedXTicks = [...xTicks, ...minorXTicks].sort((a, b) => a - b);
  const majorXTickSet = new Set(xTicks);

  return (
    <Box>
      <Box sx={{ display: "flex" }}>
        <FixedYAxisLabels
          ref={yAxisPanelRef}
          minY={minY}
          maxY={maxY}
          ticks={yTicks}
          minorTicks={minorYTicks}
          label={`Depth (${unit})`}
          chartHeight={chartHeight}
        />
        <Box sx={{ overflowX: "auto", flex: 1 }}>
          <Box ref={chartBodyRef} sx={{ width: fullWidth, height: chartHeight }}>
            <LineChart
              xAxis={[
                {
                  data: xValues,
                  scaleType: "linear",
                  valueFormatter: (value: number) => timeLabel(value),
                  // Major+minor ticks share one array so the same values drive
                  // both the tick marks and the vertical gridlines (which MUI
                  // always derives from the axis's own tickInterval); only
                  // the majors get a label via tickLabelInterval below.
                  tickInterval: combinedXTicks,
                  tickLabelInterval: (value: number) => majorXTickSet.has(value),
                  height: X_AXIS_HEIGHT,
                },
              ]}
              yAxis={[
                {
                  min: minY,
                  max: maxY,
                  // Ticks/line stay disabled - FixedYAxisLabels hand-rolls
                  // those (labels, tick marks, axis line) instead (see the
                  // comment above it). This axis exists only to drive the
                  // horizontal gridlines, so its tickInterval includes minors
                  // too even though FixedYAxisLabels only labels the majors.
                  tickInterval: [...yTicks, ...minorYTicks],
                  disableLine: true,
                  disableTicks: true,
                  tickLabelInterval: () => false,
                  width: 0,
                },
              ]}
              series={series.map((s) => ({
                id: s.id,
                data: s.data,
                color: s.color,
                label: s.label,
                showMark: false,
                connectNulls: s.connectNulls ?? false,
                curve: "linear",
                valueFormatter: (value: number | null) =>
                  value === null ? "" : `${(-value).toFixed(2)} ${unit}`,
              }))}
              margin={{ left: 4, right: 16, top: MARGIN_TOP, bottom: MARGIN_BOTTOM }}
              grid={{ horizontal: true, vertical: true }}
              hideLegend
              sx={{ "& .MuiLineChart-line": { strokeWidth: 2 }, ...axisLineSx }}
            />
          </Box>
        </Box>
      </Box>
      <Box sx={{ display: "flex" }}>
        <Box sx={{ width: Y_PANEL_WIDTH, flexShrink: 0 }} />
        <Box sx={{ flex: 1, textAlign: "center" }}>
          <Typography sx={{ fontSize: 12, fontWeight: 600, color: "#52514e" }}>
            Scan Duration (mm:ss)
          </Typography>
        </Box>
      </Box>
    </Box>
  );
}
