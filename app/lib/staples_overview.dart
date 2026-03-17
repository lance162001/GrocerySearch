import 'package:flutter/material.dart';
import 'package:flutter_front_end/check_out.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_search.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:provider/provider.dart';

const List<String> _stapleNames = [
  'milk',
  'eggs',
  'bread',
  'rice',
  'pasta',
  'flour',
  'sugar',
  'butter',
  'cheese',
  'yogurt',
  'chicken',
  'bananas',
  'apples',
  'onions',
  'potatoes',
  'tomatoes',
  'garlic',
  'olive oil',
  'salt',
  'pepper',
];

double? _productPrice(Product product) {
  return parsePriceString(product.memberPrice) ??
      parsePriceString(product.salePrice) ??
      parsePriceString(product.basePrice);
}

String _formatPrice(double price) => '\$${price.toStringAsFixed(2)}';

class StaplesOverview extends StatefulWidget {
  const StaplesOverview({super.key});

  @override
  State<StaplesOverview> createState() => _StaplesOverviewState();
}

class _StaplesOverviewState extends State<StaplesOverview> {
  Future<Map<String, List<Product>>>? _staplesFuture;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final api = context.read<GroceryApi>();
    final appState = context.read<AppState>();
    final storeIds = appState.userStores.map((s) => s.id).toList();
    _staplesFuture = api.fetchStapleProducts(storeIds, _stapleNames);
  }

  /// Pick one best product per selected store for a given staple.
  Map<int, Product> _bestPerStore(
    List<Product> products,
    List<Store> selectedStores,
  ) {
    final storeIds = selectedStores.map((s) => s.id).toSet();
    final bestByStore = <int, Product>{};
    for (final product in products) {
      if (!storeIds.contains(product.storeId)) continue;
      final existing = bestByStore[product.storeId];
      if (existing == null) {
        bestByStore[product.storeId] = product;
        continue;
      }
      final existingPrice = _productPrice(existing);
      final candidatePrice = _productPrice(product);
      if (existingPrice == null && candidatePrice != null) {
        bestByStore[product.storeId] = product;
      } else if (existingPrice != null &&
          candidatePrice != null &&
          candidatePrice < existingPrice) {
        bestByStore[product.storeId] = product;
      }
    }
    return bestByStore;
  }

  Company? _companyForStore(List<Company> companies, int companyId) {
    for (final company in companies) {
      if (company.id == companyId) return company;
    }
    return null;
  }

  Store? _storeById(List<Store> stores, int storeId) {
    for (final store in stores) {
      if (store.id == storeId) return store;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedStores = appState.userStores;
    final companies = appState.companies;
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 1100
        ? 4
        : screenWidth >= 800
            ? 3
            : screenWidth >= 600
                ? 2
                : 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery Staples'),
        actions: [
          IconButton(
            tooltip: 'Search products',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchPage()),
            ),
          ),
          IconButton(
            tooltip: 'Checkout',
            icon: const Icon(Icons.shopping_cart_checkout),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CheckOut()),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, List<Product>>>(
        future: _staplesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final staples = snapshot.data ?? {};

          final visibleStaples = _stapleNames
              .where((name) =>
                  staples.containsKey(name) && staples[name]!.isNotEmpty)
              .toList();

          if (visibleStaples.isEmpty) {
            return const Center(
              child: Text('No staple products found for your stores.'),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: visibleStaples.length,
            itemBuilder: (context, index) {
              final stapleName = visibleStaples[index];
              final products = staples[stapleName]!;
              final bestPerStore =
                  _bestPerStore(products, selectedStores);

              return _StapleCard(
                stapleName: stapleName,
                bestPerStore: bestPerStore,
                selectedStores: selectedStores,
                companies: companies,
                storeById: _storeById,
                companyForStore: _companyForStore,
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Search'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SearchPage()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.shopping_cart_checkout),
                label: Text(
                  'Checkout (${appState.cartTotalItems})',
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const CheckOut()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StapleCard extends StatelessWidget {
  const _StapleCard({
    required this.stapleName,
    required this.bestPerStore,
    required this.selectedStores,
    required this.companies,
    required this.storeById,
    required this.companyForStore,
  });

  final String stapleName;
  final Map<int, Product> bestPerStore;
  final List<Store> selectedStores;
  final List<Company> companies;
  final Store? Function(List<Store>, int) storeById;
  final Company? Function(List<Company>, int) companyForStore;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.blueGrey.shade50,
            child: Text(
              stapleName[0].toUpperCase() + stapleName.substring(1),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: bestPerStore.isEmpty
                ? const Center(
                    child: Text(
                      'No options',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: bestPerStore.entries.map((entry) {
                      final storeId = entry.key;
                      final product = entry.value;
                      final store =
                          storeById(selectedStores, storeId);
                      final company = store != null
                          ? companyForStore(companies, store.companyId)
                          : null;
                      final price = _productPrice(product);
                      final inCart = appState.quantityFor(product) > 0;

                      return _StapleProductTile(
                        product: product,
                        store: store,
                        company: company,
                        price: price,
                        inCart: inCart,
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StapleProductTile extends StatelessWidget {
  const _StapleProductTile({
    required this.product,
    required this.store,
    required this.company,
    required this.price,
    required this.inCart,
  });

  final Product product;
  final Store? store;
  final Company? company;
  final double? price;
  final bool inCart;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final appState = context.read<AppState>();
        if (inCart) {
          appState.removeFromCartAll(product);
        } else {
          appState.addToCartQty(product, 1);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: inCart ? Colors.green.shade50 : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ProductImage(
                url: product.pictureUrl,
                width: 36,
                height: 36,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  Row(
                    children: [
                      if (company != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ProductImage(
                            url: company!.logoUrl,
                            width: 14,
                            height: 14,
                          ),
                        ),
                      if (store != null)
                        Flexible(
                          child: Text(
                            store!.town,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (price != null)
              Text(
                _formatPrice(price!),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: inCart ? Colors.green.shade700 : null,
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              inCart ? Icons.check_circle : Icons.add_circle_outline,
              size: 20,
              color: inCart ? Colors.green : Colors.blueGrey,
            ),
          ],
        ),
      ),
    );
  }
}
