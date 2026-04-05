import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class SearchResultCard extends StatelessWidget {
  final String productName;
  final String brand;
  final String size;
  final String? pictureUrl;
  final double bestPrice;
  final String bestChain;
  final List<Map<String, dynamic>> otherPrices; // [{chain, price}]
  final double maxSavings;
  final bool isBestDeal;
  final bool isOnSale;
  final double? originalPrice;
  final VoidCallback? onTrack;
  final VoidCallback? onHistory;
  final VoidCallback? onTap;

  const SearchResultCard({
    super.key,
    required this.productName,
    required this.brand,
    required this.size,
    this.pictureUrl,
    required this.bestPrice,
    required this.bestChain,
    required this.otherPrices,
    required this.maxSavings,
    this.isBestDeal = false,
    this.isOnSale = false,
    this.originalPrice,
    this.onTrack,
    this.onHistory,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
          border: isBestDeal ? const Border(left: BorderSide(color: MarkupColors.darkGreen, width: 3)) : null,
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
                  child: pictureUrl != null && pictureUrl!.isNotEmpty
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(pictureUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.egg, color: MarkupColors.textHint)))
                      : const Icon(Icons.shopping_bag_outlined, color: MarkupColors.textHint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary))),
                          if (isOnSale)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: MarkupColors.orange, borderRadius: BorderRadius.circular(4)),
                              child: const Text('SALE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [if (brand.isNotEmpty) brand, if (size.isNotEmpty) size].join(' · '),
                        style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('\$${bestPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: isOnSale ? MarkupColors.orange : MarkupColors.darkGreen)),
                          if (isOnSale && originalPrice != null) ...[
                            const SizedBox(width: 6),
                            Text('\$${originalPrice!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: MarkupColors.textHint, decoration: TextDecoration.lineThrough)),
                          ],
                          const SizedBox(width: 8),
                          if (bestChain.isNotEmpty)
                            Text('at $bestChain', style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
                        ],
                      ),
                      if (otherPrices.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: otherPrices.map((p) {
                            final price = (p['price'] as num).toDouble();
                            final isExpensive = price > bestPrice * 1.3;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isExpensive ? MarkupColors.bgOrange : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${p['chain']} \$${price.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 11, color: isExpensive ? MarkupColors.orange : MarkupColors.textSecondary),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (maxSavings > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(10)),
                    child: Text('Save \$${maxSavings.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                if (onHistory != null)
                  GestureDetector(onTap: onHistory, child: const Text('📊 History', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen))),
                if (onTrack != null) ...[
                  const SizedBox(width: 16),
                  GestureDetector(onTap: onTrack, child: const Text('🔔 Track', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen))),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
