import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_front_end/bundle_plan.dart';
import 'package:flutter_front_end/check_out.dart';
import 'package:flutter_front_end/config/app_environment.dart';
import 'package:flutter_front_end/main_search.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/product_search.dart';
import 'package:flutter_front_end/staples_overview.dart';
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
    child: MaterialApp(home: home),
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

void main() {
  group('frontend widget flows', () {
    testWidgets(
      'store selection, search, sale filter, checkout, and save bundle flow',
      (tester) async {
        final apples = _product(
          id: 1,
          instanceId: 101,
          storeId: _austinStore.id,
          name: 'Apples',
          salePrice: '1.99',
          basePrice: '2.49',
        );
        final bread = _product(
          id: 2,
          instanceId: 201,
          storeId: _austinStore.id,
          name: 'Bread',
          basePrice: '3.49',
        );
        final dallasApples = _product(
          id: 1,
          instanceId: 102,
          storeId: _dallasStore.id,
          name: 'Apples',
          basePrice: '2.99',
        );

        final api = TestGroceryApi(
          allStores: <Store>[_austinStore, _dallasStore],
          allProducts: <Product>[apples, bread, dallasApples],
          bundleDetails: <int, Map<String, dynamic>>{},
        );
        final appState = _seededState(api);

        await tester.pumpWidget(
          _buildTestApp(
              home: const StoreSearch(), api: api, appState: appState),
        );
        await _pumpUi(tester);

        expect(find.text('0 selected'), findsOneWidget);
        expect(find.text('Austin'), findsOneWidget);
        expect(find.text('Dallas'), findsOneWidget);

        await tester.tap(find.text('Austin').first);
        await _pumpUi(tester);

        expect(find.text('1 selected'), findsOneWidget);
        expect(appState.userStores, <Store>[_austinStore]);

        await tester.tap(find.text('Selected only'));
        await _pumpUi(tester);

        expect(find.text('Dallas'), findsNothing);

        await tester.tap(find.text('Confirm Stores (1)'));
        await _pumpUi(tester, frames: 8);

        expect(find.byType(StaplesOverview), findsOneWidget);
        expect(api.savedStoreCalls.single['storeId'], _austinStore.id);

        await tester.tap(find.byIcon(Icons.search).first);
        await _pumpUi(tester, frames: 8);

        expect(find.byType(SearchPage), findsOneWidget);

        await tester.tap(find.byType(TextField).first);
        await tester.enterText(find.byType(TextField).first, 'App');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _pumpUi(tester);

        expect(find.text('Apples'), findsOneWidget);
        expect(
          api.fetchProductsRequests.any(
            (request) => request['search'] == 'App',
          ),
          isTrue,
        );

        await tester.tap(find.byIcon(Icons.more_vert));
        await _pumpUi(tester);
        await tester.tap(_switchForLabel('Show only items on sale'));
        await _pumpUi(tester);
        await tester.tapAt(const Offset(20, 20));
        await _pumpUi(tester);

        expect(find.text('Bread'), findsNothing);
        expect(find.text('Apples'), findsOneWidget);

        final applesCard = find
            .ancestor(
                of: find.text('Apples').first, matching: find.byType(Card))
            .first;
        await tester.ensureVisible(applesCard);
        await tester.tap(applesCard);
        await _pumpUi(tester);

        expect(appState.cartTotalItems, 1);
        expect(appState.cart.single.name, 'Apples');

        await tester.tap(find.byIcon(Icons.shopping_cart_checkout));
        await _pumpUi(tester, frames: 8);

        expect(find.byType(CheckOut), findsOneWidget);
        expect(find.text('Total Items: 1'), findsOneWidget);

        await tester.tap(find.text('Save Bundle'));
        await _pumpUi(tester, frames: 10);

        expect(find.byType(BundlePlanPage), findsOneWidget);
        expect(find.text('Bundle Planner'), findsOneWidget);
        expect(api.createBundleCalls, hasLength(1));
        expect(api.addProductCalls, hasLength(1));
        expect(api.addProductCalls.single['productId'], apples.id);
      },
    );

    testWidgets('search page tag filters request tagged products', (
      tester,
    ) async {
      final apples = _product(
        id: 1,
        instanceId: 101,
        storeId: _austinStore.id,
        name: 'Apples',
        salePrice: '1.99',
        basePrice: '2.49',
      );
      final frozenPeas = _product(
        id: 2,
        instanceId: 202,
        storeId: _dallasStore.id,
        name: 'Frozen Peas',
        basePrice: '4.29',
      );

      final api = TestGroceryApi(
        allStores: <Store>[_austinStore, _dallasStore],
        allProducts: <Product>[apples, frozenPeas],
        productTags: <int, Set<int>>{
          apples.id: <int>{_bakeryTag.id},
          frozenPeas.id: <int>{_frozenTag.id},
        },
      );
      final appState = _seededState(
        api,
        userStores: const <Store>[_austinStore, _dallasStore],
      );

      await tester.pumpWidget(
        _buildTestApp(home: const SearchPage(), api: api, appState: appState),
      );
      await _pumpUi(tester);

      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Frozen Peas'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _pumpUi(tester);
      await tester.tap(find.text('Frozen'));
      await _pumpUi(tester);

      expect(find.text('Frozen Peas'), findsOneWidget);
      expect(find.text('Apples'), findsNothing);
      expect(appState.userTags, <Tag>[_frozenTag]);
      expect(api.fetchProductsRequests.last['tagIds'], <int>[_frozenTag.id]);
    });

    testWidgets(
      'search page groups duplicate store matches and details can add a higher-priced option',
      (tester) async {
      const houstonStore = Store(
        id: 9,
        companyId: 1,
        scraperId: 9,
        town: 'Houston',
        state: 'TX',
        address: '789 Grocery Rd',
        zipcode: '77001',
      );

      final bestPriceMilk = _product(
        id: 10,
        instanceId: 1001,
        storeId: _austinStore.id,
        name: 'Organic Milk',
        basePrice: '2.00',
      );
      final middlePriceMilk = _product(
        id: 10,
        instanceId: 1002,
        storeId: _dallasStore.id,
        name: 'Organic Milk',
        basePrice: '3.00',
      );
      final highestPriceMilk = _product(
        id: 10,
        instanceId: 1003,
        storeId: houstonStore.id,
        name: 'Organic Milk',
        basePrice: '4.00',
      );

      final api = TestGroceryApi(
        allStores: <Store>[_austinStore, _dallasStore, houstonStore],
        allProducts: <Product>[
          bestPriceMilk,
          middlePriceMilk,
          highestPriceMilk,
        ],
      );
      final appState = _seededState(
        api,
        userStores: const <Store>[_austinStore, _dallasStore, houstonStore],
      );

      await tester.pumpWidget(
        _buildTestApp(home: const SearchPage(), api: api, appState: appState),
      );
      await _pumpUi(tester);

      expect(find.text('Organic Milk'), findsOneWidget);
      expect(find.text('Save \$2.00'), findsOneWidget);
      expect(find.text('2 more stores from \$3.00'), findsOneWidget);
      expect(find.byIcon(Icons.savings_outlined), findsOneWidget);

      final milkResult = find.ancestor(
        of: find.text('Organic Milk').first,
        matching: find.byType(InkWell),
      );

      await tester.tap(milkResult.first);
      await _pumpUi(tester);

      expect(appState.quantityFor(bestPriceMilk), 1);
      expect(
        appState.cart.map((product) => product.instanceId).toList(),
        <int>[bestPriceMilk.instanceId],
      );

      await tester.longPress(milkResult.first);
      await _pumpUi(tester, frames: 8);

      expect(find.text('Available at 3 selected stores'), findsOneWidget);
      expect(find.text('+\$1.00 vs lowest'), findsOneWidget);
      expect(find.text('+\$2.00 vs lowest'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('product-option-action-1002'),
        ),
      );
      await _pumpUi(tester);

      expect(appState.quantityFor(middlePriceMilk), 1);
      expect(
        appState.cart.map((product) => product.instanceId).toList(),
        <int>[bestPriceMilk.instanceId, middlePriceMilk.instanceId],
      );
    });

    testWidgets('search page defaults to recommended order for milk', (
      tester,
    ) async {
      final chocolateMilk = _product(
        id: 1,
        instanceId: 101,
        storeId: _austinStore.id,
        name: 'Chocolate Milk',
        basePrice: '3.49',
      );
      final oatMilk = _product(
        id: 2,
        instanceId: 102,
        storeId: _austinStore.id,
        name: 'Oat Milk',
        basePrice: '4.29',
      );
      final wholeMilk = _product(
        id: 3,
        instanceId: 103,
        storeId: _austinStore.id,
        name: 'Whole Milk',
        basePrice: '3.19',
      );
      final twoPercentMilk = _product(
        id: 4,
        instanceId: 104,
        storeId: _austinStore.id,
        name: '2% Reduced Fat Milk',
        basePrice: '3.19',
      );
      final onePercentMilk = _product(
        id: 5,
        instanceId: 105,
        storeId: _austinStore.id,
        name: '1% Low Fat Milk',
        basePrice: '3.19',
      );
      final skimMilk = _product(
        id: 6,
        instanceId: 106,
        storeId: _austinStore.id,
        name: 'Skim Milk',
        basePrice: '3.19',
      );
      final organicWholeMilk = _product(
        id: 7,
        instanceId: 107,
        storeId: _austinStore.id,
        name: 'Organic Whole Milk',
        basePrice: '4.19',
      );

      final api = TestGroceryApi(
        allStores: <Store>[_austinStore],
        allProducts: <Product>[
          chocolateMilk,
          oatMilk,
          wholeMilk,
          twoPercentMilk,
          onePercentMilk,
          skimMilk,
          organicWholeMilk,
        ],
      );
      final appState = _seededState(
        api,
        userStores: const <Store>[_austinStore],
        searchTerm: 'milk',
      );

      await tester.pumpWidget(
        _buildTestApp(home: const SearchPage(), api: api, appState: appState),
      );
      await _pumpUi(tester);

      final matchingTexts = tester.widgetList<Text>(
        find.descendant(
            of: find.byType(ProductBox), matching: find.byType(Text)),
      );
      final orderedNames = matchingTexts
          .map((widget) => widget.data)
          .whereType<String>()
          .where((text) => text.toLowerCase().contains('milk'))
          .toList();

      expect(
        orderedNames.take(4),
        <String>[
          'Whole Milk',
          '2% Reduced Fat Milk',
          '1% Low Fat Milk',
          'Skim Milk',
        ],
      );
    });

    testWidgets(
      'store search can reopen product search after filtered search is dismissed',
      (tester) async {
        final apples = _product(
          id: 1,
          instanceId: 101,
          storeId: _austinStore.id,
          name: 'Apples',
          basePrice: '2.49',
        );
        final frozenPeas = _product(
          id: 2,
          instanceId: 202,
          storeId: _austinStore.id,
          name: 'Frozen Peas',
          salePrice: '3.99',
          basePrice: '4.29',
        );

        final api = TestGroceryApi(
          allStores: <Store>[_austinStore],
          allProducts: <Product>[apples, frozenPeas],
          productTags: <int, Set<int>>{
            apples.id: <int>{_bakeryTag.id},
            frozenPeas.id: <int>{_frozenTag.id},
          },
        );
        final appState = _seededState(api);

        await tester.pumpWidget(
          _buildTestApp(
            home: const StoreSearch(),
            api: api,
            appState: appState,
          ),
        );
        await _pumpUi(tester);

        await tester.tap(find.text('Austin').first);
        await _pumpUi(tester);

        await tester.tap(find.text('Confirm Stores (1)'));
        await _pumpUi(tester, frames: 8);

        expect(find.byType(StaplesOverview), findsOneWidget);

        await tester.tap(find.byIcon(Icons.search).first);
        await _pumpUi(tester, frames: 8);

        expect(find.byType(SearchPage), findsOneWidget);

        await tester.tap(find.byIcon(Icons.more_vert));
        await _pumpUi(tester);
        await tester.tap(_switchForLabel('Show only items on sale'));
        await _pumpUi(tester);
        await tester.tap(find.text('Frozen'));
        await _pumpUi(tester);
        await tester.tapAt(const Offset(20, 20));
        await _pumpUi(tester);

        expect(appState.userTags, <Tag>[_frozenTag]);
        expect(find.text('Frozen Peas'), findsOneWidget);

        await tester.pageBack();
        await _pumpUi(tester, frames: 8);

        expect(find.byType(StaplesOverview), findsOneWidget);

        await tester.tap(find.byIcon(Icons.search).first);
        await _pumpUi(tester, frames: 8);

        expect(find.byType(SearchPage), findsOneWidget);
        expect(find.text('Frozen Peas'), findsOneWidget);

        final reopenedCard = find
            .ancestor(
              of: find.text('Frozen Peas').first,
              matching: find.byType(Card),
            )
            .first;
        await tester.tap(reopenedCard);
        await _pumpUi(tester);

        expect(appState.cartTotalItems, 1);
      },
    );

    testWidgets('checkout moves items between todo and done columns', (
      tester,
    ) async {
      final apples = _product(
        id: 1,
        instanceId: 101,
        storeId: _austinStore.id,
        name: 'Apples',
        basePrice: '2.00',
      );
      final api = TestGroceryApi(
        allStores: <Store>[_austinStore],
        allProducts: <Product>[apples],
      );
      final appState = _seededState(
        api,
        userStores: const <Store>[_austinStore],
        cart: <Product>[apples],
        cartQuantities: <int, int>{apples.instanceId: 2},
      );

      await tester.pumpWidget(
        _buildTestApp(home: const CheckOut(), api: api, appState: appState),
      );
      await _pumpUi(tester);

      expect(find.text('Total Items: 2'), findsOneWidget);
      expect(appState.cart, <Product>[apples]);
      expect(appState.cartFinished, isEmpty);

      await tester.tap(find.text('Apples').first);
      await _pumpUi(tester);

      expect(appState.cart, isEmpty);
      expect(appState.cartFinished, <Product>[apples]);

      await tester.tap(find.text('Apples').first);
      await _pumpUi(tester);

      expect(appState.cart, <Product>[apples]);
      expect(appState.cartFinished, isEmpty);
    });

    testWidgets('bundle planner loads detail and adds a product', (
      tester,
    ) async {
      final api = TestGroceryApi(
        allStores: <Store>[_austinStore, _dallasStore],
        allProducts: <Product>[
          _product(
            id: 9,
            instanceId: 900,
            storeId: _austinStore.id,
            name: 'Olive Oil',
            basePrice: '7.49',
          ),
        ],
        dashboardResponse: <String, dynamic>{
          'bundle_count': 1,
          'saved_store_count': 1,
          'visit_count': 2,
          'recent_zipcode': '78701',
        },
        userBundlesResponse: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 900,
            'user_id': 42,
            'name': 'Weekly Plan',
            'created_at': '2026-03-13T10:00:00',
            'product_count': 1,
            'product_ids': <int>[9],
          },
        ],
        userSavedStoresResponse: <Map<String, dynamic>>[
          <String, dynamic>{'store_id': _austinStore.id, 'member': true},
        ],
        bundleDetails: <int, Map<String, dynamic>>{
          900: _bundleDetail(
            bundleId: 900,
            name: 'Weekly Plan',
            products: <Map<String, dynamic>>[
              _bundleProductJson(
                productId: 9,
                name: 'Olive Oil',
                basePrice: '7.49',
              ),
            ],
          ),
        },
      );
      final appState = _seededState(api, userStores: const <Store>[_austinStore]);

      await tester.pumpWidget(
        _buildTestApp(
          home: const BundlePlanPage(initialUserId: 42, initialBundleId: 900),
          api: api,
          appState: appState,
        ),
      );
      await _pumpUi(tester, frames: 8);

      expect(find.text('Weekly Plan'), findsOneWidget);
      expect(find.text('Olive Oil'), findsOneWidget);
      expect(find.text('Price Points by Store'), findsOneWidget);
      expect(find.text('Austin, TX'), findsOneWidget);
      expect(find.text('Add items to bundle'), findsOneWidget);

      await tester.tap(find.text('Add items to bundle'));
      await _pumpUi(tester, frames: 8);

      expect(find.byType(SearchPage), findsOneWidget);

      await tester.tap(find.text('Olive Oil').first);
      await _pumpUi(tester, frames: 4);

      expect(api.addProductCalls, hasLength(1));
      expect(api.addProductCalls.last['bundleId'], 900);
      expect(api.addProductCalls.last['productId'], 9);
    });
  });
}
