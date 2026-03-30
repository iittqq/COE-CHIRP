import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class ChartScreen extends StatelessWidget {
  final List<List<dynamic>> data;

  const ChartScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final filtered = data.skip(1).where((row) => row.length >= 4).toList();

    final rawSpots = filtered.map((row) {
      final timestamp = double.tryParse(row[4].toString()) ?? 0;
      final depth =
          (double.tryParse(row[2].toString()) ?? 0) * 100; // convert to cm
      return FlSpot(timestamp, depth);
    }).toList();

    final maxDepthCm = rawSpots.map((e) => e.y).reduce(max);

    final spots = rawSpots.map((e) => FlSpot(e.x, maxDepthCm - e.y)).toList();

    final rawMinY = spots.map((e) => e.y).reduce(min);
    final rawMaxY = spots.map((e) => e.y).reduce(max);

    final minY = ((rawMinY / 5).floor() * 5) - 5;
    final maxY = ((rawMaxY / 5).ceil() * 5) + 5;
    final minX = spots.isNotEmpty ? spots.map((e) => e.x).reduce(min) : 0;
    final maxX = spots.isNotEmpty ? spots.map((e) => e.x).reduce(max) : 1;

    final normalizedSpots = spots.map((e) => FlSpot(e.x - minX, e.y)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Depth over Time')),
      body: Column(
        children: [
          const SizedBox(),
          SizedBox(
            height: 350,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 10, 20, 5),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (maxX - minX).toDouble(),
                  minY: minY.toDouble(),
                  maxY: maxY.toDouble(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      axisNameWidget: const Padding(
                        padding: EdgeInsets.only(),
                        child: Text(
                          'Depth (cm)',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 25,
                        getTitlesWidget: (value, _) {
                          final depthCm = (maxDepthCm - value).toStringAsFixed(
                            0,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: Text(
                              depthCm,
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameWidget: const Padding(
                        padding: EdgeInsets.only(),
                        child: Text(
                          'Time (mm:ss)',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: ((maxX - minX) / 5).toDouble(),
                        getTitlesWidget: (value, _) {
                          final label = formatElapsed(value / 1000);
                          return Transform.rotate(
                            angle: -pi / 4,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      axisNameSize: 30,
                      axisNameWidget: const Center(
                        child: Text(
                          'Depth of mudline over time',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((spot) {
                          final realDepth = (maxDepthCm - spot.y)
                              .toStringAsFixed(0);
                          final elapsed = formatElapsed(spot.x / 1000);

                          return LineTooltipItem(
                            '$realDepth cm\n$elapsed',
                            const TextStyle(color: Colors.white),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: normalizedSpots,
                      isCurved: false,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }

  String formatTimestamp(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return "${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String formatElapsed(double seconds) {
    final s = seconds.toInt();
    final mins = (s / 60).floor();
    final remSecs = s % 60;
    return "${mins}m : ${remSecs}s";
  }
}
