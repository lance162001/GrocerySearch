import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_front_end/main.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/bundle_plan.dart';

class CheckOut extends StatefulWidget {
  CheckOut({
    Key? key,
    required this.currentUserId,
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
  final int currentUserId;
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
  bool _savingBundle = false;

  double _productUnitPrice(Product product) {
    return parsePriceString(product.memberPrice) ??
        parsePriceString(product.salePrice) ??
        parsePriceString(product.basePrice) ??
        0.0;
  }

  double _checkoutTotal() {
    final productsById = <int, Product>{
      for (final product in [...widget.cart, ...widget.cartFinished])
        product.instanceId: product,
    };

    double total = 0.0;
    widget.cartQuantities.forEach((productId, quantity) {
      final product = productsById[productId];
      if (product == null || quantity <= 0) {
        return;
      }
      total += _productUnitPrice(product) * quantity;
    });

    return total;
  }

  double _storeSectionSubtotal(List<Product> products, int storeId) {
    final productsById = <int, Product>{
      for (final product in products.where((product) => product.storeId == storeId))
        product.instanceId: product,
    };

    double total = 0.0;
    widget.cartQuantities.forEach((productId, quantity) {
      final product = productsById[productId];
      if (product == null || quantity <= 0) {
        return;
      }
      total += _productUnitPrice(product) * quantity;
    });

    return total;
  }

  List<int> _cartProductIdsForBundle() {
    final productByInstance = <int, Product>{
      for (final product in [...widget.cart, ...widget.cartFinished])
        product.instanceId: product,
    };
    final productIds = <int>{};

    widget.cartQuantities.forEach((instanceId, qty) {
      if (qty <= 0) return;
      final product = productByInstance[instanceId];
      if (product == null) return;
      productIds.add(product.id);
    });

    return productIds.toList();
  }

  Future<void> _saveCartAsBundle() async {
    if (_savingBundle) return;

    final productIds = _cartProductIdsForBundle();
    if (productIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty. Add items before saving.')),
      );
      return;
    }

    setState(() => _savingBundle = true);
    try {
      final headers = {'Content-Type': 'application/json'};
      final name =
          'Checkout ${DateTime.now().toIso8601String().substring(0, 19)}';

      final createResponse = await http.post(
        Uri.http('$hostname:$port', '/users/${widget.currentUserId}/bundles'),
        headers: headers,
        body: jsonEncode({'name': name}),
      );

      if (createResponse.statusCode != 200) {
        throw Exception('Create bundle failed (${createResponse.statusCode})');
      }

      final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
      final bundleId = created['id'];
      if (bundleId is! int || bundleId <= 0) {
        throw Exception('Invalid bundle id returned by backend');
      }

      int addedCount = 0;
      for (final productId in productIds) {
        final addResponse = await http.post(
          Uri.http('$hostname:$port', '/bundles/$bundleId/products'),
          headers: headers,
          body: jsonEncode({'product_id': productId}),
        );
        if (addResponse.statusCode == 200) {
          addedCount++;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved bundle #$bundleId with $addedCount items'),
        ),
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BundlePlanPage(
            initialUserId: widget.currentUserId,
            initialBundleId: bundleId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save bundle: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingBundle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Checkout"),
          actions: [
            TextButton.icon(
              onPressed: _savingBundle ? null : _saveCartAsBundle,
              icon: _savingBundle
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save Bundle'),
            ),
          ],
        ),
        body: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("To Do:", style: TextStyle(fontWeight: FontWeight.bold)),
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total Items: ${widget.cartQuantities.values.fold(0, (a, b) => a + b)}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Total: \$${_checkoutTotal().toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
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
                                                      widget.cart.removeWhere((item) => item.instanceId == p.instanceId);
                                                      if (!widget.cartFinished.any((item) => item.instanceId == p.instanceId)) {
                                                        widget.cartFinished.add(p);
                                                      }
                                                      widget.setCart(widget.cart);
                                                      widget.setCartFinished(widget.cartFinished);
                                                    });
                                                  },
                                                  child: Column(
                                                    children: [
                                                      ProductBox(p: p, qty: widget.cartQuantities[p.instanceId] ?? 0),
                                                      Text('Qty: ${widget.cartQuantities[p.instanceId] ?? 0}'),
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
                              Text(
                                'Store Total: \$${_storeSectionSubtotal([...widget.cart, ...widget.cartFinished], s.id).toStringAsFixed(2)}',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
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
                                                if (!widget.cart.any((item) => item.instanceId == p.instanceId)) {
                                                  widget.cart.add(p);
                                                }
                                                widget.cartFinished.removeWhere((item) => item.instanceId == p.instanceId);
                                                widget.setCart(widget.cart);
                                                widget.setCartFinished(widget.cartFinished);
                                              });
                                              },
                                              child: ProductBox(p: p, qty: widget.cartQuantities[p.instanceId] ?? 0))))
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
