import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart';

class ProductBox extends StatelessWidget {
  const ProductBox({super.key, required this.p});

  final Product p;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 80,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              height: 40,
              child: Text(p.name,
                  overflow: TextOverflow.fade, softWrap: true, maxLines: 2)),
          Row(children: [
            getImage(p.pictureUrl, 24, 24),
            Expanded(
              child: Text(p.size == "N/A" ? "" : "  ${p.size}"),
            ),
          ]),
          Row(children: [
            Text(
                p.memberPrice == p.salePrice
                    ? "\$${p.basePrice}"
                    : "\$${p.basePrice} | ",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: p.memberPrice == p.salePrice
                        ? FontWeight.bold
                        : FontWeight.normal)),
            Text(p.salePrice == "" ? "" : "\$${p.salePrice}",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: p.memberPrice == "N/A"
                      ? FontWeight.bold
                      : FontWeight.normal,
                )),
            Text(p.memberPrice == "" ? "" : " | \$${p.memberPrice}",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            getNotification(p.priceHistory),
          ])
        ]));
  }
}
