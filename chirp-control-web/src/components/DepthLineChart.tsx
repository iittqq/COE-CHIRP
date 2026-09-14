import { forwardRef, type Ref } from "react";
import { Box, Typography } from "@mui/material";
import { LineChart } from "@mui/x-charts/LineChart";
import {
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

const axisLineSx = {
  "& .MuiChartsAxis-line, & .MuiChartsAxis-tick": { stroke: "#c3c2b7" },
  "& .MuiChartsAxis-tickLabel": { fill: "#52514e" },
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
}

// Hand-rolled y-axis label column (plain absolutely-positioned text, not a
// chart) — mirrors the original Flutter chart's own custom `_fixedYAxis`
// widget. A real MUI axis rendered in its own tiny chart turned out to be
// unreliable here (a dummy all-null series doesn't get its ticks rendered),
// so this sidesteps that entirely: it only needs the same height/margins/
// domain as the scrollable chart to stay pixel-aligned with it.
const FixedYAxisLabels = forwardRef<
  HTMLDivElement,
  { minY: number; maxY: number; ticks: number[]; label: string }
>(function FixedYAxisLabels({ minY, maxY, ticks, label }, ref) {
  const plotHeight = CHART_HEIGHT - MARGIN_TOP - MARGIN_BOTTOM - X_AXIS_HEIGHT;

  return (
    <Box
      ref={ref}
      sx={{ flexShrink: 0, width: Y_PANEL_WIDTH, height: CHART_HEIGHT, display: "flex" }}
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
      <Box sx={{ position: "relative", flex: 1, height: CHART_HEIGHT }}>
        {ticks.map((value) => {
          const ratio = (value - minY) / (maxY - minY);
          const rawTop = MARGIN_TOP + (1 - ratio) * plotHeight - 8;
          const top = Math.max(0, Math.min(CHART_HEIGHT - 16, rawTop));
          return (
            <Typography
              key={value}
              sx={{
                position: "absolute",
                top,
                right: 4,
                fontSize: 11,
                fontWeight: 600,
                color: "#52514e",
                lineHeight: "16px",
              }}
            >
              {Math.abs(value).toFixed(0)}
            </Typography>
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
}: DepthLineChartProps) {
  const allY = series.flatMap((s) => s.data.filter((v): v is number => v !== null));

  if (allY.length === 0 || xValues.length === 0) {
    return (
      <Box sx={{ height: CHART_HEIGHT, display: "flex", alignItems: "center", justifyContent: "center" }}>
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
  const yTicks = buildTicksInRange(minY, maxY, leftStep);

  let fullWidth = BASE_WIDTH;
  fullWidth = Math.max(fullWidth, maxX * MIN_PX_PER_SECOND);
  fullWidth = Math.max(fullWidth, xValues.length * MIN_PX_PER_POINT);
  fullWidth = Math.min(fullWidth, MAX_CHART_WIDTH);

  const bottomStep = niceBottomStep(maxX, fullWidth);
  const xTicks = buildTicksFromZero(maxX, bottomStep);

  return (
    <Box sx={{ display: "flex" }}>
      <FixedYAxisLabels
        ref={yAxisPanelRef}
        minY={minY}
        maxY={maxY}
        ticks={yTicks}
        label={`Depth (${unit})`}
      />
      <Box sx={{ overflowX: "auto", flex: 1 }}>
        <Box ref={chartBodyRef} sx={{ width: fullWidth, height: CHART_HEIGHT }}>
          <LineChart
            xAxis={[
              {
                data: xValues,
                scaleType: "linear",
                valueFormatter: (value: number) => timeLabel(value),
                label: "Scan Duration (mm:ss)",
                tickInterval: xTicks,
                tickLabelInterval: () => true,
                height: X_AXIS_HEIGHT,
              },
            ]}
            yAxis={[
              {
                min: minY,
                max: maxY,
                tickInterval: yTicks,
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
  );
}
