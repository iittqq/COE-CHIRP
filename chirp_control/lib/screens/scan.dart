import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/websocket_controller.dart';
import '../utils/sonar_repository.dart';
import '../utils/alert_prefs.dart';
import 'dart:io';
import 'package:xml/xml.dart';
import 'package:chirp_control/components/scan_duration_input.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../components/system_status_card.dart';

const _automationInProgressKey = 'automation_in_progress';
const _automationSonarNameKey = 'automation_in_progress_sonar_name';
const _automationSonarIdKey = 'automation_in_progress_sonar_id';

enum WebSocketConnectionStatus { disconnected, connecting, connected }

enum AutoState {
  idle,
  switchingOn,
  adjustingShade,
  performingScan,
  uploadingScan,
  switchingOff,
}

enum PerformScan { boat }

class DeviceControlPage extends StatefulWidget {
  const DeviceControlPage({super.key});

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  String _activeSiteName = "";
  Key _statusCardKey = UniqueKey();
  late WebSocketService ws;
  WebSocketConnectionStatus _connectionStatus =
      WebSocketConnectionStatus.disconnected;
  Timer? _reconnectTimer;
  StreamSubscription? _uiSubscription;
  Completer<XmlDocument>? _xmlUpdateCompleter;

  String deviceId = "controllerFlutter";
  String uiState = "";
  AutoState _currentState = AutoState.idle;
  bool isConnected = false;
  bool automationRunning = false;
  bool initialConnectionComplete = false;
  bool usbSwitchOn = true;

  Timer? _automationTimer;
  Duration _remainingDuration = Duration.zero;
  Duration _sessionDuration = Duration.zero;

  bool _isSynced = false;

  bool _readyToFinishScan = false;

  bool _cancelRequested = false;
  bool _stalled = false;
  bool _watchdogSuspended = false;
  DateTime? _lastProgressAt;
  Timer? _stallWatchdog;
  static const _stallThreshold = Duration(seconds: 45);

  bool _resumedFromInterruption = false;
  String? _interruptedSonarName;
  String? _interruptedSonarId;
  bool _forcingDevicesOff = false;

  bool _dredgeWarningsEnabled = true;
  bool _shallowWarningShown = false;
  bool _sonarAlertsEnabled = true;

  List<Map<String, String>> _registeredSonars = [];
  bool _sonarLoading = true;
  Map<String, String>? _selectedSonar;

  final TextEditingController _hoursController = TextEditingController(
    text: '0',
  );
  final TextEditingController _minutesController = TextEditingController(
    text: '0',
  );
  final TextEditingController _secondsController = TextEditingController(
    text: '0',
  );
  final TextEditingController _delayController = TextEditingController(
    text: '5',
  );

  void _attemptConnection() {
    setState(() => _connectionStatus = WebSocketConnectionStatus.connecting);
    _uiSubscription?.cancel();

    ws
        .connect()
        .then((_) {
          if (!mounted) return;

          _uiSubscription = ws.messages.listen((data) {
            if (automationRunning) {
              if (data.containsKey("ui_state_zip_b64") ||
                  data.toString().contains("ui_state_zip_b64")) {
                String? b64;
                if (data["ui_state_zip_b64"] != null) {
                  b64 = data["ui_state_zip_b64"];
                } else if (data.containsKey("body")) {
                  try {
                    final body = json.decode(data["body"]);
                    b64 = body["ui_state_zip_b64"];
                  } catch (_) {}
                }

                if (b64 != null) {
                  analyzeUiXml(decodeZippedXml(b64));
                }
              }
              return;
            }

            if (_connectionStatus == WebSocketConnectionStatus.connecting) {
              if (_checkDataForSuccess(data)) {
                debugPrint("Phone confirmed ONLINE ✅");
                setState(() {
                  _connectionStatus = WebSocketConnectionStatus.connected;
                  _statusCardKey = UniqueKey();
                });
              }
            }
          });

          _sendPing();
        })
        .catchError((e) {
          _handleDisconnection();
        });
  }

  bool _checkDataForSuccess(dynamic data) {
    if (data is! Map) return false;

    Map<String, dynamic> responseData;

    if (data.containsKey("body") && data["body"] is String) {
      try {
        responseData = json.decode(data["body"]).cast<String, dynamic>();
      } catch (e) {
        debugPrint("Error parsing body string: $e");
        return false;
      }
    } else {
      responseData = data.cast<String, dynamic>();
    }

    final String? status = responseData["status"];
    final String? action = responseData["action"];

    if (status == "online" || action == "checkOnline") {
      return true;
    }

    return false;
  }

  void _sendPing() {
    if (automationRunning || _selectedSonar == null) {
      debugPrint("Ping suppressed: Automation is currently running.");
      return;
    }

    setState(() {
      _connectionStatus = WebSocketConnectionStatus.connecting;
    });

    ws.sendCommand({
      "action": "checkOnline",
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  void _handleDisconnection() {
    if (!mounted) return;
    setState(() => _connectionStatus = WebSocketConnectionStatus.disconnected);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _attemptConnection();
    });
  }

  @override
  void initState() {
    super.initState();
    _reconnectTimer?.cancel();
    ws = WebSocketService(deviceId: deviceId);
    _loadSonars();
    SonarRepository.sonarsChanged.addListener(_loadSonars);
    _checkForInterruptedAutomation();
    loadDredgeWarningsEnabled().then((value) {
      if (mounted) setState(() => _dredgeWarningsEnabled = value);
    });
    loadSonarAlertsEnabled().then((value) {
      if (mounted) setState(() => _sonarAlertsEnabled = value);
    });
  }

  void _notifyScanStarted() {
    if (!_sonarAlertsEnabled || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Scan started.')));
  }

  void _notifyScanFinished() {
    if (!_sonarAlertsEnabled || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Scan finished. Dredges can be found at maps.fishdeeper.com',
        ),
      ),
    );
  }

  Future<void> _checkForInterruptedAutomation() async {
    final prefs = await SharedPreferences.getInstance();
    final wasInProgress = prefs.getBool(_automationInProgressKey) ?? false;
    if (!wasInProgress || !mounted) return;

    setState(() {
      _resumedFromInterruption = true;
      _interruptedSonarName = prefs.getString(_automationSonarNameKey);
      _interruptedSonarId = prefs.getString(_automationSonarIdKey);
    });
  }

  Future<void> _setAutomationInProgress(
    bool value, {
    String? sonarName,
    String? sonarId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_automationInProgressKey, true);
      await prefs.setString(_automationSonarNameKey, sonarName ?? '');
      await prefs.setString(_automationSonarIdKey, sonarId ?? '');
    } else {
      await prefs.remove(_automationInProgressKey);
      await prefs.remove(_automationSonarNameKey);
      await prefs.remove(_automationSonarIdKey);
    }
  }

  void _acknowledgeInterruption() {
    setState(() => _resumedFromInterruption = false);
    _setAutomationInProgress(false);
  }

  // Sends a command and waits for the UI dump the remote controller attaches
  // to its response (every action handler in remote_control.py returns one),
  // independent of _uiSubscription/automationRunning so it also works during
  // recovery, before any automation is "running". Returns null on timeout.
  Future<XmlDocument?> _sendAndAwaitUiDump(
    Map<String, dynamic> command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<XmlDocument?>();
    late final StreamSubscription sub;
    sub = ws.messages.listen((data) {
      if (completer.isCompleted) return;
      String? b64 = data['ui_state_zip_b64'] as String?;
      if (b64 == null && data['body'] is String) {
        try {
          final body = json.decode(data['body']);
          b64 = body['ui_state_zip_b64'] as String?;
        } catch (_) {}
      }
      if (b64 != null) {
        completer.complete(XmlDocument.parse(decodeZippedXml(b64)));
      }
    });

    ws.sendCommand(command);
    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return result;
  }

  // Best-effort cleanup after an interrupted automation. Can safely force-close
  // the scan/shade apps and restore WiFi (no ambiguity there). For the Tuya
  // power toggle, rather than guessing or requiring someone to be watching
  // the device to check it manually (this runs unattended), it reads the
  // switch's actual on/off state from the UI dump - uiautomator2 exposes a
  // `checked` attribute on checkable nodes like this one - and only clicks it
  // if that confirms it's still on. If the node or its state can't be read,
  // it falls back to surfacing Tuya and asking the user to verify, since
  // guessing risks turning the plug back on.
  // Note: this deliberately does NOT wait for _connectionStatus to become
  // `connected` — that only happens once the *remote* device confirms itself
  // online via a ping round-trip, which is exactly what's unavailable when
  // the remote device is the thing that's unresponsive. All this needs is the
  // local WebSocket transport to be open so sendCommand() can push messages
  // through; whether the remote device is listening is unknowable here.
  Future<void> _forceDevicesOff() async {
    final targetId = _interruptedSonarId ?? getSelectedDeviceId();
    setState(() => _forcingDevicesOff = true);

    try {
      await ws.connect();
    } catch (e) {
      if (!mounted) return;
      setState(() => _forcingDevicesOff = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't reach the device. Check your connection and try again.",
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    ws.sendCommand({
      "action": "close",
      "package": "eu.deeper.fishdeeper",
      "deviceId": targetId,
      "sender": deviceId,
    });
    await Future.delayed(const Duration(seconds: 1));

    ws.sendCommand({
      "action": "close",
      "package": "com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity",
      "deviceId": targetId,
      "sender": deviceId,
    });
    await Future.delayed(const Duration(seconds: 1));

    ws.sendCommand({
      "action": "wifi",
      "state": "on",
      "deviceId": targetId,
      "sender": deviceId,
    });
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    final tuyaDoc = await _sendAndAwaitUiDump({
      "action": "launch",
      "package":
          "com.tuya.smart/com.thingclips.smart.hometab.activity.FamilyHomeActivity",
      "deviceId": targetId,
      "sender": deviceId,
    });

    if (!mounted) return;

    String resultMessage =
        "Closed the scan/shade apps and restored WiFi. Opened Tuya — "
        "please verify the smart plug is off yourself, since the app "
        "couldn't read its current state.";

    if (tuyaDoc != null) {
      final switchBtn = tuyaDoc
          .findAllElements('node')
          .firstWhere(
            (n) =>
                n.getAttribute('resource-id') ==
                'com.tuya.smart:id/switchButton',
            orElse: () => XmlElement(XmlName('null')),
          );

      if (switchBtn.name.local != 'null') {
        final checked = switchBtn.getAttribute('checked');
        if (checked == 'false') {
          resultMessage =
              "Closed the scan/shade apps, restored WiFi, and confirmed the "
              "smart plug was already off.";
        } else if (checked == 'true') {
          await _sendAndAwaitUiDump({
            "action": "clickByXml",
            "xmlNode": switchBtn.toXmlString(),
            "deviceId": targetId,
            "sender": deviceId,
          });
          if (!mounted) return;
          resultMessage =
              "Closed the scan/shade apps, restored WiFi, and turned the "
              "smart plug off.";
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _forcingDevicesOff = false;
      _resumedFromInterruption = false;
    });
    _setAutomationInProgress(false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(resultMessage),
      ),
    );
  }

  Future<void> _loadSonars() async {
    setState(() => _sonarLoading = true);
    try {
      final sonars = await SonarRepository.fetchSonars();
      if (mounted) setState(() => _registeredSonars = sonars);
    } catch (_) {
      if (mounted) setState(() => _registeredSonars = []);
    } finally {
      if (mounted) setState(() => _sonarLoading = false);
    }
  }

  @override
  void dispose() {
    SonarRepository.sonarsChanged.removeListener(_loadSonars);
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _delayController.dispose();
    _automationTimer?.cancel();
    _stallWatchdog?.cancel();
    _reconnectTimer?.cancel();
    _uiSubscription?.cancel();
    ws.disconnect();
    super.dispose();
  }

  String decodeZippedXml(String b64) {
    final compressedBytes = base64.decode(b64);
    final decompressed = GZipCodec().decode(compressedBytes);
    return utf8.decode(decompressed);
  }

  String getSelectedDeviceId() {
    return _selectedSonar?['sonar_id'] ?? 'testAndroid';
  }

  void _startTimer(int totalSeconds) {
    _sessionDuration = Duration(seconds: totalSeconds);
    _remainingDuration = _sessionDuration;

    _automationTimer?.cancel();
    _suspendWatchdog();

    _automationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingDuration.inSeconds <= 0) {
        timer.cancel();
        _resumeWatchdog();
        setState(() {
          _readyToFinishScan = true;
          _currentState = AutoState.uploadingScan;
          debugPrint("Automation timer finished. Ready to open menu.");

          ws.sendCommand({
            "action": "wifi",
            "state": "off",
            "deviceId": getSelectedDeviceId(),
            "sender": deviceId,
          });
        });
      } else {
        setState(() {
          _remainingDuration = _remainingDuration - const Duration(seconds: 1);
        });
      }
    });
  }

  void _checkDepthWarning(String xml) {
    final isShallow = xml.toLowerCase().contains('too shallow');

    if (!isShallow) {
      _shallowWarningShown = false;
      return;
    }

    if (_shallowWarningShown) return;
    _shallowWarningShown = true;

    if (!_dredgeWarningsEnabled || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Depth warning: water is too shallow.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void analyzeUiXml(String xml) {
    if (_cancelRequested) return;
    _checkDepthWarning(xml);
    final doc = XmlDocument.parse(xml);

    if (_xmlUpdateCompleter != null && !_xmlUpdateCompleter!.isCompleted) {
      _xmlUpdateCompleter!.complete(doc);
    }

    switch (_currentState) {
      case AutoState.switchingOn:
        _handleTuyaToggle(doc, nextState: AutoState.adjustingShade);
        break;

      case AutoState.adjustingShade:
        _handleShadeToggle(doc, xml);
        break;

      case AutoState.performingScan:
        _handleFishDeeperAutomation(doc);
        break;

      case AutoState.uploadingScan:
        _handleUploadScan(doc);
        break;

      case AutoState.switchingOff:
        _handleTuyaToggle(doc, nextState: AutoState.idle);
        break;

      default:
        break;
    }
  }

  Future<void> _handleTuyaToggle(
    XmlDocument doc, {
    required AutoState nextState,
  }) async {
    final switchBtn = doc
        .findAllElements('node')
        .firstWhere(
          (n) =>
              n.getAttribute('resource-id') == 'com.tuya.smart:id/switchButton',
          orElse: () => XmlElement(XmlName('null')),
        );

    if (switchBtn.name.local != 'null') {
      debugPrint("Found Tuya Switch. Toggling and moving to $nextState");
      _clickByXmlNode(switchBtn);

      setState(() => _currentState = nextState);

      if (nextState == AutoState.adjustingShade) {
        await Future.delayed(const Duration(seconds: 20));
        if (_cancelRequested || !mounted) return;
        _launchShades();
      } else {
        debugPrint("Starting sequential shutdown...");

        await Future.delayed(const Duration(seconds: 5));
        if (_cancelRequested || !mounted) return;
        _closeApp(packageName: "com.tuya.smart");

        await Future.delayed(const Duration(seconds: 5));
        if (_cancelRequested || !mounted) return;
        _closeApp(packageName: "eu.deeper.fishdeeper");

        await Future.delayed(const Duration(seconds: 5));
        if (_cancelRequested || !mounted) return;
        _closeApp(
          packageName:
              "com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity",
        );

        await Future.delayed(const Duration(seconds: 5));
        if (_cancelRequested || !mounted) return;
        ws.sendCommand({
          "action": "wifi",
          "state": "on",
          "deviceId": getSelectedDeviceId(),
          "sender": deviceId,
        });

        _stopWatchdog();
        _setAutomationInProgress(false);
        if (mounted) {
          setState(() {
            automationRunning = false;
            _isSynced = false;
            _currentState = AutoState.idle;
            _statusCardKey = UniqueKey();
          });
        }
        _notifyScanFinished();
        debugPrint("Sequence Complete.");
      }
    }
  }

  XmlElement? _findRiseHandle(XmlDocument doc, String rawXML) {
    if (rawXML.contains("Select Device Model") ||
        rawXML.contains('content-desc="CANCEL"')) {
      debugPrint("Detected 'Select Device' screen. Dismissing...");
      _dismissDeviceSelect();
      return null;
    }

    try {
      final nodes = doc.findAllElements('node').toList();

      for (var node in nodes) {
        final String bounds = node.getAttribute('bounds') ?? "";
        final String pkg = node.getAttribute('package') ?? "";

        if (pkg != 'com.wazombi.RISE') continue;

        final match = RegExp(
          r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
        ).firstMatch(bounds);
        if (match != null) {
          int top = int.parse(match.group(2)!);

          if (top < 300) continue;

          final parent = node.parent;
          if (parent is XmlElement &&
              parent.getAttribute('resource-id') ==
                  'com.wazombi.RISE:id/window_control') {
            debugPrint("Target verified at Y: $top. Avoiding status bar.");
            return node;
          }
        }
      }
    } catch (e) {
      debugPrint("Handle detection error: $e");
    }
    return null;
  }

  void _dismissDeviceSelect() {
    _markProgress();
    ws.sendCommand({
      "action": "clickByXml",
      "xmlNode": '<node content-desc="CANCEL" />',
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  void _sendSwipeCommand(
    XmlElement node, {
    required double endX,
    required double endY,
  }) {
    _markProgress();
    final xmlString = node.toXmlString();
    ws.sendCommand({
      "action": "swipeByXml",
      "xmlNode": xmlString,
      "endX": endX,
      "endY": endY,
      "duration": 1200,
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  bool _isShadeSequenceRunning = false;

  Future<void> _handleShadeToggle(XmlDocument doc, String rawXML) async {
    if (_currentState != AutoState.adjustingShade || _isShadeSequenceRunning) {
      return;
    }

    _isShadeSequenceRunning = true;
    debugPrint("--- Starting Shade Swipe Sequence ---");

    try {
      final dragHandle = _findRiseHandle(doc, rawXML);
      if (dragHandle == null) {
        debugPrint("Handle not found in initial XML.");
        _isShadeSequenceRunning = false;
        return;
      }

      debugPrint("Step 1: Swiping DOWN to bottom.");
      _sendSwipeCommand(dragHandle, endX: 360, endY: 1500);

      _xmlUpdateCompleter = Completer<XmlDocument>();

      await Future.delayed(const Duration(seconds: 11));
      if (_cancelRequested || !mounted) return;

      final middleDoc = await _xmlUpdateCompleter!.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => doc, // Fallback to avoid hanging
      );
      if (_cancelRequested || !mounted) return;

      final movedHandle = _findRiseHandle(middleDoc, rawXML);
      if (movedHandle != null) {
        debugPrint("Step 2: Swiping back UP to center.");
        _sendSwipeCommand(movedHandle, endX: 360, endY: 600);

        await Future.delayed(const Duration(seconds: 4));
        if (_cancelRequested || !mounted) return;

        debugPrint("Shade sequence complete. Transitioning to Fish Deeper.");
        if (mounted) {
          setState(() {
            _currentState = AutoState.performingScan;
            _isShadeSequenceRunning = false;
          });
          _launchFishDeeper();
        }
      } else {
        debugPrint("Could not find handle at the bottom position.");
        _isShadeSequenceRunning = false;
      }
    } catch (e) {
      debugPrint("Error during shade sequence: $e");
      _isShadeSequenceRunning = false;
    }
  }

  void _closeApp({String? packageName}) {
    _markProgress();
    final targetDevice = getSelectedDeviceId();

    final String packageToClose = packageName ?? "eu.deeper.fishdeeper";

    debugPrint("Closing app: $packageToClose on device: $targetDevice");

    ws.sendCommand({
      "action": "close",
      "package": packageToClose,
      "deviceId": targetDevice,
      "sender": deviceId,
    });
  }

  bool clickedInitialConnect = false;

  void _handleFishDeeperAutomation(XmlDocument doc) {
    final nodes = doc.findAllElements('node').toList();

    XmlElement? findNode({String? text, String? contentDesc}) {
      try {
        return nodes.firstWhere((n) {
          if (text != null) return n.getAttribute('text') == text;
          if (contentDesc != null) {
            return n.getAttribute('content-desc') == contentDesc;
          }
          return false;
        });
      } catch (_) {
        return null;
      }
    }

    final updateNode = nodes.any(
      (n) => (n.getAttribute('text') ?? '').contains('Update Available'),
    );
    final laterNode = findNode(text: 'Later');
    final navigateNode = findNode(text: 'Navigate Without Map');
    final connectNode = findNode(text: 'Connect');
    final cancelNode = findNode(text: 'Cancel');
    final boatScanNode = findNode(contentDesc: 'Boat scan icon');

    if (updateNode && laterNode != null) {
      debugPrint('Detected Update dialog → clicking Later');
      _clickByXmlNode(laterNode);
      return;
    }

    if (navigateNode != null) {
      debugPrint('Clicking navigate without map');
      _clickByXmlNode(navigateNode);
      return;
    }

    if (connectNode != null) {
      debugPrint('Initial setup → clicking Connect');
      _clickByXmlNode(connectNode);
      return;
    }

    if (cancelNode != null) {
      debugPrint('Detected Cancel dialog → clicking Cancel');
      _clickByXmlNode(cancelNode);
      return;
    }

    if (boatScanNode != null) {
      debugPrint('Detected Boat scan icon');
      _clickByXmlNode(boatScanNode);

      final totalSeconds =
          (int.tryParse(_hoursController.text) ?? 0) * 3600 +
          (int.tryParse(_minutesController.text) ?? 0) * 60 +
          (int.tryParse(_secondsController.text) ?? 0);
      _startTimer(totalSeconds);
      setState(() => initialConnectionComplete = true);
      _notifyScanStarted();
      return;
    }

    debugPrint('No actionable elements found');
  }

  bool exportedCsv = false;
  void _handleUploadScan(XmlDocument doc) {
    if (_isSynced) {
      debugPrint('Scans synced. Transitioning to Tuya to turn off USB.');
      setState(() => _currentState = AutoState.switchingOff);
      _launchTuya();
      return;
    }
    final nodes = doc.findAllElements('node').toList();

    XmlElement? findNode({String? text, String? resId, String? contentDesc}) {
      try {
        return nodes.firstWhere((n) {
          if (text != null) {
            return (n.getAttribute('text') ?? '').contains(text);
          }
          if (resId != null) {
            return (n.getAttribute('resource-id') ?? '').contains(resId);
          }
          if (contentDesc != null) {
            return (n.getAttribute('content-desc') ?? '').contains(contentDesc);
          }
          return false;
        });
      } catch (_) {
        return null;
      }
    }

    final saveToFilesNode = findNode(text: 'Files by Google');
    final exportCsvNode = findNode(text: 'Export scan data as CSV');
    final moreIconNode = findNode(contentDesc: 'moreIcon');
    final syncScansNode = findNode(resId: 'syncScansButton');
    final historyNode = findNode(text: 'History');
    final menuButtonNode = findNode(resId: 'menuButton');

    if (saveToFilesNode != null && !exportedCsv) {
      debugPrint('Saving to files via XML');
      _clickByXmlNode(saveToFilesNode);
      exportedCsv = true;
      return;
    }

    if (exportCsvNode != null && !exportedCsv) {
      debugPrint("Exporting CSV data to phone via XML");
      _clickByXmlNode(exportCsvNode);
      return;
    }

    if (moreIconNode != null && !exportedCsv) {
      debugPrint("Clicking moreIcon via XML");
      _clickByXmlNode(moreIconNode);
      return;
    }

    if (syncScansNode != null) {
      debugPrint('History loaded: Clicking Sync via XML...');
      _clickByXmlNode(syncScansNode);
      setState(() => _isSynced = true);
      return;
    }

    if (historyNode != null) {
      debugPrint('Ready to sync: Clicking History via XML...');
      _clickByXmlNode(historyNode);
      return;
    }

    if (menuButtonNode != null) {
      debugPrint('Clicking Menu Button via XML.');
      _clickByXmlNode(menuButtonNode);
      return;
    }

    debugPrint('No actionable elements found in the current UI state');
  }

  void _clickByXmlNode(XmlElement node) {
    _markProgress();
    final xmlString = node.toXmlString();
    final cmd = {
      "action": "clickByXml",
      "xmlNode": xmlString,
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    };
    ws.sendCommand(cmd);
    debugPrint(
      "Sent clickByXml for node: ${node.getAttribute('text') ?? node.getAttribute('content-desc') ?? 'unknown'}",
    );
  }

  void startAutomation() {
    /*
    if (!isConnected) {
      debugPrint("Not connected to WebSocket.");
      return;
    }
    */

    if (_selectedSonar == null) {
      debugPrint("Please select a device before starting automation.");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a device.')));
      return;
    }

    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final seconds = int.tryParse(_secondsController.text) ?? 0;
    final totalSeconds = hours * 3600 + minutes * 60 + seconds;

    if (totalSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a duration greater than 0.')),
      );
      return;
    }

    setState(() {
      _currentState = AutoState.switchingOn;
      automationRunning = true;
      initialConnectionComplete = false;
      _readyToFinishScan = false;
    });

    _setAutomationInProgress(
      true,
      sonarName: _activeSiteName,
      sonarId: _selectedSonar?['sonar_id'],
    );
    _startWatchdog();
    _launchTuya();
  }

  void _startWatchdog() {
    _cancelRequested = false;
    _stalled = false;
    _watchdogSuspended = false;
    _lastProgressAt = DateTime.now();
    _stallWatchdog?.cancel();
    _stallWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted ||
          !automationRunning ||
          _watchdogSuspended ||
          _lastProgressAt == null) {
        return;
      }
      final elapsed = DateTime.now().difference(_lastProgressAt!);
      if (elapsed > _stallThreshold && !_stalled) {
        setState(() => _stalled = true);
      }
    });
  }

  void _stopWatchdog() {
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
  }

  void _markProgress() {
    _lastProgressAt = DateTime.now();
    if (_stalled && mounted) setState(() => _stalled = false);
  }

  // The scan-duration countdown in _startTimer is a long, expected wait with
  // nothing for the automation to click - suspend the watchdog for it rather
  // than faking "progress" every tick, so a normal multi-minute scan can't
  // get mistaken for a stuck automation once it passes the stall threshold.
  void _suspendWatchdog() {
    _watchdogSuspended = true;
    if (_stalled && mounted) setState(() => _stalled = false);
  }

  void _resumeWatchdog() {
    _watchdogSuspended = false;
    _markProgress();
  }

  void _cancelAutomation() {
    _cancelRequested = true;
    _stopWatchdog();
    _automationTimer?.cancel();
    _setAutomationInProgress(false);
    setState(() {
      automationRunning = false;
      _currentState = AutoState.idle;
      _stalled = false;
      _readyToFinishScan = false;
      initialConnectionComplete = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Automation cancelled. The physical device may still be mid-action — check it manually.',
        ),
      ),
    );
  }

  void _launchShades() {
    _markProgress();
    debugPrint("Launching Smart Shades");
    ws.sendCommand({
      "action": "launch",
      "package": "com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity",
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  void _launchTuya() {
    _markProgress();
    debugPrint("Launching Tuya to toggle USB");
    ws.sendCommand({
      "action": "launch",
      "package":
          "com.tuya.smart/com.thingclips.smart.hometab.activity.FamilyHomeActivity",
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  void _launchFishDeeper() {
    _markProgress();
    debugPrint("Launching Fish Deeper");
    ws.sendCommand({
      "action": "launch",
      "package":
          "eu.deeper.fishdeeper/eu.deeper.app.scan.live.MainScreenActivity",
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  SystemStatus _getCardStatus() {
    switch (_connectionStatus) {
      case WebSocketConnectionStatus.connected:
        return SystemStatus.online;
      case WebSocketConnectionStatus.connecting:
        return SystemStatus.connecting;
      case WebSocketConnectionStatus.disconnected:
        return SystemStatus.offline;
    }
  }

  Widget _buildInterruptionBanner() {
    if (!_resumedFromInterruption) return const SizedBox.shrink();

    final sonarLabel =
        (_interruptedSonarName != null && _interruptedSonarName!.isNotEmpty)
        ? ' on "$_interruptedSonarName"'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_problem_outlined, color: Colors.red.shade800),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Automation didn't finish cleanly",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A previous scan automation$sonarLabel was interrupted (app closed, '
            'crashed, or lost power) before it finished. Physical devices — '
            'power switch, shades, sonar app — may be left in an unknown '
            'state.',
            style: TextStyle(color: Colors.red.shade900, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _forcingDevicesOff ? null : _forceDevicesOff,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: _forcingDevicesOff
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Force devices off',
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: _forcingDevicesOff
                      ? null
                      : _acknowledgeInterruption,
                  child: const Text(
                    "I've checked it",
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "\"Force devices off\" closes the scan/shade apps and restores "
            "WiFi, then opens Tuya so you can verify the power switch "
            "yourself — it can't safely guess whether the plug is on or off.",
            style: TextStyle(color: Colors.red.shade700, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildStallBanner() {
    if (!_stalled || !automationRunning) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "No progress for a while — automation may be stuck.",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: _cancelAutomation, child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildTimerDisplay() {
    if (!automationRunning && _sessionDuration.inSeconds > 0) {
      return Column(
        children: [
          const SizedBox(height: 20),
          Text(
            "Finished, find scans on Fish Deeper website",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green.shade700,
            ),
          ),
        ],
      );
    } else if (_readyToFinishScan) {
      return Column(
        children: [
          const SizedBox(height: 20),
          Text(
            "Scanning Finished, Uploading to Fish Deeper website",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green.shade700,
            ),
          ),
        ],
      );
    }

    if (!automationRunning || !initialConnectionComplete) {
      return const SizedBox.shrink();
    }

    Color timerColor = Colors.blue.shade700;
    if (_remainingDuration.inSeconds <= 10 &&
        _remainingDuration.inSeconds > 0) {
      timerColor = Colors.orange;
    } else if (_remainingDuration.inSeconds <= 0) {
      timerColor = Colors.red;
    }

    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          "Scan Time Remaining:",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: timerColor,
          ),
        ),
        Text(
          _formatDuration(_remainingDuration),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: timerColor,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Sonar",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_sonarLoading)
          const Center(child: CircularProgressIndicator())
        else if (_registeredSonars.isEmpty)
          const Text(
            'No sonars registered. Add one in Settings.',
            style: TextStyle(color: Colors.grey),
          )
        else
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _registeredSonars.map((sonar) {
                final isSelected =
                    _selectedSonar?['sonar_id'] == sonar['sonar_id'];
                return ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedSonar = sonar;
                      _activeSiteName = sonar['name'] ?? '';
                      _statusCardKey = UniqueKey();
                    });
                    if (_connectionStatus ==
                        WebSocketConnectionStatus.disconnected) {
                      _attemptConnection();
                    } else {
                      _sendPing();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size(80, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    backgroundColor: isSelected
                        ? Colors.blue
                        : Colors.grey[300],
                    foregroundColor: isSelected ? Colors.white : Colors.black,
                  ),
                  child: Text(sonar['name'] ?? ''),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  String _getButtonLabel() {
    if (!automationRunning) return "Begin Scan";

    switch (_currentState) {
      case AutoState.switchingOn:
        return "Powering On...";
      case AutoState.adjustingShade:
        return "Adjusting Shade...";
      case AutoState.performingScan:
        return "Scanning...";
      case AutoState.uploadingScan:
        return "Uploading Scan...";
      case AutoState.switchingOff:
        return "Finishing Up...";
      case AutoState.idle:
        return "Begin Scan";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            SvgPicture.asset(
                              'assets/radar-sonar.svg',
                              height: 200,
                              width: 200,
                            ),
                            const SizedBox(height: 12),
                            _buildInterruptionBanner(),
                          ],
                        ),
                        if (_selectedSonar != null) ...[
                          SystemStatusCard(
                            key: _statusCardKey,
                            status: automationRunning
                                ? SystemStatus.connecting
                                : _getCardStatus(),
                            siteName: _activeSiteName,
                            onSendPing: _sendPing,
                          ),
                          const SizedBox(height: 20),
                        ],
                        Column(
                          children: [
                            _buildDeviceSelection(),
                            const SizedBox(height: 20),
                            Row(
                              children: const [
                                Text(
                                  "Scan Duration",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Spacer(),
                                Text(
                                  "SET TIME",
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TimerButtonRow(
                              forceClose: automationRunning,
                              buttons: [
                                TimerButtonData(title: '1', subtitle: 'Quick'),
                                TimerButtonData(title: '3', subtitle: 'Std'),
                                TimerButtonData(title: '5', subtitle: 'Long'),
                                TimerButtonData(
                                  title: 'Input',
                                  subtitle: 'Custom',
                                ),
                              ],
                              onDurationChanged: (totalSeconds) {
                                setState(() {
                                  _hoursController.text = "0";
                                  _minutesController.text = (totalSeconds ~/ 60)
                                      .toString();
                                  _secondsController.text = (totalSeconds % 60)
                                      .toString();
                                });
                              },
                            ),
                            _buildTimerDisplay(),
                            _buildStallBanner(),
                          ],
                        ),

                        Column(
                          children: [
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: automationRunning
                                  ? null
                                  : startAutomation,
                              icon: Icon(
                                automationRunning
                                    ? Icons.hourglass_full
                                    : Icons.play_arrow,
                              ),
                              label: Text(
                                _getButtonLabel(),
                                style: const TextStyle(fontSize: 16),
                              ),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: automationRunning
                                    ? Colors.orange.shade700
                                    : _selectedSonar != null
                                    ? Colors.blue.shade700
                                    : Colors.grey,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            if (automationRunning) ...[
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _cancelAutomation,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Cancel Automation'),
                              ),
                            ],
                            const SizedBox(height: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
