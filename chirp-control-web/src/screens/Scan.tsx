import { useEffect, useRef, useState } from "react";
import {
  Box,
  Button,
  Chip,
  CircularProgress,
  Typography,
} from "@mui/material";
import PlayArrowRoundedIcon from "@mui/icons-material/PlayArrowRounded";
import HourglassFullRoundedIcon from "@mui/icons-material/HourglassFullRounded";
import ReportProblemOutlinedIcon from "@mui/icons-material/ReportProblemOutlined";
import WarningAmberRoundedIcon from "@mui/icons-material/WarningAmberRounded";
import ScanDurationInput from "../components/ScanDurationInput";
import SystemStatusCard, { type SystemStatus } from "../components/SystemStatusCard";
import { WebSocketService } from "../utils/websocketController";
import { fetchSonars, sonarsChanged, type Sonar } from "../utils/sonarRepository";
import { loadDredgeWarningsEnabled, loadSonarAlertsEnabled } from "../utils/alertPrefs";
import { allNodes, decodeZippedXml, parseXml, serializeNode } from "../utils/xmlAutomation";
import { useSnackbar } from "../notifications";
import radarSonarSvg from "../assets/radar-sonar.svg";

const DEVICE_ID = "controllerFlutter";
const AUTOMATION_IN_PROGRESS_KEY = "automation_in_progress";
const AUTOMATION_SONAR_NAME_KEY = "automation_in_progress_sonar_name";
const AUTOMATION_SONAR_ID_KEY = "automation_in_progress_sonar_id";
const STALL_THRESHOLD_MS = 45_000;

type ConnectionStatus = "disconnected" | "connecting" | "connected";
type AutoState =
  | "idle"
  | "switchingOn"
  | "adjustingShade"
  | "performingScan"
  | "uploadingScan"
  | "switchingOff";

// Mirrors the Dart component's plain instance fields: values read inside
// WebSocket/timer callbacks need a ref (closures over React state go stale),
// while the UI also needs to re-render on change — this keeps both in sync
// with one setter instead of duplicating every value by hand.
function useRefState<T>(initial: T) {
  const [state, setState] = useState(initial);
  const ref = useRef(initial);
  const set = (value: T) => {
    ref.current = value;
    setState(value);
  };
  return [state, ref, set] as const;
}

function formatDuration(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

export default function Scan() {
  const { notify } = useSnackbar();

  const [currentState, currentStateRef, setCurrentState] = useRefState<AutoState>("idle");
  const [automationRunning, automationRunningRef, setAutomationRunning] = useRefState(false);
  const [selectedSonar, selectedSonarRef, setSelectedSonar] = useRefState<Sonar | null>(null);
  const [connectionStatus, connectionStatusRef, setConnectionStatus] =
    useRefState<ConnectionStatus>("disconnected");
  const [activeSiteName, , setActiveSiteName] = useRefState("");
  const [initialConnectionComplete, , setInitialConnectionComplete] = useRefState(false);
  const [readyToFinishScan, , setReadyToFinishScan] = useRefState(false);
  const [stalled, , setStalled] = useRefState(false);
  const [resumedFromInterruption, , setResumedFromInterruption] = useRefState(false);
  const [interruptedSonarName, , setInterruptedSonarName] = useRefState<string | null>(null);
  const [, interruptedSonarIdRef, setInterruptedSonarId] = useRefState<string | null>(null);
  const [forcingDevicesOff, , setForcingDevicesOff] = useRefState(false);
  const [, dredgeWarningsEnabledRef, setDredgeWarningsEnabled] = useRefState(true);
  const [, sonarAlertsEnabledRef, setSonarAlertsEnabled] = useRefState(true);
  const [registeredSonars, , setRegisteredSonars] = useRefState<Sonar[]>([]);
  const [sonarLoading, , setSonarLoading] = useRefState(true);
  const [remainingSeconds, remainingSecondsRef, setRemainingSeconds] = useRefState(0);
  const [sessionSeconds, , setSessionSeconds] = useRefState(0);
  const [, durationSecondsRef, setDurationSeconds] = useRefState(0);
  const [statusCardKey, , setStatusCardKey] = useRefState(0);
  const [, isSyncedRef, setIsSynced] = useRefState(false);

  const wsRef = useRef<WebSocketService | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const automationTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const stallWatchdogRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const cancelRequestedRef = useRef(false);
  const watchdogSuspendedRef = useRef(false);
  const lastProgressAtRef = useRef<number | null>(null);
  const exportedCsvRef = useRef(false);
  const isShadeSequenceRunningRef = useRef(false);
  const shallowWarningShownRef = useRef(false);
  const xmlUpdateResolverRef = useRef<((doc: Document) => void) | null>(null);

  const getSelectedDeviceId = () => selectedSonarRef.current?.sonar_id ?? "testAndroid";

  const markProgress = () => {
    lastProgressAtRef.current = Date.now();
    if (stalled) setStalled(false);
  };

  const suspendWatchdog = () => {
    watchdogSuspendedRef.current = true;
    if (stalled) setStalled(false);
  };

  const resumeWatchdog = () => {
    watchdogSuspendedRef.current = false;
    markProgress();
  };

  const startWatchdog = () => {
    cancelRequestedRef.current = false;
    watchdogSuspendedRef.current = false;
    lastProgressAtRef.current = Date.now();
    if (stallWatchdogRef.current) clearInterval(stallWatchdogRef.current);
    stallWatchdogRef.current = setInterval(() => {
      if (
        !automationRunningRef.current ||
        watchdogSuspendedRef.current ||
        lastProgressAtRef.current === null
      ) {
        return;
      }
      const elapsed = Date.now() - lastProgressAtRef.current;
      if (elapsed > STALL_THRESHOLD_MS) setStalled(true);
    }, 5000);
  };

  const stopWatchdog = () => {
    if (stallWatchdogRef.current) clearInterval(stallWatchdogRef.current);
    stallWatchdogRef.current = null;
  };

  const setAutomationInProgress = (
    value: boolean,
    sonarName?: string,
    sonarId?: string,
  ) => {
    if (value) {
      localStorage.setItem(AUTOMATION_IN_PROGRESS_KEY, "true");
      localStorage.setItem(AUTOMATION_SONAR_NAME_KEY, sonarName ?? "");
      localStorage.setItem(AUTOMATION_SONAR_ID_KEY, sonarId ?? "");
    } else {
      localStorage.removeItem(AUTOMATION_IN_PROGRESS_KEY);
      localStorage.removeItem(AUTOMATION_SONAR_NAME_KEY);
      localStorage.removeItem(AUTOMATION_SONAR_ID_KEY);
    }
  };

  const acknowledgeInterruption = () => {
    setResumedFromInterruption(false);
    setAutomationInProgress(false);
  };

  const notifyScanStarted = () => {
    if (!sonarAlertsEnabledRef.current) return;
    notify("Scan started.");
  };

  const notifyScanFinished = () => {
    if (!sonarAlertsEnabledRef.current) return;
    notify("Scan finished. Dredges can be found at maps.fishdeeper.com");
  };

  const launchTuya = () => {
    markProgress();
    wsRef.current?.sendCommand({
      action: "launch",
      package: "com.tuya.smart/com.thingclips.smart.hometab.activity.FamilyHomeActivity",
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const launchShades = () => {
    markProgress();
    wsRef.current?.sendCommand({
      action: "launch",
      package: "com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity",
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const launchFishDeeper = () => {
    markProgress();
    wsRef.current?.sendCommand({
      action: "launch",
      package: "eu.deeper.fishdeeper/eu.deeper.app.scan.live.MainScreenActivity",
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const closeApp = (packageName = "eu.deeper.fishdeeper") => {
    markProgress();
    wsRef.current?.sendCommand({
      action: "close",
      package: packageName,
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const clickByXmlNode = (node: Element) => {
    markProgress();
    wsRef.current?.sendCommand({
      action: "clickByXml",
      xmlNode: serializeNode(node),
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const dismissDeviceSelect = () => {
    markProgress();
    wsRef.current?.sendCommand({
      action: "clickByXml",
      xmlNode: '<node content-desc="CANCEL" />',
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const sendSwipeCommand = (node: Element, endX: number, endY: number) => {
    markProgress();
    wsRef.current?.sendCommand({
      action: "swipeByXml",
      xmlNode: serializeNode(node),
      endX,
      endY,
      duration: 1200,
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  const startTimer = (totalSeconds: number) => {
    setSessionSeconds(totalSeconds);
    setRemainingSeconds(totalSeconds);
    if (automationTimerRef.current) clearInterval(automationTimerRef.current);
    suspendWatchdog();

    automationTimerRef.current = setInterval(() => {
      if (remainingSecondsRef.current <= 0) {
        if (automationTimerRef.current) clearInterval(automationTimerRef.current);
        resumeWatchdog();
        setReadyToFinishScan(true);
        setCurrentState("uploadingScan");
        wsRef.current?.sendCommand({
          action: "wifi",
          state: "off",
          deviceId: getSelectedDeviceId(),
          sender: DEVICE_ID,
        });
      } else {
        setRemainingSeconds(remainingSecondsRef.current - 1);
      }
    }, 1000);
  };

  const checkDepthWarning = (xml: string) => {
    const isShallow = xml.toLowerCase().includes("too shallow");
    if (!isShallow) {
      shallowWarningShownRef.current = false;
      return;
    }
    if (shallowWarningShownRef.current) return;
    shallowWarningShownRef.current = true;
    if (!dredgeWarningsEnabledRef.current) return;
    notify("Depth warning: water is too shallow.", { severity: "warning" });
  };

  const findRiseHandle = (doc: Document, rawXML: string): Element | null => {
    if (rawXML.includes("Select Device Model") || rawXML.includes('content-desc="CANCEL"')) {
      dismissDeviceSelect();
      return null;
    }

    for (const node of allNodes(doc)) {
      const pkg = node.getAttribute("package") ?? "";
      if (pkg !== "com.wazombi.RISE") continue;

      const bounds = node.getAttribute("bounds") ?? "";
      const match = /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(bounds);
      if (!match) continue;

      const top = parseInt(match[2], 10);
      if (top < 300) continue;

      const parent = node.parentElement;
      if (parent?.getAttribute("resource-id") === "com.wazombi.RISE:id/window_control") {
        return node;
      }
    }
    return null;
  };

  const handleTuyaToggle = async (doc: Document, nextState: AutoState) => {
    const switchBtn = allNodes(doc).find(
      (n) => n.getAttribute("resource-id") === "com.tuya.smart:id/switchButton",
    );
    if (!switchBtn) return;

    clickByXmlNode(switchBtn);
    setCurrentState(nextState);

    if (nextState === "adjustingShade") {
      await sleep(20_000);
      if (cancelRequestedRef.current) return;
      launchShades();
      return;
    }

    await sleep(5000);
    if (cancelRequestedRef.current) return;
    closeApp("com.tuya.smart");

    await sleep(5000);
    if (cancelRequestedRef.current) return;
    closeApp("eu.deeper.fishdeeper");

    await sleep(5000);
    if (cancelRequestedRef.current) return;
    closeApp("com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity");

    await sleep(5000);
    if (cancelRequestedRef.current) return;
    wsRef.current?.sendCommand({
      action: "wifi",
      state: "on",
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });

    stopWatchdog();
    setAutomationInProgress(false);
    setAutomationRunning(false);
    setIsSynced(false);
    setCurrentState("idle");
    setStatusCardKey(statusCardKey + 1);
    notifyScanFinished();
  };

  const handleShadeToggle = async (doc: Document, rawXML: string) => {
    if (currentStateRef.current !== "adjustingShade" || isShadeSequenceRunningRef.current) {
      return;
    }
    isShadeSequenceRunningRef.current = true;

    try {
      const dragHandle = findRiseHandle(doc, rawXML);
      if (!dragHandle) {
        isShadeSequenceRunningRef.current = false;
        return;
      }

      sendSwipeCommand(dragHandle, 360, 1500);

      const waitForNextXml = new Promise<Document>((resolve) => {
        xmlUpdateResolverRef.current = resolve;
      });

      await sleep(11_000);
      if (cancelRequestedRef.current) return;

      const middleDoc = await Promise.race([
        waitForNextXml,
        sleep(12_000).then(() => doc),
      ]);
      xmlUpdateResolverRef.current = null;
      if (cancelRequestedRef.current) return;

      const movedHandle = findRiseHandle(middleDoc, rawXML);
      if (movedHandle) {
        sendSwipeCommand(movedHandle, 360, 600);
        await sleep(4000);
        if (cancelRequestedRef.current) return;

        setCurrentState("performingScan");
        isShadeSequenceRunningRef.current = false;
        launchFishDeeper();
      } else {
        isShadeSequenceRunningRef.current = false;
      }
    } catch {
      isShadeSequenceRunningRef.current = false;
    }
  };

  const handleFishDeeperAutomation = (doc: Document) => {
    const nodes = allNodes(doc);
    const findByText = (text: string) => nodes.find((n) => n.getAttribute("text") === text);
    const findByContentDesc = (desc: string) =>
      nodes.find((n) => n.getAttribute("content-desc") === desc);

    const updateNode = nodes.some((n) => (n.getAttribute("text") ?? "").includes("Update Available"));
    const laterNode = findByText("Later");
    const navigateNode = findByText("Navigate Without Map");
    const connectNode = findByText("Connect");
    const cancelNode = findByText("Cancel");
    const boatScanNode = findByContentDesc("Boat scan icon");

    if (updateNode && laterNode) {
      clickByXmlNode(laterNode);
      return;
    }
    if (navigateNode) {
      clickByXmlNode(navigateNode);
      return;
    }
    if (connectNode) {
      clickByXmlNode(connectNode);
      return;
    }
    if (cancelNode) {
      clickByXmlNode(cancelNode);
      return;
    }
    if (boatScanNode) {
      clickByXmlNode(boatScanNode);
      startTimer(durationSecondsRef.current);
      setInitialConnectionComplete(true);
      notifyScanStarted();
    }
  };

  const handleUploadScan = (doc: Document) => {
    if (isSyncedRef.current) {
      setCurrentState("switchingOff");
      launchTuya();
      return;
    }

    const nodes = allNodes(doc);
    const findByText = (text: string) =>
      nodes.find((n) => (n.getAttribute("text") ?? "").includes(text));
    const findByResId = (resId: string) =>
      nodes.find((n) => (n.getAttribute("resource-id") ?? "").includes(resId));
    const findByContentDesc = (desc: string) =>
      nodes.find((n) => (n.getAttribute("content-desc") ?? "").includes(desc));

    const saveToFilesNode = findByText("Files by Google");
    const exportCsvNode = findByText("Export scan data as CSV");
    const moreIconNode = findByContentDesc("moreIcon");
    const syncScansNode = findByResId("syncScansButton");
    const historyNode = findByText("History");
    const menuButtonNode = findByResId("menuButton");

    if (saveToFilesNode && !exportedCsvRef.current) {
      clickByXmlNode(saveToFilesNode);
      exportedCsvRef.current = true;
      return;
    }
    if (exportCsvNode && !exportedCsvRef.current) {
      clickByXmlNode(exportCsvNode);
      return;
    }
    if (moreIconNode && !exportedCsvRef.current) {
      clickByXmlNode(moreIconNode);
      return;
    }
    if (syncScansNode) {
      clickByXmlNode(syncScansNode);
      setIsSynced(true);
      return;
    }
    if (historyNode) {
      clickByXmlNode(historyNode);
      return;
    }
    if (menuButtonNode) {
      clickByXmlNode(menuButtonNode);
    }
  };

  const analyzeUiXml = (xml: string) => {
    if (cancelRequestedRef.current) return;
    checkDepthWarning(xml);
    const doc = parseXml(xml);

    xmlUpdateResolverRef.current?.(doc);

    switch (currentStateRef.current) {
      case "switchingOn":
        handleTuyaToggle(doc, "adjustingShade");
        break;
      case "adjustingShade":
        handleShadeToggle(doc, xml);
        break;
      case "performingScan":
        handleFishDeeperAutomation(doc);
        break;
      case "uploadingScan":
        handleUploadScan(doc);
        break;
      case "switchingOff":
        handleTuyaToggle(doc, "idle");
        break;
      default:
        break;
    }
  };

  const extractB64 = (data: Record<string, unknown>): string | null => {
    if (typeof data.ui_state_zip_b64 === "string") return data.ui_state_zip_b64;
    if (typeof data.body === "string") {
      try {
        const body = JSON.parse(data.body);
        if (typeof body.ui_state_zip_b64 === "string") return body.ui_state_zip_b64;
      } catch {
        /* ignore */
      }
    }
    return null;
  };

  const checkDataForSuccess = (data: Record<string, unknown>): boolean => {
    let responseData = data;
    if (typeof data.body === "string") {
      try {
        responseData = JSON.parse(data.body);
      } catch {
        return false;
      }
    }
    return responseData.status === "online" || responseData.action === "checkOnline";
  };

  const sendPing = () => {
    if (automationRunningRef.current || !selectedSonarRef.current) return;
    setConnectionStatus("connecting");
    wsRef.current?.sendCommand({
      action: "checkOnline",
      deviceId: getSelectedDeviceId(),
      sender: DEVICE_ID,
    });
  };

  const handleDisconnection = () => {
    setConnectionStatus("disconnected");
    if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
    reconnectTimerRef.current = setTimeout(() => attemptConnection(), 5000);
  };

  const attemptConnection = () => {
    setConnectionStatus("connecting");
    const ws = wsRef.current;
    if (!ws) return;

    ws.connect()
      .then(() => {
        ws.onMessage((data) => {
          if (automationRunningRef.current) {
            const b64 = extractB64(data);
            if (b64) analyzeUiXml(decodeZippedXml(b64));
            return;
          }
          if (connectionStatusRef.current === "connecting" && checkDataForSuccess(data)) {
            setConnectionStatus("connected");
            setStatusCardKey(statusCardKey + 1);
          }
        });
        ws.onDisconnect(handleDisconnection);
        sendPing();
      })
      .catch(() => handleDisconnection());
  };

  const sendAndAwaitUiDump = (
    command: Record<string, unknown>,
    timeoutMs = 30_000,
  ): Promise<Document | null> => {
    return new Promise((resolve) => {
      let settled = false;
      const unsubscribe = wsRef.current?.onMessage((data) => {
        if (settled) return;
        const b64 = extractB64(data);
        if (b64) {
          settled = true;
          unsubscribe?.();
          resolve(parseXml(decodeZippedXml(b64)));
        }
      });

      wsRef.current?.sendCommand(command);

      setTimeout(() => {
        if (settled) return;
        settled = true;
        unsubscribe?.();
        resolve(null);
      }, timeoutMs);
    });
  };

  const forceDevicesOff = async () => {
    const targetId = interruptedSonarIdRef.current ?? getSelectedDeviceId();
    setForcingDevicesOff(true);

    const ws = wsRef.current;
    if (!ws) {
      setForcingDevicesOff(false);
      notify("Couldn't reach the device. Check your connection and try again.");
      return;
    }

    try {
      await ws.connect();
    } catch {
      setForcingDevicesOff(false);
      notify("Couldn't reach the device. Check your connection and try again.");
      return;
    }

    ws.sendCommand({
      action: "close",
      package: "eu.deeper.fishdeeper",
      deviceId: targetId,
      sender: DEVICE_ID,
    });
    await sleep(1000);

    ws.sendCommand({
      action: "close",
      package: "com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity",
      deviceId: targetId,
      sender: DEVICE_ID,
    });
    await sleep(1000);

    ws.sendCommand({
      action: "wifi",
      state: "on",
      deviceId: targetId,
      sender: DEVICE_ID,
    });
    await sleep(1000);

    const tuyaDoc = await sendAndAwaitUiDump({
      action: "launch",
      package: "com.tuya.smart/com.thingclips.smart.hometab.activity.FamilyHomeActivity",
      deviceId: targetId,
      sender: DEVICE_ID,
    });

    let resultMessage =
      "Closed the scan/shade apps and restored WiFi. Opened Tuya — please verify the " +
      "smart plug is off yourself, since the app couldn't read its current state.";

    if (tuyaDoc) {
      const switchBtn = allNodes(tuyaDoc).find(
        (n) => n.getAttribute("resource-id") === "com.tuya.smart:id/switchButton",
      );

      if (switchBtn) {
        const checked = switchBtn.getAttribute("checked");
        if (checked === "false") {
          resultMessage =
            "Closed the scan/shade apps, restored WiFi, and confirmed the smart plug was already off.";
        } else if (checked === "true") {
          await sendAndAwaitUiDump({
            action: "clickByXml",
            xmlNode: serializeNode(switchBtn),
            deviceId: targetId,
            sender: DEVICE_ID,
          });
          resultMessage =
            "Closed the scan/shade apps, restored WiFi, and turned the smart plug off.";
        }
      }
    }

    setForcingDevicesOff(false);
    setResumedFromInterruption(false);
    setAutomationInProgress(false);
    notify(resultMessage, { durationMs: 6000 });
  };

  const startAutomation = () => {
    if (!selectedSonarRef.current) {
      notify("Please select a device.");
      return;
    }
    if (durationSecondsRef.current <= 0) {
      notify("Please set a duration greater than 0.");
      return;
    }

    setCurrentState("switchingOn");
    setAutomationRunning(true);
    setInitialConnectionComplete(false);
    setReadyToFinishScan(false);

    setAutomationInProgress(true, activeSiteName, selectedSonarRef.current.sonar_id);
    startWatchdog();
    launchTuya();
  };

  const cancelAutomation = () => {
    cancelRequestedRef.current = true;
    stopWatchdog();
    if (automationTimerRef.current) clearInterval(automationTimerRef.current);
    setAutomationInProgress(false);
    setAutomationRunning(false);
    setCurrentState("idle");
    setStalled(false);
    setReadyToFinishScan(false);
    setInitialConnectionComplete(false);
    notify(
      "Automation cancelled. The physical device may still be mid-action — check it manually.",
    );
  };

  const loadSonars = async () => {
    setSonarLoading(true);
    try {
      setRegisteredSonars(await fetchSonars());
    } catch {
      setRegisteredSonars([]);
    } finally {
      setSonarLoading(false);
    }
  };

  const selectSonar = (sonar: Sonar) => {
    setSelectedSonar(sonar);
    setActiveSiteName(sonar.name || sonar.sonar_id);
    setStatusCardKey(statusCardKey + 1);
    if (connectionStatusRef.current === "disconnected") {
      attemptConnection();
    } else {
      sendPing();
    }
  };

  useEffect(() => {
    const ws = new WebSocketService(DEVICE_ID);
    wsRef.current = ws;

    loadSonars();
    const unsubscribe = sonarsChanged.subscribe(loadSonars);

    const wasInProgress = localStorage.getItem(AUTOMATION_IN_PROGRESS_KEY) === "true";
    if (wasInProgress) {
      setResumedFromInterruption(true);
      setInterruptedSonarName(localStorage.getItem(AUTOMATION_SONAR_NAME_KEY));
      setInterruptedSonarId(localStorage.getItem(AUTOMATION_SONAR_ID_KEY));
    }

    setDredgeWarningsEnabled(loadDredgeWarningsEnabled());
    setSonarAlertsEnabled(loadSonarAlertsEnabled());

    return () => {
      unsubscribe();
      if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
      if (automationTimerRef.current) clearInterval(automationTimerRef.current);
      stopWatchdog();
      ws.disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const getCardStatus = (): SystemStatus => {
    if (connectionStatus === "connected") return "online";
    if (connectionStatus === "connecting") return "connecting";
    return "offline";
  };

  const getButtonLabel = (): string => {
    if (!automationRunning) return "Begin Scan";
    switch (currentState) {
      case "switchingOn":
        return "Powering On...";
      case "adjustingShade":
        return "Adjusting Shade...";
      case "performingScan":
        return "Scanning...";
      case "uploadingScan":
        return "Uploading Scan...";
      case "switchingOff":
        return "Finishing Up...";
      default:
        return "Begin Scan";
    }
  };

  const countdownColor =
    remainingSeconds <= 10 && remainingSeconds > 0
      ? "#F97316"
      : remainingSeconds <= 0
        ? "#EF4444"
        : "primary.main";

  return (
    <Box
      sx={{
        p: 2,
        display: "flex",
        flexDirection: "column",
        gap: 2.5,
        minHeight: "100%",
        maxWidth: 1080,
        mx: "auto",
        width: "100%",
      }}
    >
      <Box sx={{ display: "flex", alignItems: "center", gap: 1.5 }}>
        <Box component="img" src={radarSonarSvg} alt="" sx={{ width: 48, height: 48 }} />
        <Typography variant="h5" sx={{ fontWeight: 800 }}>
          Scan
        </Typography>
      </Box>

      {resumedFromInterruption && (
        <Box
          sx={{
            p: 1.5,
            borderRadius: "12px",
            bgcolor: "#FEF2F2",
            border: "1px solid #FECACA",
          }}
        >
          <Box sx={{ display: "flex", alignItems: "center", gap: 1.25 }}>
            <ReportProblemOutlinedIcon sx={{ color: "#991B1B" }} />
            <Typography sx={{ fontWeight: 700, flex: 1 }}>
              Automation didn&apos;t finish cleanly
            </Typography>
          </Box>
          <Typography sx={{ color: "#7F1D1D", fontSize: 13, mt: 0.75 }}>
            A previous scan automation
            {interruptedSonarName ? ` on "${interruptedSonarName}"` : ""} was interrupted
            (app closed, crashed, or lost power) before it finished. Physical devices — power
            switch, shades, sonar app — may be left in an unknown state.
          </Typography>
          <Box sx={{ display: "flex", gap: 1, mt: 1.5 }}>
            <Button
              fullWidth
              variant="outlined"
              color="error"
              onClick={forceDevicesOff}
              disabled={forcingDevicesOff}
            >
              {forcingDevicesOff ? <CircularProgress size={18} color="error" /> : "Force devices off"}
            </Button>
            <Button
              fullWidth
              variant="text"
              onClick={acknowledgeInterruption}
              disabled={forcingDevicesOff}
            >
              I&apos;ve checked it
            </Button>
          </Box>
          <Typography sx={{ color: "#B91C1C", fontSize: 11, mt: 1 }}>
            "Force devices off" closes the scan/shade apps and restores WiFi, then opens Tuya
            so you can verify the power switch yourself — it can&apos;t safely guess whether
            the plug is on or off.
          </Typography>
        </Box>
      )}

      <Box sx={{ display: "flex", flexDirection: { xs: "column", md: "row" }, gap: 3 }}>
        <Box sx={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2.5 }}>
          <Box>
            <Typography sx={{ fontWeight: 700, mb: 1 }}>Select Sonar</Typography>
            {sonarLoading ? (
              <Box sx={{ display: "flex", justifyContent: "center" }}>
                <CircularProgress size={24} />
              </Box>
            ) : registeredSonars.length === 0 ? (
              <Typography sx={{ color: "text.secondary" }}>
                No sonars registered. Add one in Settings.
              </Typography>
            ) : (
              <Box sx={{ display: "flex", flexWrap: "wrap", gap: 1 }}>
                {registeredSonars.map((sonar) => (
                  <Chip
                    key={sonar.sonar_id}
                    label={sonar.name}
                    onClick={() => selectSonar(sonar)}
                    color={selectedSonar?.sonar_id === sonar.sonar_id ? "primary" : "default"}
                    sx={{ height: 48, fontSize: 15, px: 1, fontWeight: 600 }}
                  />
                ))}
              </Box>
            )}
          </Box>

          <Box>
            <Box sx={{ display: "flex", justifyContent: "space-between", mb: 1.25 }}>
              <Typography sx={{ fontWeight: 700 }}>Scan Duration</Typography>
              <Typography sx={{ color: "primary.main", fontWeight: 700 }}>SET TIME</Typography>
            </Box>
            <ScanDurationInput
              forceClose={automationRunning}
              buttons={[
                { title: "1", subtitle: "Quick" },
                { title: "3", subtitle: "Std" },
                { title: "5", subtitle: "Long" },
                { title: "Input", subtitle: "Custom" },
              ]}
              onDurationChanged={setDurationSeconds}
            />
          </Box>
        </Box>

        <Box sx={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2.5 }}>
          {selectedSonar ? (
            <SystemStatusCard
              key={statusCardKey}
              status={automationRunning ? "connecting" : getCardStatus()}
              siteName={activeSiteName}
              onSendPing={sendPing}
            />
          ) : (
            <Box
              sx={{
                p: 2.5,
                borderRadius: "12px",
                border: "1px dashed #E5E7EB",
                textAlign: "center",
              }}
            >
              <Typography sx={{ color: "text.secondary" }}>
                Select a sonar to see live status here.
              </Typography>
            </Box>
          )}

          {!automationRunning && sessionSeconds > 0 ? (
            <Typography sx={{ fontWeight: 700, fontSize: 16, color: "#15803D", textAlign: "center" }}>
              Finished, find scans on Fish Deeper website
            </Typography>
          ) : readyToFinishScan ? (
            <Typography sx={{ fontWeight: 700, fontSize: 16, color: "#15803D", textAlign: "center" }}>
              Scanning Finished, Uploading to Fish Deeper website
            </Typography>
          ) : automationRunning && initialConnectionComplete ? (
            <Box sx={{ textAlign: "center" }}>
              <Typography sx={{ fontWeight: 700, fontSize: 16, color: countdownColor }}>
                Scan Time Remaining:
              </Typography>
              <Typography sx={{ fontSize: 48, fontWeight: 900, color: countdownColor }}>
                {formatDuration(remainingSeconds)}
              </Typography>
            </Box>
          ) : null}

          {stalled && automationRunning && (
            <Box
              sx={{
                p: 1.5,
                borderRadius: "12px",
                bgcolor: "#FFF7ED",
                border: "1px solid #FED7AA",
                display: "flex",
                alignItems: "center",
                gap: 1.25,
              }}
            >
              <WarningAmberRoundedIcon sx={{ color: "#9A3412" }} />
              <Typography sx={{ fontWeight: 600, flex: 1 }}>
                No progress for a while — automation may be stuck.
              </Typography>
              <Button onClick={cancelAutomation}>Cancel</Button>
            </Box>
          )}
        </Box>
      </Box>

      <Box sx={{ mt: "auto" }}>
        <Button
          fullWidth
          size="large"
          variant="contained"
          disabled={automationRunning}
          onClick={startAutomation}
          startIcon={automationRunning ? <HourglassFullRoundedIcon /> : <PlayArrowRoundedIcon />}
          sx={{
            height: 50,
            fontSize: 16,
            bgcolor: automationRunning ? "#C2410C" : selectedSonar ? "primary.main" : "#9CA3AF",
            "&.Mui-disabled": {
              bgcolor: "#C2410C",
              color: "#FFFFFF",
            },
          }}
        >
          {getButtonLabel()}
        </Button>
        {automationRunning && (
          <Button
            fullWidth
            variant="outlined"
            color="error"
            onClick={cancelAutomation}
            sx={{ mt: 1.25, height: 44 }}
          >
            Cancel Automation
          </Button>
        )}
      </Box>
    </Box>
  );
}
