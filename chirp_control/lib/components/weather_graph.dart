import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class WeatherGraph extends StatelessWidget {
  final List<double> xValues;
  final List<String> times;
  final String yLabel;

  const WeatherGraph({
    super.key,
    required this.xValues,
    required this.times,
    required this.yLabel,
  });

  @override
  Widget build(BuildContext context) {
    final values = xValues;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);

    final diff = max - min;
    final padding = diff == 0 ? 1.0 : diff * 0.1;
    double chartMin = 0;
    if (min == 0) {
      chartMin = min;
    } else {
      chartMin = min - padding;
    }

    double chartMax = 0;
    if (max == 0) {
      chartMax = 5;
    } else {
      chartMax = max + padding;
    }

    return AspectRatio(
      aspectRatio: 1.70,
      child: Padding(
        padding: const EdgeInsets.only(right: 15, left: 5, top: 24, bottom: 12),
        child: LineChart(chartData(chartMin, chartMax)),
      ),
    );
  }

  Widget bottomTimeLabel(double value, TitleMeta meta) {
    final index = value.toInt();
    if (index < 0 || index >= times.length) {
      return const SizedBox();
    }

    return SideTitleWidget(
      meta: meta,
      child: Text(
        times[index].substring(11, 16),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget leftValueLabel(double value, TitleMeta meta) {
    return Text(
      value.toStringAsFixed(0),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      textAlign: TextAlign.center,
    );
  }

  LineChartData chartData(double min, double max) {
    final rawInterval = (max - min) / 5;
    final interval = rawInterval == 0 ? 1.0 : rawInterval;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        verticalInterval: 1.0,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Color(0xFF37434D), strokeWidth: 1),
        getDrawingVerticalLine: (_) =>
            const FlLine(color: Color(0xFF37434D), strokeWidth: 1),
      ),

      titlesData: FlTitlesData(
        show: true,

        leftTitles: AxisTitles(
          axisNameWidget: Text(
            yLabel,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          axisNameSize: 20,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            interval: interval,
            getTitlesWidget: leftValueLabel,
          ),
        ),

        bottomTitles: AxisTitles(
          axisNameWidget: Text(
            "Time",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          axisNameSize: 20,
          sideTitles: SideTitles(
            showTitles: true,
            interval: (times.length / 6).floorToDouble().clamp(1.0, 9999.0),
            reservedSize: 20,
            getTitlesWidget: bottomTimeLabel,
          ),
        ),

        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),

      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d)),
      ),

      minX: 0,
      maxX: (xValues.length - 1).toDouble(),
      minY: (min / interval).floor() * interval,
      maxY: (max / interval).ceil() * interval,

      lineBarsData: [
        LineChartBarData(
          spots: List.generate(
            xValues.length,
            (i) => FlSpot(i.toDouble(), xValues[i]),
          ),
          isCurved: true,
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          gradient: const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: const [
                Color(0xFF00E5FF),
                Color(0xFF0091EA),
              ].map((c) => c.withValues(alpha: 0.25)).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
