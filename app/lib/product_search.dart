import 'package:flutter/material.dart';
import 'package:flutter_front_end/chart.dart';
import 'package:flutter_front_end/check_out.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/utils/product_grouping.dart';
import 'package:flutter_front_end/utils/product_recommendation_sort.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/utils/scroll_utils.dart';
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

  double? _effectivePrice(Product product) {
    return productEffectivePrice(product);
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

  String _displayPrice(Product product) {
    if (product.memberPrice.isNotEmpty) {
      return formatPriceString(product.memberPrice);
    }
    if (product.salePrice.isNotEmpty) {
      return formatPriceString(product.salePrice);
    }
    return formatPriceString(product.basePrice);
  }

  String? _secondaryPriceDetails(Product product) {
    final details = <String>[];
    if (product.memberPrice.isNotEmpty) {
      details.add('Member ${formatPriceString(product.memberPrice)}');
    }
    if (product.salePrice.isNotEmpty) {
      details.add('Sale ${formatPriceString(product.salePrice)}');
    }
    final baseLabel = formatPriceString(product.basePrice);
    if (_displayPrice(product) != baseLabel) {
      details.add('Base $baseLabel');
    }
    return details.isEmpty ? null : details.join(' • ');
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
        color: backgroundColor ?? Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? Colors.blueGrey.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) leading,
          if (leading != null) const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor ?? Colors.blueGrey.shade900,
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
            color: Colors.indigo.shade700,
          )
        : ProductImage(url: logoUrl, width: 18, height: 18);
    return _buildSummaryChip(
      label: label,
      leading: leading,
      backgroundColor: Colors.indigo.shade50,
      borderColor: Colors.indigo.shade100,
      textColor: Colors.indigo.shade900,
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
        color: Colors.blueGrey.shade700,
      ),
    );
  }

  Widget _buildStoreOptionComparisonChip(
    ProductGroup group,
    Product option,
  ) {
    final bestPrice = group.minPrice;
    final optionPrice = _effectivePrice(option);
    final isBestOption = option.instanceId == group.primaryProduct.instanceId;

    var label = 'Lowest price';
    var backgroundColor = Colors.green.shade50;
    var borderColor = Colors.green.shade200;
    var textColor = Colors.green.shade900;

    if (!isBestOption) {
      if (bestPrice == null || optionPrice == null) {
        label = 'Price unavailable';
        backgroundColor = Colors.blueGrey.shade50;
        borderColor = Colors.blueGrey.shade200;
        textColor = Colors.blueGrey.shade900;
      } else if (productPricesMatch(optionPrice, bestPrice)) {
        label = 'Same as lowest';
        backgroundColor = Colors.indigo.shade50;
        borderColor = Colors.indigo.shade200;
        textColor = Colors.indigo.shade900;
      } else {
        label = '+${_formatAmount(optionPrice - bestPrice)} vs lowest';
        backgroundColor = Colors.orange.shade50;
        borderColor = Colors.orange.shade200;
        textColor = Colors.orange.shade900;
      }
    }

    return _buildSummaryChip(
      label: label,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      textColor: textColor,
    );
  }

  Widget _buildStoreOptionCard(
    ProductGroup group,
    Product option,
    AppState appState,
  ) {
    final store = _storeForId(option.storeId);
    final logoUrl = _companyForId(option.companyId)?.logoUrl ?? '';
    final quantity = appState.quantityFor(option);
    final details = _secondaryPriceDetails(option);
    final storeLabel =
        store == null ? 'Store ${option.storeId}' : '${store.town}, ${store.state}';

    return InkWell(
      key: ValueKey<String>('product-option-${option.instanceId}'),
      onTap: () => _showStorePriceHistory(context, option, storeLabel),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: quantity > 0 ? Colors.lightBlue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: quantity > 0 ? Colors.lightBlue.shade200 : Colors.grey.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (logoUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ProductImage(url: logoUrl, width: 24, height: 24),
                  ),
                if (logoUrl.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (store != null && store.address.isNotEmpty)
                        Text(
                          store.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: _buildStoreOptionComparisonChip(group, option)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayPrice(option),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (details != null)
                        Text(
                          details,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                        ),
                      if (option.brand.isNotEmpty)
                        Text(
                          option.brand,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      if (option.size.isNotEmpty)
                        Text(
                          option.size,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              if (quantity > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Qty $quantity',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: ValueKey<String>('product-option-action-${option.instanceId}'),
                onPressed: () {
                  _toggleProduct(option, appState);
                },
                child: Text(quantity > 0 ? 'Remove' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  void _showStorePriceHistory(
    BuildContext context,
    Product option,
    String storeLabel,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (option.brand.isNotEmpty) ...
                [
                  const SizedBox(height: 2),
                  Text(
                    option.brand,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Price history',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: PriceHistoryChart(pricepoints: option.priceHistory),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showProductDetails(
    BuildContext context,
    ProductGroup group,
    AppState appState,
  ) async {
    final product = group.primaryProduct;
    final bestStore = _storeForId(product.storeId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: AnimatedBuilder(
                animation: appState,
                builder: (context, _) {
                  final groupQuantity = _groupCartQuantity(group, appState);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ProductImage(
                              url: product.pictureUrl,
                              width: 84,
                              height: 84,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${product.size} • ${product.brand}',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_displayPrice(product)} at ${bestStore?.town ?? 'Store ${product.storeId}'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (groupQuantity > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.lightBlue.shade50,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.lightBlue.shade200,
                                ),
                              ),
                              child: Text(
                                '$groupQuantity in cart',
                                style: TextStyle(
                                  color: Colors.lightBlue.shade900,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
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
                      const SizedBox(height: 16),
                      Text(
                        'Available at ${group.storeCount} selected stores',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...group.options.map(
                        (option) => _buildStoreOptionCard(group, option, appState),
                      ),
                      if (product.variationGroup != null &&
                          product.variationGroup!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.style_outlined),
                          label: const Text('See flavors / variations'),
                          onPressed: () {
                            final storeIds = context
                                .read<AppState>()
                                .userStores
                                .map((s) => s.id)
                                .toList();
                            _showVariations(context, product, storeIds);
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        'Price history',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 220,
                        child: PriceHistoryChart(pricepoints: product.priceHistory),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
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

  Widget _buildPriceSpreadBadge({
    required double amount,
    required bool isBestPrice,
    required int storeCount,
  }) {
    final amountLabel = _formatAmount(amount);
    final foregroundColor =
        isBestPrice ? Colors.green.shade800 : Colors.orange.shade900;
    final backgroundColor =
        isBestPrice ? Colors.green.shade50 : Colors.orange.shade50;
    final borderColor =
        isBestPrice ? Colors.green.shade200 : Colors.orange.shade200;
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

  void _showVariations(
    BuildContext context,
    Product product,
    List<int> storeIds,
  ) {
    final api = context.read<GroceryApi>();
    final future = api.fetchVariations(product.id, storeIds);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.7,
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
              final groups = groupProductsById(
                variations,
                confirmedPairs: _confirmedPairs,
                deniedPairs: _deniedPairs,
              );
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
                      Text(
                        title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${groups.length} other flavors / styles',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const Divider(height: 20),
                      ...groups.map((group) {
                        final p = group.primaryProduct;
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
                              if (price != null) _formatAmount(price),
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
                                _addToCart(p, 1);
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
            borderRadius: BorderRadius.circular(5),
          ),
          child: TextField(
            onSubmitted: (text) {
              appState.setSearchTerm(text);
              _reloadProducts();
            },
            controller: searchFieldController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  searchFieldController.clear();
                  appState.setSearchTerm('');
                  _reloadProducts();
                },
              ),
              hintText: 'Search By Product...',
              border: InputBorder.none,
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
            )
          else
            Row(
              children: [
                Text(appState.cartTotalItems.toString()),
                IconButton(
                  icon: const Icon(Icons.shopping_cart_checkout),
                  iconSize: 32,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CheckOut()),
                    );
                  },
                ),
              ],
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
                      ? Colors.lightBlue[100]
                      : Colors.white,
                  clipBehavior: Clip.hardEdge,
                  child: InkWell(
                    splashColor: Colors.blue.withAlpha(30),
                    onTap: () {
                      _toggleGroupedProduct(group, appState);
                    },
                    onLongPress: () {
                      _showProductDetails(context, group, appState);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                          ? const Icon(
                                              Icons.remove_shopping_cart)
                                          : const Icon(Icons.add_shopping_cart),
                                      onPressed: () {
                                        _toggleGroupedProduct(group, appState);
                                      },
                                      tooltip: primarySelected
                                          ? 'Remove cheapest option from cart'
                                          : 'Add cheapest option to cart',
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: InkResponse(
                                            onTap: () => _changeRequestedQty(
                                                product, -1),
                                            radius: 12,
                                            child: const Icon(
                                              Icons.remove_circle_outline,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 20,
                                          child: Text(
                                            '${_groupRequestedQuantity(group)}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: InkResponse(
                                            onTap: () =>
                                                _changeRequestedQty(product, 1),
                                            radius: 12,
                                            child: const Icon(
                                              Icons.add_circle_outline,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
    );
  }
}
