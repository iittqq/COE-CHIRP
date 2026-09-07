import { useEffect, useState } from "react";
import { Box, IconButton, Typography } from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import DepthLineChart from "../components/DepthLineChart";
import type { ScanData } from "../utils/scanRepo";
import { depthUnitLabel, loadIsMetric } from "../utils/unitsRepository";
import {
  calcDepthStats,
  calcSettledDepth,
  computeDepthSpots,
  mergeGappedSeriesForComparison,
} from "../utils/depthChart";
import { useSnackbar } from "../notifications";
import menuIcon from "../assets/menu.svg";

// Categorical palette, slots 1-5 (validated adjacent-pair ordering).
const SERIES_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"];

interface CompareScansProps {
  scans: ScanData[];
  onBack: () => void;
  onToggleNav: () => void;
}

export default function CompareScans({ scans, onBack, onToggleNav }: CompareScansProps) {
  const { notify } = useSnackbar();
  const [isMetric, setIsMetric] = useState(true);

  useEffect(() => {
    setIsMetric(loadIsMetric());
  }, []);

  const unit = depthUnitLabel(isMetric);
  const perScanPoints = scans.map((scan) => computeDepthSpots(scan.bathymetryRows, isMetric));
  const hasData = perScanPoints.some((points) => points.length > 0);
  const merged = mergeGappedSeriesForComparison(perScanPoints);

  const perScanStats = scans.map((scan) => calcDepthStats(scan.bathymetryRows, isMetric));
  const settledDepths = scans.map((scan) => calcSettledDepth(scan.bathymetryRows, isMetric));
  const validSettled = settledDepths.filter((v): v is number => v !== null);
  const change = validSettled.length >= 2 ? Math.max(...validSettled) - Math.min(...validSettled) : null;

  const handleShare = async () => {
    const lines = scans.map((scan, i) => {
      const depth = settledDepths[i];
      return `${scan.title}: ${depth !== null ? `${depth.toFixed(2)} ${unit}` : "—"}`;
    });
    const summary = [
      "Scan Comparison",
      change !== null ? `Depth Change: ${change.toFixed(2)} ${unit}` : null,
      ...lines,
    ]
      .filter(Boolean)
      .join("\n");

    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: "Scan Comparison", text: summary });
      } catch (err) {
        if ((err as Error).name !== "AbortError") {
          notify("Sharing failed.", { severity: "error" });
        }
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(summary);
      notify("Copied to clipboard", { severity: "success" });
    } catch {
      notify("Sharing isn't available on this browser.", { severity: "error" });
    }
  };

  return (
    <Box sx={{ height: "100%", display: "flex", flexDirection: "column", bgcolor: "#F5F6FA" }}>
      <Box
        sx={{
          position: "relative",
          zIndex: 1250,
          display: "flex",
          alignItems: "center",
          bgcolor: "#FFFFFF",
          borderBottom: "1px solid #E5E7EB",
          px: 1,
          py: 1,
        }}
      >
        <IconButton onClick={onToggleNav} aria-label="Toggle navigation">
          <Box component="img" src={menuIcon} alt="" sx={{ width: 20, height: 20 }} />
        </IconButton>
        <Typography sx={{ flex: 1, textAlign: "center", fontWeight: 700 }}>
          Scan Analysis
        </Typography>
        <IconButton onClick={handleShare}>
          <ShareOutlinedIcon />
        </IconButton>
      </Box>

      <Box sx={{ flex: 1, position: "relative", overflow: "hidden" }}>
        <IconButton
          onClick={onBack}
          sx={{
            position: "absolute",
            top: 12,
            left: 12,
            zIndex: 1,
            bgcolor: "#FFFFFF",
            border: "1px solid #E5E7EB",
            boxShadow: "0 1px 4px rgba(0,0,0,0.12)",
            "&:hover": { bgcolor: "#F5F6FA" },
          }}
        >
          <ChevronLeftRoundedIcon />
        </IconButton>
        <Box
          sx={{
            height: "100%",
            overflow: "auto",
            p: 2,
            display: "flex",
            flexDirection: "column",
            gap: 1.75,
            maxWidth: 1200,
            width: "100%",
            mx: "auto",
          }}
        >
          <Typography sx={{ fontWeight: 800, fontSize: 14, mt: 6 }}>Depth Data</Typography>

          <Box
            sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}
          >
            <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600 }}>
              Depth Change
            </Typography>
            <Typography sx={{ fontSize: 24, fontWeight: 800, mt: 1 }}>
              {change !== null ? `${change.toFixed(2)} ${unit}` : "—"}
            </Typography>
            <Box sx={{ mt: 1.5 }}>
              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: "1fr repeat(4, 64px)",
                  columnGap: 2.5,
                  mb: 0.75,
                }}
              >
                <Box />
                {["Avg", "Min", "Max", "Settled"].map((heading) => (
                  <Typography
                    key={heading}
                    sx={{
                      fontSize: 11,
                      color: "text.secondary",
                      fontWeight: 700,
                      textAlign: "center",
                    }}
                  >
                    {heading}
                  </Typography>
                ))}
              </Box>

              <Box sx={{ display: "flex", flexDirection: "column", gap: 1.25 }}>
                {scans.map((scan, i) => {
                  const scanStats = perScanStats[i];
                  const cells: [string, number | null][] = [
                    ["avg", scanStats ? scanStats.avg : null],
                    ["min", scanStats ? scanStats.min : null],
                    ["max", scanStats ? scanStats.max : null],
                    ["settled", settledDepths[i]],
                  ];
                  return (
                    <Box
                      key={scan.id}
                      sx={{
                        display: "grid",
                        gridTemplateColumns: "1fr repeat(4, 64px)",
                        columnGap: 2.5,
                        alignItems: "center",
                      }}
                    >
                      <Box sx={{ display: "flex", alignItems: "center", gap: 1, minWidth: 0 }}>
                        <Box
                          sx={{
                            width: 10,
                            height: 10,
                            borderRadius: "50%",
                            bgcolor: SERIES_COLORS[i % SERIES_COLORS.length],
                            flexShrink: 0,
                          }}
                        />
                        <Typography
                          sx={{ fontSize: 12, fontWeight: 700, color: "#374151" }}
                          noWrap
                        >
                          {scan.title}
                        </Typography>
                      </Box>
                      {cells.map(([key, value]) => (
                        <Typography
                          key={key}
                          sx={{
                            fontSize: 12,
                            fontWeight: 700,
                            textAlign: "center",
                            fontVariantNumeric: "tabular-nums",
                          }}
                        >
                          {value !== null ? value.toFixed(1) : "—"}
                        </Typography>
                      ))}
                    </Box>
                  );
                })}
              </Box>

              <Typography
                sx={{ fontSize: 11, color: "text.secondary", fontWeight: 600, mt: 1 }}
              >
                Depths in {unit}
              </Typography>
            </Box>
          </Box>

          <Box
            sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}
          >
            <Typography sx={{ fontSize: 13, fontWeight: 800 }}>Bathymetry Data</Typography>
            <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mb: 1.5 }}>
              Bathymetry depth over scan time
            </Typography>
            {!hasData ? (
              <Box
                sx={{ height: 260, display: "flex", alignItems: "center", justifyContent: "center" }}
              >
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
                  connectNulls: false,
                  label: scan.title,
                }))}
              />
            )}
          </Box>
        </Box>
      </Box>
    </Box>
  );
}
