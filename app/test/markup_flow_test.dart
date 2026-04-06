// Integration tests for the Markup 4-tab shell.
//
// We do NOT import main.dart because it transitively imports game_page.dart
// which uses dart:html (web-only). Instead we build a minimal test shell
// that mirrors MarkupShell / MarkupApp using the same screen widgets.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/config/app_environment.dart';
import 'package:flutter_front_end/config/markup_theme.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/screens/feed_screen.dart';
import 'package:flutter_front_end/screens/search_screen.dart';
import 'package:flutter_front_end/screens/tracking_screen.dart';
import 'package:flutter_front_end/screens/play_screen.dart';
import 'package:flutter_front_end/services/auth_service.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/state/markup_state.dart';

// ---------------------------------------------------------------------------
// Minimal test API — returns canned data without any HTTP calls
// ---------------------------------------------------------------------------

class _TestMarkupApi extends GroceryApi {
  _TestMarkupApi() : super(environment: AppEnvironment.local);

  @override
  Future<Map<String, dynamic>> fetchFeed({
    int page = 1,
    int size = 10,
    String? zipcode,
  }) async {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'price_reveal',
          'product_id': 1,
          'product_name': 'Large Eggs',
          'brand': 'Store Brand',
          'size': '12 ct',
          'prices': <Map<String, dynamic>>[
            <String, dynamic>{
              'chain': 'Aldi',
              'company_id': 1,
              'price': 2.99,
              'is_best': true,
              'diff_from_best': null,
            },
            <String, dynamic>{
              'chain': 'Whole Foods',
              'company_id': 2,
              'price': 5.49,
              'is_best': false,
              'diff_from_best': 2.50,
            },
          ],
        },
      ],
      'has_more': false,
    };
  }

  @override
  Future<List<Tag>> fetchTags() async => const <Tag>[];

  @override
  Future<List<Company>> fetchCompanies() async => const <Company>[];

  @override
  Future<List<Store>> fetchStores(String search,
      {int page = 1, int size = 8}) async => const <Store>[];

  @override
  Future<List<Store>> fetchAllStores() async => const <Store>[];

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
  }) async => const <Product>[];

  @override
  Future<Map<String, dynamic>?> getObject(
    String path, {
    Map<String, String>? queryParameters,
  }) async => null;

  @override
  Future<List<Map<String, dynamic>>?> getObjectList(
    String path, {
    Map<String, String>? queryParameters,
  }) async => null;

  @override
  Future<List<Product>> fetchVariations(
      int productId, List<int> storeIds) async => const <Product>[];

  @override
  Future<Map<String, List<Product>>> fetchStapleProducts(
    List<int> storeIds,
    List<String> stapleNames,
  ) async =>
      <String, List<Product>>{
        for (final name in stapleNames) name: <Product>[],
      };

  @override
  Future<List<GroupingJudgementSummary>> fetchGroupingJudgements() async =>
      const <GroupingJudgementSummary>[];

  @override
  Future<List<TrackedItem>> fetchTrackedItems(int userId) async =>
      const <TrackedItem>[];

  @override
  Future<Map<String, dynamic>> fetchPoints(int userId) async =>
      <String, dynamic>{'points': 0};

  @override
  Future<List<JudgementCandidate>> fetchJudgementCandidates({
    required String judgementType,
    required int userId,
    int count = 5,
  }) async => const <JudgementCandidate>[];
}

// ---------------------------------------------------------------------------
// Minimal AuthService stub
// ---------------------------------------------------------------------------

class _TestAuthService extends AuthService {
  _TestAuthService() : super.test();

  @override
  bool get isSignedIn => false;

  @override
  String? get displayName => null;

  @override
  String? get email => null;

  @override
  String? get photoUrl => null;
}

// ---------------------------------------------------------------------------
// Test shell — mirrors MarkupShell/MarkupApp but avoids game_page.dart
// ---------------------------------------------------------------------------

class _TestMarkupShell extends StatefulWidget {
  const _TestMarkupShell();

  @override
  State<_TestMarkupShell> createState() => _TestMarkupShellState();
}

class _TestMarkupShellState extends State<_TestMarkupShell> {
  int _currentIndex = 0;

  final _screens = const [
    FeedScreen(),
    SearchScreen(),
    TrackingScreen(),
    PlayScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Feed'),
          NavigationDestination(
              icon: Icon(Icons.search),
              selectedIcon: Icon(Icons.search),
              label: 'Search'),
          NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications),
              label: 'Tracking'),
          NavigationDestination(
              icon: Icon(Icons.sports_esports_outlined),
              selectedIcon: Icon(Icons.sports_esports),
              label: 'Play'),
        ],
      ),
    );
  }
}

Widget _buildTestMarkupApp(_TestMarkupApi api) {
  final appState = AppState(api: api)..bootstrappingUser = false;
  final markupState = MarkupState(api: api);

  return MultiProvider(
    providers: [
      Provider<AppEnvironment>.value(value: AppEnvironment.local),
      Provider<GroceryApi>.value(value: api),
      ChangeNotifierProvider<AuthService>.value(value: _TestAuthService()),
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<MarkupState>.value(value: markupState),
    ],
    child: MaterialApp(
      title: 'Markup',
      theme: markupTheme(),
      home: const _TestMarkupShell(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Markup 4-tab integration', () {
    testWidgets('App opens to Feed tab and shows price reveal card',
        (tester) async {
      final api = _TestMarkupApi();
      await tester.pumpWidget(_buildTestMarkupApp(api));

      // Let the async feed load complete.
      await tester.pumpAndSettle();

      // Branding visible in Feed header.
      expect(find.text('Markup'), findsOneWidget);

      // Price reveal card rendered with canned product name.
      expect(find.text('Large Eggs'), findsOneWidget);
    });

    testWidgets('Bottom nav switches between tabs without crashing',
        (tester) async {
      final api = _TestMarkupApi();
      await tester.pumpWidget(_buildTestMarkupApp(api));
      await tester.pumpAndSettle();

      // Tap Search tab.
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      // Tap Tracking tab.
      await tester.tap(find.text('Tracking'));
      await tester.pumpAndSettle();

      // Tap Play tab.
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Tap back to Feed.
      await tester.tap(find.text('Feed'));
      await tester.pumpAndSettle();

      // No crash; Feed branding is still visible.
      expect(find.text('Markup'), findsOneWidget);
    });
  });
}
