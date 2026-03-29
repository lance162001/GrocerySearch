import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key, this.opacity = 1.0});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFe0e0e0),
        highlightColor: const Color(0xFFf0f0f0),
        child: Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image placeholder
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Text lines
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _line(double.infinity, 12),
                          const SizedBox(height: 6),
                          _line(160, 10),
                          const SizedBox(height: 6),
                          _line(80, 10),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Price placeholder
                    _line(48, 16),
                  ],
                ),
                const SizedBox(height: 8),
                // Chip row
                Row(
                  children: [
                    _chip(100),
                    const SizedBox(width: 8),
                    _chip(72),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _line(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  static Widget _chip(double width) => Container(
        width: width,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
      );
}
