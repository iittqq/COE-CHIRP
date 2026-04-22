import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/websocket_controller.dart';
import 'dart:io';
import 'package:xml/xml.dart';
import 'package:chirp_control/components/scan_duration_input.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../components/system_status_card.dart';

enum WebSocketConnectionStatus { disconnected, connecting, connected }

enum Device { test, siteOne, siteTwo }

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
  int? _batteryPercent;
  Completer<XmlDocument>? _xmlUpdateCompleter;

  String deviceId = "controllerFlutter";
  String uiState = "";
  AutoState _currentState = AutoState.idle;
  bool isConnected = false;
  bool automationRunning = false;
  bool initialConnectionComplete = false;
  bool usbSwitchOn = true;

  Timer? _automationTimer;
  int _selectedTotalSeconds = 0;
  Duration _remainingDuration = Duration.zero;
  Duration _sessionDuration = Duration.zero;

  XmlElement? _openMenuNode;
  bool _isSynced = false;

  bool _readyToFinishScan = false;

  Device? selectedDevice;
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

  final Map<Device, String> deviceIdMap = {
    Device.test: 'testAndroid',
    Device.siteOne: 'otherAndroid',
    Device.siteTwo: 'anotherAndroid',
  };

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
        .catchError((e) => _handleDisconnection());
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
    if (automationRunning || selectedDevice == null) {
      print("Ping suppressed: Automation is currently running.");
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
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _delayController.dispose();
    _automationTimer?.cancel();
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
    return selectedDevice != null
        ? deviceIdMap[selectedDevice]!
        : 'testAndroid';
  }

  void _startTimer(int totalSeconds) {
    _sessionDuration = Duration(seconds: totalSeconds);
    _remainingDuration = _sessionDuration;

    _automationTimer?.cancel();

    _automationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingDuration.inSeconds <= 0) {
        timer.cancel();
        setState(() {
          _readyToFinishScan = true;
          _currentState = AutoState.uploadingScan;
          print("Automation timer finished. Ready to open menu.");

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

  void analyzeUiXml(String xml) {
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

  void _handleTuyaToggle(XmlDocument doc, {required AutoState nextState}) {
    final switchBtn = doc
        .findAllElements('node')
        .firstWhere(
          (n) =>
              n.getAttribute('resource-id') == 'com.tuya.smart:id/switchButton',
          orElse: () => XmlElement(XmlName('null')),
        );

    if (switchBtn.name.local != 'null') {
      print("Found Tuya Switch. Toggling and moving to $nextState");
      _clickByXmlNode(switchBtn);

      setState(() => _currentState = nextState);

      Future.delayed(const Duration(seconds: 20), () {
        if (nextState == AutoState.adjustingShade) {
          _launchShades();
        } else {
          _closeApp(packageName: "com.tuya.smart");

          Future.delayed(const Duration(seconds: 10), () {
            _closeApp(packageName: "eu.deeper.fishdeeper");
          });

          Future.delayed(const Duration(seconds: 20), () {
            _closeApp(
              packageName:
                  "com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity",
            );
          });

          Future.delayed(const Duration(seconds: 30), () {
            ws.sendCommand({
              "action": "wifi",
              "state": "on",
              "deviceId": getSelectedDeviceId(),
              "sender": deviceId,
            });
          });

          setState(() {
            automationRunning = false;
            _isSynced = false;
            _currentState = AutoState.idle;
            _statusCardKey = UniqueKey();
          });
          print("Sequence Complete.");
        }
      });
    }
  }

  XmlElement? _findRiseHandle(XmlDocument doc, String rawXML) {
    if (rawXML.contains("Select Device Model") ||
        rawXML.contains('content-desc="CANCEL"')) {
      print("Detected 'Select Device' screen. Dismissing...");
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
            print("Target verified at Y: $top. Avoiding status bar.");
            return node;
          }
        }
      }
    } catch (e) {
      print("Handle detection error: $e");
    }
    return null;
  }

  void _dismissDeviceSelect() {
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
    if (_currentState != AutoState.adjustingShade || _isShadeSequenceRunning)
      return;

    _isShadeSequenceRunning = true;
    print("--- Starting Shade Swipe Sequence ---");

    try {
      final dragHandle = _findRiseHandle(doc, rawXML);
      if (dragHandle == null) {
        print("Handle not found in initial XML.");
        _isShadeSequenceRunning = false;
        return;
      }

      print("Step 1: Swiping DOWN to bottom.");
      _sendSwipeCommand(dragHandle, endX: 360, endY: 1500);

      _xmlUpdateCompleter = Completer<XmlDocument>();

      await Future.delayed(const Duration(seconds: 11));

      final middleDoc = await _xmlUpdateCompleter!.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => doc, // Fallback to avoid hanging
      );

      final movedHandle = _findRiseHandle(middleDoc, rawXML);
      if (movedHandle != null) {
        print("Step 2: Swiping back UP to center.");
        _sendSwipeCommand(movedHandle, endX: 360, endY: 600);

        await Future.delayed(const Duration(seconds: 4));

        print("Shade sequence complete. Transitioning to Fish Deeper.");
        if (mounted) {
          setState(() {
            _currentState = AutoState.performingScan;
            _isShadeSequenceRunning = false;
          });
          _launchFishDeeper();
        }
      } else {
        print("Could not find handle at the bottom position.");
        _isShadeSequenceRunning = false;
      }
    } catch (e) {
      print("Error during shade sequence: $e");
      _isShadeSequenceRunning = false;
    }
  }

  void _closeApp({String? packageName}) {
    final targetDevice = getSelectedDeviceId();

    final String packageToClose = packageName ?? "eu.deeper.fishdeeper";

    print("Closing app: $packageToClose on device: $targetDevice");

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
          if (contentDesc != null)
            return n.getAttribute('content-desc') == contentDesc;
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
      print('Detected Update dialog → clicking Later');
      _clickByXmlNode(laterNode);
      return;
    }

    if (navigateNode != null) {
      print('Clicking navigate without map');
      _clickByXmlNode(navigateNode);
      return;
    }

    if (connectNode != null) {
      print('Initial setup → clicking Connect');
      _clickByXmlNode(connectNode);
      return;
    }

    if (cancelNode != null) {
      print('Detected Cancel dialog → clicking Cancel');
      _clickByXmlNode(cancelNode);
      return;
    }

    if (boatScanNode != null) {
      print('Detected Boat scan icon');
      _clickByXmlNode(boatScanNode);

      final totalSeconds =
          (int.tryParse(_hoursController.text) ?? 0) * 3600 +
          (int.tryParse(_minutesController.text) ?? 0) * 60 +
          (int.tryParse(_secondsController.text) ?? 0);
      _startTimer(totalSeconds);
      setState(() => initialConnectionComplete = true);
      return;
    }

    print('No actionable elements found');
  }

  bool exportedCsv = false;
  void _handleUploadScan(XmlDocument doc) {
    if (_isSynced) {
      print('Scans synced. Transitioning to Tuya to turn off USB.');
      setState(() => _currentState = AutoState.switchingOff);
      _launchTuya();
      return;
    }
    final nodes = doc.findAllElements('node').toList();

    XmlElement? findNode({String? text, String? resId, String? contentDesc}) {
      try {
        return nodes.firstWhere((n) {
          if (text != null)
            return (n.getAttribute('text') ?? '').contains(text);
          if (resId != null)
            return (n.getAttribute('resource-id') ?? '').contains(resId);
          if (contentDesc != null)
            return (n.getAttribute('content-desc') ?? '').contains(contentDesc);
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
      print('Saving to files via XML');
      _clickByXmlNode(saveToFilesNode);
      exportedCsv = true;
      return;
    }

    if (exportCsvNode != null && !exportedCsv) {
      print("Exporting CSV data to phone via XML");
      _clickByXmlNode(exportCsvNode);
      return;
    }

    if (moreIconNode != null && !exportedCsv) {
      print("Clicking moreIcon via XML");
      _clickByXmlNode(moreIconNode);
      return;
    }

    if (syncScansNode != null) {
      print('History loaded: Clicking Sync via XML...');
      _clickByXmlNode(syncScansNode);
      setState(() => _isSynced = true);
      return;
    }

    if (historyNode != null) {
      print('Ready to sync: Clicking History via XML...');
      _clickByXmlNode(historyNode);
      return;
    }

    if (menuButtonNode != null) {
      print('Clicking Menu Button via XML.');
      _clickByXmlNode(menuButtonNode);
      return;
    }

    print('No actionable elements found in the current UI state');
  }

  void _clickByXmlNode(XmlElement node) {
    final xmlString = node.toXmlString();
    final cmd = {
      "action": "clickByXml",
      "xmlNode": xmlString,
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    };
    ws.sendCommand(cmd);
    print(
      "Sent clickByXml for node: ${node.getAttribute('text') ?? node.getAttribute('content-desc') ?? 'unknown'}",
    );
  }

  void startAutomation() {
    /*
    if (!isConnected) {
      print("Not connected to WebSocket.");
      return;
    }
    */

    if (selectedDevice == null) {
      print("Please select a device before starting automation.");
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

    _launchTuya();
  }

  void _launchShades() {
    print("Launching Smart Shades");
    ws.sendCommand({
      "action": "launch",
      "package": "com.wazombi.RISE/crc64c90e479072a4489e.DrawerMainActivity",
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  void _launchTuya() {
    print("Launching Tuya to toggle USB");
    ws.sendCommand({
      "action": "launch",
      "package":
          "com.tuya.smart/com.thingclips.smart.hometab.activity.FamilyHomeActivity",
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    });
  }

  void _launchFishDeeper() {
    print("Launching Fish Deeper");
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
          "Select Sonar:",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: Device.values.map((device) {
            String label = device.toString().split('.').last;
            String displayName = label
                .replaceAllMapped(
                  RegExp(r'([A-Z])'),
                  (match) => ' ${match.group(1)}',
                )
                .trim();
            displayName =
                displayName[0].toUpperCase() + displayName.substring(1);
            return ElevatedButton(
              onPressed: () {
                setState(() {
                  selectedDevice = device;
                  _activeSiteName = displayName;
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                minimumSize: Size(80, 80),
                padding: EdgeInsets.zero,
                backgroundColor: selectedDevice == device
                    ? Colors.blue
                    : Colors.grey[300],
                foregroundColor: selectedDevice == device
                    ? Colors.white
                    : Colors.black,
              ),
              child: Text(device.toString().split('.').last),
            );
          }).toList(),
        ),
      ],
    );
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
                          ],
                        ),
                        if (selectedDevice != null) ...[
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
                                TimerButtonData(title: '5', subtitle: 'Quick'),
                                TimerButtonData(title: '10', subtitle: 'Std'),
                                TimerButtonData(title: '30', subtitle: 'Long'),
                                TimerButtonData(
                                  title: 'Input',
                                  subtitle: 'Custom',
                                ),
                              ],
                              onDurationChanged: (totalSeconds) {
                                setState(() {
                                  _selectedTotalSeconds = totalSeconds;
                                  _hoursController.text = "0";
                                  _minutesController.text = (totalSeconds ~/ 60)
                                      .toString();
                                  _secondsController.text = (totalSeconds % 60)
                                      .toString();
                                });
                              },
                            ),
                            _buildTimerDisplay(),
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
                                automationRunning
                                    ? "Scanning..."
                                    : "Begin Scan",
                                style: const TextStyle(fontSize: 16),
                              ),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: automationRunning
                                    ? Colors.orange.shade700
                                    : selectedDevice != null
                                    ? Colors.blue.shade700
                                    : Colors.grey,
                                foregroundColor: Colors.white,
                              ),
                            ),
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
