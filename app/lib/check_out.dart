import 'package:flutter/material.dart';
import 'package:flutter_front_end/bundle_plan.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/widgets/top_level_navigation.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:provider/provider.dart';

class CheckOut extends StatefulWidget {
  const CheckOut({super.key});

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

  Company? _companyForStore(AppState appState, Store store) {
    for (final company in appState.companies) {
      if (company.id == store.companyId) {
        return company;
      }
    }
    return null;
  }

  double _checkoutTotal(AppState appState) {
    final productsById = <int, Product>{
      for (final product in [...appState.cart, ...appState.cartFinished])
        product.instanceId: product,
    };

    double total = 0.0;
    appState.cartQuantities.forEach((productId, quantity) {
      final product = productsById[productId];
      if (product == null || quantity <= 0) {
        return;
      }
      total += _productUnitPrice(product) * quantity;
    });

    return total;
  }

  double _storeSectionSubtotal(AppState appState, List<Product> products, int storeId) {
    final productsById = <int, Product>{
      for (final product in products.where((product) => product.storeId == storeId))
        product.instanceId: product,
    };

    double total = 0.0;
    appState.cartQuantities.forEach((productId, quantity) {
      final product = productsById[productId];
      if (product == null || quantity <= 0) {
        return;
      }
      total += _productUnitPrice(product) * quantity;
    });

    return total;
  }

  List<int> _cartProductIdsForBundle(AppState appState) {
    final productByInstance = <int, Product>{
      for (final product in [...appState.cart, ...appState.cartFinished])
        product.instanceId: product,
    };
    final productIds = <int>{};

    appState.cartQuantities.forEach((instanceId, qty) {
      if (qty <= 0) return;
      final product = productByInstance[instanceId];
      if (product == null) return;
      productIds.add(product.id);
    });

    return productIds.toList();
  }

  Future<void> _saveCartAsBundle() async {
    if (_savingBundle) return;

    final appState = context.read<AppState>();
    final userId = appState.currentUserId;
    final productIds = _cartProductIdsForBundle(appState);
    if (productIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty. Add items before saving.')),
      );
      return;
    }
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ID is unavailable.')),
      );
      return;
    }

    setState(() => _savingBundle = true);
    try {
      final name =
          'Checkout ${DateTime.now().toIso8601String().substring(0, 19)}';
      final api = context.read<GroceryApi>();
      final bundleId = await api.createBundle(userId, name);

      int addedCount = 0;
      for (final productId in productIds) {
        try {
          await api.addProductToBundle(bundleId, productId);
          addedCount++;
        } catch (_) {
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
            initialUserId: userId,
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
    final appState = context.watch<AppState>();
    final stores = appState.userStores;
    final allProducts = [...appState.cart, ...appState.cartFinished];
    return Scaffold(
        appBar: AppBar(
          title: const Text('Cart'),
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
                        'Total Items: ${appState.cartTotalItems}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Total: \$${_checkoutTotal(appState).toStringAsFixed(2)}',
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
                  children: stores
                      .map((s) => Column(
                            children: [
                              Builder(builder: (context) {
                                final company = _companyForStore(appState, s);
                                return Row(children: [
                                  Text(s.town,
                                      style:
                                          TextStyle(fontWeight: FontWeight.bold)),
                                  if (company != null)
                                    ProductImage(
                                      url: company.logoUrl,
                                      width: 75,
                                      height: 50,
                                    ),
                                ]);
                              }),
                              Expanded(
                                child: SizedBox(
                                  width: 180,
                                  child: ListView(
                                      scrollDirection: Axis.vertical,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(1),
                                      children: appState.cart
                                          .where((p) => p.storeId == s.id)
                                          .map((p) => Card(
                                              color: Colors.white,
                                              clipBehavior: Clip.hardEdge,
                                              child: InkWell(
                                                  onTap: () {
                                                    context.read<AppState>().moveCartItemToFinished(p);
                                                  },
                                                  child: Column(
                                                    children: [
                                                      ProductBox(p: p, qty: appState.cartQuantities[p.instanceId] ?? 0),
                                                      Text('Qty: ${appState.cartQuantities[p.instanceId] ?? 0}'),
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
                  children: stores
                      .map((s) => Column(
                            children: [
                              Builder(builder: (context) {
                                final company = _companyForStore(appState, s);
                                return Row(children: [
                                  Text(s.town,
                                      style:
                                          TextStyle(fontWeight: FontWeight.bold)),
                                  if (company != null)
                                    ProductImage(
                                      url: company.logoUrl,
                                      width: 75,
                                      height: 50,
                                    ),
                                ]);
                              }),
                              Text(
                                'Store Total: \$${_storeSectionSubtotal(appState, allProducts, s.id).toStringAsFixed(2)}',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Expanded(
                                child: SizedBox(
                                  width: 180,
                                  child: ListView(
                                      scrollDirection: Axis.vertical,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(1),
                                        children: appState.cartFinished
                                          .where((p) => p.storeId == s.id)
                                          .map((p) => Card(
                                            color: Colors.white,
                                            clipBehavior: Clip.hardEdge,
                                            child: InkWell(
                                              onTap: () {
                                              context.read<AppState>().restoreFinishedItem(p);
                                              },
                                              child: ProductBox(p: p, qty: appState.cartQuantities[p.instanceId] ?? 0))))
                                          .toList()
                                          .cast<Widget>()),
                                ),
                              ),
                            ],
                          ))
                      .toList()),
            ),
          ],
        ),
        bottomNavigationBar: const SafeArea(
          top: false,
          child: TopLevelNavigationBar(
            currentDestination: AppTopLevelDestination.cart,
          ),
        ));
  }
}
