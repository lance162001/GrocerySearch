import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

enum ChallengeType { productMatch, stapleCheck }

class ChallengeCard extends StatelessWidget {
  final ChallengeType type;
  final int points;
  final String productName;
  final String productBrand;
  final String? targetProductName;
  final String? targetProductBrand;
  final String? stapleName;
  final Function(bool approved) onAnswer;
  final VoidCallback onSkip;

  const ChallengeCard({
    super.key,
    required this.type,
    required this.points,
    required this.productName,
    required this.productBrand,
    this.targetProductName,
    this.targetProductBrand,
    this.stapleName,
    required this.onAnswer,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isMatch = type == ChallengeType.productMatch;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isMatch ? '🏷️ PRODUCT MATCH' : '🥛 STAPLE CHECK',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1),
              ),
              Text(' · +$points pts', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isMatch
                ? 'Are these the same product from different stores? Matching them lets us compare their prices.'
                : 'Should this count as a basic grocery staple? This helps us build better price comparisons for everyday items.',
            style: const TextStyle(fontSize: 13, color: MarkupColors.textSecondary),
          ),
          const SizedBox(height: 10),
          if (isMatch) ...[
            Row(
              children: [
                Expanded(child: _productBox(productName, productBrand)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('=?', style: TextStyle(fontSize: 16, color: MarkupColors.textHint))),
                Expanded(child: _productBox(targetProductName ?? '', targetProductBrand ?? '')),
              ],
            ),
          ] else ...[
            _productBox(productName, '$productBrand${stapleName != null ? '\nCategory: $stapleName' : ''}'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _actionButton(isMatch ? '✓ Same product' : '👍 Yes, it\'s a staple', MarkupColors.bgGreen, MarkupColors.darkGreen, () => onAnswer(true))),
              const SizedBox(width: 8),
              Expanded(child: _actionButton(isMatch ? '✗ Different' : '👎 No', const Color(0xFFFFF0F0), MarkupColors.orange, () => onAnswer(false))),
              const SizedBox(width: 8),
              Expanded(child: _actionButton('Skip', const Color(0xFFF0F0F0), MarkupColors.textSecondary, onSkip)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productBox(String name, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary), textAlign: TextAlign.center),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: MarkupColors.textSecondary), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color bg, Color textColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor), textAlign: TextAlign.center),
      ),
    );
  }
}
