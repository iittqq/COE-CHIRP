import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
    debugPrint("Connecting to $uri ...");

    try {
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;

      _listener = _channel!.stream.listen(
        (event) {
          try {
            final decoded = jsonDecode(event);
            _incomingController.add(decoded);
          } catch (e) {
            debugPrint("Invalid message: $event");
          }
        },
        onError: (error) {
          debugPrint("WebSocket error: $error");
          throw error;
        },
        onDone: () => debugPrint("WebSocket closed"),
      );

      debugPrint("Connected to WebSocket ✅");
    } catch (e) {
      debugPrint("Connection protocol failed: $e");
      rethrow;
    }
  }

  void sendCommand(Map<String, dynamic> command) {
    if (_channel == null) {
      debugPrint("WebSocket not connected.");
      return;
    }
    final payload = jsonEncode(command);
    _channel!.sink.add(payload);
    debugPrint("Sent: $payload");
  }

  Future<void> disconnect() async {
    await _listener?.cancel();
    await _channel?.sink.close(status.normalClosure);
    debugPrint("Disconnected WebSocket");
  }
}
