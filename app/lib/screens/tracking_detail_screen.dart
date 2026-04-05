import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class TrackingDetailScreen extends StatefulWidget {
  final int productId;
  const TrackingDetailScreen({super.key, required this.productId});

  @override
  State<TrackingDetailScreen> createState() => _TrackingDetailScreenState();
}

class _TrackingDetailScreenState extends State<TrackingDetailScreen> {
  TrackedItemDetail? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<MarkupState>();
    if (state.currentUserId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await state.api.fetchTrackedDetail(state.currentUserId!, widget.productId);
      if (!mounted) return;
      setState(() { _detail = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.productName ?? 'Price History'),
        backgroundColor: Colors.white,
        foregroundColor: MarkupColors.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: MarkupColors.darkGreen))
          : _detail == null
              ? const Center(child: Text('Sign in to view price history', style: TextStyle(color: MarkupColors.textSecondary)))
              : _buildContent(_detail!),
    );
  }

  Widget _buildContent(TrackedItemDetail detail) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Price history chart
        if (detail.priceHistory.isNotEmpty) ...[
          const Text('Price history (90 days)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: MarkupColors.textSecondary)),
          const SizedBox(height: 8),
          _PriceChart(history: detail.priceHistory),
          const SizedBox(height: 24),
        ],
        // Current prices by store
        const Text('Current prices', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: MarkupColors.textSecondary)),
        const SizedBox(height: 8),
        ...detail.allStorePrices.map((p) {
          final price = (p['price'] as num?)?.toDouble() ?? 0.0;
          final chain = p['chain'] as String? ?? '';
          final isBest = p['is_best'] == true;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isBest ? MarkupColors.bgGreen : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isBest ? MarkupColors.lightGreen : const Color(0xFFEEEEEE)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(chain, style: TextStyle(fontSize: 14, fontWeight: isBest ? FontWeight.w700 : FontWeight.w500, color: MarkupColors.textPrimary))),
                if (isBest)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: MarkupColors.darkGreen, borderRadius: BorderRadius.circular(4)),
                    child: const Text('BEST', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                Text('\$${price.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isBest ? MarkupColors.darkGreen : MarkupColors.textPrimary)),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
        // Actions
        OutlinedButton.icon(
          onPressed: () async {
            final state = context.read<MarkupState>();
            if (state.currentUserId != null) {
              try { await state.api.untrackProduct(state.currentUserId!, widget.productId); } catch (_) {}
            }
            state.untrackProductLocally(widget.productId);
            if (mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.notifications_off_outlined),
          label: const Text('Stop tracking'),
          style: OutlinedButton.styleFrom(foregroundColor: MarkupColors.textSecondary),
        ),
      ],
    );
  }
}

class _PriceChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _PriceChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final prices = history.map((h) => (h['price'] as num?)?.toDouble() ?? 0.0).toList();
    if (prices.isEmpty) return const SizedBox.shrink();

    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final range = maxPrice - minPrice;

    return SizedBox(
      height: 120,
      child: CustomPaint(
        painter: _LineChartPainter(prices: prices, min: minPrice, range: range == 0 ? 1 : range),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> prices;
  final double min;
  final double range;

  _LineChartPainter({required this.prices, required this.min, required this.range});

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;

    final paint = Paint()
      ..color = MarkupColors.darkGreen
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < prices.length; i++) {
      final x = size.width * i / (prices.length - 1);
      final y = size.height - size.height * (prices[i] - min) / range;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Draw dots
    final dotPaint = Paint()..color = MarkupColors.darkGreen..style = PaintingStyle.fill;
    for (int i = 0; i < prices.length; i++) {
      final x = size.width * i / (prices.length - 1);
      final y = size.height - size.height * (prices[i] - min) / range;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.prices != prices;
}
