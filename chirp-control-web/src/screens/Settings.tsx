import { useEffect, useRef, useState, type ChangeEvent } from "react";
import {
  Avatar,
  Box,
  Divider,
  IconButton,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Switch,
  Typography,
} from "@mui/material";
import PersonRoundedIcon from "@mui/icons-material/PersonRounded";
import EditRoundedIcon from "@mui/icons-material/EditRounded";
import SquareFootRoundedIcon from "@mui/icons-material/SquareFootRounded";
import TuneRoundedIcon from "@mui/icons-material/TuneRounded";
import ChevronRightRoundedIcon from "@mui/icons-material/ChevronRightRounded";
import TrackChangesRoundedIcon from "@mui/icons-material/TrackChangesRounded";
import WarningAmberRoundedIcon from "@mui/icons-material/WarningAmberRounded";
import SupportAgentRoundedIcon from "@mui/icons-material/SupportAgentRounded";
import InfoOutlinedIcon from "@mui/icons-material/InfoOutlined";
import { fetchSonars, type Sonar } from "../utils/sonarRepository";
import {
  loadDredgeWarningsEnabled,
  loadSonarAlertsEnabled,
  saveDredgeWarningsEnabled,
  saveSonarAlertsEnabled,
} from "../utils/alertPrefs";
import { loadIsMetric, saveIsMetric } from "../utils/unitsRepository";
import { useSnackbar } from "../notifications";
import { clearSession, getSession } from "../utils/auth";

const PRIMARY = "#1E75EC";
const PROFILE_PHOTO_KEY = "chirp_profile_photo";
const SUPPORT_EMAIL = "support@chirpsonar.com";

const sectionSx = {
  bgcolor: "#FFFFFF",
  borderRadius: "16px",
  border: "1px solid #E5E7EB",
  boxShadow: "0 4px 10px rgba(0,0,0,0.02)",
  overflow: "hidden",
};

function IconBadge({ Icon }: { Icon: typeof SquareFootRoundedIcon }) {
  return (
    <Box
      sx={{
        p: 1,
        borderRadius: "50%",
        bgcolor: "#EFF6FF",
        display: "flex",
      }}
    >
      <Icon sx={{ color: PRIMARY, fontSize: 20 }} />
    </Box>
  );
}

interface SettingsProps {
  onOpenSonarSensors: () => void;
  onLogout: () => void;
}

export default function Settings({ onOpenSonarSensors, onLogout }: SettingsProps) {
  const { notify } = useSnackbar();
  const [isMetric, setIsMetric] = useState(true);
  const [sonarAlerts, setSonarAlerts] = useState(true);
  const [dredgeWarnings, setDredgeWarnings] = useState(true);
  const [sonars, setSonars] = useState<Sonar[]>([]);
  const [photo, setPhoto] = useState<string | null>(null);
  const photoInputRef = useRef<HTMLInputElement>(null);

  const session = getSession();

  useEffect(() => {
    setIsMetric(loadIsMetric());
    setSonarAlerts(loadSonarAlertsEnabled());
    setDredgeWarnings(loadDredgeWarningsEnabled());
    setPhoto(localStorage.getItem(PROFILE_PHOTO_KEY));
    fetchSonars()
      .then(setSonars)
      .catch(() => {});
  }, []);

  const handlePhotoChange = (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result;
      if (typeof dataUrl !== "string") return;
      localStorage.setItem(PROFILE_PHOTO_KEY, dataUrl);
      setPhoto(dataUrl);
    };
    reader.onerror = () => notify("Couldn't read that image.", { severity: "error" });
    reader.readAsDataURL(file);
  };

  const handleLogout = () => {
    clearSession();
    onLogout();
  };

  const setMetric = (value: boolean) => {
    setIsMetric(value);
    saveIsMetric(value);
  };

  const setAlerts = (value: boolean) => {
    setSonarAlerts(value);
    saveSonarAlertsEnabled(value);
  };

  const setDredge = (value: boolean) => {
    setDredgeWarnings(value);
    saveDredgeWarningsEnabled(value);
  };

  return (
    <Box
      sx={{
        px: 2,
        py: 3,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 2.5,
        maxWidth: 640,
        mx: "auto",
      }}
    >
      <Box sx={{ position: "relative" }}>
        <Avatar src={photo ?? undefined} sx={{ width: 110, height: 110, bgcolor: "grey.500" }}>
          {!photo && <PersonRoundedIcon sx={{ fontSize: 48 }} />}
        </Avatar>
        <IconButton
          onClick={() => photoInputRef.current?.click()}
          sx={{
            position: "absolute",
            bottom: 0,
            right: 0,
            width: 32,
            height: 32,
            bgcolor: PRIMARY,
            border: "2px solid #FFFFFF",
            "&:hover": { bgcolor: PRIMARY },
          }}
        >
          <EditRoundedIcon sx={{ color: "#FFFFFF", fontSize: 16 }} />
        </IconButton>
        <input
          ref={photoInputRef}
          type="file"
          accept="image/*"
          hidden
          onChange={handlePhotoChange}
        />
      </Box>
      <Typography sx={{ fontSize: 22, fontWeight: 700, color: "#111827", mt: -1 }}>
        {session?.email ?? "Signed in"}
      </Typography>

      <Box sx={{ width: "100%" }}>
        <Typography sx={{ fontSize: 12, fontWeight: 700, color: "#6B7280", letterSpacing: 0.5, pl: 0.5, pb: 1 }}>
          SONAR CONFIGURATION
        </Typography>
        <Box sx={sectionSx}>
          <List disablePadding>
            <ListItemButton sx={{ py: 1.5 }} disableRipple>
              <ListItemIcon sx={{ minWidth: 48 }}>
                <IconBadge Icon={SquareFootRoundedIcon} />
              </ListItemIcon>
              <ListItemText primary="Units of Measurement" slotProps={{ primary: { sx: { fontWeight: 600 } } }} />
            </ListItemButton>
            <Box sx={{ px: 2, pb: 2 }}>
              <Box sx={{ display: "flex", bgcolor: "#F1F3F5", borderRadius: "8px", height: 40, p: 0.5 }}>
                {[
                  { label: "Metric", value: true },
                  { label: "Imperial", value: false },
                ].map((opt) => {
                  const active = isMetric === opt.value;
                  return (
                    <Box
                      key={opt.label}
                      onClick={() => setMetric(opt.value)}
                      sx={{
                        flex: 1,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        borderRadius: "6px",
                        cursor: "pointer",
                        bgcolor: active ? "#FFFFFF" : "transparent",
                        boxShadow: active ? "0 2px 4px rgba(0,0,0,0.05)" : "none",
                        color: active ? PRIMARY : "#6B7280",
                        fontWeight: 700,
                        fontSize: 14,
                      }}
                    >
                      {opt.label}
                    </Box>
                  );
                })}
              </Box>
            </Box>
            <Divider />
            <ListItemButton sx={{ py: 1.5 }} onClick={onOpenSonarSensors}>
              <ListItemIcon sx={{ minWidth: 48 }}>
                <IconBadge Icon={TuneRoundedIcon} />
              </ListItemIcon>
              <ListItemText
                primary="Sonar Sensors"
                secondary="Manage or add new sensors"
                slotProps={{ primary: { sx: { fontWeight: 600 } }, secondary: { sx: { fontSize: 13, color: "#9CA3AF" } } }}
              />
              <Box sx={{ display: "flex", alignItems: "center", gap: 0.5 }}>
                <Typography sx={{ color: "grey.500", fontSize: 14 }}>
                  {sonars.length} Active
                </Typography>
                <ChevronRightRoundedIcon sx={{ color: "grey.400" }} />
              </Box>
            </ListItemButton>
          </List>
        </Box>
      </Box>

      <Box sx={{ width: "100%" }}>
        <Typography sx={{ fontSize: 12, fontWeight: 700, color: "#6B7280", letterSpacing: 0.5, pl: 0.5, pb: 1 }}>
          NOTIFICATIONS
        </Typography>
        <Box sx={sectionSx}>
          <List disablePadding>
            <ListItemButton sx={{ py: 1.5 }} disableRipple onClick={() => setAlerts(!sonarAlerts)}>
              <ListItemIcon sx={{ minWidth: 48 }}>
                <IconBadge Icon={TrackChangesRoundedIcon} />
              </ListItemIcon>
              <ListItemText
                primary="Sonar Alerts"
                secondary="Notify on connectivity loss and when a scan starts/finishes"
                slotProps={{ primary: { sx: { fontWeight: 600 } }, secondary: { sx: { fontSize: 13, color: "#9CA3AF" } } }}
              />
              <Switch checked={sonarAlerts} onChange={(e) => setAlerts(e.target.checked)} />
            </ListItemButton>
            <Divider />
            <ListItemButton sx={{ py: 1.5 }} disableRipple onClick={() => setDredge(!dredgeWarnings)}>
              <ListItemIcon sx={{ minWidth: 48 }}>
                <IconBadge Icon={WarningAmberRoundedIcon} />
              </ListItemIcon>
              <ListItemText
                primary="Dredge Depth Warnings"
                secondary="Alert during a scan if the sonar reports water is too shallow"
                slotProps={{ primary: { sx: { fontWeight: 600 } }, secondary: { sx: { fontSize: 13, color: "#9CA3AF" } } }}
              />
              <Switch checked={dredgeWarnings} onChange={(e) => setDredge(e.target.checked)} />
            </ListItemButton>
          </List>
        </Box>
      </Box>

      <Box sx={{ width: "100%" }}>
        <Typography sx={{ fontSize: 12, fontWeight: 700, color: "#6B7280", letterSpacing: 0.5, pl: 0.5, pb: 1 }}>
          SUPPORT & INFO
        </Typography>
        <Box sx={sectionSx}>
          <List disablePadding>
            <ListItemButton
              sx={{ py: 1.5 }}
              onClick={() => {
                window.location.href = `mailto:${SUPPORT_EMAIL}`;
              }}
            >
              <ListItemIcon sx={{ minWidth: 48 }}>
                <IconBadge Icon={SupportAgentRoundedIcon} />
              </ListItemIcon>
              <ListItemText primary="Contact HQ" slotProps={{ primary: { sx: { fontWeight: 600 } } }} />
              <ChevronRightRoundedIcon sx={{ color: "grey.400" }} />
            </ListItemButton>
            <Divider />
            <ListItemButton sx={{ py: 1.5 }} disableRipple>
              <ListItemIcon sx={{ minWidth: 48 }}>
                <IconBadge Icon={InfoOutlinedIcon} />
              </ListItemIcon>
              <ListItemText primary="App Version" slotProps={{ primary: { sx: { fontWeight: 600 } } }} />
              <Typography sx={{ color: "grey.500", fontSize: 14 }}>v0.0.1</Typography>
            </ListItemButton>
          </List>
        </Box>
      </Box>

      <Box
        onClick={handleLogout}
        sx={{
          width: "100%",
          height: 54,
          borderRadius: "12px",
          border: "1px solid #E5E7EB",
          bgcolor: "#FFFFFF",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          cursor: "pointer",
          boxShadow: "0 2px 4px rgba(0,0,0,0.05)",
        }}
      >
        <Typography sx={{ color: "#DC2626", fontSize: 16, fontWeight: 700 }}>Log Out</Typography>
      </Box>
    </Box>
  );
}
