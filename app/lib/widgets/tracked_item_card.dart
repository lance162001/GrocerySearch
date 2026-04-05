import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';
import 'package:flutter_front_end/models/grocery_models.dart';

class TrackedItemCard extends StatelessWidget {
  final TrackedItem item;
  final VoidCallback onTap;
  final VoidCallback onUntrack;

  const TrackedItemCard({super.key, required this.item, required this.onTap, required this.onUntrack});

  @override
  Widget build(BuildContext context) {
    final isPriceDrop = item.priceChange == 'drop';
    final isPriceUp = item.priceChange == 'up';

    Color? leftBorderColor;
    if (isPriceDrop) leftBorderColor = MarkupColors.darkGreen;
    if (isPriceUp) leftBorderColor = MarkupColors.orange;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
          border: leftBorderColor != null ? Border(left: BorderSide(color: leftBorderColor, width: 3)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(item.companyName, style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
                  const SizedBox(height: 6),
                  if (isPriceDrop) ...[
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(8)),
                        child: const Text('PRICE DROP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                      ),
                      if (item.currentPrice != null) ...[
                        const SizedBox(width: 8),
                        Text('\$${item.currentPrice!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                        if (item.previousPrice != null) ...[
                          const SizedBox(width: 6),
                          Text('\$${item.previousPrice!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: MarkupColors.textHint, decoration: TextDecoration.lineThrough)),
                        ],
                      ],
                    ]),
                  ] else if (isPriceUp) ...[
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: MarkupColors.bgOrange, borderRadius: BorderRadius.circular(8)),
                        child: const Text('PRICE UP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MarkupColors.orange)),
                      ),
                      if (item.currentPrice != null) ...[
                        const SizedBox(width: 8),
                        Text('\$${item.currentPrice!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: MarkupColors.orange)),
                      ],
                      if (item.cheapestChain != null && item.cheapestPrice != null) ...[
                        const SizedBox(width: 8),
                        Text('${item.cheapestChain} \$${item.cheapestPrice!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
                      ],
                    ]),
                  ] else ...[
                    Row(children: [
                      if (item.currentPrice != null)
                        Text('\$${item.currentPrice!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary)),
                      if (item.stableWeeks != null && item.stableWeeks! > 0) ...[
                        const SizedBox(width: 8),
                        Text('Stable ${item.stableWeeks} wks', style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
                      ],
                    ]),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.notifications_off_outlined, size: 20, color: MarkupColors.textHint),
              onPressed: onUntrack,
              tooltip: 'Stop tracking',
            ),
          ],
        ),
      ),
    );
  }
}
