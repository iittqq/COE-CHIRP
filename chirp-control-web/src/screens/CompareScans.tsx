import { useEffect, useState } from "react";
import { Box, IconButton, Typography } from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import DepthLineChart from "../components/DepthLineChart";
import type { ScanData } from "../utils/scanRepo";
import { depthUnitLabel, loadIsMetric } from "../utils/unitsRepository";
import {
  calcSettledDepth,
  computeDepthSpots,
  mergeSeriesForComparison,
} from "../utils/depthChart";
import { useSnackbar } from "../notifications";

// Categorical palette, slots 1-5 (validated adjacent-pair ordering).
const SERIES_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"];

interface CompareScansProps {
  scans: ScanData[];
  onBack: () => void;
}

export default function CompareScans({ scans, onBack }: CompareScansProps) {
  const { notify } = useSnackbar();
  const [isMetric, setIsMetric] = useState(true);

  useEffect(() => {
    setIsMetric(loadIsMetric());
  }, []);

  const unit = depthUnitLabel(isMetric);
  const perScanPoints = scans.map((scan) => computeDepthSpots(scan.bathymetryRows, isMetric));
  const hasData = perScanPoints.some((points) => points.length > 0);
  const merged = mergeSeriesForComparison(perScanPoints);

  const settledDepths = scans.map((scan) => calcSettledDepth(scan.bathymetryRows, isMetric));
  const validSettled = settledDepths.filter((v): v is number => v !== null);
  const change = validSettled.length >= 2 ? Math.max(...validSettled) - Math.min(...validSettled) : null;

  return (
    <Box sx={{ height: "100%", display: "flex", flexDirection: "column", bgcolor: "#F5F6FA" }}>
      <Box
        sx={{
          display: "flex",
          alignItems: "center",
          bgcolor: "#FFFFFF",
          borderBottom: "1px solid #E5E7EB",
          px: 1,
          py: 1,
        }}
      >
        <IconButton onClick={onBack}>
          <ChevronLeftRoundedIcon />
        </IconButton>
        <Typography sx={{ flex: 1, textAlign: "center", fontWeight: 700 }}>
          Scan Analysis
        </Typography>
        <IconButton onClick={() => notify("Sharing isn't available yet.")}>
          <ShareOutlinedIcon />
        </IconButton>
      </Box>

      <Box
        sx={{
          flex: 1,
          overflow: "auto",
          p: 2,
          display: "flex",
          flexDirection: "column",
          gap: 1.75,
          maxWidth: 900,
          width: "100%",
          mx: "auto",
        }}
      >
        <Typography sx={{ fontWeight: 800, fontSize: 14 }}>Depth Data</Typography>

        <Box sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}>
          <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600 }}>
            Depth Change
          </Typography>
          <Typography sx={{ fontSize: 24, fontWeight: 800, mt: 1 }}>
            {change !== null ? `${change.toFixed(2)} ${unit}` : "—"}
          </Typography>
          <Box sx={{ mt: 1.5, display: "flex", flexDirection: "column", gap: 1.25 }}>
            {scans.map((scan, i) => (
              <Box key={scan.id} sx={{ display: "flex", alignItems: "center", gap: 1 }}>
                <Box
                  sx={{
                    width: 10,
                    height: 10,
                    borderRadius: "50%",
                    bgcolor: SERIES_COLORS[i % SERIES_COLORS.length],
                    flexShrink: 0,
                  }}
                />
                <Typography sx={{ flex: 1, fontSize: 12, fontWeight: 700, color: "#374151" }} noWrap>
                  {scan.title}
                </Typography>
                <Typography sx={{ fontSize: 12, fontWeight: 700 }}>
                  {settledDepths[i] !== null ? `${settledDepths[i]!.toFixed(2)} ${unit}` : "—"}
                </Typography>
              </Box>
            ))}
          </Box>
        </Box>

        <Box sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}>
          <Typography sx={{ fontSize: 13, fontWeight: 800 }}>Bathymetry Data</Typography>
          <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mb: 1.5 }}>
            Bathymetry depth over scan time
          </Typography>
          {!hasData ? (
            <Box sx={{ height: 260, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <Typography>No bathymetry chart data</Typography>
            </Box>
          ) : (
            <DepthLineChart
              xValues={merged.x}
              unit={unit}
              series={scans.map((scan, i) => ({
                id: scan.id,
                data: merged.seriesY[i],
                color: SERIES_COLORS[i % SERIES_COLORS.length],
                connectNulls: true,
                label: scan.title,
              }))}
            />
          )}
        </Box>
      </Box>
    </Box>
  );
}
