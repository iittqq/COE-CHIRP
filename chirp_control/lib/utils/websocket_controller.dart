import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WebSocketService {
  final String deviceId;
  final String apiUrl;

  WebSocketChannel? _channel;
  StreamSubscription? _listener;

  WebSocketService({
    required this.deviceId,
    this.apiUrl = "wss://ywh1uzhhk9.execute-api.us-east-2.amazonaws.com/test",
  });

  final _incomingController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _incomingController.stream;

  Future<void> connect() async {
    final uri = Uri.parse("$apiUrl?deviceId=$deviceId");
    print("Connecting to $uri ...");

    try {
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;

      _listener = _channel!.stream.listen(
        (event) {
          try {
            final decoded = jsonDecode(event);
            _incomingController.add(decoded);
          } catch (e) {
            print("Invalid message: $event");
          }
        },
        onError: (error) {
          print("WebSocket error: $error");
          throw error;
        },
        onDone: () => print("WebSocket closed"),
      );

      print("Connected to WebSocket ✅");
    } catch (e) {
      print("Connection protocol failed: $e");
      rethrow;
    }
  }

  void sendCommand(Map<String, dynamic> command) {
    if (_channel == null) {
      print("WebSocket not connected.");
      return;
    }
    final payload = jsonEncode(command);
    _channel!.sink.add(payload);
    print("Sent: $payload");
  }

  Future<void> disconnect() async {
    await _listener?.cancel();
    await _channel?.sink.close(status.normalClosure);
    print("Disconnected WebSocket");
  }
}
