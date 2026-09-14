import { useState } from "react";
import {
  AppBar,
  Box,
  CssBaseline,
  IconButton,
  ThemeProvider,
  Toolbar,
  Typography,
  useMediaQuery,
} from "@mui/material";
import { theme } from "./theme";
import { SnackbarProvider } from "./notifications";
import SideNavBar, { SIDEBAR_WIDTH } from "./components/SideNavBar";
import menuIcon from "./assets/menu.svg";
import Home from "./screens/Home";
import Scan from "./screens/Scan";
import History from "./screens/History";
import Settings from "./screens/Settings";
import ScanAnalysis from "./screens/ScanAnalysis";
import CompareScans from "./screens/CompareScans";
import SonarSensors from "./screens/SonarSensors";
import IspData from "./screens/IspData";
import IspAnalysis from "./screens/IspAnalysis";
import AuthScreen from "./screens/Auth";
import type { ScanData } from "./utils/scanRepo";
import type { IspRecord } from "./utils/ispRepo";
import { getSession, clearSession, type AccountSession } from "./utils/auth";
import { migrateLegacySonarsIfNeeded } from "./utils/sonarRepository";

type DrillInRoute =
  | { screen: "scanAnalysis"; scan: ScanData }
  | { screen: "compareScans"; scans: ScanData[] }
  | { screen: "sonarSensors" }
  | { screen: "ispAnalysis"; record: IspRecord };

const TAB_TITLES = ["Home", "Scans", "Sonar Data", "ISP Data", "Settings"];
const CONTENT_MAX_WIDTH = 1400;

function AppShell({ onLogout }: { onLogout: () => void }) {
  // Mirrors main.dart's IndexedStack: all four tabs stay mounted for the
  // whole session (hidden via CSS rather than unmounted) so the Home/Scan
  // WebSocket connections, ping timers, and weather fetch survive tab
  // switches instead of tearing down and reconnecting every time.
  const [activeTab, setActiveTab] = useState(0);
  // On mobile the sidebar overlays the content (fixed + slide-in) instead of
  // pushing/shrinking it, since there's no spare width to give up — so it
  // should start closed there, unlike the desktop permanent rail.
  const [navOpen, setNavOpen] = useState(() => window.innerWidth >= 600);
  const isMobile = useMediaQuery(theme.breakpoints.down("sm"), { noSsr: true });

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
    <Box sx={{ display: "flex", height: "100dvh", width: "100%", position: "relative" }}>
      {isMobile ? (
        <>
          {navOpen && (
            <Box
              onClick={() => setNavOpen(false)}
              sx={{ position: "fixed", inset: 0, bgcolor: "rgba(0,0,0,0.4)", zIndex: 1200 }}
            />
          )}
          <Box
            sx={{
              position: "fixed",
              top: 0,
              left: 0,
              height: "100%",
              zIndex: 1300,
              boxShadow: navOpen ? "0 0 16px rgba(0,0,0,0.2)" : "none",
              transform: navOpen ? "translateX(0)" : `translateX(-${SIDEBAR_WIDTH}px)`,
              transition: "transform 0.2s ease",
            }}
          >
            <SideNavBar
              currentIndex={activeTab}
              onChange={selectTab}
              open
              onClose={() => setNavOpen(false)}
            />
          </Box>
        </>
      ) : (
        <SideNavBar currentIndex={activeTab} onChange={selectTab} open={navOpen} />
      )}
      <Box sx={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", height: "100%" }}>
        {route?.screen === "scanAnalysis" ? (
          <ScanAnalysis
            scan={route.scan}
            onBack={popRoute}
            onToggleNav={() => setNavOpen((o) => !o)}
          />
        ) : route?.screen === "compareScans" ? (
          <CompareScans
            scans={route.scans}
            onBack={popRoute}
            onToggleNav={() => setNavOpen((o) => !o)}
          />
        ) : route?.screen === "sonarSensors" ? (
          <SonarSensors onBack={popRoute} onToggleNav={() => setNavOpen((o) => !o)} />
        ) : route?.screen === "ispAnalysis" ? (
          <IspAnalysis
            record={route.record}
            onBack={popRoute}
            onToggleNav={() => setNavOpen((o) => !o)}
          />
        ) : (
          <>
            <AppBar position="static" sx={{ position: "relative", zIndex: 1250 }}>
              <Toolbar>
                <IconButton
                  onClick={() => setNavOpen((o) => !o)}
                  sx={{ mr: 1.5 }}
                  aria-label="Toggle navigation"
                >
                  <Box
                    component="img"
                    src={menuIcon}
                    alt=""
                    sx={{ width: 20, height: 20 }}
                  />
                </IconButton>
                <Typography variant="h6" sx={{ fontWeight: 700 }}>
                  {TAB_TITLES[activeTab]}
                </Typography>
              </Toolbar>
            </AppBar>
            <Box
              sx={{
                flex: 1,
                overflow: "auto",
                bgcolor: activeTab === 2 || activeTab === 3 ? "#F5F6FA" : "#FFFFFF",
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
                  <IspData onOpenRecord={(record) => setRoute({ screen: "ispAnalysis", record })} />
                </Box>
                <Box sx={{ display: activeTab === 4 ? "block" : "none", height: "100%" }}>
                  <Settings
                    onOpenSonarSensors={() => setRoute({ screen: "sonarSensors" })}
                    onLogout={onLogout}
                  />
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
  // Presence of a cached session gates the whole app shell: logged out,
  // renders the auth screen only; logged in, mounts AppShell (and with it
  // the WebSocket connections, ping timers, and weather fetch on Home).
  const [session, setSessionState] = useState<AccountSession | null>(() => getSession());

  const handleAuthenticated = (nextSession: AccountSession) => {
    setSessionState(nextSession);
    // Fire-and-forget: don't block entry into the app on this finishing.
    void migrateLegacySonarsIfNeeded();
  };

  const handleLogout = () => {
    clearSession();
    setSessionState(null);
  };

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <SnackbarProvider>
        {session ? (
          <AppShell onLogout={handleLogout} />
        ) : (
          <AuthScreen onAuthenticated={handleAuthenticated} />
        )}
      </SnackbarProvider>
    </ThemeProvider>
  );
}
