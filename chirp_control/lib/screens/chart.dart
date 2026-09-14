import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ionicons_plus/ionicons_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../utils/scan_repo.dart';
import '../utils/units_repository.dart';

class ScanAnalysisPage extends StatefulWidget {
  final ScanData scan;

  const ScanAnalysisPage({super.key, required this.scan});

  @override
  State<ScanAnalysisPage> createState() => _ScanAnalysisPageState();
}

class _ScanAnalysisPageState extends State<ScanAnalysisPage> {
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _notesCtrl = TextEditingController();
  final GlobalKey _yAxisKey = GlobalKey();
  final GlobalKey _chartKey = GlobalKey();
  bool _isMetric = true;
  bool _savingNote = false;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    _notesCtrl.text = widget.scan.notes;
    loadIsMetric().then((value) {
      if (mounted) setState(() => _isMetric = value);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _shareScan() {
    final scan = widget.scan;
    SharePlus.instance.share(
      ShareParams(
        text:
            'Sonar scan "${scan.title}"\n'
            'Location: ${scan.location}\n'
            'Recorded: ${scan.time}\n'
            'Duration: ${scan.duration}\n'
            'Shared from Chirp',
      ),
    );
  }

  Future<Uint8List?> _captureBoundary(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      final scan = widget.scan;
      final stats = _calcDepthStats(scan.bathymetryRows);
      final spots = _graphSpots(scan.bathymetryRows);

      Uint8List? yAxisBytes;
      Uint8List? chartBytes;
      if (spots.isNotEmpty) {
        yAxisBytes = await _captureBoundary(_yAxisKey);
        chartBytes = await _captureBoundary(_chartKey);
      }

      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Text(
              scan.title.isEmpty ? 'Scan Analysis' : scan.title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated ${DateTime.now()}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Scan Name: ${scan.title}'),
            pw.Text('Date, Time: ${scan.time}'),
            pw.Text('Duration: ${scan.duration}'),
            pw.SizedBox(height: 12),
            if (stats != null)
              pw.Text(
                'Avg: ${stats['avg']!.toStringAsFixed(1)} ${depthUnitLabel(_isMetric)}   '
                'Min: ${stats['min']!.toStringAsFixed(1)} ${depthUnitLabel(_isMetric)}   '
                'Max: ${stats['max']!.toStringAsFixed(1)} ${depthUnitLabel(_isMetric)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              )
            else
              pw.Text('No bathymetry stats available'),
            pw.SizedBox(height: 16),
            pw.Text(
              'Bathymetry Data',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (chartBytes != null)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (yAxisBytes != null)
                    pw.Image(pw.MemoryImage(yAxisBytes), height: 130),
                  pw.Expanded(
                    child: pw.Image(
                      pw.MemoryImage(chartBytes),
                      fit: pw.BoxFit.scaleDown,
                      height: 130,
                    ),
                  ),
                ],
              )
            else
              pw.Text('No bathymetry chart data'),
            pw.SizedBox(height: 16),
            pw.Text(
              'Notes',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(_notesCtrl.text.isEmpty ? '—' : _notesCtrl.text),
          ],
        ),
      );

      final bytes = await doc.save();
      final safeTitle = scan.title.trim().isEmpty ? 'scan' : scan.title.trim();
      await Printing.sharePdf(bytes: bytes, filename: '$safeTitle-analysis.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
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

      depthValues.add(cmToDisplayUnit(depthMeters * 100, _isMetric));
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

      final depthDisplay = cmToDisplayUnit(depthMeters * 100, _isMetric);
      points.add(FlSpot(timestampMs, depthDisplay));
    }

    if (points.isEmpty) return [];

    points.sort((a, b) => a.x.compareTo(b.x));

    final firstTime = points.first.x;
    return points
        .map((point) => FlSpot((point.x - firstTime) / 1000.0, -point.y))
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

  double _niceLeftStep(double yRange) {
    const candidates = [
      1.0,
      2.0,
      5.0,
      10.0,
      20.0,
      25.0,
      50.0,
      100.0,
      200.0,
      250.0,
      500.0,
      1000.0,
    ];
    const targetTicks = 6.0;

    for (final step in candidates) {
      if (yRange / step <= targetTicks) return step;
    }

    return candidates.last;
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

    return RepaintBoundary(
      key: _yAxisKey,
      child: Container(
        color: Colors.white,
        child: SizedBox(
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
        ),
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

    final leftStep = _niceLeftStep(maxY - minY);
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
          fullWidth = fullWidth < spots.length * minPxPerPoint
              ? spots.length * minPxPerPoint
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
                          child: RepaintBoundary(
                            key: _chartKey,
                            child: Container(
                            color: Colors.white,
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
                                lineBarsData: _splitSpotsAtGaps(spots)
                                    .map(
                                      (segment) => LineChartBarData(
                                        spots: segment,
                                        isCurved: true,
                                        barWidth: 2,
                                        color: lineColor,
                                        dotData: const FlDotData(show: false),
                                        belowBarData: BarAreaData(show: false),
                                      ),
                                    )
                                    .toList(),
                              ),
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
              '$label (${depthUnitLabel(_isMetric)})',
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
      yLabel: "Depth (${depthUnitLabel(_isMetric)})",
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
            icon: _exportingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportingPdf ? null : _exportPdf,
          ),
          IconButton(
            icon: const Icon(Ionicons.share_outline),
            onPressed: _shareScan,
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
          const Text(
            "Notes",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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

  Future<void> _saveNote() async {
    FocusScope.of(context).unfocus();
    setState(() => _savingNote = true);
    try {
      await ScanRepository.saveNotes(widget.scan, _notesCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save note: $e')));
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
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
            controller: _notesCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "Notes, site conditions, issues...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _savingNote ? null : _saveNote,
            child: _savingNote
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Save Note"),
          ),
        ],
      ),
    );
  }
}
