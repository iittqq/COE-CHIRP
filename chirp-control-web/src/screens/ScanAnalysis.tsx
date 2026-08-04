import { useEffect, useState } from "react";
import { Box, Button, IconButton, TextField, Typography } from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import DepthLineChart from "../components/DepthLineChart";
import { saveNotes, type ScanData } from "../utils/scanRepo";
import { depthUnitLabel, loadIsMetric } from "../utils/unitsRepository";
import { buildGappedSeries, calcDepthStats, computeDepthSpots } from "../utils/depthChart";
import { useSnackbar } from "../notifications";

const SEQUENTIAL_BLUE = "#2a78d6";

interface ScanAnalysisProps {
  scan: ScanData;
  onBack: () => void;
}

export default function ScanAnalysis({ scan, onBack }: ScanAnalysisProps) {
  const { notify } = useSnackbar();
  const [isMetric, setIsMetric] = useState(true);
  const [notes, setNotes] = useState(scan.notes);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setIsMetric(loadIsMetric());
  }, []);

  const unit = depthUnitLabel(isMetric);
  const stats = calcDepthStats(scan.bathymetryRows, isMetric);
  const spots = computeDepthSpots(scan.bathymetryRows, isMetric);
  const series = buildGappedSeries(spots);

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
        <Box sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}>
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
          <Box sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75, display: "flex" }}>
            {(["avg", "min", "max"] as const).map((key) => (
              <Box key={key} sx={{ flex: 1, textAlign: "center" }}>
                <Typography sx={{ fontSize: 20, fontWeight: 800 }}>
                  {stats[key].toFixed(1)}
                </Typography>
                <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mt: 0.5 }}>
                  {key === "avg" ? "Avg" : key === "min" ? "Min" : "Max"} ({unit})
                </Typography>
              </Box>
            ))}
          </Box>
        ) : (
          <Box sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}>
            <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600 }}>
              No bathymetry stats available
            </Typography>
          </Box>
        )}

        <Box sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}>
          <Typography sx={{ fontSize: 13, fontWeight: 800 }}>Bathymetry Data</Typography>
          <Typography sx={{ fontSize: 12, color: "text.secondary", fontWeight: 600, mb: 1.5 }}>
            Bathymetry depth over scan time
          </Typography>
          <DepthLineChart
            xValues={series.x}
            unit={unit}
            series={[{ id: scan.id, data: series.y, color: SEQUENTIAL_BLUE }]}
          />

        </Box>

        <Typography sx={{ fontWeight: 800, fontSize: 14 }}>Notes</Typography>
        <Box sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}>
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
  );
}
