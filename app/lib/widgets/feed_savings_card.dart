import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FeedSavingsCard extends StatelessWidget {
  final List<Map<String, dynamic>> items; // [{product_name, brand, best_chain, best_price, worst_chain, worst_price, diff}]

  const FeedSavingsCard({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BIGGEST SAVINGS TODAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1)),
          const SizedBox(height: 12),
          ...items.take(5).map((item) => _savingsRow(item)),
        ],
      ),
    );
  }

  Widget _savingsRow(Map<String, dynamic> item) {
    final name = item['product_name'] as String? ?? '';
    final bestChain = item['best_chain'] as String? ?? '';
    final bestPrice = (item['best_price'] as num?)?.toDouble() ?? 0.0;
    final worstChain = item['worst_chain'] as String? ?? '';
    final worstPrice = (item['worst_price'] as num?)?.toDouble() ?? 0.0;
    final diff = worstPrice - bestPrice;
    final pct = worstPrice > 0 ? (diff / worstPrice * 100).round() : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: MarkupColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '$bestChain \$${bestPrice.toStringAsFixed(2)}  vs  $worstChain \$${worstPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Text('Save \$${diff.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                Text('$pct% less', style: const TextStyle(fontSize: 11, color: MarkupColors.mediumGreen)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
