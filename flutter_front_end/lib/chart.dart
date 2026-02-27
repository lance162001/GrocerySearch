import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart' show PricePoint;

class BarChartSample4 extends StatefulWidget {
  BarChartSample4({super.key});

  final Color dark = Colors.cyan.shade800;
  final Color normal = Colors.cyan.shade500;
  final Color light = Colors.cyan.shade200;
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
      return Center(child: Text('No price history'));
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

    // Small padding so line doesn't sit on graph edge
    final yPadding = (maxY - minY) * 0.1;
    final minYDisplay = (minY.isFinite) ? (minY - yPadding) : 0.0;
    final maxYDisplay = (maxY.isFinite) ? (maxY + yPadding) : 1.0;

    return AspectRatio(
      aspectRatio: 1.8,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: LineChart(
          LineChartData(
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                tooltipBgColor: Colors.grey.shade800.withOpacity(0.9),
                getTooltipItems: (touchedSpots) => touchedSpots.map((t) {
                  final pp = aggEntries[t.x.toInt()];
                  final metric = _metricForPoint(pp);
                  final date = aggDates[t.x.toInt()];
                  final unitText = metric.unit != null ? '/${metric.unit}' : '';
                  final label = "${_formatCurrency(t.y)}$unitText\n${date.month}/${date.day}/${date.year}";
                  return LineTooltipItem(label, const TextStyle(color: Colors.white, fontSize: 12));
                }).toList(),
              ),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= aggDates.length) return const SizedBox.shrink();
                    final d = aggDates[i];
                    return SideTitleWidget(axisSide: meta.axisSide, child: Text('${d.month}/${d.day}/${d.year % 100}', style: const TextStyle(fontSize: 10)));
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, meta) {
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(_formatCurrency(value), style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            minY: minYDisplay,
            maxY: maxYDisplay,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                dotData: FlDotData(show: true),
                belowBarData: BarAreaData(show: true, color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
                color: Theme.of(context).colorScheme.primary,
                barWidth: 2,
              )
            ],
          ),
        ),
      ),
    );
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
      axisSide: meta.axisSide,
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
      axisSide: meta.axisSide,
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
