import { useMemo, useState } from "react";
import {
  Box,
  Button,
  Chip,
  FormControl,
  IconButton,
  InputLabel,
  MenuItem,
  OutlinedInput,
  Select,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
  type SelectChangeEvent,
} from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import { LineChart } from "@mui/x-charts/LineChart";
import { saveIspNotes, formatIspUploadedTime, type IspRecord } from "../utils/ispRepo";
import { useSnackbar } from "../notifications";
import menuIcon from "../assets/menu.svg";

// Categorical palette, slots 1-5 (validated adjacent-pair ordering) - same
// set CompareScans.tsx uses for its per-scan series.
const SERIES_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"];

interface IspAnalysisProps {
  record: IspRecord;
  onBack: () => void;
  onToggleNav: () => void;
}

function isNumericColumn(rows: IspRecord["rows"], index: number): boolean {
  let seen = 0;
  let numeric = 0;
  for (const row of rows) {
    const cell = row[index];
    if (cell === null || cell === undefined || cell === "") continue;
    seen += 1;
    if (typeof cell === "number" || (typeof cell === "string" && Number.isFinite(Number(cell)))) {
      numeric += 1;
    }
  }
  return seen > 0 && numeric / seen > 0.5;
}

export default function IspAnalysis({ record, onBack, onToggleNav }: IspAnalysisProps) {
  const { notify } = useSnackbar();
  const [notes, setNotes] = useState(record.notes);
  const [saving, setSaving] = useState(false);

  const numericColumns = useMemo(
    () => record.headers.map((_, i) => i).filter((i) => isNumericColumn(record.rows, i)),
    [record.headers, record.rows],
  );

  const [xIndex, setXIndex] = useState(0);
  const [yIndices, setYIndices] = useState<number[]>(() =>
    numericColumns.filter((i) => i !== 0),
  );

  const handleYChange = (e: SelectChangeEvent<number[]>) => {
    const value = e.target.value;
    setYIndices(typeof value === "string" ? value.split(",").map(Number) : value);
  };

  const handleSaveNote = async () => {
    setSaving(true);
    try {
      await saveIspNotes(record, notes);
      notify("Note saved", { severity: "success" });
    } catch (err) {
      notify(`Failed to save note: ${(err as Error).message}`, { severity: "error" });
    } finally {
      setSaving(false);
    }
  };

  const xLabels = record.rows.map((row) => String(row[xIndex] ?? ""));
  const series = yIndices.map((yIndex, i) => ({
    id: `col-${yIndex}`,
    label: record.headers[yIndex] ?? `Column ${yIndex + 1}`,
    color: SERIES_COLORS[i % SERIES_COLORS.length],
    data: record.rows.map((row) => {
      const raw = row[yIndex];
      const n = Number(raw);
      return raw === null || raw === undefined || raw === "" || !Number.isFinite(n) ? null : n;
    }),
  }));

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
          ISP Data
        </Typography>
        <Box sx={{ width: 40 }} />
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
              mt: 6,
            }}
          >
            {[
              ["File Name", record.fileName],
              ["Uploaded", formatIspUploadedTime(record)],
              ["Sheet", record.sheetName],
              ["Rows", String(record.rows.length)],
              ["Columns", String(record.headers.length)],
            ].map(([label, value]) => (
              <Box key={label} sx={{ display: "flex", justifyContent: "space-between", mb: 1.25 }}>
                <Typography sx={{ color: "text.secondary", fontSize: 12, fontWeight: 600 }}>
                  {label}
                </Typography>
                <Typography sx={{ fontSize: 12, fontWeight: 700 }}>{value}</Typography>
              </Box>
            ))}
          </Box>

          <Typography sx={{ fontWeight: 800, fontSize: 14 }}>Chart</Typography>

          <Box
            sx={{ bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 }}
          >
            <Box sx={{ display: "flex", flexWrap: "wrap", gap: 1.5, mb: 2 }}>
              <FormControl size="small" sx={{ minWidth: 180 }}>
                <InputLabel id="isp-x-axis-label">X-axis</InputLabel>
                <Select
                  labelId="isp-x-axis-label"
                  label="X-axis"
                  value={xIndex}
                  onChange={(e) => setXIndex(Number(e.target.value))}
                >
                  {record.headers.map((header, i) => (
                    <MenuItem key={i} value={i}>
                      {header}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
              <FormControl size="small" sx={{ minWidth: 220, flex: 1 }}>
                <InputLabel id="isp-y-axis-label">Y-axis columns</InputLabel>
                <Select
                  labelId="isp-y-axis-label"
                  multiple
                  label="Y-axis columns"
                  value={yIndices}
                  onChange={handleYChange}
                  input={<OutlinedInput label="Y-axis columns" />}
                  renderValue={(selected) => (
                    <Box sx={{ display: "flex", flexWrap: "wrap", gap: 0.5 }}>
                      {selected.map((i) => (
                        <Chip key={i} label={record.headers[i]} size="small" />
                      ))}
                    </Box>
                  )}
                >
                  {record.headers.map((header, i) => (
                    <MenuItem key={i} value={i} disabled={i === xIndex}>
                      {header}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            </Box>

            {yIndices.length === 0 || record.rows.length === 0 ? (
              <Box sx={{ height: 300, display: "flex", alignItems: "center", justifyContent: "center" }}>
                <Typography>Select at least one Y-axis column to chart</Typography>
              </Box>
            ) : (
              <LineChart
                height={300}
                xAxis={[{ scaleType: "point", data: xLabels, label: record.headers[xIndex] }]}
                series={series.map((s) => ({
                  id: s.id,
                  label: s.label,
                  color: s.color,
                  data: s.data,
                  showMark: false,
                  connectNulls: true,
                  curve: "linear",
                }))}
                margin={{ left: 60, right: 20, top: 20, bottom: 40 }}
                grid={{ horizontal: true, vertical: true }}
              />
            )}
          </Box>

          <Typography sx={{ fontWeight: 800, fontSize: 14 }}>Data Table</Typography>
          <Box
            sx={{
              bgcolor: "#FFFFFF",
              borderRadius: "14px",
              border: "1px solid #E5E7EB",
              p: 1.75,
              overflow: "hidden",
            }}
          >
            <TableContainer sx={{ maxHeight: 420 }}>
              <Table size="small" stickyHeader>
                <TableHead>
                  <TableRow>
                    {record.headers.map((header, i) => (
                      <TableCell key={i} sx={{ fontWeight: 700, whiteSpace: "nowrap" }}>
                        {header}
                      </TableCell>
                    ))}
                  </TableRow>
                </TableHead>
                <TableBody>
                  {record.rows.map((row, rIdx) => (
                    <TableRow key={rIdx}>
                      {record.headers.map((_, cIdx) => (
                        <TableCell key={cIdx} sx={{ whiteSpace: "nowrap" }}>
                          {row[cIdx] ?? ""}
                        </TableCell>
                      ))}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
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
