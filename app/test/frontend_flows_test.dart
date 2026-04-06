import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/app_environment.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/suggest_store.dart';
import 'package:flutter_front_end/services/auth_service.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _company = Company(
  id: 1,
  name: 'Trader Joes',
  logoUrl: '/logos/trader-joes.png',
);

const _austinStore = Store(
  id: 7,
  companyId: 1,
  scraperId: 7,
  town: 'Austin',
  state: 'TX',
  address: '123 Market St',
  zipcode: '78701',
);

const _dallasStore = Store(
  id: 8,
  companyId: 1,
  scraperId: 8,
  town: 'Dallas',
  state: 'TX',
  address: '456 Store Ave',
  zipcode: '75201',
);

const _frozenTag = Tag(id: 1, name: 'Frozen');
const _bakeryTag = Tag(id: 2, name: 'Bakery');

Product _product({
  required int id,
  required int instanceId,
  required int storeId,
  required String name,
  String brand = 'Store Brand',
  String memberPrice = '',
  String salePrice = '',
  String basePrice = '1.00',
  String size = '16 oz',
  String? variationGroup,
}) {
  return Product(
    id: id,
    instanceId: instanceId,
    lastUpdated: DateTime(2026, 3, 13, 10),
    brand: brand,
    memberPrice: memberPrice,
    salePrice: salePrice,
    basePrice: basePrice,
    size: size,
    pictureUrl: '/static/$instanceId.png',
    name: name,
    priceHistory: [
      PricePoint(
        memberPrice: memberPrice,
        salePrice: salePrice,
        basePrice: basePrice,
        size: size,
        timestamp: DateTime(2026, 3, 13, 10),
      ),
    ],
    companyId: 1,
    storeId: storeId,
    variationGroup: variationGroup,
  );
}

class TestGroceryApi extends GroceryApi {
  TestGroceryApi({
    required this.allStores,
    required this.allProducts,
    Map<String, List<Store>>? storeSearchResults,
    Map<int, Set<int>>? productTags,
    Map<String, dynamic>? dashboardResponse,
    List<Map<String, dynamic>>? userBundlesResponse,
    List<Map<String, dynamic>>? userSavedStoresResponse,
    Map<int, Map<String, dynamic>>? bundleDetails,
    int startingBundleId = 600,
  })  : storeSearchResults = storeSearchResults ?? <String, List<Store>>{},
        productTags = productTags ?? <int, Set<int>>{},
        dashboardResponse = dashboardResponse ??
            <String, dynamic>{
              'bundle_count': 0,
              'saved_store_count': 0,
              'visit_count': 0,
              'recent_zipcode': '78701',
            },
        userBundlesResponse = userBundlesResponse ?? <Map<String, dynamic>>[],
        userSavedStoresResponse =
            userSavedStoresResponse ?? <Map<String, dynamic>>[],
        bundleDetails = bundleDetails ?? <int, Map<String, dynamic>>{},
        _nextBundleId = startingBundleId,
        super(environment: AppEnvironment.local);

  final List<Store> allStores;
  final List<Product> allProducts;
  final Map<String, List<Store>> storeSearchResults;
  final Map<int, Set<int>> productTags;
  final Map<String, dynamic> dashboardResponse;
  final List<Map<String, dynamic>> userBundlesResponse;
  final List<Map<String, dynamic>> userSavedStoresResponse;
  final Map<int, Map<String, dynamic>> bundleDetails;

  final List<Map<String, Object?>> fetchProductsRequests =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> savedStoreCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> createBundleCalls = <Map<String, Object?>>[];
  final List<Map<String, int>> addProductCalls = <Map<String, int>>[];

  int _nextBundleId;

  @override
  Future<List<Store>> fetchStores(
    String search, {
    int page = 1,
    int size = 8,
  }) async {
    final normalized = search.trim().toLowerCase();
    if (storeSearchResults.containsKey(normalized)) {
      return List<Store>.from(storeSearchResults[normalized]!);
    }

    return allStores.where((store) {
      if (normalized.isEmpty) {
        return true;
      }
      return store.town.toLowerCase().contains(normalized) ||
          store.address.toLowerCase().contains(normalized) ||
          store.zipcode.contains(normalized);
    }).toList();
  }

  @override
  Future<List<Store>> fetchAllStores() async => List<Store>.from(allStores);

  @override
  Future<List<Tag>> fetchTags() async => const <Tag>[_frozenTag, _bakeryTag];

  @override
  Future<List<Company>> fetchCompanies() async => const <Company>[_company];

  @override
  Future<List<Product>> fetchProducts(
    List<int> storeIds, {
    String search = '',
    List<Tag> tags = const <Tag>[],
    bool onSaleOnly = false,
    bool spreadOnly = false,
    int page = 1,
    int size = 100,
    List<Product> toAdd = const <Product>[],
  }) async {
    fetchProductsRequests.add(<String, Object?>{
      'storeIds': List<int>.from(storeIds),
      'search': search,
      'tagIds': tags.map((tag) => tag.id).toList(),
      'onSaleOnly': onSaleOnly,
      'page': page,
      'size': size,
    });

    var products =
        allProducts.where((product) => storeIds.contains(product.storeId));

    if (search.trim().isNotEmpty) {
      final normalized = search.toLowerCase();
      products = products.where(
        (product) =>
            product.name.toLowerCase().contains(normalized) ||
            product.brand.toLowerCase().contains(normalized),
      );
    }

    if (tags.isNotEmpty) {
      final requiredTagIds = tags.map((tag) => tag.id).toSet();
      products = products.where((product) {
        final ids = productTags[product.id] ?? const <int>{};
        return requiredTagIds.every(ids.contains);
      });
    }

    if (onSaleOnly) {
      products = products.where(
        (product) =>
            product.salePrice.trim().isNotEmpty ||
            product.memberPrice.trim().isNotEmpty,
      );
    }

    final filtered = products.toList();
    final start = (page - 1) * size;
    if (start >= filtered.length) {
      return List<Product>.from(toAdd);
    }
    final end = min(start + size, filtered.length);
    return <Product>[
      ...toAdd,
      ...filtered.sublist(start, end),
    ];
  }

  @override
  Future<void> saveStoreForUser(
    int userId,
    int storeId, {
    bool member = false,
  }) async {
    savedStoreCalls.add(<String, Object?>{
      'userId': userId,
      'storeId': storeId,
      'member': member,
    });
    if (!userSavedStoresResponse.any((entry) => entry['store_id'] == storeId)) {
      userSavedStoresResponse.add(<String, dynamic>{
        'store_id': storeId,
        'member': member,
      });
    }
  }

  @override
  Future<int> createBundle(int userId, String name) async {
    final bundleId = _nextBundleId++;
    createBundleCalls.add(<String, Object?>{
      'userId': userId,
      'name': name,
      'bundleId': bundleId,
    });
    userBundlesResponse.add(<String, dynamic>{
      'id': bundleId,
      'user_id': userId,
      'name': name,
      'created_at': '2026-03-13T10:00:00',
      'product_count': 0,
      'product_ids': <int>[],
    });
    bundleDetails.putIfAbsent(
      bundleId,
      () => <String, dynamic>{
        'id': bundleId,
        'user_id': userId,
        'name': name,
        'created_at': '2026-03-13T10:00:00',
        'product_count': 0,
        'products': <Map<String, dynamic>>[],
      },
    );
    return bundleId;
  }

  @override
  Future<void> addProductToBundle(int bundleId, int productId) async {
    addProductCalls.add(<String, int>{
      'bundleId': bundleId,
      'productId': productId,
    });
  }

  @override
  Future<Map<String, dynamic>?> getObject(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    if (path == '/users/42/dashboard') {
      return Map<String, dynamic>.from(dashboardResponse);
    }
    if (path == '/products') {
      return <String, dynamic>{
        'items': allProducts
            .map((product) => <String, dynamic>{'id': product.id})
            .toList(),
      };
    }
    if (path.startsWith('/bundles/') && path.endsWith('/detail')) {
      final id = int.tryParse(path.split('/')[2]);
      if (id != null && bundleDetails.containsKey(id)) {
        return Map<String, dynamic>.from(bundleDetails[id]!);
      }
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>?> getObjectList(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    if (path == '/users/42/bundles') {
      return userBundlesResponse
          .map((bundle) => Map<String, dynamic>.from(bundle))
          .toList();
    }
    if (path == '/users/42/saved-stores') {
      return userSavedStoresResponse
          .map((store) => Map<String, dynamic>.from(store))
          .toList();
    }
    return null;
  }

  @override
  Future<List<Product>> fetchVariations(int productId, List<int> storeIds) async {
    return allProducts
        .where((p) {
          if (p.id == productId) return false;
          if (!storeIds.contains(p.storeId)) return false;
          final source = allProducts.cast<Product?>().firstWhere(
              (s) => s!.id == productId, orElse: () => null);
          if (source == null) return false;
          final vg = source.variationGroup;
          return vg != null && vg.isNotEmpty && p.variationGroup == vg;
        })
        .toList();
  }

  @override
  Future<Map<String, List<Product>>> fetchStapleProducts(
    List<int> storeIds,
    List<String> stapleNames,
  ) async {
    final storeIdSet = storeIds.toSet();
    final result = <String, List<Product>>{
      for (final name in stapleNames) name: <Product>[],
    };
    for (final product in allProducts) {
      if (!storeIdSet.contains(product.storeId)) {
        continue;
      }
      for (final stapleName in stapleNames) {
        if (product.name.toLowerCase().contains(stapleName)) {
          result[stapleName] = <Product>[
            ...result[stapleName] ?? const <Product>[],
            product,
          ];
        }
      }
    }
    return result;
  }

  @override
  Future<List<GroupingJudgementSummary>> fetchGroupingJudgements() async {
    return const <GroupingJudgementSummary>[];
  }
}

class DelayedStaplesApi extends TestGroceryApi {
  DelayedStaplesApi({
    required super.allStores,
    required super.allProducts,
    required this.staplesResult,
  });

  final Map<String, List<Product>> staplesResult;
  final Completer<Map<String, List<Product>>> _staplesCompleter =
      Completer<Map<String, List<Product>>>();

  void completeStaplesLoad() {
    if (_staplesCompleter.isCompleted) {
      return;
    }
    _staplesCompleter.complete(staplesResult);
  }

  @override
  Future<Map<String, List<Product>>> fetchStapleProducts(
    List<int> storeIds,
    List<String> stapleNames,
  ) {
    return _staplesCompleter.future;
  }
}

AppState _seededState(
  TestGroceryApi api, {
  int currentUserId = 42,
  List<Company> companies = const <Company>[_company],
  List<Tag> tags = const <Tag>[_frozenTag, _bakeryTag],
  List<Tag> userTags = const <Tag>[],
  List<Store> userStores = const <Store>[],
  List<Product> cart = const <Product>[],
  List<Product> cartFinished = const <Product>[],
  Map<int, int> cartQuantities = const <int, int>{},
  String searchTerm = '',
}) {
  final state = AppState(api: api)
    ..currentUserId = currentUserId
    ..companies = List<Company>.from(companies)
    ..tags = List<Tag>.from(tags)
    ..userTags = List<Tag>.from(userTags)
    ..userStores = List<Store>.from(userStores)
    ..cart = List<Product>.from(cart)
    ..cartFinished = List<Product>.from(cartFinished)
    ..searchTerm = searchTerm
    ..bootstrappingUser = false;
  state.cartQuantities.addAll(cartQuantities);
  return state;
}

class _TestAuthService extends AuthService {
  _TestAuthService() : super.test();

  @override
  bool get isSignedIn => true;

  @override
  String? get displayName => 'Test User';

  @override
  String? get email => 'test@example.com';

  @override
  String? get photoUrl => null;
}

Widget _buildTestApp({
  required Widget home,
  required TestGroceryApi api,
  required AppState appState,
}) {
  return MultiProvider(
    providers: [
      Provider<AppEnvironment>.value(value: AppEnvironment.local),
      Provider<GroceryApi>.value(value: api),
      ChangeNotifierProvider<AuthService>.value(value: _TestAuthService()),
      ChangeNotifierProvider<AppState>.value(value: appState),
    ],
    child: MaterialApp(
      home: home,
      routes: {
        AppRoutes.suggestStore: (context) => const SuggestStorePage(),
      },
    ),
  );
}

Future<void> _pumpUi(WidgetTester tester, {int frames = 4}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _switchForLabel(String label) {
  final labeledRow = find.ancestor(
    of: find.text(label),
    matching: find.byType(Row),
  );
  return find.descendant(of: labeledRow, matching: find.byType(Switch));
}

Map<String, dynamic> _bundleDetail({
  required int bundleId,
  required String name,
  required List<Map<String, dynamic>> products,
}) {
  return <String, dynamic>{
    'id': bundleId,
    'user_id': 42,
    'name': name,
    'created_at': '2026-03-13T10:00:00',
    'product_count': products.length,
    'products': products,
  };
}

Map<String, dynamic> _bundleProductJson({
  required int productId,
  required String name,
  required String basePrice,
  int storeId = 7,
}) {
  return <String, dynamic>{
    'product_id': productId,
    'name': name,
    'brand': 'Store Brand',
    'picture_url': '/static/$productId.png',
    'instances': <Map<String, dynamic>>[
      <String, dynamic>{
        'store_id': storeId,
        'price_points': <Map<String, dynamic>>[
          <String, dynamic>{
            'base_price': basePrice,
            'sale_price': '',
            'member_price': '',
            'size': '16 oz',
            'created_at': '2026-03-13T10:00:00',
          },
        ],
      },
    ],
  };
}

// All legacy screen tests have been removed as part of the Markup redesign.
// The screens they tested (StoreSearch, SearchPage, StaplesOverview, CheckOut,
// BundlePlanPage, LabelJudgementPage) have been deleted.
void main() {
  group('frontend widget flows', () {
    testWidgets(
      'staples overview shows progressive card loading before grouped content renders',
      (tester) async {},
      skip: true, // legacy screen removed
    );

    testWidgets(
      'store selection, search, sale filter, checkout, and save bundle flow',
      (tester) async {},
      skip: true, // legacy screen removed
    );

    testWidgets(
      'search page tag filters request tagged products',
      (tester) async {},
      skip: true, // legacy screen removed
    );

    testWidgets(
      'search page groups duplicate store matches and details can add a higher-priced option',
      (tester) async {},
      skip: true, // legacy screen removed
    );

    testWidgets(
      'search page defaults to recommended order for milk',
      (tester) async {},
      skip: true, // legacy screen removed
    );

    testWidgets(
      'store search can reopen product search after filtered search is dismissed',
      (tester) async {},
      skip: true, // legacy screen removed
    );

    testWidgets(
      'checkout moves items between todo and done columns',
      (tester) async {},
      skip: true, // legacy screen removed
    );

    testWidgets(
      'bundle planner loads detail and adds a product',
      (tester) async {},
      skip: true, // legacy screen removed
    );
  });
}
