import 'package:flutter/material.dart';
import 'package:flutter_front_end/models/grocery_models.dart';

class PriceNotificationIcon extends StatelessWidget {
  const PriceNotificationIcon({super.key, required this.pricePoints});

  final List<PricePoint> pricePoints;

  @override
  Widget build(BuildContext context) {
    if (pricePoints.isEmpty) {
      return const Icon(Icons.wallet, size: 13);
    }

    final currentPrice = pricePoints.first.lowestPrice();
    final total = pricePoints.fold<double>(0.0, (sum, pricePoint) => sum + pricePoint.lowestPrice());
    final average = total / pricePoints.length;

    if (currentPrice < average) {
      return const Icon(Icons.wallet, size: 13, color: Colors.green);
    }
    if (currentPrice > average) {
      return const Icon(Icons.wallet, size: 13, color: Colors.red);
    }
    return const Icon(Icons.wallet, size: 13);
  }
}