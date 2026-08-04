import { useState } from "react";
import { AppBar, Box, CssBaseline, ThemeProvider, Toolbar, Typography } from "@mui/material";
import { theme } from "./theme";
import { SnackbarProvider } from "./notifications";
import SideNavBar from "./components/SideNavBar";
import Home from "./screens/Home";
import Scan from "./screens/Scan";
import History from "./screens/History";
import Settings from "./screens/Settings";
import ScanAnalysis from "./screens/ScanAnalysis";
import CompareScans from "./screens/CompareScans";
import SonarSensors from "./screens/SonarSensors";
import type { ScanData } from "./utils/scanRepo";

type DrillInRoute =
  | { screen: "scanAnalysis"; scan: ScanData }
  | { screen: "compareScans"; scans: ScanData[] }
  | { screen: "sonarSensors" };

const TAB_TITLES = ["Home", "Scans", "History", "Settings"];
const CONTENT_MAX_WIDTH = 1100;

function AppShell() {
  // Mirrors main.dart's IndexedStack: all four tabs stay mounted for the
  // whole session (hidden via CSS rather than unmounted) so the Home/Scan
  // WebSocket connections, ping timers, and weather fetch survive tab
  // switches instead of tearing down and reconnecting every time.
  const [activeTab, setActiveTab] = useState(0);

  // Drill-in routes (History -> ScanAnalysis/CompareScans, Settings ->
  // SonarSensors) mirror Navigator.push, but only replace the content pane —
  // the sidebar stays put, matching a desktop app's persistent nav rail
  // rather than a mobile full-screen page push.
  const [route, setRoute] = useState<DrillInRoute | null>(null);
  const popRoute = () => setRoute(null);

  const selectTab = (index: number) => {
    setRoute(null);
    setActiveTab(index);
  };

  return (
    <Box sx={{ display: "flex", height: "100dvh", width: "100%" }}>
      <SideNavBar currentIndex={activeTab} onChange={selectTab} />
      <Box sx={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", height: "100%" }}>
        {route?.screen === "scanAnalysis" ? (
          <ScanAnalysis scan={route.scan} onBack={popRoute} />
        ) : route?.screen === "compareScans" ? (
          <CompareScans scans={route.scans} onBack={popRoute} />
        ) : route?.screen === "sonarSensors" ? (
          <SonarSensors onBack={popRoute} />
        ) : (
          <>
            <AppBar position="static">
              <Toolbar>
                <Typography variant="h6" sx={{ fontWeight: 700 }}>
                  {TAB_TITLES[activeTab]}
                </Typography>
              </Toolbar>
            </AppBar>
            <Box
              sx={{
                flex: 1,
                overflow: "auto",
                bgcolor: activeTab === 2 ? "#F5F6FA" : "#FFFFFF",
              }}
            >
              <Box sx={{ maxWidth: CONTENT_MAX_WIDTH, mx: "auto", height: "100%" }}>
                <Box sx={{ display: activeTab === 0 ? "block" : "none", height: "100%" }}>
                  <Home onNavScan={() => selectTab(1)} onScanImported={() => selectTab(2)} />
                </Box>
                <Box sx={{ display: activeTab === 1 ? "block" : "none", height: "100%" }}>
                  <Scan />
                </Box>
                <Box sx={{ display: activeTab === 2 ? "block" : "none", height: "100%" }}>
                  <History
                    onOpenScan={(scan) => setRoute({ screen: "scanAnalysis", scan })}
                    onCompareScans={(scans) => setRoute({ screen: "compareScans", scans })}
                  />
                </Box>
                <Box sx={{ display: activeTab === 3 ? "block" : "none", height: "100%" }}>
                  <Settings onOpenSonarSensors={() => setRoute({ screen: "sonarSensors" })} />
                </Box>
              </Box>
            </Box>
          </>
        )}
      </Box>
    </Box>
  );
}

export default function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <SnackbarProvider>
        <AppShell />
      </SnackbarProvider>
    </ThemeProvider>
  );
}
