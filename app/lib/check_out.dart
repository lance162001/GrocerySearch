import 'package:flutter/material.dart';
import 'package:flutter_front_end/bundle_plan.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/widgets/app_bar_user_menu.dart';
import 'package:flutter_front_end/widgets/hint_banner.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:flutter_front_end/widgets/top_level_navigation.dart';
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

  Widget _buildCheckoutSummary(AppState appState) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runAlignment: WrapAlignment.spaceBetween,
        runSpacing: 8,
        spacing: 12,
        children: [
          const Text(
            'Cart overview',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'Total Items: ${appState.cartTotalItems}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'Total: \$${_checkoutTotal(appState).toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCartProductEntry(
    AppState appState,
    Product product, {
    required VoidCallback onTap,
    required bool showQuantity,
  }) {
    return Card(
      color: Colors.white,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            ProductBox(
              p: product,
              qty: appState.cartQuantities[product.instanceId] ?? 0,
            ),
            if (showQuantity)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Qty: ${appState.cartQuantities[product.instanceId] ?? 0}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideStoreColumn(
    AppState appState,
    Store store,
    List<Product> products, {
    required bool finished,
    required List<Product> allProducts,
  }) {
    final company = _companyForStore(appState, store);
    return Column(
      children: [
        Row(
          children: [
            Text(
              store.town,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (company != null)
              ProductImage(
                url: company.logoUrl,
                width: 75,
                height: 50,
              ),
          ],
        ),
        if (finished)
          Text(
            'Store Total: \$${_storeSectionSubtotal(appState, allProducts, store.id).toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        Expanded(
          child: SizedBox(
            width: 180,
            child: ListView(
              scrollDirection: Axis.vertical,
              shrinkWrap: true,
              padding: const EdgeInsets.all(1),
              children: products
                  .map((product) => _buildCartProductEntry(
                        appState,
                        product,
                        onTap: () {
                          if (finished) {
                            context.read<AppState>().restoreFinishedItem(product);
                          } else {
                            context.read<AppState>().moveCartItemToFinished(product);
                          }
                        },
                        showQuantity: !finished,
                      ))
                  .toList()
                  .cast<Widget>(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStoreSection(
    AppState appState,
    Store store,
    List<Product> allProducts,
  ) {
    final company = _companyForStore(appState, store);
    final todoProducts = appState.cart
        .where((product) => product.storeId == store.id)
        .toList(growable: false);
    final doneProducts = appState.cartFinished
        .where((product) => product.storeId == store.id)
        .toList(growable: false);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.town,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Store Total: \$${_storeSectionSubtotal(appState, allProducts, store.id).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (company != null)
                  ProductImage(
                    url: company.logoUrl,
                    width: 64,
                    height: 40,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'To Do',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (todoProducts.isEmpty)
              Text(
                'No items to pick up.',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              ...todoProducts.map(
                (product) => _buildCartProductEntry(
                  appState,
                  product,
                  onTap: () => context.read<AppState>().moveCartItemToFinished(product),
                  showQuantity: true,
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (doneProducts.isEmpty)
              Text(
                'Nothing marked done yet.',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              ...doneProducts.map(
                (product) => _buildCartProductEntry(
                  appState,
                  product,
                  onTap: () => context.read<AppState>().restoreFinishedItem(product),
                  showQuantity: false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final stores = appState.userStores;
    final allProducts = [...appState.cart, ...appState.cartFinished];
    final screenWidth = MediaQuery.of(context).size.width;
    final compactLayout = screenWidth < 720;
    final compactAction = screenWidth < 430;
    return Scaffold(
        appBar: AppBar(
          title: const Text('Cart'),
          actions: [
            const AppBarUserMenu(),
            if (compactAction)
              IconButton(
                tooltip: 'Save Bundle',
                onPressed: _savingBundle ? null : _saveCartAsBundle,
                icon: _savingBundle
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
              )
            else
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
            const HintBanner(
              hintKey: 'cart',
              message:
                  'Items are grouped by store for efficient shopping. '
                  'Tap a product to mark it done; tap again to move it back. '
                  'Use "Save Bundle" to preserve this list for future trips.',
              icon: Icons.shopping_cart_outlined,
            ),
            Expanded(
              child: compactLayout
                  ? ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _buildCheckoutSummary(appState),
                  if (stores.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Pick stores and add products to start building your cart.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  else
                    ...stores.map(
                      (store) => _buildCompactStoreSection(
                        appState,
                        store,
                        allProducts,
                      ),
                    ),
                ],
              )
            : Column(
                children: [
                  _buildCheckoutSummary(appState),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      'To Do',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(1),
                      children: stores
                          .map(
                            (store) => _buildWideStoreColumn(
                              appState,
                              store,
                              appState.cart
                                  .where((product) => product.storeId == store.id)
                                  .toList(growable: false),
                              finished: false,
                              allProducts: allProducts,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(1),
                      children: stores
                          .map(
                            (store) => _buildWideStoreColumn(
                              appState,
                              store,
                              appState.cartFinished
                                  .where((product) => product.storeId == store.id)
                                  .toList(growable: false),
                              finished: true,
                              allProducts: allProducts,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
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
