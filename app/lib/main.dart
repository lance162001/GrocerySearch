import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/app_environment.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/firebase_options.dart';
import 'package:flutter_front_end/main_search.dart';
import 'package:flutter_front_end/services/auth_service.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chart.dart';
import 'package:flutter_front_end/bundle_plan.dart';
import 'package:flutter_front_end/check_out.dart';
import 'package:flutter_front_end/label_judgement.dart';
import 'package:flutter_front_end/product_search.dart';
import 'package:flutter_front_end/suggest_store.dart';
import 'package:flutter_front_end/shared_bundle_page.dart';
import 'package:flutter_front_end/staples_overview.dart';
import 'package:flutter_front_end/unsubscribe_page.dart';
import 'package:flutter_front_end/preferences_page.dart';
import 'package:flutter_front_end/game_page.dart';
import 'package:flutter_front_end/user_id_cache.dart' as user_cache;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';

dynamic extractPage(Map<String, dynamic> json) {
  return json['items'];
}

String get hostname => AppEnvironment.current.hostname;
String get port => AppEnvironment.current.port;

Future<int> fetchOrCreateUserId() async {
  final cachedUserId = await user_cache.readCachedUserId();
  if (cachedUserId != null && cachedUserId > 0) {
    return cachedUserId;
  }

  final uri = Uri.http('$hostname:$port', '/users/create');
  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  final response = await http.post(uri, headers: headers);
  if (response.statusCode != 200) {
    throw Exception('Failed to create user: ${response.statusCode}');
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final userId = decoded['id'];
  if (userId is! int || userId <= 0) {
    throw Exception('Backend returned invalid user id');
  }

  await user_cache.writeCachedUserId(userId);
  return userId;
}

double? parsePriceString(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String formatPriceString(String raw) {
  final parsed = parsePriceString(raw);
  if (parsed == null) {
    return raw.startsWith(r'$') ? raw : r'$' + raw;
  }
  return '\$${parsed.toStringAsFixed(2)}';
}

Future<List<Product>> fetchProducts(List<int> storeIds,
    {String search = "",
    List<Tag> tags = const [],
    bool onSaleOnly = false,
    int page = 1,
    int size = 100,
    List<Product> toAdd = const []}) async {
  final queryParams = <String, String>{
    'page': '$page',
    'size': '$size',
    if (search != "") 'search': search,
    if (onSaleOnly) 'on_sale': 'true',
  };
  final uri = Uri.http('$hostname:$port', '/stores/product_search', queryParams)
      .toString();

  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  Object body =
      jsonEncode({'ids': storeIds, 'tags': tags.map((t) => t.id).toList()});
  final response =
      await http.post(Uri.parse(uri), body: body, headers: headers);

  if (response.statusCode == 200) {
    // If the server did return a 200 OK response,
    // then parse the JSON.
    return [
      ...toAdd,
      ...extractPage(jsonDecode(response.body))
          .map((j) => Product.fromJson(j))
          .toList()
          .cast<Product>()
    ];
  } else {
    // If the server did not return a 200 OK response,
    // then throw an exception.
    throw Exception('Failed to load products');
  }
}

Future<List<Store>> fetchStores(String search,
    {int page = 1, int size = 8}) async {
  final uri = search == ""
      ? 'http://$hostname:$port/stores/search?page=$page&size=$size'
      : 'http://$hostname:$port/stores/search?search=$search&page=$page&size=$size';

  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  final response = await http.get(Uri.parse(uri), headers: headers);
  if (response.statusCode == 200) {
    return extractPage(jsonDecode(response.body))
        .map((j) => Store.fromJson(j))
        .toList()
        .cast<Store>();
  } else {
    throw Exception('Failed to load stores');
  }
}

Future<List<Store>> fetchAllStores() async {
  final uri = Uri.http('$hostname:$port', '/stores');
  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  final response = await http.get(uri, headers: headers);
  if (response.statusCode == 200) {
    return (jsonDecode(response.body) as List<dynamic>)
        .map((j) => Store.fromJson(j as Map<String, dynamic>))
        .toList();
  } else {
    throw Exception('Failed to load all stores');
  }
}

Future<Set<int>> fetchSavedStoreIdsForUser(int userId) async {
  final uri = Uri.http('$hostname:$port', '/users/$userId/saved-stores');
  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  final response = await http.get(uri, headers: headers);

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

Future<List<Tag>> fetchTags() async {
  final uri = Uri.http('$hostname:$port', '/products/tags');
  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  final response = await http.get(uri, headers: headers);
  if (response.statusCode == 200) {
    return jsonDecode(response.body)
        .map((j) => Tag.fromJson(j))
        .toList()
        .cast<Tag>();
  } else {
    throw Exception('Failed to load tags');
  }
}

Future<List<Company>> fetchCompanies() async {
  final uri = Uri.http('$hostname:$port', '/company');
  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  final response = await http.get(uri, headers: headers);
  if (response.statusCode == 200) {
    return jsonDecode(response.body)
        .map((j) => Company.fromJson(j))
        .toList()
        .cast<Company>();
  } else {
    throw Exception('Failed to load companies');
  }
}

class Tag {
  int id;
  String name;

  Tag({required this.id, required this.name});

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'],
      name: json['name'],
    );
  }

  @override
  bool operator ==(Object other) {
    return (other is Tag) && (other.id == id);
  }

  @override
  int get hashCode => id;
}

class Company {
  int id;
  String name;
  String logoUrl;

  Company({required this.id, required this.name, required this.logoUrl});

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
        id: json['id'], name: json['name'], logoUrl: json['logo_url']);
  }
}

class PricePoint {
  String memberPrice;
  String salePrice;
  String basePrice;
  String size;
  DateTime timestamp;

  double lowestPrice() {
    late String out;
    if (memberPrice != "") {
      out = memberPrice;
    } else if (salePrice != "") {
      out = salePrice;
    } else {
      out = basePrice;
    }
    // String stringPrice = out;
    // out = (out.split("\$")[1]);
    // if (out.contains("/")) {
    //   out = out.split("/")[0];
    // }
    return double.parse(out); //.toStringAsPrecision(
    //     stringPrice.contains(".") ? out.length - 1 : out.length);
  }

  Map toObject() {
    return {
      "timestamp": "${timestamp.year}/${timestamp.month}/${timestamp.day}",
      "lowestPrice": lowestPrice(),
    };
  }

  PricePoint({
    required this.memberPrice,
    required this.salePrice,
    required this.basePrice,
    required this.size,
    required this.timestamp,
  });

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    json['sale_price'] ??= '';
    json['member_price'] ??= '';

    return PricePoint(
      salePrice: json['sale_price'],
      basePrice: json['base_price'],
      size: json['size'],
      memberPrice: json['member_price'],
      timestamp: DateTime.parse(json['created_at']),
    );
  }
}

class Product {
  int id;
  int instanceId;
  DateTime lastUpdated;
  String brand;
  String memberPrice;
  String salePrice;
  String basePrice;
  String size;
  String pictureUrl;
  String name;
  List<PricePoint> priceHistory;
  int companyId;
  int storeId;
  bool inCart;

  PricePoint toPricePoint() {
    return PricePoint(
      memberPrice: memberPrice,
      salePrice: salePrice,
      basePrice: basePrice,
      size: size,
      timestamp: lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) {
    return (other is Product) && (other.instanceId == instanceId);
  }

  @override
  int get hashCode => instanceId;

  Product({
    required this.id,
    required this.instanceId,
    required this.lastUpdated,
    required this.brand,
    required this.memberPrice,
    required this.salePrice,
    required this.basePrice,
    required this.size,
    required this.pictureUrl,
    required this.name,
    required this.priceHistory,
    required this.companyId,
    required this.storeId,
    this.inCart = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> p = json['Product'];
    Map<String, dynamic> i = json['Product_Instance'];
    final dynamic rawInstanceId = i['id'];
    final int safeInstanceId = rawInstanceId is int
        ? rawInstanceId
        : Object.hash(p['id'], i['store_id']) & 0x3fffffff;

    List<PricePoint> pHistory = i['price_points']
        .map((p) => PricePoint.fromJson(p))
        .toList()
        .cast<PricePoint>();

    pHistory.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    PricePoint latest = pHistory.isNotEmpty ? pHistory.first : PricePoint(
      memberPrice: '',
      salePrice: '',
      basePrice: '0',
      size: '',
      timestamp: DateTime.now(),
    );
    for (final pp in pHistory) {
      final isNewer = pp.timestamp.isAfter(latest.timestamp);
      final isSameTimeButBetter =
          pp.timestamp.isAtSameMomentAs(latest.timestamp) &&
              pp.lowestPrice() < latest.lowestPrice();
      if (isNewer || isSameTimeButBetter) {
        latest = pp;
      }
    }
    return Product(
      id: p['id'],
      instanceId: safeInstanceId,
      lastUpdated: latest.timestamp,
      brand: p['brand'],
      memberPrice: latest.memberPrice,
      salePrice: latest.salePrice,
      basePrice: latest.basePrice,
      size: latest.size,
      pictureUrl: p['picture_url'],
      name: p['name'],
      priceHistory: pHistory,
      companyId: p['company_id'],
      storeId: i['store_id'],
    );
  }
}

class Store {
  int id;
  int companyId;
  int scraperId;
  String address;
  String town;
  String state;
  String zipcode;

  Store({
    required this.id,
    required this.companyId,
    required this.scraperId,
    required this.town,
    required this.state,
    required this.address,
    required this.zipcode,
  });

  @override
  bool operator ==(Object other) {
    return (other is Store) && (other.id == id);
  }

  @override
  int get hashCode => id;

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
        id: json['id'],
        companyId: json['company_id'],
        scraperId: json['scraper_id'],
        town: json['town'],
        state: json['state'],
        address: json['address'],
        zipcode: json['zipcode']);
  }
}

// From https://coflutter.com/flutter-check-if-the-listview-reaches-the-top-or-the-bottom/
void setupScrollListener(
    {required ScrollController scrollController,
    Function? onAtTop,
    Function? onAtBottom}) {
  scrollController.addListener(() {
    if (scrollController.position.atEdge) {
      // Reach the top of the list
      if (scrollController.position.pixels == 0) {
        onAtTop?.call();
      }
      // Reach the bottom of the list
      else {
        onAtBottom?.call();
      }
    }
  });
}

Widget getNotification(List<PricePoint> pricepoints) {
  PricePoint curPrice = pricepoints[0];
  //Duration fullRange = curPrice.timestamp.difference(pricepoints.last.timestamp);
  Icon icon = Icon(Icons.wallet, size: 13);
  late double average = 0;

  for (PricePoint p in pricepoints) {
    average += p.lowestPrice();
  }
  average /= pricepoints.length;
  if (curPrice.lowestPrice() < average) {
    icon = Icon(Icons.wallet, size: 13, color: Colors.green);
  }
  if (curPrice.lowestPrice() > average) {
    icon = Icon(Icons.wallet, size: 13, color: Colors.red);
  }
  return icon;
}

Widget getImage(String url, double width, double height) {
  String imageUrl;
  if (url.startsWith('http')) {
    imageUrl = url;
  } else if (url.startsWith('/')) {
    imageUrl = 'http://$hostname:$port$url';
  } else {
    imageUrl = 'http://$hostname:$port/$url';
  }
  return CachedNetworkImage(
    imageUrl: imageUrl,
    width: width,
    height: height,
    fit: BoxFit.contain,
    alignment: Alignment.center,
    fadeInDuration: Duration(milliseconds: 250),
    placeholder: (context, url) => Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      child: SizedBox(
        width: (width < 24) ? 12 : 20,
        height: (height < 24) ? 12 : 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    errorWidget: (context, url, error) => Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(Icons.broken_image, size: (width < 24) ? 12 : 20, color: Colors.grey[600]),
    ),
  );
}

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<List<Store>> stores;
  int? currentUserId;
  bool bootstrappingUser = true;
  String? userBootstrapError;
  List<Tag> tags = [];
  List<Company> companies = [];
  List<Store> userStores = [];
  late Future<List<Product>> products;
  List<Product> cart = [];
  List<Product> cartFinished = [];
  Map<int, int> cartQuantities = {};
  List<Tag> userTags = [];
  String searchTerm = "";
  void setTags(Tag tag) => setState(
      () => userTags.contains(tag) ? userTags.remove(tag) : userTags.add(tag));

  void setCart(List<Product> newCart) => setState(() => cart = newCart);
  void setCartFinished(List<Product> newCartFinished) =>
      setState(() => cartFinished = newCartFinished);

  void addToCartQty(Product p, int qty) => setState(() {
      cartQuantities[p.instanceId] = (cartQuantities[p.instanceId] ?? 0) + qty;
      if (!cart.any((item) => item.instanceId == p.instanceId)) cart.add(p);
      });

  void removeFromCartAll(Product p) => setState(() {
      cartQuantities.remove(p.instanceId);
      cart.removeWhere((item) => item.instanceId == p.instanceId);
      });

  int cartTotalItems() => cartQuantities.values.fold(0, (a, b) => a + b);
  void setStore(Store store) => setState(() => userStores.contains(store)
      ? userStores.remove(store)
      : userStores.add(store));
  void setSearchTerm(String term) => setState(() => searchTerm = term);

  Widget _buildHomePage(BuildContext context, AppState appState) {
    final authService = context.watch<AuthService>();

    if (!authService.isSignedIn) {
      return _SignInPage(authService: authService);
    }

    if (appState.bootstrappingUser) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Setting up local user...'),
            ],
          ),
        ),
      );
    }

    if (appState.currentUserId == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Unable to load user ID.'),
                const SizedBox(height: 8),
                if (appState.userBootstrapError != null)
                  Text(
                    appState.userBootstrapError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.read<AppState>().initialize(force: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const StoreSearch();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    const environment = AppEnvironment.current;
    return MultiProvider(
      providers: [
        Provider<AppEnvironment>.value(value: environment),
        Provider<GroceryApi>(
          create: (_) => GroceryApi(environment: environment),
        ),
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(),
        ),
        ChangeNotifierProvider<AppState>(
          create: (context) =>
              AppState(api: context.read<GroceryApi>())..initialize(),
        ),
      ],
      child: Builder(
        builder: (context) {
          // Standalone flows that must not depend on AppState
          // (AppState rebuilds reset the Navigator back to home:).
          if (kIsWeb && (
            Uri.base.path == AppRoutes.unsubscribe ||
            Uri.base.path == AppRoutes.sharedBundle ||
            Uri.base.path == AppRoutes.game
          )) {
            // Game needs GroceryApi; wrap with explicit providers so the page
            // can make API calls without depending on AppState.
            if (Uri.base.path == AppRoutes.game) {
              return MultiProvider(
                providers: [
                  Provider<AppEnvironment>.value(value: environment),
                  Provider<GroceryApi>(
                    create: (_) => GroceryApi(environment: environment),
                  ),
                ],
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: 'GrocerySearch',
                  initialRoute: AppRoutes.game,
                  routes: {
                    AppRoutes.game: (context) => const GamePage(),
                  },
                ),
              );
            }
            final home = Uri.base.path == AppRoutes.sharedBundle
                ? const SharedBundlePage()
                : const UnsubscribePage();
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'GrocerySearch',
              home: home,
            );
          }
          final appState = context.watch<AppState>();
          final plannerUserId = appState.currentUserId ?? 1;
          final homePage = _buildHomePage(context, appState);
          return MaterialApp(
            home: homePage,
            routes: {
              AppRoutes.storeSearch: (context) => const StoreSearch(),
              AppRoutes.chart: (context) => BarChartSample4(),
              AppRoutes.bundlePlan: (context) =>
                  BundlePlanPage(initialUserId: plannerUserId),
              AppRoutes.staplesOverview: (context) =>
                const StaplesOverview(),
              AppRoutes.search: (context) => const SearchPage(),
              AppRoutes.checkout: (context) => const CheckOut(),
              AppRoutes.labelJudgement: (context) =>
                  const LabelJudgementPage(),
              AppRoutes.suggestStore: (context) =>
                  const SuggestStorePage(),
              AppRoutes.unsubscribe: (context) =>
                  const UnsubscribePage(),
              AppRoutes.sharedBundle: (context) =>
                  const SharedBundlePage(),
              AppRoutes.preferences: (context) =>
                  const PreferencesPage(),
              AppRoutes.game: (context) => const GamePage(),
            },
            onUnknownRoute: (settings) =>
                MaterialPageRoute(builder: (context) => homePage),
            debugShowCheckedModeBanner: false,
            title: 'GrocerySearch',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1b4332),
                brightness: Brightness.light,
              ),
              primaryColor: const Color(0xFF1b4332),
              scaffoldBackgroundColor: const Color(0xFFFAFAFA),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1b4332),
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: IconThemeData(color: Colors.white),
                actionsIconTheme: IconThemeData(color: Colors.white),
                titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Color(0xFFDCE8DC)),
                ),
                color: Colors.white,
              ),
              dividerTheme: const DividerThemeData(
                color: Color(0xFFDCE8DC),
                thickness: 1,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1b4332),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1b4332),
                  side: const BorderSide(color: Color(0xFFDCE8DC)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1b4332),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1b4332), width: 1.5),
                ),
                hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
              ),
              chipTheme: ChipThemeData(
                backgroundColor: const Color(0xFFF4F4F5),
                selectedColor: const Color(0xFFE9F7EE),
                side: const BorderSide(color: Color(0xFFDCE8DC)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              tabBarTheme: const TabBarThemeData(
                labelColor: Colors.white,
                unselectedLabelColor: Color(0xFF71717A),
                indicatorColor: Color(0xFF1b4332),
              ),
              snackBarTheme: SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage({required this.authService});
  final AuthService authService;

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage>
    with SingleTickerProviderStateMixin {
  bool _signingIn = false;
  String? _error;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final result = await widget.authService.signInWithGoogle();
      if (result != null && mounted) {
        context.read<AppState>().initialize(force: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _signingIn = false);
      }
    }
  }

  Future<void> _openGithubProfile() async {
    const githubUri = 'https://github.com/lance162001';
    final opened = await launchUrl(Uri.parse(githubUri));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open github.com/lance162001')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF09090B), // zinc-950
              Color(0xFF18181B), // zinc-900
              Color(0xFF27272A), // zinc-800
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background circles
            Positioned(
              top: -size.height * 0.12,
              right: -size.width * 0.18,
              child: Container(
                width: size.width * 0.6,
                height: size.width * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1b4332).withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: -size.height * 0.08,
              left: -size.width * 0.2,
              child: Container(
                width: size.width * 0.7,
                height: size.width * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1b4332).withValues(alpha: 0.04),
                ),
              ),
            ),
            // Main content
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: size.height -
                            MediaQuery.of(context).padding.top -
                            MediaQuery.of(context).padding.bottom,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 52),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Logo circle
                            Container(
                              width: 108,
                              height: 108,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF1b4332),
                                    Color(0xFF2D6A4F),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1b4332)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 32,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.shopping_basket_rounded,
                                size: 54,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 28),
                            // Title
                            Text(
                              'GrocerySearch',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: const Text(
                                'Smart shopping. Better prices.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFA1A1AA),
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 48),
                            // Feature cards
                            _LandingFeatureCard(
                              icon: Icons.compare_arrows_rounded,
                              iconColor: const Color(0xFF2D6A4F),
                              title: 'Compare Prices',
                              description:
                                  'Side-by-side prices from Whole Foods, Wegmans, Trader Joe\'s, and more.',
                            ),
                            const SizedBox(height: 10),
                            _LandingFeatureCard(
                              icon: Icons.local_offer_rounded,
                              iconColor: const Color(0xFFFBBF24),
                              title: 'Spot the Best Deals',
                              description:
                                  'Sale and member pricing clearly surfaced so you never overpay.',
                            ),
                            const SizedBox(height: 10),
                            _LandingFeatureCard(
                              icon: Icons.inventory_2_rounded,
                              iconColor: const Color(0xFF95D5B2),
                              title: 'Bundle & Plan',
                              description:
                                  'Build shopping bundles and track your pantry staples over time.',
                            ),
                            const SizedBox(height: 52),
                            // CTA button
                            if (_signingIn)
                              const SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            else
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _handleGoogleSignIn,
                                  icon: const Icon(Icons.login_rounded,
                                      size: 20),
                                  label: const Text(
                                    'Sign in with Google',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1b4332),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13),
                                ),
                              ),
                            ],
                            const SizedBox(height: 36),
                            DefaultTextStyle(
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.3),
                                letterSpacing: 0.4,
                              ),
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  const Text('made with'),
                                  Icon(
                                    Icons.favorite_rounded,
                                    size: 14,
                                    color: Colors.redAccent.withValues(alpha: 0.8),
                                  ),
                                  const Text('by'),
                                  TextButton(
                                    onPressed: _openGithubProfile,
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          Colors.white.withValues(alpha: 0.65),
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'github.com/lance162001',
                                      style: TextStyle(
                                        decoration: TextDecoration.underline,
                                        decorationThickness: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingFeatureCard extends StatelessWidget {
  const _LandingFeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class StoreRow extends StatelessWidget {
  const StoreRow(
      {super.key,
      required this.store,
      required this.product,
      required this.logoUrl});

  final Store store;
  final Product product;
  final String logoUrl;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          getImage(logoUrl, 20, 20),
          SizedBox(height: 2),
          Text(store.town,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
