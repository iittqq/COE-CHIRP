import { useEffect, useRef, useState } from "react";
import { Box, IconButton, Typography } from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import PictureAsPdfOutlinedIcon from "@mui/icons-material/PictureAsPdfOutlined";
import DepthLineChart from "../components/DepthLineChart";
import type { ScanData } from "../utils/scanRepo";
import { depthUnitLabel, loadIsMetric } from "../utils/unitsRepository";
import {
  calcDepthStats,
  calcSettledDepth,
  computeDepthSpots,
  mergeGappedSeriesForComparison,
  timeLabel,
} from "../utils/depthChart";
import { useSnackbar } from "../notifications";
import {
  addCenteredCaption,
  addHeading,
  addImagesInRow,
  addLabelValueLine,
  addSubtext,
  addWrappedText,
  captureNode,
  newReportDoc,
  pageContentWidth,
  PRINT_CHART_WIDTH,
  sliceImageHorizontally,
} from "../utils/exportPdf";
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
  const [exporting, setExporting] = useState(false);
  const yAxisPanelRef = useRef<HTMLDivElement>(null);
  const chartBodyRef = useRef<HTMLDivElement>(null);
  const overviewYAxisPanelRef = useRef<HTMLDivElement>(null);
  const overviewChartBodyRef = useRef<HTMLDivElement>(null);

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

  const handleExportPdf = async () => {
    setExporting(true);
    try {
      const [yAxisImg, chartImg, overviewYAxisImg, overviewChartImg] = await Promise.all([
        captureNode(yAxisPanelRef.current),
        captureNode(chartBodyRef.current),
        captureNode(overviewYAxisPanelRef.current),
        captureNode(overviewChartBodyRef.current),
      ]);

      const doc = newReportDoc();
      let y = 50;
      y = addHeading(doc, "Scan Comparison", y, 18);
      y = addSubtext(doc, `Generated ${new Date().toLocaleString()}`, y);

      y = addLabelValueLine(
        doc,
        "Depth Change",
        change !== null ? `${change.toFixed(2)} ${unit}` : "—",
        y,
      );
      y += 10;

      y = addHeading(doc, "Scans", y, 13);
      scans.forEach((scan, i) => {
        const scanStats = perScanStats[i];
        const settled = settledDepths[i];
        y = addLabelValueLine(
          doc,
          scan.title,
          scanStats
            ? `avg ${scanStats.avg.toFixed(1)}  min ${scanStats.min.toFixed(1)}  max ${scanStats.max.toFixed(1)}  settled ${
                settled !== null ? settled.toFixed(1) : "—"
              } (${unit})`
            : "No bathymetry stats available",
          y,
        );
      });
      y += 10;

      y = addHeading(doc, "Bathymetry Data", y, 13);
      if (overviewYAxisImg || overviewChartImg) {
        y = addImagesInRow(doc, [overviewYAxisImg, overviewChartImg], y);
        addCenteredCaption(doc, "Scan Duration (mm:ss)", y);
      } else {
        addWrappedText(doc, "No bathymetry chart data", y);
      }

      // Full-resolution comparison chart, paginated as extra pages after the
      // main report so long scans stay readable instead of being crushed
      // into the compact overview above.
      if (chartImg) {
        const maxSliceWidth = Math.max(150, pageContentWidth(doc) - (yAxisImg?.width ?? 0) - 8);
        const slices = await sliceImageHorizontally(chartImg, maxSliceWidth);
        if (slices.length > 1) {
          const maxX = Math.max(...merged.x, 1);
          slices.forEach((slice, i) => {
            doc.addPage();
            let py = 50;
            py = addHeading(doc, `Bathymetry Detail (${i + 1}/${slices.length})`, py, 13);
            py = addSubtext(
              doc,
              `${timeLabel(maxX * slice.startFraction)} – ${timeLabel(maxX * slice.endFraction)}`,
              py,
            );
            py = addImagesInRow(doc, [yAxisImg, slice], py);
            addCenteredCaption(doc, "Scan Duration (mm:ss)", py);
          });
        }
      }

      doc.save("scan-comparison.pdf");
      notify("PDF exported", { severity: "success" });
    } catch (err) {
      notify(`Export failed: ${(err as Error).message}`, { severity: "error" });
    } finally {
      setExporting(false);
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
        <IconButton onClick={handleExportPdf} disabled={exporting} aria-label="Export to PDF">
          <PictureAsPdfOutlinedIcon />
        </IconButton>
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
                yAxisPanelRef={yAxisPanelRef}
                chartBodyRef={chartBodyRef}
              />
            )}
          </Box>
        </Box>
      </Box>

      {/* Off-screen compact render used only to capture a single-page-
          friendly chart image for PDF export - see handleExportPdf. */}
      {hasData && (
        <Box sx={{ position: "fixed", top: -10000, left: -10000, pointerEvents: "none" }} aria-hidden>
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
            yAxisPanelRef={overviewYAxisPanelRef}
            chartBodyRef={overviewChartBodyRef}
            printWidth={PRINT_CHART_WIDTH}
          />
        </Box>
      )}
    </Box>
  );
}
