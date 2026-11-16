import 'package:flutter/material.dart';
import 'package:ionicons_plus/ionicons_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/acquisition.dart';
import '../utils/depth_processing.dart';
import '../utils/scan_repo.dart';
import '../utils/units_repository.dart';

class CompareScansPage extends StatefulWidget {
  final List<ScanData> scans;

  const CompareScansPage({super.key, required this.scans});

  @override
  State<CompareScansPage> createState() => _CompareScansPageState();
}

class _CompareScansPageState extends State<CompareScansPage> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _isMetric = true;

  final List<Color> _colors = const [
    Color(0xFF1F77B4),
    Color(0xFFFF7F0E),
    Color(0xFF2CA02C),
    Color(0xFFD62728),
    Color(0xFF9467BD),
  ];

  @override
  void initState() {
    super.initState();
    loadIsMetric().then((value) {
      if (mounted) setState(() => _isMetric = value);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _shareComparison() {
    final titles = widget.scans.map((s) => s.title).join(', ');
    SharePlus.instance.share(
      ShareParams(
        text:
            'Comparing ${widget.scans.length} sonar scans: $titles\n'
            'Shared from Chirp',
      ),
    );
  }

  String _timeLabel(double secondsValue) {
    final totalSeconds = secondsValue.round().clamp(0, 999999);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Same processing as the analysis screen and the web app
  // (lib/utils/depth_processing.dart).
  ProcessedScan? _processed(ScanData scan) => tryProcessBathymetry(
    scan.bathymetryRows,
    blindSpotOffsetCm: acquisitionNumber(scan.acquisition, 'blindSpotOffsetCm'),
  ).scan;

  double? _calcSettledDepth(ScanData scan) {
    final p = _processed(scan);
    final settled = p == null ? null : settledDepth(p);
    return settled == null ? null : cmToDisplayUnit(settled.depthCm, _isMetric);
  }

  // Signed: settled depth of the chronologically latest scan minus the
  // earliest. Negative = mudline rose toward the sonar.
  ({double change, String from, String to, String meaning})? _calcChange() {
    final valid = <ScanData>[];
    final processed = <ProcessedScan>[];
    for (final scan in widget.scans) {
      final p = _processed(scan);
      if (p == null) continue;
      valid.add(scan);
      processed.add(p);
    }
    final result = depthChange(processed);
    if (result == null) return null;
    return (
      change: cmToDisplayUnit(result.changeCm, _isMetric),
      from: valid[result.earliestIndex].title,
      to: valid[result.latestIndex].title,
      meaning: describeDepthChange(result.changeCm),
    );
  }

  List<FlSpot> _graphSpots(ScanData scan) {
    final p = _processed(scan);
    if (p == null) return [];
    return depthSeries(p)
        .map(
          (pt) => FlSpot(pt.seconds, -cmToDisplayUnit(pt.depthCm, _isMetric)),
        )
        .toList();
  }

  List<List<FlSpot>> _splitSpotsAtGaps(List<FlSpot> spots) {
    if (spots.length < 3) return [spots];

    final deltas = <double>[];
    for (var i = 1; i < spots.length; i++) {
      deltas.add(spots[i].x - spots[i - 1].x);
    }

    final sortedDeltas = [...deltas]..sort();
    final median = sortedDeltas[sortedDeltas.length ~/ 2];
    final threshold = median * 3.0 < 1.0 ? 1.0 : median * 3.0;

    final segments = <List<FlSpot>>[];
    var current = <FlSpot>[spots.first];

    for (var i = 1; i < spots.length; i++) {
      if (deltas[i - 1] > threshold) {
        segments.add(current);
        current = <FlSpot>[];
      }
      current.add(spots[i]);
    }
    segments.add(current);

    return segments;
  }

  double _niceBottomStep(double xRange, double fullWidth) {
    const candidates = [
      5.0,
      10.0,
      15.0,
      20.0,
      30.0,
      45.0,
      60.0,
      90.0,
      120.0,
      180.0,
      240.0,
      300.0,
      450.0,
      600.0,
      900.0,
      1200.0,
      1800.0,
      2700.0,
      3600.0,
      5400.0,
      7200.0,
      10800.0,
    ];
    const targetPxPerLabel = 65.0;

    final pxPerSecond = fullWidth / xRange;
    final minStepForSpacing = targetPxPerLabel / pxPerSecond;

    for (final step in candidates) {
      if (step >= minStepForSpacing) return step;
    }

    return candidates.last;
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
    required List<LineChartBarData> bars,
    required String emptyText,
    required String xLabel,
    required String yLabel,
  }) {
    if (bars.isEmpty) {
      return SizedBox(height: 320, child: Center(child: Text(emptyText)));
    }

    final graphSpots = bars.expand((b) => b.spots).toList();

    double lowY = graphSpots.first.y;
    double highY = graphSpots.first.y;

    for (final spot in graphSpots) {
      if (spot.y < lowY) lowY = spot.y;
      if (spot.y > highY) highY = spot.y;
    }

    final range = (highY - lowY).abs();
    final extraSpace = range < 0.01 ? 1.0 : range * 0.08;

    final minY = lowY - extraSpace;
    final maxY = highY + extraSpace;

    final minX = 0.0;
    double maxX = 1.0;
    for (final spot in graphSpots) {
      if (spot.x > maxX) maxX = spot.x;
    }

    final xRange = (maxX - minX).abs();

    const leftStep = 10.0;
    const graphHeight = 260.0;

    return SizedBox(
      height: 320,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minPxPerSecond = 8.0;
          const minPxPerPoint = 3.0;
          const maxFullWidth = 20000.0;
          final baseWidth = constraints.maxWidth - 52;
          final seenWidth = baseWidth < 220 ? 220.0 : baseWidth;

          double fullWidth = seenWidth;
          fullWidth = fullWidth < xRange * minPxPerSecond
              ? xRange * minPxPerSecond
              : fullWidth;
          fullWidth = fullWidth < graphSpots.length * minPxPerPoint
              ? graphSpots.length * minPxPerPoint
              : fullWidth;
          if (fullWidth > maxFullWidth) fullWidth = maxFullWidth;

          final bottomStep = _niceBottomStep(xRange, fullWidth);

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
                                lineTouchData: LineTouchData(
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipItems: (touchedSpots) {
                                      return touchedSpots.map((spot) {
                                        return LineTooltipItem(
                                          '${(-spot.y).toStringAsFixed(2)} ${depthUnitLabel(_isMetric)}',
                                          const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        );
                                      }).toList();
                                    },
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
                                lineBarsData: bars,
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

  Widget _buildChart() {
    final bars = <LineChartBarData>[];

    for (int i = 0; i < widget.scans.length; i++) {
      final spots = _graphSpots(widget.scans[i]);
      if (spots.isEmpty) continue;

      final color = _colors[i % _colors.length];

      for (final segment in _splitSpotsAtGaps(spots)) {
        bars.add(
          LineChartBarData(
            spots: segment,
            isCurved: true,
            barWidth: 2,
            color: color,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }

    return _graphWrap(
      bars: bars,
      emptyText: "No bathymetry chart data",
      xLabel: "Scan Duration (mm:ss)",
      yLabel: "Depth (${depthUnitLabel(_isMetric)})",
    );
  }

  Widget _topStats() {
    final change = _calcChange();

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
          const Text(
            "Depth Change",
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            change != null
                ? "${change.change > 0 ? '+' : ''}${change.change.toStringAsFixed(2)} "
                      "${depthUnitLabel(_isMetric)} (${change.meaning})"
                : "—",
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            change != null
                ? "Settled depth of ${change.to} (latest) minus ${change.from} "
                      "(earliest). Settled = mean of the last ${settledWindowS}s. "
                      "Negative = mudline rose."
                : "Needs at least two scans with bathymetry data.",
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in widget.scans.asMap().entries)
            Builder(
              builder: (context) {
                final i = entry.key;
                final scan = entry.value;
                final settled = _calcSettledDepth(scan);
                final color = _colors[i % _colors.length];

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i == widget.scans.length - 1 ? 0 : 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scan.title,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        settled != null
                            ? "${settled.toStringAsFixed(2)} ${depthUnitLabel(_isMetric)}"
                            : "—",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
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

  @override
  Widget build(BuildContext context) {
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
            onPressed: _shareComparison,
          ),
        ],
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Depth Data",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          _topStats(),
          const SizedBox(height: 14),
          _sectionCard(
            title: "Bathymetry Data",
            subtitle: "Bathymetry depth over scan time",
            child: _buildChart(),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
