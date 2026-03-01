import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/main_search.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/product_search.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'chart.dart';
import 'package:flutter_front_end/pretty_search.dart';

dynamic extractPage(Map<String, dynamic> json) {
  return json['items'];
}

//// CHANGE ME
bool local = true;
////

String hostname = local ? 'localhost' : 'asktheinter.net';
String port = local ? '8000' : '23451';

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
    int page = 1,
    int size = 100,
    List<Product> toAdd = const []}) async {
  final String uri;
  if (search != "") {
    uri =
        'http://$hostname:$port/stores/product_search?search=$search&page=$page&size=$size';
  } else {
    uri = 'http://$hostname:$port/stores/product_search?page=$page&size=$size';
  }

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
    print(response.body);
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
    imageUrl = 'http://$hostname:$port' + url;
  } else {
    imageUrl = 'http://$hostname:$port/' + url;
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

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<List<Store>> stores;
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

  @override
  void initState() {
    super.initState();
    fetchTags().then((t) => setState(() => tags = t));
    fetchCompanies().then((value) => setState(() => companies = value));
    stores = fetchStores("");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: '/',
      routes: {
        '/chart': (context) => BarChartSample4(),
        '/testing' : (context) => PrettySearch(),
        '/': (context) => StoreSearch(
              companies: companies,
              tags: tags,
              setTags: setTags,
              stores: stores,
              userStores: userStores,
              userTags: userTags,
              cart: cart,
              cartFinished: cartFinished,
              setStore: setStore,
              setCart: setCart,
              setCartFinished: setCartFinished,
              addToCartQty: addToCartQty,
              removeFromCartAll: removeFromCartAll,
              cartQuantities: cartQuantities,
              searchTerm: searchTerm,
              setSearchTerm: setSearchTerm,
            )
      },
      debugShowCheckedModeBanner: false,
      title: 'GrocerySearch testing',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        primaryColor: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
        cardTheme: CardThemeData(
          elevation: 2,
          margin: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.grey[900], displayColor: Colors.grey[900]),
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
      width: 110,
      child: Column(
        children: [
          Text(product.brand,
              maxLines: 2,
              style: TextStyle(fontSize: 11),
              overflow: TextOverflow.fade,
              softWrap: true),
          Row(
            children: [
              Text(store.town,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              getImage(logoUrl, 30, 30)
            ],
          ),
        ],
      ),
    );
  }
}
