import 'package:flutter/material.dart';
import 'package:flutter_front_end/check_out.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_search.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/utils/product_grouping.dart';
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

String _formatPrice(double price) => '\$${price.toStringAsFixed(2)}';

class StaplesOverview extends StatefulWidget {
  const StaplesOverview({super.key});

  @override
  State<StaplesOverview> createState() => _StaplesOverviewState();
}

class _StaplesOverviewState extends State<StaplesOverview> {
  Future<Map<String, List<Product>>>? _staplesFuture;
  Set<(int, int)> _confirmedGroupPairs = {};
  Set<(int, int)> _deniedGroupPairs = {};
  /// Product IDs denied as a staple during this session, keyed by staple name.
  final Map<String, Set<int>> _sessionDenied = {};
  bool _initialized = false;

  // Cached selections: recomputed when raw data or session denials change.
  Map<String, List<Product>>? _cachedRawStaples;
  Map<String, List<Product>> _stapleSelections = {};
  List<String> _visibleStaples = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final api = context.read<GroceryApi>();
    final appState = context.read<AppState>();
    final storeIds = appState.userStores.map((s) => s.id).toList();
    final rawFuture = api.fetchStapleProducts(storeIds, _stapleNames);
    _staplesFuture = rawFuture;
    rawFuture.then((data) {
      if (!mounted) return;
      setState(() {
        _cachedRawStaples = data;
        _rebuildSelections();
      });
    }).catchError((_) {});
    _loadGroupingJudgements(api);
  }

  Future<void> _loadGroupingJudgements(GroceryApi api) async {
    try {
      final summaries = await api.fetchGroupingJudgements();
      if (!mounted) return;
      final confirmed = <(int, int)>{};
      final denied = <(int, int)>{};
      for (final s in summaries) {
        final pair = (s.productId, s.targetProductId);
        if (s.netScore > 0) {
          confirmed.add(pair);
        } else if (s.netScore < 0) {
          denied.add(pair);
        }
      }
      setState(() {
        _confirmedGroupPairs = confirmed;
        _deniedGroupPairs = denied;
      });
    } catch (_) {
      // Best-effort.
    }
  }

  /// Recomputes [_stapleSelections] from the current raw staple data,
  /// judgements, heuristics, and session denials.  Call this inside a
  /// [setState] whenever any of those inputs change.
  /// Recomputes [_stapleSelections] from the current raw data and session denials.
  /// Scoring and ranking are handled server-side; the client only filters
  /// products the user denied during the current session.
  void _rebuildSelections() {
    final staples = _cachedRawStaples;
    if (staples == null) return;

    final selections = <String, List<Product>>{};
    for (final name in _stapleNames) {
      final raw = staples[name];
      if (raw == null || raw.isEmpty) continue;
      final denied = _sessionDenied[name] ?? const {};
      selections[name] = raw.where((p) => !denied.contains(p.id)).toList();
    }
    _visibleStaples = selections.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => e.key)
        .toList();
    _stapleSelections = selections;
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
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'label') {
                Navigator.pushNamed(context, AppRoutes.labelJudgement);
              } else if (value == 'suggest_store') {
                Navigator.pushNamed(context, AppRoutes.suggestStore);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'label',
                child: Row(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Help label products'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'suggest_store',
                child: Row(
                  children: [
                    Icon(Icons.add_business, size: 20),
                    SizedBox(width: 12),
                    Text('Suggest a store'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<Map<String, List<Product>>>(
        future: _staplesFuture,
        builder: (context, snapshot) {
          // Show loading state until the cache is populated by the .then() callback.
          if (_cachedRawStaples == null) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            return const Center(child: CircularProgressIndicator());
          }

          if (_visibleStaples.isEmpty) {
            return const Center(
              child: Text('No staple products found for your stores.'),
            );
          }

          // Selections are pre-computed in state and updated only when inputs
          // change (data, judgements, heuristics, denials) — not on cart updates.
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            // Keep ~600 px beyond the viewport pre-built so scrolling into the
            // next row of cards feels instant.
            cacheExtent: 600,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: crossAxisCount == 1
                  ? 1.2
                  : crossAxisCount == 2
                      ? 0.75
                      : 0.55,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _visibleStaples.length,
            itemBuilder: (context, index) {
              final stapleName = _visibleStaples[index];
              final stapleProducts = _stapleSelections[stapleName] ?? [];

              // RepaintBoundary isolates each card so that a cart change
              // in one card doesn't repaint its neighbours.
              return RepaintBoundary(
                child: _StapleCard(
                  key: ValueKey('$stapleName-${_sessionDenied[stapleName]?.length ?? 0}'),
                  stapleName: stapleName,
                  products: stapleProducts,
                  selectedStores: selectedStores,
                  companies: companies,
                  storeById: _storeById,
                  companyForStore: _companyForStore,
                  confirmedGroupPairs: _confirmedGroupPairs,
                  deniedGroupPairs: _deniedGroupPairs,
                  onDenyProduct: (productId) {
                    setState(() {
                      _sessionDenied
                          .putIfAbsent(stapleName, () => {})
                          .add(productId);
                      _rebuildSelections();
                    });
                  },
                ),
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
    super.key,
    required this.stapleName,
    required this.products,
    required this.selectedStores,
    required this.companies,
    required this.storeById,
    required this.companyForStore,
    this.confirmedGroupPairs = const {},
    this.deniedGroupPairs = const {},
    this.onDenyProduct,
  });

  final String stapleName;
  final List<Product> products;
  final List<Store> selectedStores;
  final List<Company> companies;
  final Store? Function(List<Store>, int) storeById;
  final Company? Function(List<Company>, int) companyForStore;
  final Set<(int, int)> confirmedGroupPairs;
  final Set<(int, int)> deniedGroupPairs;
  final void Function(int productId)? onDenyProduct;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final groups = groupProductsById(
      products,
      confirmedPairs: confirmedGroupPairs,
      deniedPairs: deniedGroupPairs,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFFAFAFA),
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
            child: groups.isEmpty
                ? const Center(
                    child: Text(
                      'No options',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final product = group.primaryProduct;
                      final store =
                          storeById(selectedStores, product.storeId);
                      final company = store != null
                          ? companyForStore(companies, store.companyId)
                          : null;
                      final price = productEffectivePrice(product);
                      final inCart = group.options
                          .any((p) => appState.quantityFor(p) > 0);

                      return _StapleProductTile(
                        group: group,
                        store: store,
                        company: company,
                        price: price,
                        inCart: inCart,
                        stapleName: stapleName,
                        onDenyProduct: onDenyProduct,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StapleProductTile extends StatelessWidget {
  const _StapleProductTile({
    required this.group,
    required this.store,
    required this.company,
    required this.price,
    required this.inCart,
    required this.stapleName,
    this.onDenyProduct,
  });

  final ProductGroup group;
  final Store? store;
  final Company? company;
  final double? price;
  final bool inCart;
  final String stapleName;
  final void Function(int productId)? onDenyProduct;

  @override
  Widget build(BuildContext context) {
    final product = group.primaryProduct;
    return InkWell(
      onTap: () {
        final appState = context.read<AppState>();
        if (inCart) {
          appState.removeFromCartAll(product);
        } else {
          appState.addToCartQty(product, 1);
        }
      },
      onLongPress: () => _showProductDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: inCart ? const Color(0xFFF5F3FF) : null,
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
                  if (product.brand.isNotEmpty)
                    Text(
                      product.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
                      if (group.otherStoreCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '+${group.otherStoreCount} more',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFFA1A1AA),
                          ),
                        ),
                      ],
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
                  color: inCart ? const Color(0xFF4F46E5) : null,
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              inCart ? Icons.check_circle : Icons.add_circle_outline,
              size: 20,
              color: inCart ? const Color(0xFF6366F1) : const Color(0xFFA1A1AA),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDetail(BuildContext context) {
    final product = group.primaryProduct;
    final appState = context.read<AppState>();
    final api = context.read<GroceryApi>();
    final allStores = appState.userStores;
    final allCompanies = appState.companies;
    final displayStaple = stapleName[0].toUpperCase() + stapleName.substring(1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Product image + name
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ProductImage(
                          url: product.pictureUrl,
                          width: 80,
                          height: 80,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (product.brand.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                product.brand,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                            if (product.size.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                product.size,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),

                  // Store options
                  if (group.options.length > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Available at ${group.options.length} stores',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...group.options.map((option) {
                      final optStore = allStores
                          .cast<Store?>()
                          .firstWhere((s) => s!.id == option.storeId,
                              orElse: () => null);
                      final optCompany = optStore != null
                          ? allCompanies.cast<Company?>().firstWhere(
                              (c) => c!.id == optStore.companyId,
                              orElse: () => null)
                          : null;
                      final optPrice = productEffectivePrice(option);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            if (optCompany != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ProductImage(
                                  url: optCompany.logoUrl,
                                  width: 20,
                                  height: 20,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                optStore?.town ?? 'Store ${option.storeId}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (optPrice != null)
                              Text(
                                _formatPrice(optPrice),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 24),
                  ],

                  // Variations button
                  if (product.variationGroup != null &&
                      product.variationGroup!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.style_outlined),
                      label: const Text('See flavors / variations'),
                      onPressed: () {
                        final storeIds =
                            allStores.map((s) => s.id).toList();
                        _showVariations(sheetContext, api, product, storeIds);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Judge section
                  const SizedBox(height: 8),
                  Text(
                    'Is this $displayStaple?',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your feedback helps improve staple recommendations.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(Icons.thumb_down_outlined,
                              color: Colors.red.shade400),
                          label: Text('Not $displayStaple',
                              style: TextStyle(color: Colors.red.shade400)),
                          onPressed: () {
                            _submitStapleJudgement(
                                api, appState, product, false);
                            onDenyProduct?.call(product.id);
                            Navigator.pop(sheetContext);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.thumb_up_outlined,
                              color: Colors.white),
                          label: const Text('Yes',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF18181B),
                          ),
                          onPressed: () {
                            _submitStapleJudgement(
                                api, appState, product, true);
                            Navigator.pop(sheetContext);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _submitStapleJudgement(
    GroceryApi api,
    AppState appState,
    Product product,
    bool approved,
  ) {
    final userId = appState.currentUserId;
    if (userId == null) return;
    api.submitJudgement(
      userId: userId,
      productId: product.id,
      judgementType: 'staple',
      approved: approved,
      stapleName: stapleName,
    );
  }

  void _showVariations(
    BuildContext context,
    GroceryApi api,
    Product product,
    List<int> storeIds,
  ) {
    final future = api.fetchVariations(product.id, storeIds);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: FutureBuilder<List<Product>>(
            future: future,
            builder: (context, snapshot) {
              final title = '${product.brand} variations';
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],
                );
              }
              final variations = snapshot.data ?? [];
              if (variations.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      const Text('No other variations found.'),
                    ],
                  ),
                );
              }
              // Group and deduplicate variation results.
              final groups = groupProductsById(variations);
              return Consumer<AppState>(
                builder: (context, appState, _) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        '${groups.length} other flavors / styles',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const Divider(height: 20),
                      ...groups.map((g) {
                        final p = g.primaryProduct;
                        final price = productEffectivePrice(p);
                        final inCart = appState.quantityFor(p) > 0;
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: ProductImage(
                                url: p.pictureUrl, width: 44, height: 44),
                          ),
                          title: Text(p.name,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              if (p.size.isNotEmpty) p.size,
                              if (price != null)
                                '\$${price.toStringAsFixed(2)}',
                            ].join(' • '),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              inCart
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              color: inCart ? Colors.green : null,
                            ),
                            onPressed: () {
                              if (inCart) {
                                appState.removeFromCartAll(p);
                              } else {
                                appState.addToCartQty(p, 1);
                              }
                            },
                          ),
                        );
                      }),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
