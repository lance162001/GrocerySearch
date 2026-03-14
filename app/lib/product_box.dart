import 'package:flutter/material.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/widgets/price_notification_icon.dart';
import 'package:flutter_front_end/widgets/product_image.dart';

class ProductBox extends StatelessWidget {
  const ProductBox({super.key, required this.p, this.qty = 0});

  final Product p;
  final int qty;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: ProductImage(url: p.pictureUrl, width: 40, height: 40),
              ),
            ),
            SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    style: TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6),
                  if (p.size != "")
                    Text(
                      p.size,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  if (p.size != "") SizedBox(height: 6),
                  Row(children: [
                    PriceNotificationIcon(pricePoints: p.priceHistory),
                  ])
                ],
              ),
            ),
            SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show member price if present (most prominent)
                  if (p.memberPrice != "")
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatPriceString(p.memberPrice),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  if (p.memberPrice != "") SizedBox(height: 6),

                  // Show sale price if present (red)
                  if (p.salePrice != "")
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatPriceString(p.salePrice),
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (p.salePrice != "") SizedBox(height: 4),

                  // Base price: strike-through and muted only when there is a sale or member price
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatPriceString(p.basePrice),
                      style: (p.salePrice != "" || p.memberPrice != "")
                          ? TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            )
                          : TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                    ),
                  ),
                  if (qty > 0) SizedBox(height: 6),
                  if (qty > 0)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Qty: $qty', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
