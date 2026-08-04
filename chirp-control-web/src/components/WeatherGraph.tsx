import { LineChart } from "@mui/x-charts/LineChart";
import { Box } from "@mui/material";

const SEQUENTIAL_BLUE = "#2a78d6";

interface WeatherGraphProps {
  xValues: number[];
  times: string[];
  yLabel: string;
}

export default function WeatherGraph({
  xValues,
  times,
  yLabel,
}: WeatherGraphProps) {
  const min = Math.min(...xValues);
  const max = Math.max(...xValues);
  const diff = max - min;
  const padding = diff === 0 ? 1 : diff * 0.1;

  const chartMin = min === 0 ? min : min - padding;
  const chartMax = max === 0 ? 5 : max + padding;

  return (
    <Box sx={{ width: "100%", height: "100%" }}>
      <LineChart
        xAxis={[
          {
            data: xValues.map((_, i) => i),
            valueFormatter: (value: number) => {
              const time = times[value];
              return time ? time.substring(11, 16) : "";
            },
            tickMinStep: 1,
            tickInterval: (_value, index) =>
              index % Math.max(1, Math.floor(times.length / 6)) === 0,
          },
        ]}
        yAxis={[{ min: chartMin, max: chartMax, label: yLabel }]}
        series={[
          {
            data: xValues,
            area: true,
            showMark: false,
            color: SEQUENTIAL_BLUE,
            curve: "monotoneX",
          },
        ]}
        grid={{ horizontal: true, vertical: true }}
        margin={{ left: 56, right: 16, top: 24, bottom: 32 }}
        sx={{
          "& .MuiLineElement-root": { strokeWidth: 3 },
          "& .MuiAreaElement-root": { fillOpacity: 0.18 },
          "& .MuiChartsAxis-line, & .MuiChartsAxis-tick": {
            stroke: "#c3c2b7",
          },
          "& .MuiChartsAxis-tickLabel": { fill: "#52514e" },
        }}
      />
    </Box>
  );
}
