import 'package:flutter/material.dart';
import 'package:ionicons_plus/ionicons_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/isp_repo.dart';

// Cap how many rows get built into the on-screen DataTable - ISP workbooks
// could have thousands of rows, and an unvirtualized DataTable of that size
// would be slow to build/scroll. The chart itself still uses every row.
const _maxTableRows = 200;

const _seriesColors = [
  Color(0xFF2a78d6),
  Color(0xFFeb6834),
  Color(0xFF1baf7a),
  Color(0xFFeda100),
  Color(0xFFe87ba4),
];

class IspAnalysisPage extends StatefulWidget {
  final IspData record;

  const IspAnalysisPage({super.key, required this.record});

  @override
  State<IspAnalysisPage> createState() => _IspAnalysisPageState();
}

class _IspAnalysisPageState extends State<IspAnalysisPage> {
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _notesCtrl = TextEditingController();
  bool _savingNote = false;

  late int _xIndex;
  late Set<int> _selectedY;

  @override
  void initState() {
    super.initState();
    _notesCtrl.text = widget.record.notes;
    _xIndex = 0;
    _selectedY = _autoDetectNumericColumns();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _isNumeric(dynamic value) {
    if (value == null) return false;
    if (value is num) return true;
    return double.tryParse(value.toString()) != null;
  }

  Set<int> _autoDetectNumericColumns() {
    final rows = widget.record.rows;
    final headers = widget.record.headers;
    final result = <int>{};

    for (var col = 0; col < headers.length; col++) {
      var numericCount = 0;
      var seenCount = 0;

      for (final row in rows) {
        if (col >= row.length || row[col] == null) continue;
        seenCount++;
        if (_isNumeric(row[col])) numericCount++;
      }

      if (seenCount > 0 && numericCount / seenCount > 0.5 && col != _xIndex) {
        result.add(col);
      }
    }

    return result;
  }

  double? _numericAt(int row, int col) {
    final rows = widget.record.rows;
    if (row >= rows.length || col >= rows[row].length) return null;
    final value = rows[row][col];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  double _niceStep(double range, {double targetTicks = 8}) {
    const candidates = [
      1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0,
      1000.0, 2000.0, 5000.0, 10000.0,
    ];
    for (final step in candidates) {
      if (range / step <= targetTicks) return step;
    }
    return candidates.last;
  }

  String _xLabelAt(int index) {
    final rows = widget.record.rows;
    if (index < 0 || index >= rows.length || _xIndex >= rows[index].length) {
      return '';
    }
    final value = rows[index][_xIndex];
    return value?.toString() ?? '';
  }

  Widget _chart() {
    final rows = widget.record.rows;
    final ySelection = _selectedY.toList()..sort();

    if (ySelection.isEmpty || rows.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('No numeric columns selected')),
      );
    }

    final bars = <LineChartBarData>[];
    double lowY = double.infinity;
    double highY = double.negativeInfinity;

    for (var s = 0; s < ySelection.length; s++) {
      final col = ySelection[s];
      final spots = <FlSpot>[];

      for (var r = 0; r < rows.length; r++) {
        final v = _numericAt(r, col);
        if (v == null) continue;
        spots.add(FlSpot(r.toDouble(), v));
        if (v < lowY) lowY = v;
        if (v > highY) highY = v;
      }

      if (spots.isEmpty) continue;

      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          barWidth: 2,
          color: _seriesColors[s % _seriesColors.length],
          dotData: FlDotData(show: rows.length < 40),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    if (bars.isEmpty || !lowY.isFinite || !highY.isFinite) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('No numeric data in selected columns')),
      );
    }

    final yRange = (highY - lowY).abs();
    final yPadding = yRange < 0.01 ? 1.0 : yRange * 0.08;
    final minY = lowY - yPadding;
    final maxY = highY + yPadding;
    final leftStep = _niceStep(maxY - minY);

    final maxX = (rows.length - 1).toDouble().clamp(1.0, double.infinity);
    final bottomStep = _niceStep(maxX);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (var s = 0; s < ySelection.length; s++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _seriesColors[s % _seriesColors.length],
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.record.headers[ySelection[s]],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const minPxPerPoint = 4.0;
              final baseWidth = constraints.maxWidth;
              var fullWidth = baseWidth < 220 ? 220.0 : baseWidth;
              fullWidth = fullWidth < rows.length * minPxPerPoint
                  ? rows.length * minPxPerPoint
                  : fullWidth;
              if (fullWidth > 20000) fullWidth = 20000;

              return RawScrollbar(
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
                    height: 260,
                    child: LineChart(
                      LineChartData(
                        minX: 0.0,
                        maxX: maxX,
                        minY: minY,
                        maxY: maxY,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          verticalInterval: bottomStep,
                          horizontalInterval: leftStep,
                          getDrawingHorizontalLine: (value) => const FlLine(
                            color: Color(0xFFD1D5DB),
                            strokeWidth: 1,
                            dashArray: [6, 4],
                          ),
                          getDrawingVerticalLine: (value) => const FlLine(
                            color: Color(0xFFD1D5DB),
                            strokeWidth: 1,
                            dashArray: [6, 4],
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                final label = _xLabelAt(spot.x.round());
                                return LineTooltipItem(
                                  '${label.isNotEmpty ? '$label: ' : ''}${spot.y.toStringAsFixed(2)}',
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
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: leftStep,
                              reservedSize: 44,
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              interval: bottomStep,
                              getTitlesWidget: (value, meta) {
                                final label = _xLabelAt(value.round());
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    label.length > 10
                                        ? '${label.substring(0, 10)}…'
                                        : label,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: bars,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.record.headers[_xIndex],
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _columnControls() {
    final headers = widget.record.headers;

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
            'X-Axis Column',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButton<int>(
            value: _xIndex,
            isExpanded: true,
            items: [
              for (var i = 0; i < headers.length; i++)
                DropdownMenuItem(value: i, child: Text(headers[i])),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _xIndex = value;
                _selectedY.remove(value);
              });
            },
          ),
          const SizedBox(height: 14),
          const Text(
            'Y-Axis Columns',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < headers.length; i++)
                if (i != _xIndex)
                  FilterChip(
                    label: Text(headers[i]),
                    selected: _selectedY.contains(i),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedY.add(i);
                        } else {
                          _selectedY.remove(i);
                        }
                      });
                    },
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dataTable() {
    final headers = widget.record.headers;
    final rows = widget.record.rows;
    final shown = rows.length > _maxTableRows
        ? rows.sublist(0, _maxTableRows)
        : rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [for (final h in headers) DataColumn(label: Text(h))],
            rows: [
              for (final row in shown)
                DataRow(
                  cells: [
                    for (var i = 0; i < headers.length; i++)
                      DataCell(Text(i < row.length ? (row[i]?.toString() ?? '') : '')),
                  ],
                ),
            ],
          ),
        ),
        if (rows.length > _maxTableRows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing first $_maxTableRows of ${rows.length} rows',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          _infoLine('File Name', widget.record.fileName),
          _infoLine('Uploaded', widget.record.time),
          _infoLine('Rows', widget.record.rows.length.toString()),
          _infoLine('Columns', widget.record.headers.length.toString()),
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
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
      await IspRepository.saveIspNotes(widget.record, _notesCtrl.text);
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

  @override
  Widget build(BuildContext context) {
    final headers = widget.record.headers;

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
          "ISP Data",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      body: headers.isEmpty
          ? const Center(child: Text('This workbook has no readable data.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _infoCard(),
                const SizedBox(height: 14),
                const Text(
                  "Chart",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 10),
                _columnControls(),
                const SizedBox(height: 14),
                _sectionCard(
                  title: "Column Data",
                  subtitle: "Selected columns plotted against ${headers[_xIndex]}",
                  child: _chart(),
                ),
                const SizedBox(height: 14),
                const Text(
                  "Data Table",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: _dataTable(),
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
}
