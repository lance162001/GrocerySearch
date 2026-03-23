import 'package:flutter/material.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/utils/product_grouping.dart';
import 'package:flutter_front_end/utils/product_recommendation_sort.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/utils/scroll_utils.dart';
import 'package:flutter_front_end/widgets/product_detail_sheet.dart';
import 'package:flutter_front_end/widgets/top_level_navigation.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:provider/provider.dart';

String _formatAmount(double amount) => '\$${amount.toStringAsFixed(2)}';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.bundleId, this.bundleName});

  /// When set, the page operates in bundle-add mode: every product added to
  /// cart is also queued to be added to this bundle, and the checkout button
  /// is replaced with a Done button.
  final int? bundleId;
  final String? bundleName;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const int pageLength = 100;

  final Map<int, int> quantities = <int, int>{};
  final ScrollController scrollController = ScrollController();
  final TextEditingController searchFieldController = TextEditingController();

  int page = 1;
  bool showOnlySpread = false;
  bool showOnlySale = false;
  bool _initialized = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Future<List<Product>>? _productsFuture;
  Set<(int, int)> _confirmedPairs = {};
  Set<(int, int)> _deniedPairs = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    final appState = context.read<AppState>();
    searchFieldController.text = appState.searchTerm;
    _productsFuture = _loadProducts(resetPage: true);
    setupScrollListener(
      scrollController: scrollController,
      onAtBottom: _loadMoreProducts,
    );
    _loadGroupingJudgements();
    _initialized = true;
  }

  Future<void> _loadGroupingJudgements() async {
    try {
      final api = context.read<GroceryApi>();
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
        _confirmedPairs = confirmed;
        _deniedPairs = denied;
      });
    } catch (_) {
      // Best-effort; grouping works without judgements.
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    searchFieldController.dispose();
    super.dispose();
  }

  void _addToCart(Product product, int qty) {
    context.read<AppState>().addToCartQty(product, qty);
    final bundleId = widget.bundleId;
    if (bundleId != null) {
      context.read<GroceryApi>().addProductToBundle(bundleId, product.id);
    }
  }

  void _removeFromCart(Product product) {
    context.read<AppState>().removeFromCartAll(product);
  }

  void _toggleProduct(Product product, AppState appState) {
    final qty = quantities[product.instanceId] ?? 1;
    if (appState.quantityFor(product) > 0) {
      _removeFromCart(product);
    } else {
      _addToCart(product, qty);
    }
  }

  void _changeRequestedQty(Product product, int delta) {
    setState(() {
      final current = quantities[product.instanceId] ?? 1;
      quantities[product.instanceId] = (current + delta).clamp(1, 999);
    });
  }

  bool _hasSalePrice(Product product) {
    bool hasValue(String value) {
      final normalized = value.trim().toLowerCase();
      return normalized.isNotEmpty &&
          normalized != 'null' &&
          normalized != 'none';
    }

    return hasValue(product.salePrice) || hasValue(product.memberPrice);
  }

  List<ProductGroup> _groupProducts(List<Product> products, String searchTerm) {
    final groups = groupProductsById(
      products,
      confirmedPairs: _confirmedPairs,
      deniedPairs: _deniedPairs,
    );
    final sortedProducts = sortProductsByRecommendation(
      groups.map((group) => group.primaryProduct).toList(growable: false),
      searchTerm,
    );
    final groupsByProductId = <int, ProductGroup>{
      for (final group in groups) group.primaryProduct.id: group,
    };
    return sortedProducts
        .map((product) => groupsByProductId[product.id]!)
        .toList(growable: false);
  }

  List<ProductGroup> _applyViewFilters(
    List<Product> products,
    String searchTerm,
  ) {
    var groups = _groupProducts(products, searchTerm);
    if (showOnlySale) {
      groups = groups
          .where((group) => group.options.any(_hasSalePrice))
          .toList(growable: false);
    }
    if (showOnlySpread) {
      groups = groups
          .where((group) => group.hasPriceSpread)
          .toList(growable: false);
    }
    return groups;
  }

  int _groupCartQuantity(ProductGroup group, AppState appState) {
    var total = 0;
    for (final option in group.options) {
      total += appState.quantityFor(option);
    }
    return total;
  }

  int _groupRequestedQuantity(ProductGroup group) {
    return quantities[group.primaryProduct.instanceId] ?? 1;
  }

  void _toggleGroupedProduct(ProductGroup group, AppState appState) {
    _toggleProduct(group.primaryProduct, appState);
  }

  Store? _storeForId(int storeId) {
    for (final store in context.read<AppState>().userStores) {
      if (store.id == storeId) {
        return store;
      }
    }
    return null;
  }

  Company? _companyForId(int companyId) {
    for (final company in context.read<AppState>().companies) {
      if (company.id == companyId) {
        return company;
      }
    }
    return null;
  }

  Future<List<Product>> _loadProducts({
    bool resetPage = false,
    List<Product> toAdd = const [],
    int? targetPage,
  }) {
    final appState = context.read<AppState>();
    final storeIds = appState.userStores.map((store) => store.id).toList();
    if (resetPage) {
      page = 1;
      _hasMore = true;
    }
    if (storeIds.isEmpty) {
      return Future.value(<Product>[]);
    }
    return context.read<GroceryApi>().fetchProducts(
          storeIds,
          search: appState.searchTerm,
          tags: appState.userTags,
          onSaleOnly: showOnlySale,
          spreadOnly: showOnlySpread,
          page: targetPage ?? page,
          size: pageLength,
          toAdd: toAdd,
        );
  }

  Future<void> _reloadProducts() async {
    setState(() {
      _productsFuture = _loadProducts(resetPage: true);
    });
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore || _productsFuture == null) {
      return;
    }

    _isLoadingMore = true;
    try {
      final existing = await _productsFuture!;
      if (!mounted) {
        return;
      }
      if (existing.length < page * pageLength) {
        _hasMore = false;
        return;
      }

      final nextPage = page + 1;
      final nextProducts = await _loadProducts(
        targetPage: nextPage,
        toAdd: existing,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        page = nextPage;
        _hasMore = nextProducts.length > existing.length;
        _productsFuture = Future.value(nextProducts);
      });
    } finally {
      _isLoadingMore = false;
    }
  }

  Widget _buildSummaryChip({
    required String label,
    Widget? leading,
    Color? backgroundColor,
    Color? borderColor,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? const Color(0xFFE4E4E7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) leading,
          if (leading != null) const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor ?? const Color(0xFF27272A),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBestStoreChip(ProductGroup group) {
    final bestOption = group.primaryProduct;
    final store = _storeForId(bestOption.storeId);
    final logoUrl = _companyForId(bestOption.companyId)?.logoUrl ?? '';
    final label = store == null ? 'Best selected-store option' : 'Best at ${store.town}';
    final leading = logoUrl.isEmpty
        ? Icon(
            Icons.storefront_outlined,
            size: 16,
            color: const Color(0xFF1b4332),
          )
        : ProductImage(url: logoUrl, width: 18, height: 18);
    return _buildSummaryChip(
      label: label,
      leading: leading,
      backgroundColor: const Color(0xFFE9F7EE),
      borderColor: const Color(0xFF95D5B2),
      textColor: const Color(0xFF1b4332),
    );
  }

  Widget _buildOtherStoresChip(ProductGroup group) {
    final lowestAlternatePrice = group.lowestAlternatePrice;
    final label = lowestAlternatePrice == null
        ? group.otherStoreCount == 1
            ? '1 more store'
            : '${group.otherStoreCount} more stores'
        : group.otherStoreCount == 1
            ? '1 more store from ${_formatAmount(lowestAlternatePrice)}'
            : '${group.otherStoreCount} more stores from ${_formatAmount(lowestAlternatePrice)}';
    return _buildSummaryChip(
      label: label,
      leading: Icon(
        Icons.local_offer_outlined,
        size: 16,
        color: const Color(0xFF71717A),
      ),
    );
  }

  Future<void> _showProductDetails(
    BuildContext context,
    ProductGroup group,
    AppState appState,
  ) async {
    final storeIds =
        appState.userStores.map((s) => s.id).toList();
    await showProductDetailSheet(
      context: context,
      group: group,
      storeLookup: _storeForId,
      companyLookup: _companyForId,
      cartQuantityFor: appState.quantityFor,
      onToggleOption: (option) => _toggleProduct(option, appState),
      storeIds: storeIds,
      fetchVariations: context.read<GroceryApi>().fetchVariations,
      confirmedPairs: _confirmedPairs,
      deniedPairs: _deniedPairs,
    );
  }

  Widget _buildStatusPill(BuildContext context, Product product) {
    Color? backgroundColor;
    String? label;

    if (product.salePrice.isNotEmpty) {
      backgroundColor = Colors.redAccent;
      label = 'SALE';
    } else if (product.memberPrice.isNotEmpty) {
      backgroundColor = Theme.of(context).colorScheme.primary;
      label = 'MEMBER';
    }

    if (label == null || backgroundColor == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildQuantityStepper(ProductGroup group, Product product) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: InkResponse(
              onTap: () => _changeRequestedQty(product, -1),
              radius: 12,
              child: const Icon(
                Icons.remove_circle_outline,
                size: 13,
              ),
            ),
          ),
          SizedBox(
            width: 18,
            child: Text(
              '${_groupRequestedQuantity(group)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 14,
            height: 14,
            child: InkResponse(
              onTap: () => _changeRequestedQty(product, 1),
              radius: 12,
              child: const Icon(
                Icons.add_circle_outline,
                size: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionBar(
    BuildContext context,
    ProductGroup group,
    Product product,
    AppState appState,
  ) {
    final primarySelected = appState.quantityFor(product) > 0;
    final hasStatusPill =
        product.salePrice.isNotEmpty || product.memberPrice.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: () => _toggleGroupedProduct(group, appState),
              icon: Icon(
                primarySelected
                    ? Icons.remove_shopping_cart
                    : Icons.add_shopping_cart,
                size: 16,
              ),
              label: Text(
                primarySelected ? 'Remove' : 'Add',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          _buildQuantityStepper(group, product),
          if (hasStatusPill) _buildStatusPill(context, product),
        ],
      ),
    );
  }

  Widget _buildPriceSpreadBadge({
    required double amount,
    required bool isBestPrice,
    required int storeCount,
  }) {
    final amountLabel = _formatAmount(amount);
    final foregroundColor =
        isBestPrice ? const Color(0xFF1b4332) : Colors.orange.shade900;
    final backgroundColor =
        isBestPrice ? const Color(0xFFE9F7EE) : Colors.orange.shade50;
    final borderColor =
        isBestPrice ? const Color(0xFF95D5B2) : Colors.orange.shade200;
    final icon =
        isBestPrice ? Icons.savings_outlined : Icons.trending_up_rounded;
    final label = isBestPrice ? 'Save $amountLabel' : '+$amountLabel';
    final tooltip = isBestPrice
        ? 'Best price across $storeCount selected stores. Up to $amountLabel lower than the priciest option.'
        : '$amountLabel above the best selected-store price across $storeCount stores.';

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSheet(AppState appState) {
    return StatefulBuilder(
      builder: (context, modalSetState) {
        return SizedBox(
          height: 320,
          child: Column(
            children: [
              const Text(
                'Filters',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Show only items on sale',
                      style: TextStyle(fontSize: 14),
                    ),
                    Switch(
                      value: showOnlySale,
                      onChanged: (value) {
                        modalSetState(() => showOnlySale = value);
                        _reloadProducts();
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Show items with price spread',
                      style: TextStyle(fontSize: 14),
                    ),
                    Switch(
                      value: showOnlySpread,
                      onChanged: (value) {
                        modalSetState(() => showOnlySpread = value);
                        _reloadProducts();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(),
              const Text(
                'Filter By Tags',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 150,
                child: SingleChildScrollView(
                  child: Wrap(
                    runSpacing: 2,
                    spacing: 5,
                    children: appState.tags
                        .map(
                          (tag) => FilterChip(
                            label: Text(tag.name),
                            selected: appState.userTags.contains(tag),
                            onSelected: (selected) {
                              appState.toggleTag(tag);
                              _reloadProducts();
                              modalSetState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final stores = appState.userStores;

    return Scaffold(
      appBar: AppBar(
        title: Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            onSubmitted: (text) {
              appState.setSearchTerm(text);
              _reloadProducts();
            },
            controller: searchFieldController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: Color(0xFF71717A)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Color(0xFF71717A)),
                onPressed: () {
                  searchFieldController.clear();
                  appState.setSearchTerm('');
                  _reloadProducts();
                },
              ),
              hintText: 'Search by product...',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        actions: [
          IconButton(
            iconSize: 32,
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (context) => _buildFilterSheet(appState),
              );
            },
          ),
          if (widget.bundleId != null)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
        ],
      ),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            if (stores.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Select at least one store before searching products.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              );
            }

            final groupedProducts = _applyViewFilters(
              snapshot.data!,
              appState.searchTerm,
            );
            if (groupedProducts.isEmpty) {
              final message = showOnlySale
                  ? 'No products found that are currently on sale'
                  : showOnlySpread
                      ? 'No products found with price differences across stores'
                      : 'No Products Found!';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              );
            }

            return ListView.builder(
              controller: scrollController,
              itemCount: groupedProducts.length,
              padding: const EdgeInsets.all(1),
              itemBuilder: (context, index) {
                final group = groupedProducts[index];
                final product = group.primaryProduct;
                final groupQuantity = _groupCartQuantity(group, appState);
                final primarySelected = appState.quantityFor(product) > 0;

                return Card(
                  color: groupQuantity > 0
                      ? const Color(0xFFE9F7EE)
                      : Colors.white,
                  clipBehavior: Clip.hardEdge,
                  child: InkWell(
                    splashColor: const Color(0xFF1b4332).withAlpha(20),
                    onTap: () {
                      _toggleGroupedProduct(group, appState);
                    },
                    onLongPress: () {
                      _showProductDetails(context, group, appState);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compactCard = constraints.maxWidth < 430;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (compactCard) ...[
                                ProductBox(
                                  p: product,
                                  qty: groupQuantity,
                                ),
                                _buildCompactActionBar(
                                  context,
                                  group,
                                  product,
                                  appState,
                                ),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ProductBox(
                                        p: product,
                                        qty: groupQuantity,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      width: 72,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            iconSize: 22,
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            icon: primarySelected
                                                ? const Icon(Icons.remove_shopping_cart)
                                                : const Icon(Icons.add_shopping_cart),
                                            onPressed: () {
                                              _toggleGroupedProduct(group, appState);
                                            },
                                            tooltip: primarySelected
                                                ? 'Remove cheapest option from cart'
                                                : 'Add cheapest option to cart',
                                          ),
                                          const SizedBox(height: 4),
                                          _buildQuantityStepper(group, product),
                                          const SizedBox(height: 6),
                                          _buildStatusPill(context, product),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  top: 2,
                                  bottom: 4,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildBestStoreChip(group),
                                    if (group.otherStoreCount > 0)
                                      _buildOtherStoresChip(group),
                                    if (group.priceSpread != null)
                                      _buildPriceSpreadBadge(
                                        amount: group.priceSpread!,
                                        isBestPrice: true,
                                        storeCount: group.storeCount,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
      bottomNavigationBar: widget.bundleId == null
          ? const SafeArea(
              top: false,
              child: TopLevelNavigationBar(
                currentDestination: AppTopLevelDestination.search,
              ),
            )
          : null,
    );
  }
}
