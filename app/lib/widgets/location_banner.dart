import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class LocationBanner extends StatelessWidget {
  final String? zipcode;
  final VoidCallback onSetArea;

  const LocationBanner({super.key, this.zipcode, required this.onSetArea});

  @override
  Widget build(BuildContext context) {
    final label = zipcode != null ? 'Prices near $zipcode' : 'Showing prices from all regions';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MarkupColors.bgGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, size: 16, color: MarkupColors.darkGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: MarkupColors.darkGreen)),
          ),
          GestureDetector(
            onTap: onSetArea,
            child: Text(
              zipcode != null ? 'Change' : 'Set your area',
              style: const TextStyle(
                fontSize: 13,
                color: MarkupColors.darkGreen,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
