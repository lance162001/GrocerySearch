import 'package:flutter/material.dart';
import 'package:flutter_front_end/chart.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/utils/product_grouping.dart';
import 'package:flutter_front_end/widgets/product_image.dart';

// ---------------------------------------------------------------------------
// Public entry-points
// ---------------------------------------------------------------------------

/// Shows the full product detail bottom sheet.
///
/// [group] — the per-store options, cheapest first (required).
/// [storeLookup] / [companyLookup] — optional lookups for store/company
///   metadata; pass null when not available (bundle / shared-bundle contexts).
/// [cartQuantity] — total quantity of this product group in the cart, or null
///   when the cart is not available (shared-bundle context).
/// [onToggleOption] — called when the user taps Add/Remove on a store option;
///   receives the chosen [Product]. Pass null to hide cart action buttons.
/// [onAddToCartVariation] / [onRemoveFromCartVariation] — optional callbacks
///   for variation (flavour) items shown in the variations sub-sheet.
/// [storeIds] — store ids to use when fetching variations; ignored when
///   [fetchVariations] is null.
/// [fetchVariations] — async callback to load variation products. Pass null to
///   hide the "See flavors / variations" button.
Future<void> showProductDetailSheet({
  required BuildContext context,
  required ProductGroup group,
  Store? Function(int storeId)? storeLookup,
  Company? Function(int companyId)? companyLookup,
  int Function(Product)? cartQuantityFor,
  void Function(Product)? onToggleOption,
  List<int> storeIds = const [],
  Future<List<Product>> Function(int productId, List<int> storeIds)?
      fetchVariations,
  Set<(int, int)> confirmedPairs = const {},
  Set<(int, int)> deniedPairs = const {},
}) async {
  final product = group.primaryProduct;
  final selectedForHistory = ValueNotifier<Product>(product);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: Material(
            color: Theme.of(sheetContext).scaffoldBackgroundColor,
            child: _ProductDetailContent(
              group: group,
              storeLookup: storeLookup,
              companyLookup: companyLookup,
              cartQuantityFor: cartQuantityFor,
              onToggleOption: onToggleOption,
              storeIds: storeIds,
              fetchVariations: fetchVariations,
              confirmedPairs: confirmedPairs,
              deniedPairs: deniedPairs,
              selectedForHistory: selectedForHistory,
            ),
          ),
        ),
      );
    },
  );

  selectedForHistory.dispose();
}

// ---------------------------------------------------------------------------
// Internal content widget
// ---------------------------------------------------------------------------

class _ProductDetailContent extends StatelessWidget {
  const _ProductDetailContent({
    required this.group,
    required this.selectedForHistory,
    this.storeLookup,
    this.companyLookup,
    this.cartQuantityFor,
    this.onToggleOption,
    this.storeIds = const [],
    this.fetchVariations,
    this.confirmedPairs = const {},
    this.deniedPairs = const {},
  });

  final ProductGroup group;
  final ValueNotifier<Product> selectedForHistory;
  final Store? Function(int storeId)? storeLookup;
  final Company? Function(int companyId)? companyLookup;
  final int Function(Product)? cartQuantityFor;
  final void Function(Product)? onToggleOption;
  final List<int> storeIds;
  final Future<List<Product>> Function(int productId, List<int> storeIds)?
      fetchVariations;
  final Set<(int, int)> confirmedPairs;
  final Set<(int, int)> deniedPairs;

  Store? _store(int storeId) => storeLookup?.call(storeId);
  Company? _company(int companyId) => companyLookup?.call(companyId);
  int _quantity(Product p) => cartQuantityFor?.call(p) ?? 0;

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

  Widget _summaryChip({
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

  Widget _bestStoreChip() {
    final bestOption = group.primaryProduct;
    final store = _store(bestOption.storeId);
    final logoUrl = _company(bestOption.companyId)?.logoUrl ?? '';
    final label =
        store == null ? 'Best option' : 'Best at ${store.town}';
    final leading = logoUrl.isEmpty
        ? const Icon(Icons.storefront_outlined,
            size: 16, color: Color(0xFF1b4332))
        : ProductImage(url: logoUrl, width: 18, height: 18);
    return _summaryChip(
      label: label,
      leading: leading,
      backgroundColor: const Color(0xFFE9F7EE),
      borderColor: const Color(0xFF95D5B2),
      textColor: const Color(0xFF1b4332),
    );
  }

  Widget _otherStoresChip() {
    final lowestAlt = group.lowestAlternatePrice;
    final count = group.otherStoreCount;
    final label = lowestAlt == null
        ? count == 1 ? '1 more store' : '$count more stores'
        : count == 1
            ? '1 more store from \$${lowestAlt.toStringAsFixed(2)}'
            : '$count more stores from \$${lowestAlt.toStringAsFixed(2)}';
    return _summaryChip(
      label: label,
      leading: const Icon(Icons.local_offer_outlined,
          size: 16, color: Color(0xFF71717A)),
    );
  }

  Widget _comparisonChip(Product option) {
    final bestPrice = group.minPrice;
    final optionPrice = productEffectivePrice(option);
    final isBest = option.instanceId == group.primaryProduct.instanceId;

    var label = 'Lowest price';
    var bg = const Color(0xFFE9F7EE);
    var border = const Color(0xFF95D5B2);
    var fg = const Color(0xFF1b4332);

    if (!isBest) {
      if (bestPrice == null || optionPrice == null) {
        label = 'Price unavailable';
        bg = const Color(0xFFF4F4F5);
        border = const Color(0xFFE4E4E7);
        fg = const Color(0xFF52525B);
      } else if (productPricesMatch(optionPrice, bestPrice)) {
        label = 'Same as lowest';
      } else {
        final delta = optionPrice - bestPrice;
        label = '+\$${delta.toStringAsFixed(2)} vs lowest';
        bg = Colors.orange.shade50;
        border = Colors.orange.shade200;
        fg = Colors.orange.shade900;
      }
    }

    return _summaryChip(
        label: label, backgroundColor: bg, borderColor: border, textColor: fg);
  }

  Widget _priceSpreadBadge(double amount) {
    const fg = Color(0xFF1b4332);
    const bg = Color(0xFFE9F7EE);
    const border = Color(0xFF95D5B2);
    return Tooltip(
      message:
          'Best price across ${group.storeCount} stores. Up to \$${amount.toStringAsFixed(2)} lower than the priciest option.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.savings_outlined, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(
              'Save \$${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: fg, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _storeOptionCard(
    BuildContext context,
    Product option,
    ValueNotifier<Product> selectedForHistory,
  ) {
    final store = _store(option.storeId);
    final logoUrl = _company(option.companyId)?.logoUrl ?? '';
    final quantity = _quantity(option);
    final details = _secondaryPriceDetails(option);
    final storeLabel = store == null
        ? 'Store ${option.storeId}'
        : '${store.town}, ${store.state}';

    return InkWell(
      key: ValueKey<String>('product-option-${option.instanceId}'),
      onTap: () => selectedForHistory.value = option,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: quantity > 0 ? const Color(0xFFE9F7EE) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: quantity > 0
                ? const Color(0xFF95D5B2)
                : const Color(0xFFDCE8DC),
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
                      Text(storeLabel,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      if (store != null && store.address.isNotEmpty)
                        Text(
                          store.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: _comparisonChip(option)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (option.pictureUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ProductImage(
                        url: option.pictureUrl, width: 48, height: 48),
                  ),
                  const SizedBox(width: 10),
                ],
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
                        Text(details,
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 12)),
                      if (option.brand.isNotEmpty)
                        Text(option.brand,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                      if (option.size.isNotEmpty)
                        Text(option.size,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                if (quantity > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Qty $quantity',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                if (onToggleOption != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    key: ValueKey<String>(
                        'product-option-action-${option.instanceId}'),
                    onPressed: () => onToggleOption!(option),
                    child: Text(quantity > 0 ? 'Remove' : 'Add'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = group.primaryProduct;
    final bestStore = _store(product.storeId);

    return AnimatedBuilder(
      animation: selectedForHistory,
      builder: (context, _) {
        final historyProduct = selectedForHistory.value;
        final isDefaultHistory =
            historyProduct.instanceId == product.instanceId;
        final historyStore = isDefaultHistory
            ? bestStore
            : _store(historyProduct.storeId);

        // Total cart quantity across all options in this group.
        final groupQuantity = cartQuantityFor == null
            ? null
            : group.options.fold<int>(0, (acc, o) => acc + _quantity(o));

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            // ── Header ─────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ProductImage(
                      url: product.pictureUrl, width: 84, height: 84),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${product.size} • ${product.brand}',
                        style: TextStyle(
                            color: Colors.grey[700], fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_displayPrice(product)} at ${bestStore?.town ?? 'Store ${product.storeId}'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF18181B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (groupQuantity != null && groupQuantity > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F7EE),
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: const Color(0xFF95D5B2)),
                    ),
                    child: Text(
                      '$groupQuantity in cart',
                      style: const TextStyle(
                        color: Color(0xFF1b4332),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Store summary chips ────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _bestStoreChip(),
                if (group.otherStoreCount > 0) _otherStoresChip(),
                if (group.priceSpread != null)
                  _priceSpreadBadge(group.priceSpread!),
              ],
            ),
            const SizedBox(height: 16),

            // ── Price history ──────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Price history',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      if (!isDefaultHistory)
                        Text(
                          historyStore != null
                              ? historyStore.town
                              : 'Store ${historyProduct.storeId}',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 11),
                        ),
                    ],
                  ),
                ),
                if (!isDefaultHistory)
                  TextButton(
                    onPressed: () =>
                        selectedForHistory.value = product,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Show best store',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: PriceHistoryChart(pricepoints: historyProduct.priceHistory),
            ),
            const SizedBox(height: 16),

            // ── Store options ──────────────────────────────────────────
            Text(
              'Available at ${group.storeCount} store${group.storeCount == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a store to view its price history',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const SizedBox(height: 8),
            ...group.options.map(
              (option) =>
                  _storeOptionCard(context, option, selectedForHistory),
            ),

            // ── Variations ─────────────────────────────────────────────
            if (fetchVariations != null &&
                product.variationGroup != null &&
                product.variationGroup!.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.style_outlined),
                label: const Text('See flavors / variations'),
                onPressed: () => _showVariations(context, product),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showVariations(BuildContext context, Product product) {
    final future = fetchVariations!(product.id, storeIds);
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
                confirmedPairs: confirmedPairs,
                deniedPairs: deniedPairs,
              );
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
                  ...groups.map((group) {
                    final p = group.primaryProduct;
                    final price = productEffectivePrice(p);
                    final inCart = (_quantity(p)) > 0;
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
                      trailing: onToggleOption == null
                          ? null
                          : IconButton(
                              icon: Icon(
                                inCart
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: inCart ? Colors.green : null,
                              ),
                              onPressed: () => onToggleOption!(p),
                            ),
                    );
                  }),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
