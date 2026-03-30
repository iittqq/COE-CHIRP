import 'package:flutter/material.dart';

enum SystemStatus { online, connecting, offline }

class SystemStatusCard extends StatelessWidget {
  final SystemStatus status;
  final String siteName;

  const SystemStatusCard({
    super.key,
    required this.status,
    required this.siteName,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOnline = status == SystemStatus.online;
    final bool isConnecting = status == SystemStatus.connecting;

    Color bgColor = const Color(0xFFFEEBC8);
    Color dotColor = Colors.orange;
    Color textColor = Colors.orange.shade800;
    String statusLabel = "Connecting";

    if (isOnline) {
      bgColor = const Color(0xFFE6F9F1);
      dotColor = const Color(0xFF38A169);
      textColor = const Color(0xFF2F855A);
      statusLabel = "Online";
    } else if (status == SystemStatus.offline) {
      bgColor = Colors.red.shade50;
      dotColor = Colors.red;
      textColor = Colors.red.shade800;
      statusLabel = "Offline";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            "System Status",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
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
                siteName,
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
