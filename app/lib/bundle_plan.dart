import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_front_end/main.dart' show hostname, port;

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
  late final TextEditingController _bundleIdController;
  final TextEditingController _bundleNameController =
      TextEditingController(text: 'Weekly Essentials');
  final TextEditingController _productIdController = TextEditingController();
  final TextEditingController _storeIdController = TextEditingController();
  final TextEditingController _visitStoreIdController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _status;
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _dashboard;
  List<Map<String, dynamic>> _userBundles = [];
  List<Map<String, dynamic>> _userSavedStores = [];
  List<Map<String, dynamic>> _userVisits = [];
  final Map<int, String> _storeLabels = {};
  bool _memberFlag = false;

  @override
  void initState() {
    super.initState();
    _userIdController = TextEditingController(text: '${widget.initialUserId}');
    _bundleIdController = TextEditingController(
      text: '${widget.initialBundleId ?? 1}',
    );

    if (widget.initialBundleId != null && widget.initialBundleId! > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchPlan();
        }
      });
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _bundleIdController.dispose();
    _bundleNameController.dispose();
    _productIdController.dispose();
    _storeIdController.dispose();
    _visitStoreIdController.dispose();
    super.dispose();
  }

  int? _parsePositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  void _setError(String message) {
    setState(() {
      _error = message;
      _status = null;
    });
  }

  void _setStatus(String message) {
    setState(() {
      _status = message;
      _error = null;
    });
  }

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

  Future<List<Map<String, dynamic>>?> _getPageItems(Uri uri) async {
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final items = decoded['items'];
    if (items is! List<dynamic>) return null;
    return items
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _fetchPlan() async {
    final bundleId = int.tryParse(_bundleIdController.text.trim());
    if (bundleId == null || bundleId <= 0) {
      setState(() {
        _error = 'Enter a valid bundle id';
        _plan = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    final uri = Uri.http(
      '$hostname:$port',
      '/bundles/$bundleId/plan',
      {'use_saved_stores': 'true'},
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        await _ensureStoreLabels();
        setState(() {
          _plan = jsonDecode(response.body) as Map<String, dynamic>;
          _error = null;
          _status = 'Bundle plan loaded';
        });
      } else {
        setState(() {
          _plan = null;
          _error = 'Request failed (${response.statusCode}): ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _plan = null;
        _error = 'Network error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
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

  String _storeName(dynamic rawStoreId) {
    if (rawStoreId is! int) return 'Store';
    return _storeLabels[rawStoreId] ?? 'Store $rawStoreId';
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
      _plan = null;
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
        setState(() {
          _error = 'Failed to create demo bundle (${createBundleResponse.statusCode})';
        });
        return;
      }

      final created = jsonDecode(createBundleResponse.body) as Map<String, dynamic>;
      final int? bundleId = created['id'] as int?;
      if (bundleId == null) {
        setState(() {
          _error = 'Demo bundle created without a valid id';
        });
        return;
      }

      final productsResponse = await http.get(
        Uri.http('$hostname:$port', '/products', {'page': '1', 'size': '8'}),
      );

      if (productsResponse.statusCode != 200) {
        setState(() {
          _error = 'Failed to fetch products for demo bundle';
        });
        return;
      }

      final productsPage = jsonDecode(productsResponse.body) as Map<String, dynamic>;
      final items = (productsPage['items'] as List<dynamic>? ?? []);
      final productIds = <int>[];
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final id = m['id'];
        if (id is int) productIds.add(id);
        if (productIds.length >= 5) break;
      }

      for (final pid in productIds) {
        await http.post(
          Uri.http('$hostname:$port', '/bundles/$bundleId/products'),
          headers: headers,
          body: jsonEncode({'product_id': pid}),
        );
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

      _bundleIdController.text = '$bundleId';
      _userIdController.text = '$userId';
      await _fetchPlan();
      await _refreshUserData();
    } catch (e) {
      setState(() {
        _error = 'Failed to create demo bundle: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bundleId = data['id'];
      if (bundleId is int) {
        _bundleIdController.text = '$bundleId';
      }
      await _refreshUserData();
      _setStatus('Bundle created');
    } catch (e) {
      _setError('Create bundle failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addProductToBundle() async {
    final bundleId = _parsePositiveInt(_bundleIdController.text);
    final productId = _parsePositiveInt(_productIdController.text);
    if (bundleId == null || productId == null) {
      _setError('Enter valid bundle id and product id');
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.http('$hostname:$port', '/bundles/$bundleId/products'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'product_id': productId}),
      );
      if (response.statusCode != 200) {
        _setError('Failed to add product (${response.statusCode})');
        return;
      }
      await _fetchPlan();
      await _refreshUserData();
      _setStatus('Product added to bundle');
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
      await _refreshUserData();
      _setStatus('Saved store updated');
    } catch (e) {
      _setError('Save store failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _logVisit() async {
    final bundleId = _parsePositiveInt(_bundleIdController.text);
    if (bundleId == null) {
      _setError('Enter a valid bundle id');
      return;
    }

    final rawStore = _visitStoreIdController.text.trim();
    final storeId = rawStore.isEmpty ? null : _parsePositiveInt(rawStore);
    if (rawStore.isNotEmpty && storeId == null) {
      _setError('Visit store id must be a positive integer');
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.http('$hostname:$port', '/bundles/$bundleId/visit'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'store_id': storeId}),
      );
      if (response.statusCode != 200) {
        _setError('Failed to log visit (${response.statusCode})');
        return;
      }
      await _refreshUserData();
      _setStatus('Visit logged');
    } catch (e) {
      _setError('Log visit failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshUserData() async {
    final userId = _parsePositiveInt(_userIdController.text);
    if (userId == null) {
      _setError('Enter a valid user id');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      await _ensureStoreLabels();
      final dashboardUri = Uri.http('$hostname:$port', '/users/$userId/dashboard');
      final bundlesUri = Uri.http('$hostname:$port', '/users/$userId/bundles');
      final storesUri = Uri.http('$hostname:$port', '/users/$userId/saved-stores');
      final visitsUri = Uri.http('$hostname:$port', '/users/$userId/visits');

      final dashboard = await _getObject(dashboardUri);
      final bundles = await _getList(bundlesUri);
      final stores = await _getList(storesUri);
      final visits = await _getList(visitsUri);

      setState(() {
        _dashboard = dashboard;
        _userBundles = bundles ?? _userBundles;
        _userSavedStores = stores ?? _userSavedStores;
        _userVisits = visits ?? _userVisits;
      });

      if (dashboard == null && bundles == null && stores == null && visits == null) {
        _setStatus('User list endpoints are not available on this backend yet');
      } else {
        _setStatus('User data refreshed');
      }
    } catch (e) {
      _setError('Refresh user data failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _money(num? value) {
    final n = value?.toDouble() ?? 0;
    return '\$${n.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    return Scaffold(
      appBar: AppBar(title: const Text('User & Bundle Planner')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'User ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _loading ? null : _refreshUserData,
                  child: const Text('Load user'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bundleIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bundle ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _fetchPlan,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bundleNameController,
                    decoration: const InputDecoration(
                      labelText: 'Bundle name',
                      border: OutlineInputBorder(),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _productIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Product ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _loading ? null : _addProductToBundle,
                  child: const Text('Add product'),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _storeIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Store ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilterChip(
                  label: const Text('Member store'),
                  selected: _memberFlag,
                  onSelected: _loading
                      ? null
                      : (value) {
                          setState(() => _memberFlag = value);
                        },
                ),
                FilledButton.tonal(
                  onPressed: _loading ? null : _saveStoreForUser,
                  child: const Text('Save store'),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _visitStoreIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Visit Store ID (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _loading ? null : _logVisit,
                  child: const Text('Log visit'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _createDemoBundle,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Create demo bundle'),
              ),
            ),
            const SizedBox(height: 12),
            if (_status != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_status!, style: TextStyle(color: Colors.green.shade800)),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
              ),
            const SizedBox(height: 8),
            if (_dashboard != null)
              Container(
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
                    Text('Dashboard', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Bundles: ${_dashboard!['bundle_count'] ?? '-'}'),
                    Text('Saved stores: ${_dashboard!['saved_store_count'] ?? '-'}'),
                    Text('Visits: ${_dashboard!['visit_count'] ?? '-'}'),
                    Text('Recent zip: ${_dashboard!['recent_zipcode'] ?? '-'}'),
                  ],
                ),
              ),
            if (_dashboard != null) const SizedBox(height: 10),
            if (plan != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan['bundle_name']?.toString() ?? 'Bundle',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text('Items: ${plan['item_count']}'),
                    Text('Split-store total: ${_money(plan['split_store_total'] as num?)}'),
                    Text(
                      'Best single-store: ${plan['single_store_best'] == null ? 'N/A' : _money((plan['single_store_best'] as Map<String, dynamic>)['total'] as num?)}',
                    ),
                    Text(
                      'Estimated savings: ${plan['estimated_savings_vs_best_single'] == null ? 'N/A' : _money(plan['estimated_savings_vs_best_single'] as num?)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    if (_userBundles.isNotEmpty) ...[
                      const Text('User bundles', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ..._userBundles.take(8).map((b) {
                        final id = b['id'];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(b['name']?.toString() ?? 'Bundle'),
                          subtitle: Text('ID ${id ?? '-'}'),
                          trailing: id is int
                              ? TextButton(
                                  onPressed: () {
                                    _bundleIdController.text = '$id';
                                    _fetchPlan();
                                  },
                                  child: const Text('Open'),
                                )
                              : null,
                        );
                      }),
                      const Divider(),
                    ],
                    if (_userSavedStores.isNotEmpty) ...[
                      const Text('Saved stores', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ..._userSavedStores.take(8).map((s) {
                        final storeId = s['store_id'];
                        final label = _storeName(storeId);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          subtitle: Text('Store ID ${storeId ?? '-'}'),
                          trailing: Text((s['member'] == true) ? 'Member' : 'Standard'),
                        );
                      }),
                      const Divider(),
                    ],
                    if (_userVisits.isNotEmpty) ...[
                      const Text('Recent visits', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ..._userVisits.take(8).map((v) {
                        final storeId = v['store_id'];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Bundle ${v['bundle_id'] ?? '-'}'),
                          subtitle: Text(
                              '${_storeName(storeId)} • ${v['created_at']?.toString() ?? ''}'),
                        );
                      }),
                      const Divider(),
                    ],
                    const Text('Split by store', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...((plan['split_by_store'] as List<dynamic>? ?? []).map((s) {
                      final row = s as Map<String, dynamic>;
                      final storeId = row['store_id'];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_storeName(storeId)),
                        subtitle: Text('${row['item_count']} items'),
                        trailing: Text(_money(row['total'] as num?)),
                      );
                    })),
                    const Divider(),
                    const Text('Best item picks', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...((plan['lines'] as List<dynamic>? ?? []).map((l) {
                      final row = l as Map<String, dynamic>;
                      final storeId = row['best_store_id'];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(row['product_name']?.toString() ?? ''),
                        subtitle: Text('${row['brand']} • ${_storeName(storeId)}'),
                        trailing: Text(_money(row['best_price'] as num?)),
                      );
                    })),
                  ],
                ),
              ),
            ],
            if (plan == null)
              Expanded(
                child: ListView(
                  children: [
                    if (_userBundles.isNotEmpty) ...[
                      const Text('User bundles', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ..._userBundles.take(8).map((b) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(b['name']?.toString() ?? 'Bundle'),
                            subtitle: Text('ID ${b['id'] ?? '-'}'),
                          )),
                    ] else
                      Text(
                        'Load a user or create a demo bundle to populate user-schema data.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
