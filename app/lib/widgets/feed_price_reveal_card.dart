import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FeedPriceRevealCard extends StatelessWidget {
  final String productName;
  final String brand;
  final String size;
  final List<Map<String, dynamic>> prices; // [{chain, price, is_best, diff_from_best}]
  final VoidCallback? onTrack;
  final VoidCallback? onHistory;

  const FeedPriceRevealCard({
    super.key,
    required this.productName,
    required this.brand,
    required this.size,
    required this.prices,
    this.onTrack,
    this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
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
          const Text('PRICE REVEAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(productName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary)),
          if (size.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('$brand · $size', style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          Row(
            children: prices.take(3).map((p) => Expanded(child: _priceChip(p))).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (onHistory != null)
                _actionPill('📊 Price history', onHistory!),
              const SizedBox(width: 8),
              if (onTrack != null)
                _actionPill('🔔 Track price', onTrack!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceChip(Map<String, dynamic> p) {
    final isBest = p['is_best'] == true;
    final price = (p['price'] as num).toDouble();
    final diff = p['diff_from_best'] as num?;
    final chain = p['chain'] as String? ?? '';

    final Color bg = isBest ? MarkupColors.bgGreen : (diff != null && diff > 2 ? MarkupColors.bgOrange : const Color(0xFFF5F5F5));
    final Color priceColor = isBest ? MarkupColors.darkGreen : (diff != null && diff > 2 ? MarkupColors.orange : MarkupColors.textPrimary);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: !isBest && diff != null && diff > 2 ? Border.all(color: const Color(0xFFF0E0C0)) : null,
      ),
      child: Column(
        children: [
          Text(chain, style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('\$${price.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: priceColor)),
          const SizedBox(height: 2),
          Text(
            isBest ? 'Best price' : (diff != null ? '+\$${diff.toStringAsFixed(2)} more' : ''),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: priceColor),
          ),
        ],
      ),
    );
  }

  Widget _actionPill(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen)),
      ),
    );
  }
}
