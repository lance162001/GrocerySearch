import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

Future<List<Product>> fetchProducts(List<int> storeIds,
    {String search = "",
    List<int> tags = const [],
    int page = 1,
    int size = 25}) async {
  final parameters = {'ids': storeIds, 'tags': tags};
  final Uri uri;
  if (search != "") {
    uri = Uri.http(
        'http://asktheinter.net:23451',
        '/stores/product_search?searh=$search&page=$page&size=$size',
        parameters);
  } else {
    uri = Uri.http('http://asktheinter.net:23451',
        '/stores/product_search?page=$page&size=$size', parameters);
  }
  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  Object body = {'ids': storeIds, 'tags': tags};
  final response = await http.post(uri, body: body, headers: headers);
  if (response.statusCode == 200) {
    // If the server did return a 200 OK response,
    // then parse the JSON.
    return jsonDecode(response.body)
        .map((j) => Product.fromJson(j))
        .toList()
        .cast<Product>();
  } else {
    // If the server did not return a 200 OK response,
    // then throw an exception.
    throw Exception('Failed to load products');
  }
}

Future<List<Store>> fetchStores(String search,
    {int page = 1, int size = 1}) async {
  final uri = Uri.http(
      'localhost:23451', '/stores/$search?page=$page&size=$size');
  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  final response = await http.get(uri, headers: headers);
  if (response.statusCode == 200) {
    return jsonDecode(response.body)
        .map((j) => Store.fromJson(j))
        .toList()
        .cast<Store>();
  } else {
    throw Exception('Failed to load stores');
  }
}

Future<List<Tag>> fetchTags() async {
  final uri = Uri.http('localhost:23451', '/products/tag');
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
  final uri = Uri.http('localhost:23451', '/company');
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

  String lowestPrice() {
    late String out;
    if (memberPrice != "N/A") {
      out = memberPrice;
    } else if (salePrice != "N/A") {
      out = salePrice;
    } else {
      out = basePrice;
    }
    String stringPrice = out;
    out = (out.split("\$")[1]);
    if (out.contains("/")) {
      out = out.split("/")[0];
    }
    return double.parse(out).toStringAsPrecision(
        stringPrice.contains(".") ? out.length - 1 : out.length);
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
    return PricePoint(
      salePrice: json['sale_price'],
      basePrice: json['base_price'],
      size: json['size'],
      memberPrice: json['member_price'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class Product {
  int id;
  DateTime lastUpdated;
  String brand;
  String memberPrice;
  String salePrice;
  String basePrice;
  String size;
  String pictureUrl;
  String name;
  List<PricePoint> priceHistory;
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

  Product({
    required this.id,
    required this.lastUpdated,
    required this.brand,
    required this.memberPrice,
    required this.salePrice,
    required this.basePrice,
    required this.size,
    required this.pictureUrl,
    required this.name,
    required this.priceHistory,
    this.inCart = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {

    return Product(
        id: json['id'],
        lastUpdated: DateTime.parse(json['last_updated']),
        brand: json['brand'],
        memberPrice: json['member_price'],
        salePrice: json['sale_price'],
        basePrice: json['base_price'],
        size: json['size'],
        pictureUrl: json['picture_url'],
        name: json['name'],
        priceHistory: json['price_history']
            .map((p) => PricePoint.fromJson(p))
            .toList()
            .cast<PricePoint>());
  }
}

class Store {
  int id;
  int companyId;
  int scraperId;
  String address;
  String zipcode;

  Store({
    required this.id,
    required this.companyId,
    required this.scraperId,
    required this.address,
    required this.zipcode,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
        id: json['id'],
        companyId: json['company_id'],
        scraperId: json['scraper_id'],
        address: json['address'],
        zipcode: json['zipcode']);
  }
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
  late Future<List<Tag>> tags;
  late Future<List<Company>> companies;
  List<Product> cart = [];
  setCart(List<Product> newCart) => setState(() => cart = newCart);

  @override
  void initState() {
    super.initState();
    tags = fetchTags();
    companies = fetchCompanies();
    stores = fetchStores("");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (context) =>
            Dashboard(companies: companies, stores: stores, setCart: setCart),
        '/search': (context) =>
            SearchPage(stores: stores, cart: cart, setCart: setCart),
        '/checkout': (context) => CheckOut(cart: cart, setCart: setCart),
      },
      debugShowCheckedModeBanner: false,
      title: 'GrocerySearch testing',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
    );
  }
}

class Dashboard extends StatefulWidget {
  Dashboard({
    Key? key,
    required this.companies,
    required this.stores,
    required this.setCart,
  }) : super(key: key);

  final Future<List<Company>> companies;
  Future<List<Store>> stores;
  final Function setCart;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late String storeSearch;
  final TextEditingController storeSearchController = TextEditingController();
  bool populatedStores = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(5)),
          child: TextFormField(
            keyboardType: TextInputType.number,
            onChanged: (text) => {
              setState(() {
                populatedStores = true;
                widget.stores = fetchStores(text);
              })
            },
            controller: storeSearchController,
            decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    storeSearchController.clear();
                  },
                ),
                hintText: 'Search For Stores By Zipcode or Address!',
                border: InputBorder.none),
          ),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Reset',
            onPressed: () => 1,
          )
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<List<Company>>(
              future: widget.companies,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return GridView.count(
                      primary: false,
                      padding: const EdgeInsets.all(20),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      crossAxisCount: 2,
                      children: snapshot.data!
                          .map(
                            (company) => Card(
                              color: Colors.green,
                              child: Row(children: [
                                Text(company.name),
                                Image(image: NetworkImage(company.logoUrl))
                              ]),
                            ),
                          )
                          .toList()
                          .cast<Widget>());
                } else if (snapshot.hasError) {
                  return Text('${snapshot.error}');
                }
                return Text("!!!");
              }),
          Container(
              child: populatedStores
                  ? FutureBuilder<List<Store>>(
                      future: widget.stores,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return GridView.count(
                              primary: false,
                              padding: const EdgeInsets.all(20),
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              crossAxisCount: 2,
                              children: snapshot.data!
                                  .map(
                                    (store) => Card(
                                      color: Colors.teal[100],
                                      child: Row(children: [
                                        Text(store.address),
                                        Text(store.zipcode)
                                      ]),
                                    ),
                                  )
                                  .toList()
                                  .cast<Widget>());
                        } else if (snapshot.hasError) {
                          return Text('${snapshot.error}');
                        }
                        return CircularProgressIndicator();
                      })
                  : Text("!")),
        ],
      ),
    );
  }
}

class CheckOut extends StatefulWidget {
  CheckOut({
    Key? key,
    required this.cart,
    required this.setCart,
  }) : super(key: key);

  final Function setCart;
  final List<Product> cart;

  @override
  State<CheckOut> createState() => _CheckOutState();
}

class _CheckOutState extends State<CheckOut> {
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}

class SearchPage extends StatefulWidget {
  SearchPage({
    Key? key,
    required this.stores,
    required this.cart,
    required this.setCart,
  }) : super(key: key);

  final Function setCart;
  final List<Product> cart;
  final Future<List<Store>> stores;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late Product selectedProduct;
  String searchTerm = "";
  final TextEditingController searchFieldController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Container(
            width: double.infinity,
            height: 40,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(5)),
            child: TextField(
              onChanged: (text) => {setState(() => searchTerm = text)},
              controller: searchFieldController,
              decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      searchFieldController.clear();
                    },
                  ),
                  hintText: 'Search By Product...',
                  border: InputBorder.none),
            ),
          ),
          actions: []),
      body: FutureBuilder<List<Store>>(
        future: widget.stores,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Row(
                children: snapshot.data!
                    .map((store) => Text(store.address))
                    // .map((store) => Expanded(
                    //       child: Column(
                    //         children: [
                    //           Text(store.address,
                    //               style:
                    //                   TextStyle(fontWeight: FontWeight.bold)),
                    //           Expanded(
                    //             child: ListView(
                    //                 scrollDirection: Axis.vertical,
                    //                 shrinkWrap: true,
                    //                 padding: const EdgeInsets.all(1),
                    //                 children: store.products
                    //                     .where((product) => product.name
                    //                         .toLowerCase()
                    //                         .contains(searchTerm.toLowerCase()))
                    //                     .map((p) => Card(
                    //                           clipBehavior: Clip.hardEdge,
                    //                           child: InkWell(
                    //                             splashColor:
                    //                                 Colors.blue.withAlpha(30),
                    //                             onTap: () {
                    //                               setState(() =>
                    //                                   selectedProduct = p);
                    //                               showModalBottomSheet<void>(
                    //                                   context: context,
                    //                                   builder: (BuildContext
                    //                                       context) {
                    //                                     return SizedBox(
                    //                                       height: 225,
                    //                                       child: Column(
                    //                                         children: [
                    //                                           Text(
                    //                                               "${selectedProduct.name}\nPrice History",
                    //                                               style: TextStyle(
                    //                                                   fontWeight:
                    //                                                       FontWeight
                    //                                                           .bold)),
                    //                                           SizedBox(
                    //                                             width: 200,
                    //                                             height: 100,
                    //                                             child: Chart(
                    //                                               data: List<Map>.from(selectedProduct
                    //                                                       .priceHistory
                    //                                                       .map((p) => p
                    //                                                           .toObject())
                    //                                                       .toList()
                    //                                                       .cast<
                    //                                                           Map>()) +
                    //                                                   [
                    //                                                     selectedProduct
                    //                                                         .toPricePoint()
                    //                                                         .toObject()
                    //                                                   ],
                    //                                               variables: {
                    //                                                 'timestamp':
                    //                                                     Variable(
                    //                                                   accessor: (Map
                    //                                                           map) =>
                    //                                                       map['timestamp']
                    //                                                           as String,
                    //                                                 ),
                    //                                                 'lowestPrice':
                    //                                                     Variable(
                    //                                                   accessor: (Map
                    //                                                           map) =>
                    //                                                       map['lowestPrice']
                    //                                                           as num,
                    //                                                 ),
                    //                                               },
                    //                                               elements: [
                    //                                                 IntervalElement()
                    //                                               ],
                    //                                               axes: [
                    //                                                 Defaults
                    //                                                     .horizontalAxis,
                    //                                                 Defaults
                    //                                                     .verticalAxis,
                    //                                               ],
                    //                                             ),
                    //                                           ),
                    //                                           SizedBox(
                    //                                               height: 12),
                    //                                           ElevatedButton(
                    //                                             onPressed: () =>
                    //                                                 {
                    //                                               selectedProduct
                    //                                                       .inCart
                    //                                                   ? widget
                    //                                                       .cart
                    //                                                       .remove(
                    //                                                           selectedProduct)
                    //                                                   : widget
                    //                                                       .cart
                    //                                                       .add(
                    //                                                           selectedProduct),
                    //                                               widget.setCart(
                    //                                                   widget
                    //                                                       .cart),
                    //                                               selectedProduct
                    //                                                       .inCart =
                    //                                                   !selectedProduct
                    //                                                       .inCart,
                    //                                               Navigator.pop(
                    //                                                   context)
                    //                                             },
                    //                                             child: Column(
                    //                                               children: [
                    //                                                 Row(
                    //                                                     mainAxisAlignment:
                    //                                                         MainAxisAlignment
                    //                                                             .center,
                    //                                                     mainAxisSize:
                    //                                                         MainAxisSize
                    //                                                             .min,
                    //                                                     children: selectedProduct.inCart
                    //                                                         ? [
                    //                                                             Text("Remove from Cart?"),
                    //                                                             Icon(Icons.remove_shopping_cart)
                    //                                                           ]
                    //                                                         : [
                    //                                                             Text("Add To Cart?"),
                    //                                                             Icon(Icons.add_shopping_cart)
                    //                                                           ]),
                    //                                               ],
                    //                                             ),
                    //                                           ),
                    //                                         ],
                    //                                       ),
                    //                                     );
                    //                                   });
                    //                             },
                    //                             child: SizedBox(
                    //                                 height: 70,
                    //                                 child: Column(
                    //                                     crossAxisAlignment:
                    //                                         CrossAxisAlignment
                    //                                             .start,
                    //                                     children: [
                    //                                       SizedBox(
                    //                                           height: 34,
                    //                                           child: Text(
                    //                                               p.name,
                    //                                               maxLines: 2)),
                    //                                       Row(children: [
                    //                                         Image.network(
                    //                                             p.pictureUrl[
                    //                                                         0] ==
                    //                                                     "h"
                    //                                                 ? p.pictureUrl
                    //                                                 : "https://${p.pictureUrl}",
                    //                                             width: 20,
                    //                                             height: 20),
                    //                                         Text(p.size == "N/A"
                    //                                             ? ""
                    //                                             : p.size),
                    //                                       ]),
                    //                                       Row(children: [
                    //                                         Text(
                    //                                             p.memberPrice ==
                    //                                                     p
                    //                                                         .salePrice
                    //                                                 ? p
                    //                                                     .basePrice
                    //                                                 : "${p.basePrice}, ",
                    //                                             style: TextStyle(
                    //                                                 fontWeight: p.memberPrice ==
                    //                                                         p
                    //                                                             .salePrice
                    //                                                     ? FontWeight
                    //                                                         .bold
                    //                                                     : FontWeight
                    //                                                         .normal)),
                    //                                         Text(
                    //                                             p.salePrice == "N/A"
                    //                                                 ? ""
                    //                                                 : "${p.salePrice}, ",
                    //                                             style: TextStyle(
                    //                                                 fontWeight: p.memberPrice ==
                    //                                                         "N/A"
                    //                                                     ? FontWeight
                    //                                                         .bold
                    //                                                     : FontWeight
                    //                                                         .normal,
                    //                                                 fontStyle:
                    //                                                     FontStyle
                    //                                                         .italic)),
                    //                                         Text(
                    //                                             p.memberPrice ==
                    //                                                     "N/A"
                    //                                                 ? ""
                    //                                                 : p
                    //                                                     .memberPrice,
                    //                                             style: TextStyle(
                    //                                                 fontWeight:
                    //                                                     FontWeight
                    //                                                         .bold)),
                    //                                       ])
                    //                                     ])),
                    //                           ),
                    //                         ))
                    //                     .toList()
                    //                     .cast<Widget>()),
                    //           ),
                    // ],
                    // ),
                    // ))
                    .toList()
                    .cast<Widget>());
          } else if (snapshot.hasError) {
            return Text('${snapshot.error}');
          }

          // By default, show a loading spinner.
          return CircularProgressIndicator();
        },
      ),
    );
  }
}
