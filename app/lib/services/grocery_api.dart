import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_front_end/config/app_environment.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/user_id_cache.dart' as user_cache;
import 'package:http/http.dart' as http;

class GroceryApi {
  GroceryApi({required this.environment, http.Client? client})
      : _client = client ?? http.Client();

  final AppEnvironment environment;
  final http.Client _client;

  Map<String, String> get jsonHeaders =>
      const {HttpHeaders.contentTypeHeader: 'application/json'};

  Uri buildUri(String path, [Map<String, String>? queryParameters]) {
    return environment.uri(path, queryParameters);
  }

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
    return _client.get(uri, headers: headers ?? jsonHeaders);
  }

  Future<http.Response> post(
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
  }) {
    return _client.post(uri, headers: headers ?? jsonHeaders, body: body);
  }

  Future<Map<String, dynamic>?> getObject(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await get(buildUri(path, queryParameters));
    if (response.statusCode != 200) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getObjectList(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await get(buildUri(path, queryParameters));
    if (response.statusCode != 200) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      return null;
    }
    return decoded
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<int> fetchOrCreateUserId() async {
    // If a Firebase user is signed in, resolve the backend user by their UID so
    // that the same account always maps to the same bundles on any device.
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      final response = await post(
        buildUri('/users/lookup-or-create'),
        body: jsonEncode({'firebase_uid': firebaseUser.uid}),
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to resolve user: ${response.statusCode} ${response.body}',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final userId = decoded['id'];
      if (userId is! int || userId <= 0) {
        throw Exception('Backend returned invalid user id');
      }
      await user_cache.writeCachedUserId(userId);
      return userId;
    }

    // Anonymous fallback: use locally cached ID or create a new one.
    final cachedUserId = await user_cache.readCachedUserId();
    if (cachedUserId != null && cachedUserId > 0) {
      return cachedUserId;
    }

    final response = await post(buildUri('/users/create'));
    if (response.statusCode == 404) {
      const fallbackUserId = 1;
      await user_cache.writeCachedUserId(fallbackUserId);
      return fallbackUserId;
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to create user: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final userId = decoded['id'];
    if (userId is! int || userId <= 0) {
      throw Exception('Backend returned invalid user id');
    }

    await user_cache.writeCachedUserId(userId);
    return userId;
  }

  Future<List<Product>> fetchProducts(
    List<int> storeIds, {
    String search = '',
    List<Tag> tags = const [],
    bool onSaleOnly = false,
    bool spreadOnly = false,
    int page = 1,
    int size = 100,
    List<Product> toAdd = const [],
  }) async {
    final queryParams = <String, String>{
      'page': '$page',
      'size': '$size',
      if (search.isNotEmpty) 'search': search,
      if (onSaleOnly) 'on_sale': 'true',
      if (spreadOnly) 'has_spread': 'true',
    };
    final response = await post(
      buildUri('/stores/product_search', queryParams),
      body: jsonEncode({
        'ids': storeIds,
        'tags': tags.map((tag) => tag.id).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load products');
    }

    final items = _extractItemsPage(jsonDecode(response.body));
    return [
      ...toAdd,
      ...items
          .map((entry) => Product.fromJson(Map<String, dynamic>.from(entry as Map<dynamic, dynamic>)))
          ,
    ];
  }

  Future<List<Store>> fetchStores(
    String search, {
    int page = 1,
    int size = 8,
  }) async {
    final queryParams = <String, String>{
      'page': '$page',
      'size': '$size',
      if (search.isNotEmpty) 'search': search,
    };
    final response = await get(buildUri('/stores/search', queryParams));
    if (response.statusCode != 200) {
      throw Exception('Failed to load stores');
    }

    return _extractItemsPage(jsonDecode(response.body))
        .map((entry) => Store.fromJson(Map<String, dynamic>.from(entry as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<List<Store>> fetchAllStores() async {
    final response = await get(buildUri('/stores'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load all stores');
    }

    return (jsonDecode(response.body) as List<dynamic>)
        .map((entry) => Store.fromJson(Map<String, dynamic>.from(entry as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<Set<int>> fetchSavedStoreIdsForUser(int userId) async {
    final response = await get(buildUri('/users/$userId/saved-stores'));
    if (response.statusCode == 404) {
      return <int>{};
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to load saved stores: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final List<dynamic> payload;
    if (decoded is List<dynamic>) {
      payload = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['items'] is List<dynamic>) {
      payload = decoded['items'] as List<dynamic>;
    } else {
      return <int>{};
    }

    return payload
        .map((entry) => (entry as Map<String, dynamic>)['store_id'])
        .map((value) => value is int ? value : int.tryParse('$value'))
        .whereType<int>()
        .toSet();
  }

  Future<void> saveStoreForUser(
    int userId,
    int storeId, {
    bool member = false,
  }) async {
    final response = await post(
      buildUri('/users/$userId/saved-stores'),
      body: jsonEncode({'store_id': storeId, 'member': member}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed saving store $storeId: ${response.statusCode}');
    }
  }

  Future<List<Tag>> fetchTags() async {
    final response = await get(buildUri('/products/tags'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load tags');
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((entry) => Tag.fromJson(Map<String, dynamic>.from(entry as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<List<Company>> fetchCompanies() async {
    final response = await get(buildUri('/company'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load companies');
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((entry) => Company.fromJson(Map<String, dynamic>.from(entry as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<int> createBundle(int userId, String name) async {
    final response = await post(
      buildUri('/users/$userId/bundles'),
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 200) {
      throw Exception('Create bundle failed (${response.statusCode})');
    }
    final created = jsonDecode(response.body) as Map<String, dynamic>;
    final bundleId = created['id'];
    if (bundleId is! int || bundleId <= 0) {
      throw Exception('Invalid bundle id returned by backend');
    }
    return bundleId;
  }

  Future<void> addProductToBundle(int bundleId, int productId) async {
    final response = await post(
      buildUri('/bundles/$bundleId/products'),
      body: jsonEncode({'product_id': productId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to add product $productId (${response.statusCode})');
    }
  }

  Future<Map<String, List<Product>>> fetchStapleProducts(
    List<int> storeIds,
    List<String> stapleNames,
  ) async {
    final results = <String, List<Product>>{};
    final futures = <String, Future<List<Product>>>{};
    for (final name in stapleNames) {
      futures[name] = fetchProducts(storeIds, search: name, size: 50);
    }
    for (final entry in futures.entries) {
      try {
        results[entry.key] = await entry.value;
      } catch (_) {
        results[entry.key] = [];
      }
    }
    return results;
  }

  List<dynamic> _extractItemsPage(dynamic json) {
    if (json is Map<String, dynamic> && json['items'] is List<dynamic>) {
      return json['items'] as List<dynamic>;
    }
    if (json is List<dynamic>) {
      return json;
    }
    return const [];
  }

  /// Fetch random products to judge as staple or grouping.
  Future<List<JudgementCandidate>> fetchJudgementCandidates({
    required String judgementType,
    required int userId,
    int count = 5,
  }) async {
    final response = await get(buildUri('/products/judgement-candidates', {
      'judgement_type': judgementType,
      'user_id': '$userId',
      'count': '$count',
    }));
    if (response.statusCode != 200) {
      throw Exception('Failed to load judgement candidates: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => JudgementCandidate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Submit a staple or grouping judgement.
  Future<void> submitJudgement({
    required int userId,
    required int productId,
    required String judgementType,
    required bool approved,
    int? targetProductId,
    String? stapleName,
    String? flavour,
  }) async {
    final body = <String, dynamic>{
      'user_id': userId,
      'product_id': productId,
      'judgement_type': judgementType,
      'approved': approved,
    };
    if (targetProductId != null) {
      body['target_product_id'] = targetProductId;
    }
    if (stapleName != null) {
      body['staple_name'] = stapleName;
    }
    if (flavour != null) {
      body['flavour'] = flavour;
    }
    final response = await post(
      buildUri('/products/judgement'),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to submit judgement: ${response.statusCode}');
    }
  }

  /// Fetch aggregated staple judgements across all users.
  Future<List<StapleJudgementSummary>> fetchStapleJudgements() async {
    final list = await getObjectList('/products/staple-judgements');
    if (list == null) return [];
    return list.map((e) => StapleJudgementSummary.fromJson(e)).toList();
  }

  /// Fetch aggregated grouping judgements across all users.
  Future<List<GroupingJudgementSummary>> fetchGroupingJudgements() async {
    final list = await getObjectList('/products/grouping-judgements');
    if (list == null) return [];
    return list.map((e) => GroupingJudgementSummary.fromJson(e)).toList();
  }

  /// Fetch heuristic staple scores inferred from existing user labels.
  Future<List<StapleHeuristic>> fetchStapleHeuristics() async {
    final list = await getObjectList('/products/staple-heuristics');
    if (list == null) return [];
    return list.map((e) => StapleHeuristic.fromJson(e)).toList();
  }

  /// Fetch other products in the same variation group.
  Future<List<Product>> fetchVariations(int productId, List<int> storeIds) async {
    final uri = buildUri('/products/$productId/variations').replace(
      queryParameters: {
        'store_ids': storeIds.map((id) => '$id').toList(),
      },
    );
    final response = await get(uri);
    if (response.statusCode != 200) {
      return [];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Submit a new store suggestion.
  Future<void> suggestStore({
    required int companyId,
    required String address,
    required String town,
    required String state,
    required String zipcode,
  }) async {
    final response = await post(
      buildUri('/stores/suggest'),
      body: jsonEncode({
        'company_id': companyId,
        'address': address,
        'town': town,
        'state': state,
        'zipcode': zipcode,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to suggest store: ${response.statusCode}');
    }
  }
}