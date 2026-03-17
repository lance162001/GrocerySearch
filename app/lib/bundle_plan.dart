import 'package:flutter/material.dart';
import 'package:flutter_front_end/product_search.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class _BundleSummary {
  final int id;
  final int userId;
  final String name;
  final DateTime? createdAt;
  final int productCount;
  final List<int> productIds;

  _BundleSummary({
    required this.id,
    required this.userId,
    required this.name,
    this.createdAt,
    required this.productCount,
    required this.productIds,
  });

  factory _BundleSummary.fromJson(Map<String, dynamic> j) => _BundleSummary(
        id: j['id'] as int,
        userId: j['user_id'] as int,
        name: j['name']?.toString() ?? '',
        createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
        productCount: j['product_count'] as int? ?? 0,
        productIds: (j['product_ids'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
      );
}

class _PricePointData {
  final String basePrice;
  final String? salePrice;
  final String? memberPrice;
  final String? size;
  final DateTime? createdAt;

  _PricePointData({
    required this.basePrice,
    this.salePrice,
    this.memberPrice,
    this.size,
    this.createdAt,
  });

  factory _PricePointData.fromJson(Map<String, dynamic> j) => _PricePointData(
        basePrice: j['base_price']?.toString() ?? '0',
        salePrice: j['sale_price']?.toString(),
        memberPrice: j['member_price']?.toString(),
        size: j['size']?.toString(),
        createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
      );

  double? get effectivePrice =>
      parsePriceString(memberPrice ?? '') ??
      parsePriceString(salePrice ?? '') ??
      parsePriceString(basePrice);
}

class _InstanceData {
  final int storeId;
  final List<_PricePointData> pricePoints;

  _InstanceData({required this.storeId, required this.pricePoints});

  factory _InstanceData.fromJson(Map<String, dynamic> j) => _InstanceData(
        storeId: j['store_id'] as int,
        pricePoints: (j['price_points'] as List<dynamic>? ?? [])
            .map((e) => _PricePointData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class _BundleProduct {
  final int productId;
  final String name;
  final String brand;
  final String pictureUrl;
  final List<_InstanceData> instances;

  _BundleProduct({
    required this.productId,
    required this.name,
    required this.brand,
    required this.pictureUrl,
    required this.instances,
  });

  factory _BundleProduct.fromJson(Map<String, dynamic> j) => _BundleProduct(
        productId: j['product_id'] as int,
        name: j['name']?.toString() ?? '',
        brand: j['brand']?.toString() ?? '',
        pictureUrl: j['picture_url']?.toString() ?? '',
        instances: (j['instances'] as List<dynamic>? ?? [])
            .map((e) => _InstanceData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Lowest effective price across all instances.
  double? get bestPrice {
    double? best;
    for (final inst in instances) {
      for (final pp in inst.pricePoints) {
        final p = pp.effectivePrice;
        if (p != null && (best == null || p < best)) best = p;
      }
    }
    return best;
  }
}

class _BundleDetail {
  final int id;
  final int userId;
  final String name;
  final DateTime? createdAt;
  final int productCount;
  final List<_BundleProduct> products;

  _BundleDetail({
    required this.id,
    required this.userId,
    required this.name,
    this.createdAt,
    required this.productCount,
    required this.products,
  });

  factory _BundleDetail.fromJson(Map<String, dynamic> j) => _BundleDetail(
        id: j['id'] as int,
        userId: j['user_id'] as int,
        name: j['name']?.toString() ?? '',
        createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
        productCount: j['product_count'] as int? ?? 0,
        products: (j['products'] as List<dynamic>? ?? [])
            .map((e) => _BundleProduct.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class BundlePlanPage extends StatefulWidget {
  const BundlePlanPage({
    super.key,
    required this.initialUserId,
    this.initialBundleId,
  });

  final int initialUserId;
  final int? initialBundleId;

  @override
  State<BundlePlanPage> createState() => _BundlePlanPageState();
}

class _BundlePlanPageState extends State<BundlePlanPage> {
  final TextEditingController _bundleNameController =
      TextEditingController(text: 'Weekly Essentials');

  bool _loading = false;
  String? _error;

  List<_BundleSummary> _userBundles = [];
  final Map<int, String> _storeLabels = {};

  // Selected bundle detail
  _BundleDetail? _selectedBundle;

  GroceryApi get _api => context.read<GroceryApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadUser();
      }
    });
  }

  @override
  void dispose() {
    _bundleNameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _setError(String message) => setState(() {
        _error = message;
      });

  String _money(num? value) {
    final n = value?.toDouble() ?? 0;
    return '\$${n.toStringAsFixed(2)}';
  }

  String _storeName(dynamic rawStoreId) {
    if (rawStoreId is! int) return 'Store';
    return _storeLabels[rawStoreId] ?? 'Store $rawStoreId';
  }

  // ---------------------------------------------------------------------------
  // Network helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _getObject(String path) async {
    return _api.getObject(path);
  }

  Future<List<Map<String, dynamic>>?> _getList(String path) async {
    return _api.getObjectList(path);
  }

  Future<void> _ensureStoreLabels() async {
    if (_storeLabels.isNotEmpty) return;
    try {
      final stores = await _api.fetchAllStores();
      for (final store in stores) {
        final id = store.id;
        String label = 'Store $id';
        if (store.town.isNotEmpty && store.state.isNotEmpty) {
          label = '${store.town}, ${store.state}';
        } else if (store.address.isNotEmpty) {
          label = store.address;
        }
        _storeLabels[id] = label;
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Core data loading
  // ---------------------------------------------------------------------------

  /// Load user bundles.
  Future<void> _loadUser() async {
    final userId = widget.initialUserId;

    setState(() {
      _loading = true;
      _error = null;
      _selectedBundle = null;
    });

    try {
      await _ensureStoreLabels();

      final bundlesRaw = await _getList('/users/$userId/bundles');
      final bundles = (bundlesRaw ?? []).map((b) => _BundleSummary.fromJson(b)).toList();

      setState(() {
        _userBundles = bundles;
      });

      // Auto-open if we were given an initial bundle id
      if (widget.initialBundleId != null && widget.initialBundleId! > 0) {
        await _openBundle(widget.initialBundleId!);
      }
    } catch (e) {
      _setError('Failed to load bundles: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Fetch full detail for a specific bundle and show it.
  Future<void> _openBundle(int bundleId) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedBundle = null;
    });

    try {
      await _ensureStoreLabels();
      final data = await _getObject('/bundles/$bundleId/detail');
      if (data == null) {
        _setError('Failed to load bundle detail');
        return;
      }
      setState(() {
        _selectedBundle = _BundleDetail.fromJson(data);
      });
    } catch (e) {
      _setError('Error loading bundle: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _createBundle() async {
    final userId = widget.initialUserId;
    final name = _bundleNameController.text.trim();
    if (name.isEmpty) {
      _setError('Enter a bundle name');
      return;
    }

    setState(() => _loading = true);
    try {
      await _api.createBundle(userId, name);
      await _loadUser();
    } catch (e) {
      _setError('Create bundle failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addItemsToBundle(int bundleId, String bundleName) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SearchPage(bundleId: bundleId, bundleName: bundleName),
      ),
    );
    if (mounted) {
      _openBundle(bundleId);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bundle Planner'),
        actions: [
          if (_selectedBundle != null)
            IconButton(
              tooltip: 'Back to bundles',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedBundle = null),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
            ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),

          // ---- Main content ----
          Expanded(
            child: _selectedBundle != null
                ? _buildBundleDetail(cs)
                : _buildBundleList(cs),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bundle list view (preloaded)
  // ---------------------------------------------------------------------------

  Widget _buildBundleList(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        // ---- Create bundle ----
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bundleNameController,
                  decoration: const InputDecoration(
                    labelText: 'New bundle name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loading ? null : _createBundle,
                child: const Text('Create bundle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---- Bundles ----
        Text(
          'Your Bundles',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface),
        ),
        const SizedBox(height: 6),

        if (_userBundles.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No bundles yet. Create one or generate a demo.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),

        ..._userBundles.map((bundle) {
          final dateStr = bundle.createdAt != null
              ? '${bundle.createdAt!.month}/${bundle.createdAt!.day}/${bundle.createdAt!.year}'
              : '';
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text('${bundle.productCount}', style: TextStyle(color: cs.onPrimaryContainer)),
              ),
              title: Text(bundle.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${bundle.productCount} product(s) \u2022 $dateStr'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openBundle(bundle.id),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bundle detail view
  // ---------------------------------------------------------------------------

  Widget _buildBundleDetail(ColorScheme cs) {
    final bundle = _selectedBundle!;

    // Compute totals
    double totalBest = 0;
    for (final p in bundle.products) {
      totalBest += p.bestPrice ?? 0;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        // ---- Header ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bundle.name,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: cs.onSurface),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedBundle = null),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text('${bundle.productCount} product(s)'),
                  Text('Best\u2011price total: ${_money(totalBest)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ---- Add items ----
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Add items to bundle'),
            onPressed: _loading ? null : () => _addItemsToBundle(bundle.id, bundle.name),
          ),
        ),
        const SizedBox(height: 12),

        // ---- Product cards ----
        if (bundle.products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('This bundle has no products yet.',
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
          ),

        ...bundle.products.map((product) => _buildProductCard(product, cs)),
      ],
    );
  }

  Widget _buildProductCard(_BundleProduct product, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Product header ----
            Row(
              children: [
                if (product.pictureUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ProductImage(
                      url: product.pictureUrl,
                      width: 48,
                      height: 48,
                    ),
                  ),
                if (product.pictureUrl.isNotEmpty) const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (product.brand.isNotEmpty)
                        Text(product.brand,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                if (product.bestPrice != null)
                  Text(
                    _money(product.bestPrice),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: cs.primary,
                    ),
                  ),
              ],
            ),

            // ---- Price points by store ----
            if (product.instances.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text('Price Points by Store',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              ...product.instances.map((inst) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _storeName(inst.storeId),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        if (inst.pricePoints.isEmpty)
                          Text('No price data',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ...inst.pricePoints.map((pp) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              children: [
                                // Size
                                if (pp.size != null && pp.size!.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.secondaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(pp.size!,
                                        style: TextStyle(
                                            fontSize: 11, color: cs.onSecondaryContainer)),
                                  ),
                                // Base price
                                Text(
                                  formatPriceString(pp.basePrice),
                                  style: (pp.salePrice != null && pp.salePrice!.isNotEmpty) ||
                                          (pp.memberPrice != null && pp.memberPrice!.isNotEmpty)
                                      ? TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                          decoration: TextDecoration.lineThrough,
                                        )
                                      : const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                // Sale price
                                if (pp.salePrice != null && pp.salePrice!.isNotEmpty)
                                  Text(
                                    formatPriceString(pp.salePrice!),
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (pp.salePrice != null && pp.salePrice!.isNotEmpty)
                                  const SizedBox(width: 8),
                                // Member price
                                if (pp.memberPrice != null && pp.memberPrice!.isNotEmpty)
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      formatPriceString(pp.memberPrice!),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                // Date
                                if (pp.createdAt != null)
                                  Text(
                                    '${pp.createdAt!.month}/${pp.createdAt!.day}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
