import { useEffect, useState } from "react";
import {
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  TextField,
  Typography,
} from "@mui/material";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import AddCircleOutlineRoundedIcon from "@mui/icons-material/AddCircleOutlineRounded";
import SensorsRoundedIcon from "@mui/icons-material/SensorsRounded";
import WifiOffRoundedIcon from "@mui/icons-material/WifiOffRounded";
import DeleteOutlineRoundedIcon from "@mui/icons-material/DeleteOutlineRounded";
import { addSonar, deleteSonar, fetchSonars, type Sonar } from "../utils/sonarRepository";
import { useSnackbar } from "../notifications";

const PRIMARY = "#1E75EC";

interface SonarSensorsProps {
  onBack: () => void;
}

export default function SonarSensors({ onBack }: SonarSensorsProps) {
  const { notify } = useSnackbar();
  const [sonars, setSonars] = useState<Sonar[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [name, setName] = useState("");
  const [sonarId, setSonarId] = useState("");
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      setSonars(await fetchSonars());
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const submitAdd = async () => {
    if (!name.trim() || !sonarId.trim()) return;
    setSaving(true);
    try {
      await addSonar(name.trim(), sonarId.trim());
      setDialogOpen(false);
      setName("");
      setSonarId("");
      await load();
    } catch (err) {
      notify(`Error: ${(err as Error).message}`, { severity: "error" });
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id: string) => {
    try {
      await deleteSonar(id);
      await load();
    } catch (err) {
      notify(`Error: ${(err as Error).message}`, { severity: "error" });
    }
  };

  return (
    <Box sx={{ height: "100%", display: "flex", flexDirection: "column" }}>
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
          Sonar Sensors
        </Typography>
        <IconButton onClick={() => setDialogOpen(true)}>
          <AddCircleOutlineRoundedIcon sx={{ color: PRIMARY }} />
        </IconButton>
      </Box>

      <Box sx={{ flex: 1, overflow: "auto", p: 2, maxWidth: 900, width: "100%", mx: "auto" }}>
        {loading ? (
          <Box sx={{ display: "flex", justifyContent: "center", py: 4 }}>
            <CircularProgress />
          </Box>
        ) : error ? (
          <Box
            sx={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 1.5, mt: 4 }}
          >
            <WifiOffRoundedIcon sx={{ fontSize: 48, color: "#9CA3AF" }} />
            <Typography sx={{ color: "text.secondary", textAlign: "center" }}>{error}</Typography>
            <Button variant="contained" onClick={load}>
              Retry
            </Button>
          </Box>
        ) : sonars.length === 0 ? (
          <Box
            sx={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 1.5, mt: 4 }}
          >
            <Box sx={{ p: 2.5, borderRadius: "50%", bgcolor: "#EFF6FF" }}>
              <SensorsRoundedIcon sx={{ fontSize: 48, color: PRIMARY }} />
            </Box>
            <Typography sx={{ fontSize: 18, fontWeight: 700 }}>No Sensors Added</Typography>
            <Typography sx={{ fontSize: 14, color: "#9CA3AF" }}>
              Tap + to add your first sonar sensor
            </Typography>
          </Box>
        ) : (
          <List sx={{ display: "flex", flexDirection: "column", gap: 1.25 }}>
            {sonars.map((sonar) => (
              <ListItem
                key={sonar.sonar_id}
                sx={{
                  bgcolor: "#FFFFFF",
                  borderRadius: "14px",
                  border: "1px solid #E5E7EB",
                  boxShadow: "0 4px 10px rgba(0,0,0,0.02)",
                }}
                secondaryAction={
                  <Box sx={{ display: "flex", alignItems: "center", gap: 0.5 }}>
                    <Chip
                      label={sonar.status ?? "Active"}
                      size="small"
                      color="success"
                      variant="outlined"
                    />
                    <IconButton onClick={() => remove(sonar.sonar_id)}>
                      <DeleteOutlineRoundedIcon sx={{ color: "#9CA3AF" }} />
                    </IconButton>
                  </Box>
                }
              >
                <ListItemIcon sx={{ minWidth: 48 }}>
                  <Box sx={{ p: 1, borderRadius: "50%", bgcolor: "#EFF6FF", display: "flex" }}>
                    <SensorsRoundedIcon sx={{ color: PRIMARY }} />
                  </Box>
                </ListItemIcon>
                <ListItemText
                  primary={sonar.name}
                  secondary={`ID: ${sonar.sonar_id}`}
                  slotProps={{
                    primary: { sx: { fontWeight: 600 } },
                    secondary: { sx: { fontSize: 13, color: "#9CA3AF" } },
                  }}
                />
              </ListItem>
            ))}
          </List>
        )}
      </Box>

      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} fullWidth maxWidth="xs">
        <DialogTitle sx={{ fontWeight: 700 }}>Add Sonar Sensor</DialogTitle>
        <DialogContent
          sx={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "space-evenly",
            minHeight: 200,
          }}
        >
          <TextField
            label="Sensor Name"
            placeholder="e.g. Port Sonar"
            value={name}
            disabled={saving}
            onChange={(e) => setName(e.target.value)}
            fullWidth
          />
          <TextField
            label="Sensor ID"
            placeholder="e.g. SN-001"
            value={sonarId}
            disabled={saving}
            onChange={(e) => setSonarId(e.target.value)}
            fullWidth
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button variant="contained" onClick={submitAdd} disabled={saving}>
            {saving ? <CircularProgress size={18} color="inherit" /> : "Add"}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
