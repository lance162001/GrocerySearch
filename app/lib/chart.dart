import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/models/grocery_models.dart';

class BarChartSample4 extends StatefulWidget {
  BarChartSample4({super.key});

  final Color dark = const Color(0xFF312E81);
  final Color normal = const Color(0xFF6366F1);
  final Color light = const Color(0xFFC7D2FE);
  @override
  State<StatefulWidget> createState() => BarChartSample4State();
}

/// A simple line chart widget that plots the lowest price from a list of
/// [PricePoint]s against their chronological order. Designed to be small
/// and robust for use in product detail modals.
class PriceHistoryChart extends StatelessWidget {
  final List<PricePoint> pricepoints;

  const PriceHistoryChart({super.key, required this.pricepoints});

  static const double _gramsPerOunce = 28.349523125;
  static const double _mlPerFluidOunce = 29.5735295625;

  ({double amount, String unit})? _normalizeSize(String size) {
    final raw = size.trim().toLowerCase();
    if (raw.isEmpty || raw == 'n/a' || raw == 'na') return null;

    final match = RegExp(r'(\d+(?:\.\d+)?)\s*([a-zA-Z]+(?:\s*[a-zA-Z]+)?)').firstMatch(raw);
    if (match == null) return null;

    final qty = double.tryParse(match.group(1)!);
    if (qty == null || qty <= 0) return null;

    final unitRaw = match.group(2)!.replaceAll(' ', '').toLowerCase();

    switch (unitRaw) {
      case 'oz':
      case 'ounce':
      case 'ounces':
        return (amount: qty, unit: 'oz');
      case 'lb':
      case 'lbs':
      case 'pound':
      case 'pounds':
        return (amount: qty * 16.0, unit: 'oz');
      case 'g':
      case 'gram':
      case 'grams':
        return (amount: qty / _gramsPerOunce, unit: 'oz');
      case 'kg':
      case 'kilogram':
      case 'kilograms':
        return (amount: (qty * 1000.0) / _gramsPerOunce, unit: 'oz');
      case 'floz':
      case 'fluidounce':
      case 'fluidounces':
        return (amount: qty, unit: 'fl oz');
      case 'ml':
      case 'milliliter':
      case 'milliliters':
        return (amount: qty / _mlPerFluidOunce, unit: 'fl oz');
      case 'l':
      case 'liter':
      case 'liters':
      case 'ltr':
        return (amount: (qty * 1000.0) / _mlPerFluidOunce, unit: 'fl oz');
      case 'qt':
      case 'quart':
      case 'quarts':
        return (amount: qty * 32.0, unit: 'fl oz');
      case 'pt':
      case 'pint':
      case 'pints':
        return (amount: qty * 16.0, unit: 'fl oz');
      case 'gal':
      case 'gallon':
      case 'gallons':
        return (amount: qty * 128.0, unit: 'fl oz');
      case 'ct':
      case 'count':
      case 'ea':
      case 'each':
      case 'pk':
      case 'pack':
        return (amount: qty, unit: 'ct');
      default:
        return null;
    }
  }

  ({double value, String? unit}) _metricForPoint(PricePoint point) {
    final normalized = _normalizeSize(point.size);
    if (normalized == null || normalized.amount <= 0) {
      return (value: point.lowestPrice(), unit: null);
    }
    return (value: point.lowestPrice() / normalized.amount, unit: normalized.unit);
  }

  double _priceForChart(PricePoint point) {
    return _metricForPoint(point).value;
  }

  String _formatCurrency(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    if (pricepoints.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart, size: 36, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                'No price history yet',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // Aggregate by UTC calendar day so each day has exactly one data point.
    // If multiple entries exist on the same day, keep only the latest one.
    final Map<int, PricePoint> latestByUtcDay = {};
    for (final pp in pricepoints) {
      final utc = pp.timestamp.toUtc();
      final dayKey = DateTime.utc(utc.year, utc.month, utc.day).millisecondsSinceEpoch;
      final existing = latestByUtcDay[dayKey];
        final shouldReplace = existing == null ||
          pp.timestamp.isAfter(existing.timestamp) ||
          (pp.timestamp.isAtSameMomentAs(existing.timestamp) && _priceForChart(pp) < _priceForChart(existing));
      if (shouldReplace) {
        latestByUtcDay[dayKey] = pp;
      }
    }

    // Sort aggregated entries chronologically (one per day).
    final aggEntries = latestByUtcDay.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final spots = <FlSpot>[];
    final aggDates = <DateTime>[];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (var i = 0; i < aggEntries.length; i++) {
      final pp = aggEntries[i];
      final y = _priceForChart(pp);
      spots.add(FlSpot(i.toDouble(), y));
      aggDates.add(pp.timestamp);
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    // Keep bottom date labels sparse and deterministic to avoid overlap.
    const maxDateLabels = 4;
    final labelStep = aggDates.length <= maxDateLabels
        ? 1
        : (aggDates.length / (maxDateLabels - 1)).ceil();
    final labeledIndexes = <int>{
      for (var i = 0; i < aggDates.length; i += labelStep) i,
      if (aggDates.isNotEmpty) aggDates.length - 1,
    };

    // Ensure a minimum y-range so the chart renders correctly with very few
    // data points (e.g. a single reading where minY == maxY).
    final yRange = maxY - minY;
    final yPadding = yRange > 0.001
        ? yRange * 0.2
        : (maxY > 0 ? maxY * 0.1 : 0.5);
    final minYDisplay =
        minY.isFinite ? (minY - yPadding).clamp(0.0, double.infinity) : 0.0;
    final maxYDisplay = maxY.isFinite ? (maxY + yPadding) : 1.0;

    // For very sparse data show a subtle label beneath the chart.
    final isSparse = aggEntries.length <= 3;
    final sparseNote = isSparse
        ? '${aggEntries.length} reading${aggEntries.length == 1 ? '' : 's'} available'
        : null;

    final primaryColor = Theme.of(context).colorScheme.primary;
    // Show larger dots and a wider line when there are few data points so
    // the chart has clear visual weight even with minimal data.
    final barWidth = isSparse ? 2.5 : 2.0;
    final showDots = spots.length <= 30;

    Widget chart = Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) =>
                  Colors.grey.shade800.withValues(alpha: 0.9),
              getTooltipItems: (touchedSpots) => touchedSpots.map((t) {
                final pp = aggEntries[t.x.toInt()];
                final metric = _metricForPoint(pp);
                final date = aggDates[t.x.toInt()];
                final unitText = metric.unit != null ? '/${metric.unit}' : '';
                final label =
                    '${_formatCurrency(t.y)}$unitText\n${date.month}/${date.day}/${date.year}';
                return LineTooltipItem(
                  label,
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
              left: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: labelStep.toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if ((value - i).abs() > 0.001) return const SizedBox.shrink();
                  if (i < 0 || i >= aggDates.length) {
                    return const SizedBox.shrink();
                  }
                  if (!labeledIndexes.contains(i)) {
                    return const SizedBox.shrink();
                  }
                  final d = aggDates[i];
                  return SideTitleWidget(
                    meta: meta,
                    angle: -0.5,
                    child: Text(
                      '${d.month}/${d.day}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _formatCurrency(value),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          minY: minYDisplay,
          maxY: maxYDisplay,
          minX: 0,
          maxX: spots.length <= 1
              ? 1.0
              : (spots.length - 1).toDouble(),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: spots.length > 2,
              curveSmoothness: 0.25,
              dotData: FlDotData(
                show: showDots,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: isSparse ? 4 : 2.5,
                  color: primaryColor,
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: primaryColor.withValues(alpha: 0.12),
              ),
              color: primaryColor,
              barWidth: barWidth,
            ),
          ],
        ),
      ),
    );

    if (sparseNote != null) {
      return Column(
        children: [
          Expanded(child: chart),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              sparseNote,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
            ),
          ),
        ],
      );
    }
    return chart;
  }
}

class BarChartSample4State extends State<BarChartSample4> {
  Widget bottomTitles(double value, TitleMeta meta) {
    const style = TextStyle(fontSize: 10);
    String text;
    switch (value.toInt()) {
      case 0:
        text = 'Apr';
        break;
      case 1:
        text = 'May';
        break;
      case 2:
        text = 'Jun';
        break;
      case 3:
        text = 'Jul';
        break;
      case 4:
        text = 'Aug';
        break;
      default:
        text = '';
        break;
    }
    return SideTitleWidget(
      meta: meta,
      child: Text(text, style: style),
    );
  }

  Widget leftTitles(double value, TitleMeta meta) {
    if (value == meta.max) {
      return Container();
    }
    const style = TextStyle(
      fontSize: 10,
    );
    return SideTitleWidget(
      meta: meta,
      child: Text(
        meta.formattedValue,
        style: style,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.66,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barsSpace = 4.0 * constraints.maxWidth / 400;
            final barsWidth = 8.0 * constraints.maxWidth / 400;
            return BarChart(
              BarChartData(
                alignment: BarChartAlignment.center,
                barTouchData: BarTouchData(
                  enabled: false,
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: bottomTitles,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: leftTitles,
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  checkToShowHorizontalLine: (value) => value % 10 == 0,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.brown,
                    strokeWidth: 1,
                  ),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(
                  show: false,
                ),
                groupsSpace: barsSpace,
                barGroups: getData(barsWidth, barsSpace),
              ),
            );
          },
        ),
      ),
    );
  }

  List<BarChartGroupData> getData(double barsWidth, double barsSpace) {
    return [
      BarChartGroupData(
        x: 0,
        barsSpace: barsSpace,
        barRods: [
          BarChartRodData(
            toY: 17000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 2000000000, widget.dark),
              BarChartRodStackItem(2000000000, 12000000000, widget.normal),
              BarChartRodStackItem(12000000000, 17000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 24000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 13000000000, widget.dark),
              BarChartRodStackItem(13000000000, 14000000000, widget.normal),
              BarChartRodStackItem(14000000000, 24000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 23000000000.5,
            rodStackItems: [
              BarChartRodStackItem(0, 6000000000.5, widget.dark),
              BarChartRodStackItem(6000000000.5, 18000000000, widget.normal),
              BarChartRodStackItem(18000000000, 23000000000.5, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 29000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 9000000000, widget.dark),
              BarChartRodStackItem(9000000000, 15000000000, widget.normal),
              BarChartRodStackItem(15000000000, 29000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 32000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 2000000000.5, widget.dark),
              BarChartRodStackItem(2000000000.5, 17000000000.5, widget.normal),
              BarChartRodStackItem(17000000000.5, 32000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
        ],
      ),
      BarChartGroupData(
        x: 1,
        barsSpace: barsSpace,
        barRods: [
          BarChartRodData(
            toY: 31000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 11000000000, widget.dark),
              BarChartRodStackItem(11000000000, 18000000000, widget.normal),
              BarChartRodStackItem(18000000000, 31000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 35000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 14000000000, widget.dark),
              BarChartRodStackItem(14000000000, 27000000000, widget.normal),
              BarChartRodStackItem(27000000000, 35000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 31000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 8000000000, widget.dark),
              BarChartRodStackItem(8000000000, 24000000000, widget.normal),
              BarChartRodStackItem(24000000000, 31000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 15000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 6000000000.5, widget.dark),
              BarChartRodStackItem(6000000000.5, 12000000000.5, widget.normal),
              BarChartRodStackItem(12000000000.5, 15000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 17000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 9000000000, widget.dark),
              BarChartRodStackItem(9000000000, 15000000000, widget.normal),
              BarChartRodStackItem(15000000000, 17000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
        ],
      ),
      BarChartGroupData(
        x: 2,
        barsSpace: barsSpace,
        barRods: [
          BarChartRodData(
            toY: 34000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 6000000000, widget.dark),
              BarChartRodStackItem(6000000000, 23000000000, widget.normal),
              BarChartRodStackItem(23000000000, 34000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 32000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 7000000000, widget.dark),
              BarChartRodStackItem(7000000000, 24000000000, widget.normal),
              BarChartRodStackItem(24000000000, 32000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 14000000000.5,
            rodStackItems: [
              BarChartRodStackItem(0, 1000000000.5, widget.dark),
              BarChartRodStackItem(1000000000.5, 12000000000, widget.normal),
              BarChartRodStackItem(12000000000, 14000000000.5, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 20000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 4000000000, widget.dark),
              BarChartRodStackItem(4000000000, 15000000000, widget.normal),
              BarChartRodStackItem(15000000000, 20000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 24000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 4000000000, widget.dark),
              BarChartRodStackItem(4000000000, 15000000000, widget.normal),
              BarChartRodStackItem(15000000000, 24000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
        ],
      ),
      BarChartGroupData(
        x: 3,
        barsSpace: barsSpace,
        barRods: [
          BarChartRodData(
            toY: 14000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 1000000000.5, widget.dark),
              BarChartRodStackItem(1000000000.5, 12000000000, widget.normal),
              BarChartRodStackItem(12000000000, 14000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 27000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 7000000000, widget.dark),
              BarChartRodStackItem(7000000000, 25000000000, widget.normal),
              BarChartRodStackItem(25000000000, 27000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 29000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 6000000000, widget.dark),
              BarChartRodStackItem(6000000000, 23000000000, widget.normal),
              BarChartRodStackItem(23000000000, 29000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 16000000000.5,
            rodStackItems: [
              BarChartRodStackItem(0, 9000000000, widget.dark),
              BarChartRodStackItem(9000000000, 15000000000, widget.normal),
              BarChartRodStackItem(15000000000, 16000000000.5, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
          BarChartRodData(
            toY: 15000000000,
            rodStackItems: [
              BarChartRodStackItem(0, 7000000000, widget.dark),
              BarChartRodStackItem(7000000000, 12000000000.5, widget.normal),
              BarChartRodStackItem(12000000000.5, 15000000000, widget.light),
            ],
            borderRadius: BorderRadius.zero,
            width: barsWidth,
          ),
        ],
      ),
    ];
  }
}
