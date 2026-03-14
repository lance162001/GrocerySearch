import 'package:flutter/material.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/widgets/product_image.dart';

class StoreRow extends StatelessWidget {
  const StoreRow({
    super.key,
    required this.store,
    required this.logoUrl,
  });

  final Store store;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ProductImage(url: logoUrl, width: 20, height: 20),
          const SizedBox(height: 2),
          Text(
            store.town,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}