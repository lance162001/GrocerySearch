import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FeedCommunityCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const FeedCommunityCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final product1 = data['product1'] as Map<String, dynamic>? ?? {};
    final product2 = data['product2'] as Map<String, dynamic>? ?? {};
    final p1Name = product1['name'] as String? ?? '';
    final p2Name = product2['name'] as String? ?? '';

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
          const Text('PRODUCT MATCH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1)),
          const SizedBox(height: 4),
          const Text('Are these the same product?', style: TextStyle(fontSize: 13, color: MarkupColors.textSecondary)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _productBox(p1Name)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('vs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: MarkupColors.textHint)),
              ),
              Expanded(child: _productBox(p2Name)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _answerButton('Same', MarkupColors.darkGreen, Colors.white, () {})),
              const SizedBox(width: 8),
              Expanded(child: _answerButton('Different', const Color(0xFFF5F5F5), MarkupColors.textPrimary, () {})),
              const SizedBox(width: 8),
              Expanded(child: _answerButton('Skip', const Color(0xFFF5F5F5), MarkupColors.textSecondary, () {})),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productBox(String name) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: MarkupColors.textPrimary), textAlign: TextAlign.center),
    );
  }

  Widget _answerButton(String label, Color bg, Color fg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }
}
