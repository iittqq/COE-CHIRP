import 'package:chirp_control/components/system_status_card.dart';
import 'package:flutter/material.dart';
import '../components/weather_graph.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:chirp_control/screens/data.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import '../utils/websocket_controller.dart';

Future<Weather> fetchWeather() async {
  final response = await http.get(
    Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=29.7977&longitude=-93.3251&hourly=temperature_2m,rain,showers,cloud_cover,sunshine_duration&timezone=America%2FChicago&wind_speed_unit=mph&temperature_unit=fahrenheit&precipitation_unit=inch&forecast_hours=24',
    ),
  );

  if (response.statusCode == 200) {
    return Weather.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  } else {
    throw Exception('Failed to load weather');
  }
}

class Weather {
  final Map<String, dynamic> hourlyUnits;
  final List<String> times;
  final List<double> temperatures;
  final List<double> rainChances;
  final List<double> showerChances;
  final List<int> cloudCovers;
  final List<double> sunshineDuration;

  const Weather({
    required this.hourlyUnits,
    required this.times,
    required this.temperatures,
    required this.rainChances,
    required this.showerChances,
    required this.cloudCovers,
    required this.sunshineDuration,
  });

  factory Weather.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'hourly_units': Map<String, dynamic> hourlyUnits,
        'hourly': Map<String, dynamic> hourly,
      } =>
        Weather(
          hourlyUnits: hourlyUnits,
          times: List<String>.from(hourly['time']),
          temperatures: List<double>.from(hourly['temperature_2m']),
          rainChances: List<double>.from(hourly['rain']),
          showerChances: List<double>.from(hourly['showers']),
          cloudCovers: List<int>.from(hourly['cloud_cover']),
          sunshineDuration: List<double>.from(hourly['sunshine_duration']),
        ),
      _ => throw const FormatException('Failed to load weather'),
    };
  }
}

enum WebSocketConnectionStatus { disconnected, connecting, connected }

enum Device { test, siteOne, siteTwo }

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavScan;

  const HomeScreen({super.key, required this.onNavScan});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String deviceId = "controllerFlutter";
  late Future<Weather> futureWeather;
  String selectedMetric = 'Temperature (°F)';
  List<double> selectedData = [];
  late WebSocketService ws;
  WebSocketConnectionStatus _connectionStatus =
      WebSocketConnectionStatus.disconnected;
  Timer? _reconnectTimer;
  StreamSubscription? _uiSubscription;
  Device? selectedDevice;

  void _attemptConnection() {
    setState(() => _connectionStatus = WebSocketConnectionStatus.connecting);
    _uiSubscription?.cancel();

    ws
        .connect()
        .then((_) {
          if (!mounted) return;

          _uiSubscription = ws.messages.listen(
            (data) {
              if (_checkDataForSuccess(data)) {
                debugPrint("Phone confirmed ONLINE ✅");
                setState(() {
                  _connectionStatus = WebSocketConnectionStatus.connected;
                });
              }
            },
            onError: (error) => _handleDisconnection(),
            onDone: () => _handleDisconnection(),
          );

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
    if (_connectionStatus == WebSocketConnectionStatus.disconnected) return;

    setState(() {
      _connectionStatus = WebSocketConnectionStatus.connecting;
    });

    ws.sendCommand({
      "action": "checkOnline",
      "deviceId": "testAndroid",
      "sender": deviceId,
    });
  }

  @override
  void initState() {
    super.initState();
    futureWeather = fetchWeather();
    ws = WebSocketService(deviceId: deviceId);
    _attemptConnection();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _uiSubscription?.cancel();
    ws.disconnect();
    super.dispose();
  }

  void _handleDisconnection() {
    if (!mounted) return;
    setState(() => _connectionStatus = WebSocketConnectionStatus.disconnected);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _attemptConnection();
    });
  }

  void updateGraph(String metric, Weather weather) {
    setState(() {
      selectedMetric = metric;
      switch (metric) {
        case 'Temperature (°F)':
          selectedData = weather.temperatures;
          break;
        case 'Rain (in)':
          selectedData = weather.rainChances;
          break;
        case 'Showers (in)':
          selectedData = weather.showerChances;
          break;
        case 'Cloud Cover (%)':
          selectedData = weather.cloudCovers.map((e) => e.toDouble()).toList();
          break;
        case 'Sunshine (s)':
          selectedData = weather.sunshineDuration;
          break;
        default:
          selectedData = [];
      }
    });
  }

  Future<void> _importFolder() async {
    PermissionStatus status;

    if (Platform.isAndroid) {
      if (await Permission.storage.isGranted) {
        status = PermissionStatus.granted;
      } else {
        status = await Permission.manageExternalStorage.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          openAppSettings();
          return;
        }
      }
    } else {
      status = await Permission.storage.request();
      if (!status.isGranted) return;
    }

    final result = await FilePicker.getDirectoryPath();
    if (result == null) return;

    final pickedDir = Directory(result);
    final appDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${appDir.path}/scans');

    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }

    final dest = Directory(
      '${scansDir.path}/${pickedDir.path.split(Platform.pathSeparator).last}',
    );

    if (await dest.exists()) {
      await dest.delete(recursive: true);
    }

    await _copyDirectory(pickedDir, dest);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan imported successfully!')),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const HistoryPage()),
      );
    }
  }

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (var entity in src.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
          '${dest.path}/${entity.path.split(Platform.pathSeparator).last}',
        );
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(
          '${dest.path}/${entity.path.split(Platform.pathSeparator).last}',
        );
      }
    }
  }

  SystemStatus _mapStatus() {
    switch (_connectionStatus) {
      case WebSocketConnectionStatus.connected:
        return SystemStatus.online;
      case WebSocketConnectionStatus.connecting:
        return SystemStatus.connecting;
      case WebSocketConnectionStatus.disconnected:
        return SystemStatus.offline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(12.0),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SystemStatusCard(
              status: _mapStatus(),
              siteName: 'Site One',
              onSendPing: _sendPing,
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'WEATHER CONDITIONS',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            FutureBuilder<Weather>(
              future: futureWeather,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SizedBox(
                    height: MediaQuery.of(context).size.height / 3 + 60,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                } else if (snapshot.hasError) {
                  return Text('${snapshot.error}');
                } else if (snapshot.hasData) {
                  final weather = snapshot.data!;
                  if (selectedData.isEmpty) {
                    selectedData = weather.temperatures;
                  }

                  final metrics = [
                    'Temperature (°F)',
                    'Rain (in)',
                    'Showers (in)',
                    'Cloud Cover (%)',
                    'Sunshine (s)',
                  ];

                  return Column(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height / 3,
                        width: double.infinity,
                        child: WeatherGraph(
                          xValues: selectedData,
                          times: weather.times,
                          yLabel: selectedMetric,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: metrics.map((metric) {
                            final isSelected = metric == selectedMetric;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected
                                      ? Colors.blue
                                      : Colors.grey[300],
                                  foregroundColor: isSelected
                                      ? Colors.white
                                      : Colors.black,
                                ),
                                onPressed: () => updateGraph(metric, weather),
                                child: Text(metric),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            const SizedBox(height: 10),

            _buildActionButton(
              label: 'Start New Scan',
              icon: Icons.play_arrow,
              onTap: widget.onNavScan,
              isPrimary: true,
            ),

            const SizedBox(height: 10),

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'UPLOAD SCAN',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            _buildActionButton(
              label: 'Upload New Scan',
              icon: Icons.cloud_upload,
              onTap: _importFolder,
              isPrimary: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return Material(
      color: isPrimary ? Colors.blue : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: isPrimary ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isPrimary ? null : Border.all(color: Colors.blue, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isPrimary ? Colors.white : Colors.black),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
