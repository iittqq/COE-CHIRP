import 'dart:async';
import 'package:flutter/material.dart';

enum SystemStatus { online, connecting, offline }

class SystemStatusCard extends StatefulWidget {
  final SystemStatus status;
  final String siteName;
  final VoidCallback onSendPing;
  final bool showHeader;

  const SystemStatusCard({
    super.key,
    required this.status,
    required this.siteName,
    required this.onSendPing,
    this.showHeader = true,
  });

  @override
  State<SystemStatusCard> createState() => _SystemStatusCardState();
}

class _SystemStatusCardState extends State<SystemStatusCard>
    with WidgetsBindingObserver {
  Timer? _pingTimer;
  int _elapsedSeconds = 0;
  bool _appInForeground = true;
  static const int _pingIntervalSeconds = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant SystemStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) _armTimer();
  }

  // Timer.periodic runs on the wall clock rather than the frame scheduler,
  // so this 60s check keeps firing across in-app tab switches, unlike a
  // Ticker which stalls once Flutter stops rendering frames. It's still
  // explicitly cancelled while backgrounded (see didChangeAppLifecycleState)
  // so it doesn't run at all while the app itself isn't in use.
  //
  // Pauses (without resetting the countdown) while a check is already in
  // flight (status == connecting) and resumes from where it left off once
  // settled - a brief connecting blip (e.g. a periodic reconnect attempt)
  // shouldn't keep restarting the clock, or a flaky connection would never
  // let the countdown progress long enough to fire the next check.
  void _armTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
    if (!_appInForeground || widget.status == SystemStatus.connecting) return;
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
        if (_elapsedSeconds >= _pingIntervalSeconds) {
          widget.onSendPing();
          _elapsedSeconds = 0;
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pingTimer?.cancel();
    super.dispose();
  }

  int get _remainingSeconds => _pingIntervalSeconds - _elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    final bool isOnline = widget.status == SystemStatus.online;

    Color bgColor = const Color(0xFFFEEBC8);
    Color dotColor = Colors.orange;
    Color textColor = Colors.orange.shade800;
    String statusLabel = "Connecting";

    if (isOnline) {
      bgColor = const Color(0xFFE6F9F1);
      dotColor = const Color(0xFF38A169);
      textColor = const Color(0xFF2F855A);
      statusLabel = "Online";
    } else if (widget.status == SystemStatus.offline) {
      bgColor = Colors.red.shade50;
      dotColor = Colors.red;
      textColor = Colors.red.shade800;
      statusLabel = "Offline";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12, right: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // The title is skipped in contexts (like the Home carousel)
              // that already show a "System Status" section header once,
              // above every card - but the per-card countdown still needs
              // to render there.
              if (widget.showHeader)
                const Text(
                  "System Status",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                )
              else
                const SizedBox.shrink(),
              Text(
                '$_remainingSeconds',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.wifi_tethering,
                        color: Colors.blue.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        "Connection",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A202C),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.siteName,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A202C),
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
