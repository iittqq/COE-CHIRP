import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/websocket_controller.dart';
import 'dart:io';
import 'package:xml/xml.dart';
import 'package:chirp_control/components/scan_duration_input.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum WebSocketConnectionStatus { disconnected, connecting, connected }

enum Device { test, siteOne, siteTwo }

enum AutoState {
  idle,
  switchingOn,
  adjustingShade,
  runningAutomation,
  switchingOff,
}

class DeviceControlPage extends StatefulWidget {
  const DeviceControlPage({super.key});

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
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
    _reconnectTimer?.cancel();

    setState(() => _connectionStatus = WebSocketConnectionStatus.connecting);

    _uiSubscription?.cancel();

    ws
        .connect()
        .then((_) {
          if (!mounted) return;

          print("Socket connected successfully ✅");
          setState(() {
            _connectionStatus = WebSocketConnectionStatus.connected;
            isConnected = true;
          });

          _uiSubscription = ws.messages.listen(
            (data) {
              if (data is Map && data.containsKey("ui_state_zip_b64")) {
                final xml = decodeZippedXml(data["ui_state_zip_b64"]);
                setState(() => uiState = xml);
                analyzeUiXml(xml);
              }
            },
            onError: (error) {
              print("Stream Error: $error");
              _handleDisconnection();
            },
            onDone: () {
              print("Stream Done (Disconnected)");
              _handleDisconnection();
            },
            cancelOnError: true,
          );
        })
        .catchError((e) {
          print("Socket connection failed: $e");
          _handleDisconnection();
        });
  }

  void _handleDisconnection() {
    if (!mounted) return;

    setState(() {
      _connectionStatus = WebSocketConnectionStatus.disconnected; // Show RED
      isConnected = false;
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _attemptConnection();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _reconnectTimer?.cancel();
    ws = WebSocketService(deviceId: deviceId);
    _attemptConnection();
  }

  Color _getStatusColor() {
    switch (_connectionStatus) {
      case WebSocketConnectionStatus.connected:
        return Colors.green;
      case WebSocketConnectionStatus.connecting:
        return Colors.orange;
      case WebSocketConnectionStatus.disconnected:
        return Colors.red;
    }
  }

  String _getStatusText() {
    switch (_connectionStatus) {
      case WebSocketConnectionStatus.connected:
        return "Ready";
      case WebSocketConnectionStatus.connecting:
        return "Reconnecting...";
      case WebSocketConnectionStatus.disconnected:
        return "Connection Lost";
    }
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
          print("Automation timer finished. Ready to open menu.");

          ws.sendCommand({
            "action": "restart",
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

  XmlElement? _findClickableAncestor(XmlElement node) {
    XmlElement? current = node;

    while (current != null) {
      final clickable = current.getAttribute('clickable');
      if (clickable == 'true') {
        return current;
      }
      final parent = current.parent;
      if (parent is XmlElement) {
        current = parent;
      } else {
        break;
      }
    }
    return null;
  }

  void _clickElementSmart(
    XmlDocument doc, {
    String? text,
    String? contentDesc,
    String? resourceId,
  }) {
    final nodes = doc.findAllElements('node');

    for (final node in nodes) {
      bool matches = false;

      if (text != null && node.getAttribute('text') == text) {
        matches = true;
      } else if (contentDesc != null &&
          node.getAttribute('content-desc') == contentDesc) {
        matches = true;
      } else if (resourceId != null &&
          node.getAttribute('resource-id') == resourceId) {
        matches = true;
      }

      if (matches) {
        if (node.getAttribute('clickable') == 'true') {
          _clickByXmlNode(node);
          return;
        }

        final clickableParent = _findClickableAncestor(node);
        if (clickableParent != null) {
          print("Found clickable parent for target element");
          _clickByXmlNode(clickableParent);
          return;
        }

        print("No clickable parent found, clicking target node directly");
        _clickByXmlNode(node);
        return;
      }
    }

    print("Element not found: text=$text, desc=$contentDesc, id=$resourceId");
  }

  bool _hasFabImageDescendant(XmlElement xmlNode, String contentDescription) {
    for (final child in xmlNode.children.whereType<XmlElement>()) {
      String contentDescAttr = child.getAttribute('content-desc') ?? '';
      String contentDesc = contentDescAttr.trim();

      if (contentDesc == contentDescription) {
        return true;
      }

      if (_hasFabImageDescendant(child, contentDescription)) {
        return true;
      }
    }
    return false;
  }

  void analyzeUiXml(String xml) {
    final doc = XmlDocument.parse(xml);

    if (_xmlUpdateCompleter != null && !_xmlUpdateCompleter!.isCompleted) {
      _xmlUpdateCompleter!.complete(doc);
    }

    if (xml.contains("Select Device Model") ||
        xml.contains('content-desc="CANCEL"')) {
      print("Detected 'Select Device' screen. Dismissing...");
      _dismissDeviceSelect();
      return;
    }

    switch (_currentState) {
      case AutoState.switchingOn:
        _handleTuyaToggle(doc, nextState: AutoState.adjustingShade);
        break;

      case AutoState.adjustingShade:
        _handleShadeToggle(doc);
        break;

      case AutoState.runningAutomation:
        _handleFishDeeperAutomation(doc);
        break;

      case AutoState.switchingOff:
        _handleTuyaToggle(doc, nextState: AutoState.idle);
        break;

      default:
        break;
    }
  }

  XmlElement? _findRiseHandle(XmlDocument doc) {
    try {
      return doc
          .findAllElements('node')
          .firstWhere(
            (n) =>
                n.getAttribute('class') == 'android.widget.ImageView' &&
                n.getAttribute('index') == '3' &&
                n.getAttribute('package') == 'com.wazombi.RISE',
          );
    } catch (e) {
      print("Handle not found in XML.");
      return null;
    }
  }

  bool _isShadeSequenceRunning = false;

  Future<void> _handleShadeToggle(XmlDocument initialDoc) async {
    if (_currentState != AutoState.adjustingShade || _isShadeSequenceRunning)
      return;

    _isShadeSequenceRunning = true;
    print("--- Starting Shade Swipe Sequence ---");

    try {
      final dragHandle = _findRiseHandle(initialDoc);
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
        onTimeout: () => initialDoc, // Fallback to avoid hanging
      );

      final movedHandle = _findRiseHandle(middleDoc);
      if (movedHandle != null) {
        print("Step 2: Swiping back UP to center.");
        _sendSwipeCommand(movedHandle, endX: 360, endY: 600);

        await Future.delayed(const Duration(seconds: 4));

        print("Shade sequence complete. Transitioning to Fish Deeper.");
        if (mounted) {
          setState(() {
            _currentState = AutoState.runningAutomation;
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

  void _dismissDeviceSelect() {
    ws.sendCommand({
      "action": "clickBySelector",
      "desc": "CANCEL", // Matches the content-desc in the XML
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

      Future.delayed(const Duration(seconds: 2), () {
        if (nextState == AutoState.adjustingShade) {
          _launchShades();
        } else {
          _closeApp(packageName: "com.tuya.smart");

          Future.delayed(const Duration(milliseconds: 500), () {
            _closeApp(packageName: "eu.deeper.fishdeeper");
          });
          setState(() {
            automationRunning = false;
            _isSynced = false;
            _currentState = AutoState.idle;
          });
          print("Sequence Complete.");
        }
      });
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

  void _handleFishDeeperAutomation(XmlDocument doc) {
    final nodes = doc.findAllElements('node');

    bool updateFound = false;
    bool laterFound = false;
    bool connectFound = false;
    bool scanOptionsFound = false;
    bool pauseFound = false;
    bool resumeFound = false;
    bool cancelFound = false;
    bool boatScanIconFound = false;
    bool openMenuFound = false;
    bool navigateWithoutMapFound = false;
    bool paused = false;
    bool historyFound = false;
    bool syncScansFound = false;
    bool notConnectedFound = false;
    String scanOptionsIndex = '';
    String openMenuIndex = '';

    _openMenuNode = null;

    for (final node in nodes) {
      final textAttr = node.getAttribute('text') ?? '';
      final resourceIdAttr = node.getAttribute('resource-id') ?? '';
      final contentDescAttr = node.getAttribute('content-desc') ?? '';
      final indexAttr = node.getAttribute('index') ?? '';
      final clickableAttr = node.getAttribute('clickable') ?? '';

      if (textAttr.contains('Update Available')) updateFound = true;
      if (textAttr.trim() == 'Later') laterFound = true;
      if (textAttr.trim() == 'Connect') connectFound = true;
      if (textAttr.trim() == 'Pause') pauseFound = true;
      if (textAttr.trim() == 'Resume') resumeFound = true;
      if (textAttr.trim() == 'Cancel') cancelFound = true;
      if (textAttr.trim() == 'Navigate Without Map') {
        navigateWithoutMapFound = true;
      }
      if (textAttr.trim() == 'Power save') paused = true;

      if (textAttr.trim() == 'Not Connected') notConnectedFound = true;

      if (contentDescAttr.trim() == 'Boat scan icon') boatScanIconFound = true;

      scanOptionsIndex = paused == true ? '2' : '1';
      if (indexAttr.trim() == scanOptionsIndex &&
          clickableAttr.trim() == 'true') {
        scanOptionsFound = true;
      }

      openMenuIndex = notConnectedFound == true ? '3' : '3';
      if (indexAttr.trim() == openMenuIndex && clickableAttr.trim() == 'true') {
        bool hasFabImageChild = _hasFabImageDescendant(node, 'Fab Image');

        if (hasFabImageChild) {
          openMenuFound = true;
          _openMenuNode = node;
        }
      }
      if (textAttr.trim() == 'History') historyFound = true;
      if (resourceIdAttr.trim() == 'syncScansButton') syncScansFound = true;
    }

    if (updateFound && laterFound) {
      print('Detected Update dialog → clicking Later button');
      _clickElementSmart(doc, text: 'Later');
      return;
    }

    if (navigateWithoutMapFound) {
      print('Clicking navigate without map');
      _clickElementSmart(doc, text: 'Navigate Without Map');
      return;
    }

    if (!initialConnectionComplete) {
      if (boatScanIconFound) {
        print('Initial setup found Boat Scan Icon → clicking it');
        _clickElementSmart(doc, contentDesc: 'Boat scan icon');

        final hours = int.tryParse(_hoursController.text) ?? 0;
        final minutes = int.tryParse(_minutesController.text) ?? 0;
        final seconds = int.tryParse(_secondsController.text) ?? 0;
        final totalSeconds = hours * 3600 + minutes * 60 + seconds;
        _startTimer(totalSeconds);

        setState(() => initialConnectionComplete = true);
        print(
          'Initial connection complete. Starting timer and Pause/Resume cycle.',
        );
        return;
      }

      if (connectFound) {
        print('Initial setup clicking Connect button');
        _clickElementSmart(doc, text: 'Connect');
        return;
      }

      if (cancelFound) {
        print('Detected Cancel dialog → clicking Cancel');
        _clickElementSmart(doc, text: 'Cancel');
        return;
      }
    }

    if (_readyToFinishScan) {
      if (_isSynced) {
        print('Scans synced. Transitioning to Tuya to turn off USB.');
        setState(() => _currentState = AutoState.switchingOff);
        _launchTuya();
        return;
      }

      if (historyFound) {
        print('Opening History');
        _clickElementSmart(doc, text: 'History');
        return;
      }

      if (syncScansFound) {
        print('Syncing Scans');
        _clickElementSmart(doc, resourceId: 'syncScansButton');
        setState(() {
          _isSynced = true;
        });

        return;
      }

      if (openMenuFound) {
        print('Timer over, Pause/Resume cleared. Clicking Menu (Fab Image).');
        if (_openMenuNode != null) {
          _clickByXmlNode(_openMenuNode!);
          return;
        }
      }
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

  void _clickByIndex(String index) {
    final cmd = {
      "action": "clickByIndex",
      "index": index,
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    };
    ws.sendCommand(cmd);
    print("Sent clickByIndex for index='$index' to ${getSelectedDeviceId()}");
  }

  void startAutomation() {
    if (!isConnected) {
      print("Not connected to WebSocket.");
      return;
    }

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

  void toggleUsbSwitch(String xml) {
    final scanDeviceId = getSelectedDeviceId();

    final Map<String, String> launchUsbController = <String, String>{
      "action": "launch",
      "package":
          "com.tuya.smart/com.thingclips.smart.hometab.activity.FamilyHomeActivity",
      "deviceId": scanDeviceId,
      "sender": deviceId,
    };

    ws.sendCommand(launchUsbController);

    final doc = XmlDocument.parse(xml);
    _clickElementSmart(doc, resourceId: 'com.tuya.smart:id/switchButton');
    return;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Widget _buildBatteryStatus() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'BATTERY',
          style: TextStyle(
            color: Colors.grey[500],
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        if (_batteryPercent == null)
          Text(
            'Start scan to determine battery',
            style: TextStyle(
              color: Colors.grey,
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _batteryPercent! < 20
                    ? Icons.battery_alert
                    : Icons.battery_full,
                color: Colors.blue[600],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '$_batteryPercent%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey[900],
                ),
              ),
            ],
          ),
      ],
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
          "Select Sonar:",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: Device.values.map((device) {
            return ElevatedButton(
              onPressed: () {
                setState(() {
                  selectedDevice = device;
                });
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
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    "WebSocket Connection",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            if (_connectionStatus ==
                                                WebSocketConnectionStatus
                                                    .connecting)
                                              BoxShadow(
                                                color: Colors.orange.withValues(
                                                  alpha: 0.5,
                                                ),
                                                blurRadius: 8,
                                                spreadRadius: 2,
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _getStatusText(),
                                        style: TextStyle(
                                          color: _getStatusColor(),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 4),
                                  const Divider(),
                                  Center(child: _buildBatteryStatus()),
                                  const Divider(),
                                ],
                              ),
                            ),
                          ],
                        ),

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
                            const Divider(),
                            const SizedBox(height: 10),
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
