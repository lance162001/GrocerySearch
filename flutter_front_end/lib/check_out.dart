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
  }) : super(key: key);

  final Function setCart;
  final Function setCartFinished;
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
            Text("To Do:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                                                    widget.cart.remove(p);
                                                    widget.cartFinished.add(p);
                                                    widget.setCart(widget.cart);
                                                    widget.setCartFinished(
                                                        widget.cartFinished);
                                                  },
                                                  child: ProductBox(p: p))))
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
                                                    widget.cart.add(p);
                                                    widget.cartFinished
                                                        .remove(p);
                                                    widget.setCart(widget.cart);
                                                    widget.setCartFinished(
                                                        widget.cartFinished);
                                                  },
                                                  child: ProductBox(p: p))))
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
