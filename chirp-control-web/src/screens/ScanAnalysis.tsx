import { useEffect, useRef, useState } from "react";
import { Box, Button, IconButton, Menu, MenuItem, TextField, Typography } from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import PictureAsPdfOutlinedIcon from "@mui/icons-material/PictureAsPdfOutlined";
import FileDownloadOutlinedIcon from "@mui/icons-material/FileDownloadOutlined";
import DepthLineChart from "../components/DepthLineChart";
import AcquisitionCard from "../components/AcquisitionCard";
import { saveAcquisition, saveNotes, type ScanData } from "../utils/scanRepo";
import { cmToDisplayUnit, depthUnitLabel, loadIsMetric } from "../utils/unitsRepository";
import { buildGappedSeries, computeDepthSpots, timeLabel } from "../utils/depthChart";
import {
  depthStatistics,
  mudlineElevationM,
  processingSummary,
  settledDepth,
  SETTLED_WINDOW_S,
  tryProcessBathymetry,
} from "../utils/bathymetry";
import { ACQUISITION_FIELDS, formatAcquisitionValue, type AcquisitionMetadata } from "../utils/acquisition";
import { buildAnnotatedCsv, downloadText, safeFileName } from "../utils/exportScanCsv";
import { downloadBytes, encodeScanNetcdf } from "../utils/exportScanNetcdf";
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

const SEQUENTIAL_BLUE = "#2a78d6";
const cardSx = { bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 };

interface ScanAnalysisProps {
  scan: ScanData;
  onBack: () => void;
  onToggleNav: () => void;
}

export default function ScanAnalysis({ scan, onBack, onToggleNav }: ScanAnalysisProps) {
  const { notify } = useSnackbar();
  const [isMetric, setIsMetric] = useState(true);
  const [notes, setNotes] = useState(scan.notes);
  const [saving, setSaving] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [acquisition, setAcquisition] = useState<AcquisitionMetadata>(scan.acquisition);
  const [exportMenuAnchor, setExportMenuAnchor] = useState<HTMLElement | null>(null);
  const yAxisPanelRef = useRef<HTMLDivElement>(null);
  const chartBodyRef = useRef<HTMLDivElement>(null);
  const overviewYAxisPanelRef = useRef<HTMLDivElement>(null);
  const overviewChartBodyRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setIsMetric(loadIsMetric());
  }, []);

  const unit = depthUnitLabel(isMetric);
  const { scan: processed, error: formatError } = tryProcessBathymetry(scan.bathymetryRows, {
    blindSpotOffsetCm: acquisition.blindSpotOffsetCm,
  });
  const statsCm = processed ? depthStatistics(processed) : null;
  const settledCm = processed ? settledDepth(processed) : null;
  const toDisplay = (cm: number) => cmToDisplayUnit(cm, isMetric);
  const stats = statsCm
    ? {
        avg: toDisplay(statsCm.avgCm),
        min: toDisplay(statsCm.minCm),
        max: toDisplay(statsCm.maxCm),
        sd: statsCm.stdCm === null ? null : toDisplay(statsCm.stdCm),
        n: statsCm.n,
      }
    : null;
  const settled = settledCm ? toDisplay(settledCm.depthCm) : null;
  const mudlineElevation = mudlineElevationM(acquisition.transducerElevationM, settledCm?.depthCm);
  const spots = processed ? computeDepthSpots(processed, isMetric) : [];
  const series = buildGappedSeries(spots);
  const offsetCm = acquisition.blindSpotOffsetCm ?? 0;
  const correctionText =
    offsetCm === 0
      ? "No blind-spot correction applied (depths as reported by the sonar)"
      : `Blind-spot offset of ${offsetCm > 0 ? "+" : ""}${offsetCm} cm added to every depth`;
  const processingLines = processed
    ? [
        processingSummary(processed.counts),
        correctionText,
        `Depth is measured downward from the transducer face. Settled depth = mean of the last ${SETTLED_WINDOW_S} s (n = ${settledCm?.n ?? 0}).`,
      ]
    : [];

  const handleSaveAcquisition = async (next: AcquisitionMetadata) => {
    try {
      const saved = await saveAcquisition(scan, next);
      setAcquisition(saved);
      notify("Acquisition settings saved", { severity: "success" });
    } catch (err) {
      notify(`Failed to save settings: ${(err as Error).message}`, { severity: "error" });
      throw err;
    }
  };

  const handleExportCsv = () => {
    if (!processed) {
      notify("No bathymetry data to export", { severity: "error" });
      return;
    }
    const csv = buildAnnotatedCsv({
      title: scan.title,
      scanId: scan.id,
      folderName: scan.folderName,
      scan: processed,
      acquisition,
    });
    downloadText(`${safeFileName(scan.title)}-bathymetry.csv`, csv);
    notify("CSV exported", { severity: "success" });
  };

  const handleExportNetcdf = () => {
    if (!processed || processed.samples.length === 0) {
      notify("No bathymetry data to export", { severity: "error" });
      return;
    }
    try {
      const bytes = encodeScanNetcdf({
        title: scan.title,
        scanId: scan.id,
        folderName: scan.folderName,
        scan: processed,
        acquisition,
        sonarRows: scan.sonarRows,
      });
      downloadBytes(`${safeFileName(scan.title)}-bathymetry.nc`, bytes, "application/x-netcdf");
      notify("NetCDF exported", { severity: "success" });
    } catch (err) {
      notify(`NetCDF export failed: ${(err as Error).message}`, { severity: "error" });
    }
  };

  const handleShare = async () => {
    const summary = `${scan.title} — ${scan.time} (${scan.duration})`;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: scan.title, text: summary });
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

  const handleSaveNote = async () => {
    setSaving(true);
    try {
      await saveNotes(scan, notes);
      notify("Note saved", { severity: "success" });
    } catch (err) {
      notify(`Failed to save note: ${(err as Error).message}`, { severity: "error" });
    } finally {
      setSaving(false);
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
      y = addHeading(doc, scan.title, y, 18);
      y = addSubtext(doc, `Generated ${new Date().toLocaleString()}`, y);

      y = addLabelValueLine(doc, "Date, Time", scan.time, y);
      y = addLabelValueLine(doc, "Duration", scan.duration, y);
      y += 10;

      y = addHeading(doc, "Depth Data", y, 13);
      if (stats) {
        y = addLabelValueLine(doc, `Avg (${unit})`, stats.avg.toFixed(1), y);
        y = addLabelValueLine(doc, `SD (${unit})`, stats.sd !== null ? stats.sd.toFixed(2) : "—", y);
        y = addLabelValueLine(doc, `Min (${unit})`, stats.min.toFixed(1), y);
        y = addLabelValueLine(doc, `Max (${unit})`, stats.max.toFixed(1), y);
        y = addLabelValueLine(
          doc,
          `Settled, last ${SETTLED_WINDOW_S} s (${unit})`,
          settled !== null ? settled.toFixed(1) : "—",
          y,
        );
        y = addLabelValueLine(doc, "Samples (n)", String(stats.n), y);
        if (mudlineElevation !== null) {
          y = addLabelValueLine(
            doc,
            "Mudline elevation (m)",
            `${mudlineElevation.toFixed(3)} ${acquisition.datum ?? ""}`.trim(),
            y,
          );
        }
      } else {
        y = addWrappedText(doc, formatError ?? "No bathymetry stats available", y);
      }
      y += 10;

      y = addHeading(doc, "Processing", y, 13);
      for (const line of processingLines) y = addWrappedText(doc, line, y);
      y = addWrappedText(doc, `Software: chirp-control-web ${__APP_VERSION__}`, y);
      y += 10;

      y = addHeading(doc, "Acquisition Settings", y, 13);
      for (const spec of ACQUISITION_FIELDS) {
        y = addLabelValueLine(doc, spec.label, formatAcquisitionValue(acquisition, spec), y);
      }
      y += 10;

      y = addHeading(doc, "Bathymetry Data", y, 13);
      if (overviewYAxisImg || overviewChartImg) {
        y = addImagesInRow(doc, [overviewYAxisImg, overviewChartImg], y);
        y = addCenteredCaption(doc, "Scan Duration (mm:ss)", y);
      } else {
        y = addWrappedText(doc, "No bathymetry chart data", y);
      }

      y = addHeading(doc, "Notes", y, 13);
      addWrappedText(doc, notes, y);

      // Full-resolution bathymetry chart, paginated as extra pages after the
      // main report so long scans stay readable instead of being crushed
      // into the compact overview above.
      if (chartImg) {
        const maxSliceWidth = Math.max(150, pageContentWidth(doc) - (yAxisImg?.width ?? 0) - 8);
        const slices = await sliceImageHorizontally(chartImg, maxSliceWidth);
        if (slices.length > 1) {
          const maxX = Math.max(...series.x, 1);
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

      doc.save(`${scan.title || "scan"}-analysis.pdf`);
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
        <IconButton
          onClick={(e) => setExportMenuAnchor(e.currentTarget)}
          disabled={!processed}
          aria-label="Export data"
        >
          <FileDownloadOutlinedIcon />
        </IconButton>
        <Menu
          anchorEl={exportMenuAnchor}
          open={exportMenuAnchor !== null}
          onClose={() => setExportMenuAnchor(null)}
        >
          <MenuItem
            onClick={() => {
              setExportMenuAnchor(null);
              handleExportCsv();
            }}
          >
            Annotated CSV (.csv)
          </MenuItem>
          <MenuItem
            onClick={() => {
              setExportMenuAnchor(null);
              handleExportNetcdf();
            }}
          >
            NetCDF, CF-1.8 (.nc)
          </MenuItem>
        </Menu>
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
          <Box
            sx={{
              bgcolor: "#FFFFFF",
              borderRadius: "14px",
              border: "1px solid #E5E7EB",
              p: 1.75,
              // Clear the floating back button (top/left 12, ~40px box) so it
              // doesn't overlap this first card.
              mt: 6,
            }}
          >
            {[
              ["Scan Name", scan.title],
              ["Date, Time", scan.time],
              ["Duration", scan.duration],
            ].map(([label, value]) => (
              <Box key={label} sx={{ display: "flex", justifyContent: "space-between", mb: 1.25 }}>
                <Typography sx={{ color: "text.secondary", fontSize: 12, fontWeight: 600 }}>
                  {label}
                </Typography>
                <Typography sx={{ fontSize: 12, fontWeight: 700 }}>{value}</Typography>
              </Box>
            ))}
          </Box>

          <Typography sx={{ fontWeight: 800, fontSize: 14 }}>Depth Data</Typography>

          {stats ? (
            <Box
              sx={{
                bgcolor: "#FFFFFF",
                borderRadius: "14px",
                border: "1px solid #E5E7EB",
                p: 1.75,
                display: "flex",
              }}
            >
              {(["avg", "min", "max"] as const).map((key) => (
                <Box key={key} sx={{ flex: 1, textAlign: "center" }}>
                  <Typography sx={{ fontSize: 20, fontWeight: 800 }}>
                    {stats[key].toFixed(1)}
                  </Typography>
                  <Typography
                    sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mt: 0.5 }}
                  >
                    {key === "avg" ? "Avg" : key === "min" ? "Min" : "Max"} ({unit})
                  </Typography>
                </Box>
              ))}
            </Box>
          ) : (
            <Box sx={cardSx}>
              <Typography
                sx={{ fontSize: 12, color: formatError ? "error.main" : "text.secondary", fontWeight: 600 }}
              >
                {formatError ?? "No bathymetry stats available"}
              </Typography>
            </Box>
          )}

          {stats && (
            <Box sx={{ ...cardSx, display: "flex" }}>
              {[
                [stats.sd !== null ? stats.sd.toFixed(2) : "—", `SD (${unit})`],
                [settled !== null ? settled.toFixed(1) : "—", `Settled (${unit})`],
                [String(stats.n), "Samples"],
                ...(mudlineElevation !== null
                  ? [[mudlineElevation.toFixed(3), `Mudline elev. (m${acquisition.datum ? `, ${acquisition.datum}` : ""})`]]
                  : []),
              ].map(([value, label]) => (
                <Box key={label} sx={{ flex: 1, textAlign: "center" }}>
                  <Typography sx={{ fontSize: 20, fontWeight: 800 }}>{value}</Typography>
                  <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mt: 0.5 }}>
                    {label}
                  </Typography>
                </Box>
              ))}
            </Box>
          )}

          {processed && (
            <Box sx={cardSx}>
              <Typography sx={{ fontSize: 13, fontWeight: 800, mb: 0.75 }}>Processing</Typography>
              {processingLines.map((line) => (
                <Typography key={line} sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mb: 0.5 }}>
                  {line}
                </Typography>
              ))}
            </Box>
          )}

          <AcquisitionCard acquisition={acquisition} onSave={handleSaveAcquisition} />

          <Box
            sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}
          >
            <Typography sx={{ fontSize: 13, fontWeight: 800, textAlign: "center" }}>
              Bathymetry Data
            </Typography>
            <Typography
              sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mb: 1.5, textAlign: "center" }}
            >
              Bathymetry depth over scan time
            </Typography>
            <DepthLineChart
              xValues={series.x}
              unit={unit}
              series={[{ id: scan.id, data: series.y, color: SEQUENTIAL_BLUE }]}
              yAxisPanelRef={yAxisPanelRef}
              chartBodyRef={chartBodyRef}
              height={450}
              pxPerSecond={16}
            />
          </Box>

          {/* Off-screen compact render used only to capture a single-page-
              friendly chart image for PDF export - see handleExportPdf. */}
          <Box sx={{ position: "fixed", top: -10000, left: -10000, pointerEvents: "none" }} aria-hidden>
            <DepthLineChart
              xValues={series.x}
              unit={unit}
              series={[{ id: scan.id, data: series.y, color: SEQUENTIAL_BLUE }]}
              yAxisPanelRef={overviewYAxisPanelRef}
              chartBodyRef={overviewChartBodyRef}
              printWidth={PRINT_CHART_WIDTH}
            />
          </Box>

          <Typography sx={{ fontWeight: 800, fontSize: 14 }}>Notes</Typography>
          <Box
            sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}
          >
            <TextField
              fullWidth
              multiline
              minRows={4}
              placeholder="Notes, site conditions, issues..."
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
            <Button
              fullWidth
              variant="contained"
              onClick={handleSaveNote}
              disabled={saving}
              sx={{ mt: 1.5 }}
            >
              {saving ? "Saving..." : "Save Note"}
            </Button>
          </Box>
        </Box>
      </Box>
    </Box>
  );
}
