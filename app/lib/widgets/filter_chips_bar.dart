import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FilterChipsBar extends StatelessWidget {
  final bool onSaleActive;
  final bool biggestSpreadsActive;
  final List<String> tagNames;
  final List<int> tagIds; // actual DB IDs parallel to tagNames
  final List<int> activeTagIds;
  final VoidCallback onToggleOnSale;
  final VoidCallback onToggleSpreads;
  final Function(int) onToggleTag; // receives tag ID (not index)

  const FilterChipsBar({
    super.key,
    required this.onSaleActive,
    required this.biggestSpreadsActive,
    required this.tagNames,
    required this.tagIds,
    required this.activeTagIds,
    required this.onToggleOnSale,
    required this.onToggleSpreads,
    required this.onToggleTag,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip('On Sale', onSaleActive, onToggleOnSale),
          const SizedBox(width: 6),
          _chip('Biggest Spreads', biggestSpreadsActive, onToggleSpreads),
          ...tagNames.asMap().entries.map((e) {
            final idx = e.key;
            final name = e.value;
            final id = idx < tagIds.length ? tagIds[idx] : idx;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _chip(name, activeTagIds.contains(id), () => onToggleTag(id)),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? MarkupColors.bgGreen : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? MarkupColors.lightGreen : const Color(0xFFE0E0E0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? MarkupColors.darkGreen : MarkupColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
