import { useEffect, useRef, useState } from "react";
import { Box, Button, IconButton, TextField, Typography } from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import PictureAsPdfOutlinedIcon from "@mui/icons-material/PictureAsPdfOutlined";
import DepthLineChart from "../components/DepthLineChart";
import { saveNotes, type ScanData } from "../utils/scanRepo";
import { depthUnitLabel, loadIsMetric } from "../utils/unitsRepository";
import { buildGappedSeries, calcDepthStats, computeDepthSpots } from "../utils/depthChart";
import { useSnackbar } from "../notifications";
import {
  addHeading,
  addImagesInRow,
  addLabelValueLine,
  addSubtext,
  addWrappedText,
  captureNode,
  newReportDoc,
} from "../utils/exportPdf";
import menuIcon from "../assets/menu.svg";

const SEQUENTIAL_BLUE = "#2a78d6";

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
  const yAxisPanelRef = useRef<HTMLDivElement>(null);
  const chartBodyRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setIsMetric(loadIsMetric());
  }, []);

  const unit = depthUnitLabel(isMetric);
  const stats = calcDepthStats(scan.bathymetryRows, isMetric);
  const spots = computeDepthSpots(scan.bathymetryRows, isMetric);
  const series = buildGappedSeries(spots);

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
      const [yAxisImg, chartImg] = await Promise.all([
        captureNode(yAxisPanelRef.current),
        captureNode(chartBodyRef.current),
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
        y = addLabelValueLine(doc, `Min (${unit})`, stats.min.toFixed(1), y);
        y = addLabelValueLine(doc, `Max (${unit})`, stats.max.toFixed(1), y);
      } else {
        y = addWrappedText(doc, "No bathymetry stats available", y);
      }
      y += 10;

      y = addHeading(doc, "Bathymetry Data", y, 13);
      if (yAxisImg || chartImg) {
        y = addImagesInRow(doc, [yAxisImg, chartImg], y);
      } else {
        y = addWrappedText(doc, "No bathymetry chart data", y);
      }

      y = addHeading(doc, "Notes", y, 13);
      addWrappedText(doc, notes, y);

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
            <Box
              sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}
            >
              <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600 }}>
                No bathymetry stats available
              </Typography>
            </Box>
          )}

          <Box
            sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}
          >
            <Typography sx={{ fontSize: 13, fontWeight: 800 }}>Bathymetry Data</Typography>
            <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mb: 1.5 }}>
              Bathymetry depth over scan time
            </Typography>
            <DepthLineChart
              xValues={series.x}
              unit={unit}
              series={[{ id: scan.id, data: series.y, color: SEQUENTIAL_BLUE }]}
              yAxisPanelRef={yAxisPanelRef}
              chartBodyRef={chartBodyRef}
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
