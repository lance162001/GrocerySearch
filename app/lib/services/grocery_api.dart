import 'dart:convert';
import 'dart:io';

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
    int page = 1,
    int size = 100,
    List<Product> toAdd = const [],
  }) async {
    final queryParams = <String, String>{
      'page': '$page',
      'size': '$size',
      if (search.isNotEmpty) 'search': search,
      if (onSaleOnly) 'on_sale': 'true',
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

  List<dynamic> _extractItemsPage(dynamic json) {
    if (json is Map<String, dynamic> && json['items'] is List<dynamic>) {
      return json['items'] as List<dynamic>;
    }
    if (json is List<dynamic>) {
      return json;
    }
    return const [];
  }
}