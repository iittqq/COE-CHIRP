import { useEffect, useRef, useState, type ChangeEvent } from "react";
import {
  Box,
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  List,
  ListItemButton,
  ListItemText,
  TextField,
  Typography,
} from "@mui/material";
import PlayArrowRoundedIcon from "@mui/icons-material/PlayArrowRounded";
import CloudUploadRoundedIcon from "@mui/icons-material/CloudUploadRounded";
import CloudOffRoundedIcon from "@mui/icons-material/CloudOffRounded";
import SensorsOffRoundedIcon from "@mui/icons-material/SensorsOffRounded";
import LocationOnRoundedIcon from "@mui/icons-material/LocationOnRounded";
import WeatherGraph from "../components/WeatherGraph";
import SystemStatusCard, { type SystemStatus } from "../components/SystemStatusCard";
import { WebSocketService } from "../utils/websocketController";
import { fetchSonars, sonarsChanged, type Sonar } from "../utils/sonarRepository";
import { loadSonarAlertsEnabled } from "../utils/alertPrefs";
import { deriveFolderName, importScanZip } from "../utils/importScan";
import { findScanByFolderName, type ScanData } from "../utils/scanRepo";
import { useSnackbar } from "../notifications";
import {
  defaultWeatherLocation,
  fetchWeather,
  loadSavedWeatherLocation,
  saveWeatherLocation,
  searchWeatherLocations,
  type Weather,
  type WeatherLocation,
} from "../utils/weather";

const DEVICE_ID = "controllerFlutter";
const PING_TIMEOUT_MS = 15_000;

const METRICS = [
  "Temperature (°F)",
  "Rain (in)",
  "Showers (in)",
  "Cloud Cover (%)",
  "Sunshine (s)",
] as const;

function metricData(metric: (typeof METRICS)[number], weather: Weather): number[] {
  switch (metric) {
    case "Temperature (°F)":
      return weather.temperatures;
    case "Rain (in)":
      return weather.rainChances;
    case "Showers (in)":
      return weather.showerChances;
    case "Cloud Cover (%)":
      return weather.cloudCovers;
    case "Sunshine (s)":
      return weather.sunshineDuration;
    default:
      return [];
  }
}

interface HomeProps {
  onNavScan: () => void;
  onScanImported: () => void;
}

export default function Home({ onNavScan, onScanImported }: HomeProps) {
  const { notify } = useSnackbar();

  const [weatherLocation, setWeatherLocation] = useState<WeatherLocation>(
    defaultWeatherLocation,
  );
  const [weather, setWeather] = useState<Weather | null>(null);
  const [weatherLoading, setWeatherLoading] = useState(true);
  const [weatherError, setWeatherError] = useState(false);
  const [selectedMetric, setSelectedMetric] =
    useState<(typeof METRICS)[number]>("Temperature (°F)");
  const [selectedData, setSelectedData] = useState<number[]>([]);

  const [connectionStatus, setConnectionStatus] = useState<
    "disconnected" | "connecting" | "connected"
  >("disconnected");
  const [registeredSonars, setRegisteredSonars] = useState<Sonar[]>([]);
  const [sonarLoading, setSonarLoading] = useState(true);
  const [sonarAlertsEnabled, setSonarAlertsEnabled] = useState(true);
  const [sonarStatuses, setSonarStatuses] = useState<Record<string, SystemStatus>>({});

  const [locationDialogOpen, setLocationDialogOpen] = useState(false);
  const [locationQuery, setLocationQuery] = useState("");
  const [locationResults, setLocationResults] = useState<WeatherLocation[]>([]);
  const [locationSearching, setLocationSearching] = useState(false);
  const [pendingImport, setPendingImport] = useState<{ file: File; existing: ScanData } | null>(null);

  const wsRef = useRef<WebSocketService | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pingTimeoutTimersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(
    new Map(),
  );
  const sonarAlertsEnabledRef = useRef(sonarAlertsEnabled);
  sonarAlertsEnabledRef.current = sonarAlertsEnabled;
  const registeredSonarsRef = useRef<Sonar[]>([]);
  registeredSonarsRef.current = registeredSonars;
  const connectionStatusRef = useRef(connectionStatus);
  connectionStatusRef.current = connectionStatus;
  const importInputRef = useRef<HTMLInputElement>(null);
  const sonarStatusesRef = useRef(sonarStatuses);
  sonarStatusesRef.current = sonarStatuses;

  const sendPingFor = (sonarId: string) => {
    if (connectionStatusRef.current !== "connected") return;
    const wasOnline = sonarStatusesRef.current[sonarId] === "online";

    setSonarStatuses((prev) => ({ ...prev, [sonarId]: "connecting" }));

    const existingTimer = pingTimeoutTimersRef.current.get(sonarId);
    if (existingTimer) clearTimeout(existingTimer);
    const timer = setTimeout(() => {
      setSonarStatuses((prev) => ({ ...prev, [sonarId]: "offline" }));
      if (wasOnline && sonarAlertsEnabledRef.current) {
        const match = registeredSonarsRef.current.find((s) => s.sonar_id === sonarId);
        notify(`${match?.name ?? sonarId} went offline`);
      }
    }, PING_TIMEOUT_MS);
    pingTimeoutTimersRef.current.set(sonarId, timer);

    wsRef.current?.sendCommand({
      action: "checkOnline",
      deviceId: sonarId,
      sender: DEVICE_ID,
    });
  };

  const pingAllSonars = () => {
    for (const sonar of registeredSonarsRef.current) sendPingFor(sonar.sonar_id);
  };

  const handleIncomingMessage = (data: Record<string, unknown>) => {
    let responseData: Record<string, unknown>;
    if (typeof data.body === "string") {
      try {
        responseData = JSON.parse(data.body);
      } catch {
        return;
      }
    } else {
      responseData = data;
    }

    const status = responseData.status as string | undefined;
    const sonarId = responseData.deviceId as string | undefined;
    if (!sonarId || status !== "online") return;

    const timer = pingTimeoutTimersRef.current.get(sonarId);
    if (timer) {
      clearTimeout(timer);
      pingTimeoutTimersRef.current.delete(sonarId);
    }
    setSonarStatuses((prev) => ({ ...prev, [sonarId]: "online" }));
  };

  const handleDisconnection = () => {
    const anyWasOnline = Object.values(sonarStatusesRef.current).some(
      (s) => s === "online",
    );
    setConnectionStatus("disconnected");
    for (const timer of pingTimeoutTimersRef.current.values()) clearTimeout(timer);
    pingTimeoutTimersRef.current.clear();
    setSonarStatuses((prev) => {
      const next: Record<string, SystemStatus> = {};
      for (const key of Object.keys(prev)) next[key] = "offline";
      return next;
    });

    if (anyWasOnline && sonarAlertsEnabledRef.current) {
      notify("Connection lost. Sonars marked offline.");
    }

    if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
    reconnectTimerRef.current = setTimeout(() => attemptConnection(), 5000);
  };

  const attemptConnection = () => {
    setConnectionStatus("connecting");
    const ws = wsRef.current;
    if (!ws) return;

    ws.connect()
      .then(() => {
        setConnectionStatus("connected");
        ws.onMessage(handleIncomingMessage);
        ws.onDisconnect(handleDisconnection);
        pingAllSonars();
      })
      .catch(() => handleDisconnection());
  };

  const loadSonars = async () => {
    setSonarLoading(true);
    try {
      const sonars = await fetchSonars();
      setRegisteredSonars(sonars);
      registeredSonarsRef.current = sonars;
      pingAllSonars();
    } catch {
      setRegisteredSonars([]);
    } finally {
      setSonarLoading(false);
    }
  };

  const loadWeather = async (location: WeatherLocation) => {
    setWeatherLoading(true);
    setWeatherError(false);
    try {
      const data = await fetchWeather(location);
      setWeather(data);
      setSelectedData((prev) => (prev.length === 0 ? data.temperatures : prev));
    } catch {
      setWeatherError(true);
    } finally {
      setWeatherLoading(false);
    }
  };

  useEffect(() => {
    const savedLocation = loadSavedWeatherLocation();
    setWeatherLocation(savedLocation);
    loadWeather(savedLocation);

    const ws = new WebSocketService(DEVICE_ID);
    wsRef.current = ws;
    attemptConnection();

    loadSonars();
    const unsubscribe = sonarsChanged.subscribe(loadSonars);
    setSonarAlertsEnabled(loadSonarAlertsEnabled());

    // Capture the Map itself (not re-read `.current` inside the cleanup
    // closure below) - it's the same object for the component's whole
    // lifetime, only ever mutated via .set()/.delete(), so this still sees
    // every timer scheduled between mount and unmount.
    const pingTimeoutTimers = pingTimeoutTimersRef.current;

    return () => {
      unsubscribe();
      if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
      for (const timer of pingTimeoutTimers.values()) clearTimeout(timer);
      ws.disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const updateGraph = (metric: (typeof METRICS)[number]) => {
    if (!weather) return;
    setSelectedMetric(metric);
    setSelectedData(metricData(metric, weather));
  };

  const searchLocations = async () => {
    const query = locationQuery.trim();
    if (!query) return;
    setLocationSearching(true);
    try {
      setLocationResults(await searchWeatherLocations(query));
    } catch {
      notify("Search failed. Please try again.", { severity: "error" });
    } finally {
      setLocationSearching(false);
    }
  };

  const selectLocation = (location: WeatherLocation) => {
    saveWeatherLocation(location);
    setWeatherLocation(location);
    setSelectedData([]);
    setLocationDialogOpen(false);
    loadWeather(location);
  };

  const finishImport = async (file: File, overwriteId?: string) => {
    try {
      await importScanZip(file, { overwriteId });
      notify("Scan imported successfully!", { severity: "success" });
      onScanImported();
    } catch (err) {
      notify(`Import failed: ${(err as Error).message}`, { severity: "error" });
    }
  };

  const handleImportFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    const existing = await findScanByFolderName(deriveFolderName(file.name));
    if (existing) {
      setPendingImport({ file, existing });
      return;
    }
    await finishImport(file);
  };

  const confirmOverwriteImport = async () => {
    if (!pendingImport) return;
    const { file, existing } = pendingImport;
    setPendingImport(null);
    await finishImport(file, existing.id);
  };

  return (
    <Box sx={{ p: 2, maxWidth: 1280, mx: "auto" }}>
      {sonarLoading ? (
        <Box sx={{ display: "flex", justifyContent: "center", py: 2 }}>
          <CircularProgress />
        </Box>
      ) : registeredSonars.length === 0 ? (
        <Box
          sx={{
            width: "100%",
            p: 2.5,
            borderRadius: "20px",
            border: "1px solid #F3F4F6",
            boxShadow: "0 4px 12px rgba(0,0,0,0.04)",
            display: "flex",
            alignItems: "center",
            gap: 1.75,
          }}
        >
          <SensorsOffRoundedIcon sx={{ color: "#9CA3AF", fontSize: 28 }} />
          <Typography sx={{ color: "text.secondary", fontSize: 14 }}>
            No sonars registered. Add one in Settings.
          </Typography>
        </Box>
      ) : (
        <Box>
          <Typography sx={{ fontSize: 16, fontWeight: 600, color: "text.secondary", pl: 0.5, pb: 1.5 }}>
            System Status
          </Typography>
          <Box sx={{ display: "flex", flexWrap: "wrap", gap: 1.5 }}>
            {registeredSonars.map((sonar) => (
              <Box key={sonar.sonar_id} sx={{ flex: "1 1 320px", minWidth: 280 }}>
                <SystemStatusCard
                  status={sonarStatuses[sonar.sonar_id] ?? "connecting"}
                  siteName={sonar.name || sonar.sonar_id}
                  onSendPing={() => sendPingFor(sonar.sonar_id)}
                  showHeader={false}
                />
              </Box>
            ))}
          </Box>
        </Box>
      )}

      <Box sx={{ display: "flex", justifyContent: "space-between", alignItems: "center", mt: 1.25, mb: 1, px: 0.5 }}>
        <Typography sx={{ color: "text.secondary", fontWeight: 700, fontSize: 12, letterSpacing: 1.2 }}>
          WEATHER CONDITIONS
        </Typography>
        <Box
          onClick={() => setLocationDialogOpen(true)}
          sx={{ display: "flex", alignItems: "center", gap: 0.5, cursor: "pointer" }}
        >
          <LocationOnRoundedIcon sx={{ fontSize: 14, color: "primary.main" }} />
          <Typography sx={{ color: "primary.main", fontWeight: 600, fontSize: 12 }}>
            {weatherLocation.name}
          </Typography>
        </Box>
      </Box>

      {weatherLoading ? (
        <Box sx={{ height: 260, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <CircularProgress />
        </Box>
      ) : weatherError ? (
        <Box sx={{ height: 260, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 1.5 }}>
          <CloudOffRoundedIcon sx={{ fontSize: 40, color: "#D1D5DB" }} />
          <Typography sx={{ color: "text.secondary" }}>Couldn&apos;t load weather data.</Typography>
          <Button variant="contained" onClick={() => loadWeather(weatherLocation)}>
            Retry
          </Button>
        </Box>
      ) : weather ? (
        <Box>
          <Box sx={{ height: 260, width: "100%" }}>
            <WeatherGraph xValues={selectedData} times={weather.times} yLabel={selectedMetric} />
          </Box>
          <Box sx={{ display: "flex", gap: 1, overflowX: "auto", py: 1 }}>
            {METRICS.map((metric) => {
              const isSelected = metric === selectedMetric;
              return (
                <Button
                  key={metric}
                  onClick={() => updateGraph(metric)}
                  variant={isSelected ? "contained" : "outlined"}
                  sx={{ whiteSpace: "nowrap", flexShrink: 0 }}
                >
                  {metric}
                </Button>
              );
            })}
          </Box>
        </Box>
      ) : null}

      <Box sx={{ mt: 1.5 }}>
        <Button
          fullWidth
          variant="contained"
          size="large"
          startIcon={<PlayArrowRoundedIcon />}
          onClick={onNavScan}
          sx={{ height: 60, fontSize: 18 }}
        >
          Start New Scan
        </Button>
      </Box>

      <Typography sx={{ color: "text.secondary", fontWeight: 700, fontSize: 12, letterSpacing: 1.2, mt: 1.5, mb: 1, px: 0.5 }}>
        UPLOAD SCAN
      </Typography>
      <Button
        fullWidth
        variant="outlined"
        size="large"
        startIcon={<CloudUploadRoundedIcon />}
        onClick={() => importInputRef.current?.click()}
        sx={{ height: 60, fontSize: 18 }}
      >
        Upload New Scan
      </Button>
      <input
        ref={importInputRef}
        type="file"
        accept=".zip"
        hidden
        onChange={handleImportFile}
      />

      <Dialog
        open={locationDialogOpen}
        onClose={() => setLocationDialogOpen(false)}
        fullWidth
        maxWidth="xs"
      >
        <DialogTitle sx={{ fontWeight: 700 }}>Set Weather Location</DialogTitle>
        <DialogContent>
          <Box sx={{ display: "flex", gap: 1, mt: 0.5 }}>
            <TextField
              fullWidth
              autoFocus
              placeholder="City name (e.g. Port Arthur, TX)"
              value={locationQuery}
              onChange={(e) => setLocationQuery(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && searchLocations()}
            />
            <Button variant="contained" onClick={searchLocations} disabled={locationSearching}>
              Search
            </Button>
          </Box>
          {locationSearching && (
            <Box sx={{ display: "flex", justifyContent: "center", py: 2 }}>
              <CircularProgress size={24} />
            </Box>
          )}
          {!locationSearching && locationResults.length === 0 && (
            <Typography sx={{ color: "text.secondary", mt: 2 }}>
              Search for a city to set the weather location.
            </Typography>
          )}
          <List sx={{ overflowY: "auto" }}>
            {locationResults.map((result, index) => (
              <ListItemButton key={index} onClick={() => selectLocation(result)}>
                <LocationOnRoundedIcon sx={{ mr: 1.5, color: "text.secondary" }} />
                <ListItemText
                  primary={result.name}
                  secondary={`${result.latitude.toFixed(2)}, ${result.longitude.toFixed(2)}`}
                />
              </ListItemButton>
            ))}
          </List>
        </DialogContent>
      </Dialog>

      <Dialog open={!!pendingImport} onClose={() => setPendingImport(null)} fullWidth maxWidth="xs">
        <DialogTitle sx={{ fontWeight: 700 }}>Scan already exists</DialogTitle>
        <DialogContent>
          <Typography>
            A scan named &quot;{pendingImport?.existing.title}&quot; already exists. Importing
            will overwrite it and its data cannot be recovered.
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPendingImport(null)}>Cancel</Button>
          <Button color="error" onClick={confirmOverwriteImport}>
            Overwrite
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
