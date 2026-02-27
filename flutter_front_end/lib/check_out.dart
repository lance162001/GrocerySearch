import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart';
import 'package:flutter_front_end/product_box.dart';

class CheckOut extends StatefulWidget {
  CheckOut({
    Key? key,
    required this.cart,
    required this.cartFinished,
    required this.stores,
    required this.setCart,
    required this.setCartFinished,
    required this.companies,
    required this.addToCartQty,
    required this.removeFromCartAll,
    required this.cartQuantities,
  }) : super(key: key);

  final Function setCart;
  final Function setCartFinished;
  final Function addToCartQty;
  final Function removeFromCartAll;
  final Map<int, int> cartQuantities;
  List<Product> cartFinished;
  List<Product> cart;
  final List<Store> stores;
  final List<Company> companies;

  @override
  State<CheckOut> createState() => _CheckOutState();
}

class _CheckOutState extends State<CheckOut> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Checkout"),
        ),
        body: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("To Do:", style: TextStyle(fontWeight: FontWeight.bold)),
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Text('Total Items: ${widget.cartQuantities.values.fold(0, (a, b) => a + b)}', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
            Expanded(
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(1),
                  children: widget.stores
                      .map((s) => Column(
                            children: [
                              Row(children: [
                                Text(s.town,
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                getImage(
                                    widget.companies[s.companyId - 1].logoUrl,
                                    75,
                                    50),
                              ]),
                              Expanded(
                                child: SizedBox(
                                  width: 180,
                                  child: ListView(
                                      scrollDirection: Axis.vertical,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(1),
                                      children: widget.cart
                                          .where((p) => p.storeId == s.id)
                                          .map((p) => Card(
                                              color: Colors.white,
                                              clipBehavior: Clip.hardEdge,
                                              child: InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      widget.cart.removeWhere((item) => item.id == p.id);
                                                      if (!widget.cartFinished.any((item) => item.id == p.id)) {
                                                        widget.cartFinished.add(p);
                                                      }
                                                      widget.setCart(widget.cart);
                                                      widget.setCartFinished(widget.cartFinished);
                                                    });
                                                  },
                                                  child: Column(
                                                    children: [
                                                      ProductBox(p: p, qty: widget.cartQuantities[p.id] ?? 0),
                                                      Text('Qty: ${widget.cartQuantities[p.id] ?? 0}'),
                                                    ],
                                                  ))))
                                          .toList()
                                          .cast<Widget>()),
                                ),
                              ),
                            ],
                          ))
                      .toList()),
            ),
            SizedBox(height: 35),
            Text("Done:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(1),
                  children: widget.stores
                      .map((s) => Column(
                            children: [
                              Row(children: [
                                Text(s.town,
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                getImage(
                                    widget.companies[s.companyId - 1].logoUrl,
                                    75,
                                    50),
                              ]),
                              Expanded(
                                child: SizedBox(
                                  width: 180,
                                  child: ListView(
                                      scrollDirection: Axis.vertical,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(1),
                                        children: widget.cartFinished
                                          .where((p) => p.storeId == s.id)
                                          .map((p) => Card(
                                            color: Colors.white,
                                            clipBehavior: Clip.hardEdge,
                                            child: InkWell(
                                              onTap: () {
                                              setState(() {
                                                if (!widget.cart.any((item) => item.id == p.id)) {
                                                  widget.cart.add(p);
                                                }
                                                widget.cartFinished.removeWhere((item) => item.id == p.id);
                                                widget.setCart(widget.cart);
                                                widget.setCartFinished(widget.cartFinished);
                                              });
                                              },
                                              child: ProductBox(p: p, qty: widget.cartQuantities[p.id] ?? 0))))
                                          .toList()
                                          .cast<Widget>()),
                                ),
                              ),
                            ],
                          ))
                      .toList()),
            ),
          ],
        ));
  }
}
