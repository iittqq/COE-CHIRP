import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/scan_repo.dart';

class ScanAnalysisPage extends StatefulWidget {
  final ScanData scan;

  const ScanAnalysisPage({super.key, required this.scan});

  @override
  State<ScanAnalysisPage> createState() => _ScanAnalysisPageState();
}

class _ScanAnalysisPageState extends State<ScanAnalysisPage> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _timeLabel(double secondsValue) {
    final totalSeconds = secondsValue.round().clamp(0, 999999);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, double>? _calcDepthStats(List<List<dynamic>> rows) {
    final depthValues = <double>[];

    for (final row in rows) {
      if (row.length < 5) continue;

      final depthMeters = _toDouble(row[2]);
      if (depthMeters == null) continue;

      depthValues.add(depthMeters * 100);
    }

    if (depthValues.isEmpty) return null;

    final sum = depthValues.reduce((a, b) => a + b);
    final avg = sum / depthValues.length;
    final min = depthValues.reduce((a, b) => a < b ? a : b);
    final max = depthValues.reduce((a, b) => a > b ? a : b);

    return {'avg': avg, 'min': min, 'max': max};
  }

  List<FlSpot> _graphSpots(List<List<dynamic>> rows) {
    final validRows = rows.where((row) => row.length >= 5).toList();
    if (validRows.isEmpty) return [];

    final points = <FlSpot>[];

    for (final row in validRows) {
      final depthMeters = _toDouble(row[2]);
      final timestampMs = _toDouble(row[4]);

      if (depthMeters == null || timestampMs == null) continue;

      final depthCm = depthMeters * 100;
      points.add(FlSpot(timestampMs, depthCm));
    }

    if (points.isEmpty) return [];

    points.sort((a, b) => a.x.compareTo(b.x));

    final firstTime = points.first.x;
    return points
        .map((point) => FlSpot((point.x - firstTime) / 1000.0, -point.y))
        .toList();
  }

  Widget _xTick(double value, TitleMeta meta) {
    if ((value - meta.min).abs() < 0.01) {
      return const SizedBox.shrink();
    }

    return SideTitleWidget(
      meta: meta,
      child: Text(
        _timeLabel(value),
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF6B7280),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _fixedYAxis({
    required double minY,
    required double maxY,
    required double interval,
    required String yLabel,
    required double graphHeight,
  }) {
    final labels = <double>[];

    double current = (minY / interval).ceil() * interval;

    while (current <= maxY + 0.0001) {
      labels.add(current);
      current += interval;
    }

    return SizedBox(
      width: 52,
      height: graphHeight,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  yLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: labels.map((value) {
                final ratio = (value - minY) / (maxY - minY);
                double top = graphHeight - (ratio * graphHeight) - 8;

                if (top < 0) top = 0;
                if (top > graphHeight - 16) top = graphHeight - 16;

                return Positioned(
                  right: 4,
                  top: top,
                  child: Text(
                    (-value).toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _graphWrap({
    required List<FlSpot> spots,
    required String emptyText,
    required String xLabel,
    required String yLabel,
    Color lineColor = const Color(0xFF06B6D4),
  }) {
    if (spots.isEmpty) {
      return SizedBox(height: 320, child: Center(child: Text(emptyText)));
    }

    double lowY = spots.first.y;
    double highY = spots.first.y;

    for (final spot in spots) {
      if (spot.y < lowY) lowY = spot.y;
      if (spot.y > highY) highY = spot.y;
    }

    final yRange = (highY - lowY).abs();
    final yPadding = yRange < 0.01 ? 1.0 : yRange * 0.08;

    final minY = lowY - yPadding;
    final maxY = highY + yPadding;

    final minX = 0.0;
    final maxX = spots.last.x <= 0 ? 1.0 : spots.last.x;

    final xRange = (maxX - minX).abs();

    final bottomStep = xRange <= 60
        ? 10.0
        : xRange <= 180
        ? 30.0
        : xRange <= 600
        ? 60.0
        : 120.0;

    const leftStep = 10.0;
    const graphHeight = 260.0;

    return SizedBox(
      height: 320,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const beforeScroll = 300.0;
          final baseWidth = constraints.maxWidth - 52;
          final seenWidth = baseWidth < 220 ? 220.0 : baseWidth;

          double fullWidth = seenWidth;
          if (xRange > beforeScroll) {
            fullWidth = seenWidth * (xRange / beforeScroll);
          }

          if (fullWidth < seenWidth) {
            fullWidth = seenWidth;
          }

          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _fixedYAxis(
                      minY: minY,
                      maxY: maxY,
                      interval: leftStep,
                      yLabel: yLabel,
                      graphHeight: graphHeight,
                    ),
                    Expanded(
                      child: RawScrollbar(
                        controller: _scrollCtrl,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 8,
                        radius: const Radius.circular(10),
                        scrollbarOrientation: ScrollbarOrientation.bottom,
                        child: SingleChildScrollView(
                          controller: _scrollCtrl,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: fullWidth,
                            height: graphHeight,
                            child: LineChart(
                              LineChartData(
                                minX: minX,
                                maxX: maxX,
                                minY: minY,
                                maxY: maxY,
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: true,
                                  verticalInterval: bottomStep,
                                  horizontalInterval: leftStep,
                                  getDrawingHorizontalLine: (value) {
                                    return const FlLine(
                                      color: Color(0xFFD1D5DB),
                                      strokeWidth: 1,
                                      dashArray: [6, 4],
                                    );
                                  },
                                  getDrawingVerticalLine: (value) {
                                    return const FlLine(
                                      color: Color(0xFFD1D5DB),
                                      strokeWidth: 1,
                                      dashArray: [6, 4],
                                    );
                                  },
                                ),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border.all(
                                    color: const Color(0xFFD1D5DB),
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  leftTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      interval: bottomStep,
                                      getTitlesWidget: _xTick,
                                    ),
                                  ),
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: spots,
                                    isCurved: true,
                                    barWidth: 2,
                                    color: lineColor,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(show: false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                xLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _depthStatsCard(List<List<dynamic>> rows) {
    final stats = _calcDepthStats(rows);

    if (stats == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Text(
          "No bathymetry stats available",
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget oneStat(String label, double value) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '$label (cm)',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          oneStat('Avg', stats['avg']!),
          oneStat('Min', stats['min']!),
          oneStat('Max', stats['max']!),
        ],
      ),
    );
  }

  Widget _depthChart(List<List<dynamic>> rows) {
    final spots = _graphSpots(rows);

    return _graphWrap(
      spots: spots,
      emptyText: "No bathymetry chart data",
      xLabel: "Scan Duration (mm:ss)",
      yLabel: "Depth (cm)",
    );
  }

  @override
  Widget build(BuildContext context) {
    final bathymetryRows = widget.scan.bathymetryRows;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Ionicons.chevron_back_outline),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Scan Analysis",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Ionicons.share_outline),
            onPressed: () {},
          ),
        ],
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _scanInfoCard(),
          const SizedBox(height: 14),
          const Text(
            "Depth Data",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          _depthStatsCard(bathymetryRows),
          const SizedBox(height: 14),
          _sectionCard(
            title: "Bathymetry Data",
            subtitle: "Bathymetry depth over scan time",
            child: _depthChart(bathymetryRows),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Text(
                "Notes",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              Spacer(),
              Icon(Ionicons.menu_outline, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          _notesBox(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _scanInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          _infoLine("Scan Name", widget.scan.title),
          _infoLine("Date, Time", widget.scan.time),
          _infoLine("Duration", widget.scan.duration),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _notesBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          TextField(
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "Notes, site conditions, issues...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
            },
            child: const Text("Save Note"),
          ),
        ],
      ),
    );
  }
}
