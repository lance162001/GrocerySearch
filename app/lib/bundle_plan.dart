import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_front_end/main.dart' show hostname, port, formatPriceString, parsePriceString;

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
  late final TextEditingController _userIdController;
  final TextEditingController _bundleNameController =
      TextEditingController(text: 'Weekly Essentials');
  final TextEditingController _productIdController = TextEditingController();
  final TextEditingController _storeIdController = TextEditingController();
  bool _memberFlag = false;

  bool _loading = false;
  String? _error;
  String? _status;

  // User data
  Map<String, dynamic>? _dashboard;
  List<_BundleSummary> _userBundles = [];
  List<Map<String, dynamic>> _userSavedStores = [];
  final Map<int, String> _storeLabels = {};

  // Selected bundle detail
  _BundleDetail? _selectedBundle;

  @override
  void initState() {
    super.initState();
    _userIdController = TextEditingController(text: '${widget.initialUserId}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadUser();
      }
    });
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _bundleNameController.dispose();
    _productIdController.dispose();
    _storeIdController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int? _parsePositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  void _setError(String message) => setState(() {
        _error = message;
        _status = null;
      });

  void _setStatus(String message) => setState(() {
        _status = message;
        _error = null;
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

  Future<Map<String, dynamic>?> _getObject(Uri uri) async {
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<List<Map<String, dynamic>>?> _getList(Uri uri) async {
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) return null;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _ensureStoreLabels() async {
    if (_storeLabels.isNotEmpty) return;
    final uri = Uri.http('$hostname:$port', '/stores');
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return;
      final List<dynamic> stores = jsonDecode(response.body) as List<dynamic>;
      for (final s in stores) {
        final m = s as Map<String, dynamic>;
        final id = m['id'];
        if (id is! int) continue;
        final town = (m['town'] ?? '').toString();
        final state = (m['state'] ?? '').toString();
        final address = (m['address'] ?? '').toString();
        String label = 'Store $id';
        if (town.isNotEmpty && state.isNotEmpty) {
          label = '$town, $state';
        } else if (address.isNotEmpty) {
          label = address;
        }
        _storeLabels[id] = label;
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Core data loading
  // ---------------------------------------------------------------------------

  /// Load user dashboard, bundles, saved stores.
  Future<void> _loadUser() async {
    final userId = _parsePositiveInt(_userIdController.text);
    if (userId == null) {
      _setError('Enter a valid user id');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = null;
      _selectedBundle = null;
    });

    try {
      await _ensureStoreLabels();

      final dashboardUri = Uri.http('$hostname:$port', '/users/$userId/dashboard');
      final bundlesUri = Uri.http('$hostname:$port', '/users/$userId/bundles');
      final storesUri = Uri.http('$hostname:$port', '/users/$userId/saved-stores');

      final results = await Future.wait([
        _getObject(dashboardUri),
        _getList(bundlesUri),
        _getList(storesUri),
      ]);

      final dashboard = results[0] as Map<String, dynamic>?;
      final bundlesRaw = results[1] as List<Map<String, dynamic>>?;
      final stores = results[2] as List<Map<String, dynamic>>?;

      final bundles = (bundlesRaw ?? []).map((b) => _BundleSummary.fromJson(b)).toList();

      setState(() {
        _dashboard = dashboard;
        _userBundles = bundles;
        _userSavedStores = stores ?? _userSavedStores;
      });

      // Auto-open if we were given an initial bundle id
      if (widget.initialBundleId != null && widget.initialBundleId! > 0) {
        await _openBundle(widget.initialBundleId!);
      }

      _setStatus('User data loaded \u2014 ${bundles.length} bundle(s)');
    } catch (e) {
      _setError('Failed to load user data: $e');
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
      final uri = Uri.http('$hostname:$port', '/bundles/$bundleId/detail');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        _setError('Failed to load bundle detail (${response.statusCode})');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() {
        _selectedBundle = _BundleDetail.fromJson(data);
        _status = null;
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
    final userId = _parsePositiveInt(_userIdController.text);
    final name = _bundleNameController.text.trim();
    if (userId == null) {
      _setError('Enter a valid user id');
      return;
    }
    if (name.isEmpty) {
      _setError('Enter a bundle name');
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.http('$hostname:$port', '/users/$userId/bundles'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode != 200) {
        _setError('Failed to create bundle (${response.statusCode})');
        return;
      }
      _setStatus('Bundle created');
      await _loadUser();
    } catch (e) {
      _setError('Create bundle failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addProductToBundle() async {
    if (_selectedBundle == null) {
      _setError('Open a bundle first');
      return;
    }
    final productId = _parsePositiveInt(_productIdController.text);
    if (productId == null) {
      _setError('Enter a valid product id');
      return;
    }

    setState(() => _loading = true);
    try {
      final bundleId = _selectedBundle!.id;
      final response = await http.post(
        Uri.http('$hostname:$port', '/bundles/$bundleId/products'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'product_id': productId}),
      );
      if (response.statusCode != 200) {
        _setError('Failed to add product (${response.statusCode})');
        return;
      }
      _setStatus('Product added');
      await _openBundle(bundleId);
    } catch (e) {
      _setError('Add product failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveStoreForUser() async {
    final userId = _parsePositiveInt(_userIdController.text);
    final storeId = _parsePositiveInt(_storeIdController.text);
    if (userId == null || storeId == null) {
      _setError('Enter valid user id and store id');
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.http('$hostname:$port', '/users/$userId/saved-stores'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'store_id': storeId, 'member': _memberFlag}),
      );
      if (response.statusCode != 200) {
        _setError('Failed to save store (${response.statusCode})');
        return;
      }
      _setStatus('Store saved');
      await _loadUser();
    } catch (e) {
      _setError('Save store failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createDemoBundle() async {
    final userId = _parsePositiveInt(_userIdController.text);
    if (userId == null) {
      _setError('Enter a valid user id');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selectedBundle = null;
    });

    try {
      final headers = {'Content-Type': 'application/json'};

      final createBundleResponse = await http.post(
        Uri.http('$hostname:$port', '/users/$userId/bundles'),
        headers: headers,
        body: jsonEncode({
          'name': 'Demo Bundle ${DateTime.now().toIso8601String().substring(0, 19)}',
        }),
      );

      if (createBundleResponse.statusCode != 200) {
        _setError('Failed to create demo bundle (${createBundleResponse.statusCode})');
        return;
      }

      final created = jsonDecode(createBundleResponse.body) as Map<String, dynamic>;
      final int? bundleId = created['id'] as int?;
      if (bundleId == null) {
        _setError('Demo bundle created without a valid id');
        return;
      }

      final productsResponse = await http.get(
        Uri.http('$hostname:$port', '/products', {'page': '1', 'size': '8'}),
      );

      if (productsResponse.statusCode == 200) {
        final productsPage = jsonDecode(productsResponse.body) as Map<String, dynamic>;
        final items = (productsPage['items'] as List<dynamic>? ?? []);
        int added = 0;
        for (final item in items) {
          final m = item as Map<String, dynamic>;
          final id = m['id'];
          if (id is int) {
            await http.post(
              Uri.http('$hostname:$port', '/bundles/$bundleId/products'),
              headers: headers,
              body: jsonEncode({'product_id': id}),
            );
            added++;
            if (added >= 5) break;
          }
        }
      }

      final storesResponse = await http.get(Uri.http('$hostname:$port', '/stores'));
      if (storesResponse.statusCode == 200) {
        final stores = jsonDecode(storesResponse.body) as List<dynamic>;
        int savedCount = 0;
        for (final s in stores) {
          final m = s as Map<String, dynamic>;
          final id = m['id'];
          if (id is! int) continue;
          await http.post(
            Uri.http('$hostname:$port', '/users/$userId/saved-stores'),
            headers: headers,
            body: jsonEncode({'store_id': id, 'member': false}),
          );
          savedCount++;
          if (savedCount >= 3) break;
        }
      }

      await _loadUser();
      await _openBundle(bundleId);
    } catch (e) {
      _setError('Failed to create demo bundle: $e');
    } finally {
      setState(() => _loading = false);
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
        title: const Text('User & Bundle Planner'),
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
          // ---- Top bar: user id + load ----
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'User ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _loading ? null : _loadUser,
                  child: const Text('Load user'),
                ),
              ],
            ),
          ),

          // ---- Status / error banners ----
          if (_status != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_status!, style: TextStyle(color: Colors.green.shade800, fontSize: 13)),
            ),
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

          // ---- Dashboard summary ----
          if (_dashboard != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('Bundles: ${_dashboard!['bundle_count'] ?? '-'}'),
                    Text('Saved stores: ${_dashboard!['saved_store_count'] ?? '-'}'),
                    Text('Visits: ${_dashboard!['visit_count'] ?? '-'}'),
                    Text('Recent zip: ${_dashboard!['recent_zipcode'] ?? '-'}'),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

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
        // ---- Quick actions ----
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _bundleNameController,
                decoration: const InputDecoration(
                  labelText: 'New bundle name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            FilledButton.tonal(
              onPressed: _loading ? null : _createBundle,
              child: const Text('Create bundle'),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _storeIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Store ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            FilterChip(
              label: const Text('Member'),
              selected: _memberFlag,
              onSelected: _loading ? null : (v) => setState(() => _memberFlag = v),
            ),
            FilledButton.tonal(
              onPressed: _loading ? null : _saveStoreForUser,
              child: const Text('Save store'),
            ),
            TextButton.icon(
              onPressed: _loading ? null : _createDemoBundle,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Demo bundle'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ---- Saved stores ----
        if (_userSavedStores.isNotEmpty) ...[
          Text('Saved Stores', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _userSavedStores.map((s) {
              final storeId = s['store_id'];
              final label = _storeName(storeId);
              final isMember = s['member'] == true;
              return Chip(
                avatar: Icon(isMember ? Icons.star : Icons.store, size: 16),
                label: Text(label, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],

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

        // ---- Add product ----
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _productIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Product ID to add',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _loading ? null : _addProductToBundle,
              child: const Text('Add product'),
            ),
          ],
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
                    child: Image.network(
                      product.pictureUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48),
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
