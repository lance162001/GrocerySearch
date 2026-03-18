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

const int _minStapleItems = 8;

String _formatPrice(double price) => '\$${price.toStringAsFixed(2)}';

/// Confidence score for how well a product name matches a staple keyword.
/// Lower is better (0 = exact match).
double _stapleConfidence(Product product, String staple) {
  final name = product.name.toLowerCase().trim();
  final query = staple.toLowerCase().trim();

  // Exact match.
  if (name == query) return 0.0;

  // Name is the staple with simple qualifiers (e.g. "whole milk").
  final words = name.split(RegExp(r'\s+'));
  final queryWords = query.split(RegExp(r'\s+'));
  if (words.length <= queryWords.length + 1 && name.contains(query)) return 0.1;

  // Name starts with the staple term.
  if (name.startsWith(query)) return 0.2;

  // Staple term starts a word boundary in the name.
  final wordBoundary = RegExp(r'\b' + RegExp.escape(query) + r'\b');
  if (wordBoundary.hasMatch(name)) {
    // Penalize by extra word count — more words = less confident.
    final extraWords = words.length - queryWords.length;
    return 0.3 + extraWords * 0.05;
  }

  // Partial substring match.
  if (name.contains(query)) return 0.7 + words.length * 0.02;

  // No match at all (shouldn't happen since the API searched for it).
  return 1.0;
}

/// Select products for a staple card.
/// Selects up to [_minStapleItems] **distinct products** (by product ID),
/// guaranteeing at least one per store, then returns all store instances for
/// those selected products so prices across stores can be displayed.
/// [stapleJudgements] maps product IDs to their net judgement score
/// (positive = confirmed staple, negative = denied).
List<Product> _selectStapleProducts(
  List<Product> products,
  String stapleName,
  Set<int> storeIds, {
  Map<int, int> stapleJudgements = const {},
  Map<int, double> stapleHeuristics = const {},
}) {
  // Filter to selected stores and deduplicate by instanceId.
  final seen = <int>{};
  final eligible = <Product>[];
  for (final product in products) {
    if (!storeIds.contains(product.storeId)) continue;
    if (seen.add(product.instanceId)) {
      eligible.add(product);
    }
  }

  // Filter out products denied by judgements (net score < 0).
  final candidates = <Product>[];
  for (final product in eligible) {
    final score = stapleJudgements[product.id];
    if (score != null && score < 0) continue; // denied by users
    candidates.add(product);
  }

  // Score and sort by confidence, boosted by judgements.
  candidates.sort((a, b) {
    var ca = _stapleConfidence(a, stapleName);
    var cb = _stapleConfidence(b, stapleName);
    // Boost confirmed products (lower confidence = better).
    final sa = stapleJudgements[a.id];
    final sb = stapleJudgements[b.id];
    if (sa != null && sa > 0) ca -= 0.5;
    if (sb != null && sb > 0) cb -= 0.5;
    // Heuristic boost/demote when no explicit judgement exists.
    if (sa == null) {
      final ha = stapleHeuristics[a.id];
      if (ha != null) ca -= (ha - 0.5) * 0.6;
    }
    if (sb == null) {
      final hb = stapleHeuristics[b.id];
      if (hb != null) cb -= (hb - 0.5) * 0.6;
    }
    final cmp = ca.compareTo(cb);
    if (cmp != 0) return cmp;
    // Tie-break: prefer cheaper.
    final pa = productEffectivePrice(a) ?? double.infinity;
    final pb = productEffectivePrice(b) ?? double.infinity;
    return pa.compareTo(pb);
  });

  // Select up to _minStapleItems DISTINCT product IDs.
  // Skip products that share a variation group with an already-selected one
  // so that the staples view doesn't show redundant flavors/styles.
  final selectedProductIds = <int>{};
  final claimedVariationGroups = <String>{};

  // Helper: returns true if a product can be selected (not a duplicate
  // variation of something already chosen).
  bool canSelect(Product p) {
    if (selectedProductIds.contains(p.id)) return true; // already in
    final vg = p.variationGroup;
    if (vg != null && vg.isNotEmpty && claimedVariationGroups.contains(vg)) {
      return false;
    }
    return true;
  }

  void markSelected(Product p) {
    selectedProductIds.add(p.id);
    final vg = p.variationGroup;
    if (vg != null && vg.isNotEmpty) {
      claimedVariationGroups.add(vg);
    }
  }

  // Phase 1: guarantee at least one distinct product per store.
  for (final storeId in storeIds) {
    if (selectedProductIds.length >= _minStapleItems) break;
    final best = candidates.cast<Product?>().firstWhere(
          (p) => p!.storeId == storeId && canSelect(p),
          orElse: () => null,
        );
    if (best != null) markSelected(best);
  }

  // Phase 2: fill remaining slots with best-confidence distinct products.
  for (final product in candidates) {
    if (selectedProductIds.length >= _minStapleItems) break;
    if (canSelect(product)) markSelected(product);
  }

  // Return ALL instances for the selected product IDs so that per-store
  // prices can be shown by groupProductsById downstream.
  return candidates.where((p) => selectedProductIds.contains(p.id)).toList();
}

class StaplesOverview extends StatefulWidget {
  const StaplesOverview({super.key});

  @override
  State<StaplesOverview> createState() => _StaplesOverviewState();
}

class _StaplesOverviewState extends State<StaplesOverview> {
  Future<Map<String, List<Product>>>? _staplesFuture;
  /// Maps (staple_name, product_id) → net score from judgements.
  Map<String, Map<int, int>> _stapleJudgements = {};
  /// Heuristic staple scores inferred from existing labels.
  Map<String, Map<int, double>> _stapleHeuristics = {};
  Set<(int, int)> _confirmedGroupPairs = {};
  Set<(int, int)> _deniedGroupPairs = {};
  /// Product IDs denied as a staple during this session, keyed by staple name.
  final Map<String, Set<int>> _sessionDenied = {};
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
    _loadStapleJudgements(api);
    _loadStapleHeuristics(api);
    _loadGroupingJudgements(api);
  }

  Future<void> _loadStapleJudgements(GroceryApi api) async {
    try {
      final summaries = await api.fetchStapleJudgements();
      if (!mounted) return;
      final map = <String, Map<int, int>>{};
      for (final s in summaries) {
        map.putIfAbsent(s.stapleName, () => {})[s.productId] = s.netScore;
      }
      setState(() {
        _stapleJudgements = map;
      });
    } catch (_) {
      // Best-effort; screen works without judgements.
    }
  }

  Future<void> _loadStapleHeuristics(GroceryApi api) async {
    try {
      final heuristics = await api.fetchStapleHeuristics();
      if (!mounted) return;
      final map = <String, Map<int, double>>{};
      for (final h in heuristics) {
        map.putIfAbsent(h.stapleName, () => {})[h.productId] = h.score;
      }
      setState(() {
        _stapleHeuristics = map;
      });
    } catch (_) {
      // Best-effort.
    }
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

          // Pre-compute staple selections with exclusivity:
          // a product claimed by an earlier staple is excluded from later ones.
          final storeIds = selectedStores.map((s) => s.id).toSet();
          final claimedProductIds = <int>{};
          final stapleSelections = <String, List<Product>>{};
          for (final stapleName in visibleStaples) {
            final products = staples[stapleName]!;
            final denied = _sessionDenied[stapleName] ?? const {};
            final filtered = products.where((p) {
              if (denied.contains(p.id)) return false;
              if (claimedProductIds.contains(p.id)) return false;
              return true;
            }).toList();
            final selected = _selectStapleProducts(
              filtered,
              stapleName,
              storeIds,
              stapleJudgements: _stapleJudgements[stapleName] ?? {},
              stapleHeuristics: _stapleHeuristics[stapleName] ?? {},
            );
            stapleSelections[stapleName] = selected;
            claimedProductIds.addAll(selected.map((p) => p.id));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
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
            itemCount: visibleStaples.length,
            itemBuilder: (context, index) {
              final stapleName = visibleStaples[index];
              final stapleProducts = stapleSelections[stapleName]!;

              return _StapleCard(
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
                  });
                },
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
