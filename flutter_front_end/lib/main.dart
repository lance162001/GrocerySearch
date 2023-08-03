import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

dynamic extractPage(Map<String, dynamic> json) {
  return json['items'];
}

Future<List<Product>> fetchProducts(List<int> storeIds,
    {String search = "",
    List<Tag> tags = const [],
    int page = 1,
    int size = 100}) async {
  final String uri;
  if (search != "") {
    uri =
        'http://localhost:23451/stores/product_search?search=$search&page=$page&size=$size';
  } else {
    uri = 'http://localhost:23451/stores/product_search?page=$page&size=$size';
  }

  final headers = {HttpHeaders.contentTypeHeader: 'application/json'};
  Object body =
      jsonEncode({'ids': storeIds, 'tags': tags.map((t) => t.id).toList()});
  final response =
      await http.post(Uri.parse(uri), body: body, headers: headers);

  if (response.statusCode == 200) {
    // If the server did return a 200 OK response,
    // then parse the JSON.
    return extractPage(jsonDecode(response.body))
        .map((j) => Product.fromJson(j))
        .toList()
        .cast<Product>();
  } else {
    print(response.body);
    // If the server did not return a 200 OK response,
    // then throw an exception.
    throw Exception('Failed to load products');
  }
}

Future<List<Store>> fetchStores(String search,
    {int page = 1, int size = 4}) async {
  final uri = search == ""
      ? 'http://localhost:23451/stores/search?page=$page&size=$size'
      : 'http://localhost:23451/stores/search?search=$search&page=$page&size=$size';

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
  final uri = Uri.http('localhost:23451', '/products/tags');
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
    return (other is Product) && (other.id == id);
  }

  @override
  int get hashCode => id;

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
    required this.companyId,
    required this.storeId,
    this.inCart = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> p = json['Product'];
    Map<String, dynamic> i = json['Product_Instance'];

    List<PricePoint> pHistory = i['price_points']
        .map((p) => PricePoint.fromJson(p))
        .toList()
        .cast<PricePoint>();

    pHistory.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Product(
      id: p['id'],
      lastUpdated: pHistory[0].timestamp,
      brand: p['brand'],
      memberPrice: pHistory[0].memberPrice,
      salePrice: pHistory[0].salePrice,
      basePrice: pHistory[0].basePrice,
      size: pHistory[0].size,
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
  // late Future<List<Company>> companies;
  // List<Company> companies = [
  //   Company(
  //       id: 1,
  //       name: "Whole Foods",
  //       logoUrl:
  //           "https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fcdn2.thelineofbestfit.com%2Fmedia%2F2013%2F08%2Fwhole-foods-logo.png&f=1&nofb=1&ipt=0c8e87c4626f259464ef9df05e119efce140f958aca5f51b07a040aeaa208739&ipo=images"),
  //   Company(
  //       id: 2,
  //       name: "Trader Joes",
  //       logoUrl:
  //           "https://external-content.duckduckgo.com/iu/?u=https%3A%2F%2Fwww.cityofredlands.org%2Fsites%2Fmain%2Ffiles%2Fimagecache%2Flightbox%2Fmain-images%2Ftrader_joes_logo-removebg-preview.png&f=1&nofb=1&ipt=254e1fc23e39cde3a17e2605723792e1609da040b3baea00502eaa54a2b0ee42&ipo=images")
  // ];
  List<Company> companies = [];
  List<Store> userStores = [];
  late Future<List<Product>> products;
  List<Product> cart = [];
  List<Tag> userTags = [];
  void setTags(Tag tag) => setState(
      () => userTags.contains(tag) ? userTags.remove(tag) : userTags.add(tag));

  void setCart(List<Product> newCart) => setState(() => cart = newCart);
  void setStore(Store store) => setState(() => userStores.contains(store)
      ? userStores.remove(store)
      : userStores.add(store));

  @override
  void initState() {
    super.initState();
    fetchTags().then((t) => tags = t);
    fetchCompanies().then((value) => companies = value);
    stores = fetchStores("");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (context) => Dashboard(
            companies: companies,
            tags: tags,
            setTags: setTags,
            stores: stores,
            userStores: userStores,
            userTags: userTags,
            setStore: setStore,
            setCart: setCart),
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
    required this.tags,
    required this.stores,
    required this.userStores,
    required this.userTags,
    required this.setStore,
    required this.setCart,
    required this.setTags,
  }) : super(key: key);

  final List<Company> companies;
  final List<Tag> tags;
  Future<List<Store>> stores;
  List<Store> userStores;
  List<Tag> userTags;
  final Function setStore;
  final Function setCart;
  final Function setTags;

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
      ),
      body: Center(
        child: Column(
          children: [
            Column(
              children: [
                SizedBox(
                  height: 500,
                  child: FutureBuilder<List<Store>>(
                      future: widget.stores,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          List<Store> stores =
                              snapshot.data! + widget.userStores;

                          stores = stores.toSet().toList();
                          return GridView.builder(
                            itemCount: stores.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2),
                            shrinkWrap: true,
                            primary: false,
                            padding: const EdgeInsets.all(20),
                            itemBuilder: (context, index) {
                              Store store = stores[index];
                              return Card(
                                semanticContainer: true,
                                color: widget.userStores.contains(store)
                                    ? Colors.blue[800]
                                    : Colors.blue,
                                clipBehavior: Clip.hardEdge,
                                child: InkWell(
                                    splashColor: Colors.blue.withAlpha(30),
                                    onTap: () {
                                      widget.setStore(store);
                                    },
                                    child: Column(children: [
                                      widget.companies.isNotEmpty
                                          ? Image(
                                              width: 100,
                                              height: 100,
                                              image: NetworkImage(widget
                                                  .companies[
                                                      store.companyId - 1]
                                                  .logoUrl))
                                          : Text(""),
                                      Text(store.town,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      Text(store.state,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      Text(store.address,
                                          style: TextStyle(
                                              fontStyle: FontStyle.italic)),
                                    ])),
                              );
                            },
                          );
                        } else if (snapshot.hasError) {
                          return Text('${snapshot.error}');
                        }
                        return CircularProgressIndicator();
                      }),
                ),
                SizedBox(height: 50),
                widget.userStores.isEmpty
                    ? OutlinedButton(
                        onPressed: () => {}, child: Text("Confirm Stores"))
                    : ElevatedButton(
                        onPressed: () => {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => SearchPage(
                                          companies: widget.companies,
                                          tags: widget.tags,
                                          stores: widget.userStores,
                                          userTags: widget.userTags,
                                          setTags: widget.setTags,
                                          cart: [],
                                          setCart: widget.setCart)))
                            },
                        child: Text("Confirm Stores"))
              ],
            )
          ],
        ),
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
    required this.userTags,
    required this.companies,
    required this.tags,
    required this.cart,
    required this.setCart,
    required this.setTags,
  }) : super(key: key);

  final List<Company> companies;
  final List<Tag> tags;
  final Function setCart;
  final Function setTags;
  final List<Product> cart;
  final List<Store> stores;
  Future<List<Product>>? products;
  List<Tag> userTags = [];

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late Product selectedProduct;
  String searchTerm = "";
  final TextEditingController searchFieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.products = fetchProducts(widget.stores.map((s) => s.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    List<int> storeIds = widget.stores.map((s) => s.id).toList();
    return Scaffold(
        appBar: AppBar(
            title: Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(5)),
              child: TextField(
                onSubmitted: (text) {
                  searchTerm = text;
                  widget.products = fetchProducts(
                    storeIds,
                    search: text,
                    tags: widget.userTags,
                  );
                  setState(() => 1);
                },
                controller: searchFieldController,
                decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchFieldController.clear();
                        widget.products = fetchProducts(storeIds);
                        setState(() => 1);
                      },
                    ),
                    hintText: 'Search By Product...',
                    border: InputBorder.none),
              ),
            ),
            actions: [
              IconButton(
                iconSize: 32,
                icon: Icon(Icons.more_vert),
                onPressed: () => {
                  showModalBottomSheet<void>(
                      context: context,
                      builder: (BuildContext context) {
                        return SizedBox(
                          height: 200,
                          child: Column(
                            children: [
                              Text("Filter By Tags",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(height: 5),
                              Wrap(
                                  spacing: 5.0,
                                  children: widget.tags
                                      .map((tag) => FilterChip(
                                          label: Text(tag.name),
                                          selected:
                                              widget.userTags.contains(tag),
                                          onSelected: (bool selected) {
                                            widget.setTags(tag);
                                            widget.products = fetchProducts(
                                              storeIds,
                                              search: searchTerm,
                                              tags: widget.userTags,
                                            );
                                            setState(() => 1);
                                          }))
                                      .toList()
                                      .cast<Widget>()),
                            ],
                          ),
                        );
                      })
                },
              )
            ]),
        body: Row(
            children: widget.stores
                .map((store) => Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(store.town,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Image(
                                  width: 50,
                                  height: 50,
                                  image: NetworkImage(widget
                                      .companies[store.companyId - 1].logoUrl))
                            ],
                          ),
                          Expanded(
                            child: FutureBuilder<List<Product>>(
                              future: widget.products,
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  return ListView(
                                      scrollDirection: Axis.vertical,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(1),
                                      children: snapshot.data!
                                          .where((product) =>
                                              product.storeId == store.id)
                                          .map((p) => Card(
                                                color: widget.cart.contains(p)
                                                    ? Colors.lightBlue[100]
                                                    : Colors.white,
                                                clipBehavior: Clip.hardEdge,
                                                child: InkWell(
                                                  splashColor:
                                                      Colors.blue.withAlpha(30),
                                                  onTap: () {
                                                    setState(() {
                                                      widget.cart.contains(p)
                                                          ? widget.cart
                                                              .remove(p)
                                                          : widget.cart.add(p);
                                                      // widget
                                                      //     .setCart(widget.cart);
                                                    });
                                                  },
                                                  onLongPress: () {
                                                    showModalBottomSheet<void>(
                                                        context: context,
                                                        builder: (BuildContext
                                                            context) {
                                                          return SizedBox(
                                                            height: 225,
                                                            child: Column(
                                                              children: [
                                                                Text(
                                                                    "${p.name}\nPrice History",
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold)),
                                                                SizedBox(
                                                                  width: 200,
                                                                  height: 100,
                                                                  child:
                                                                      BarChart(
                                                                    BarChartData(),
                                                                    swapAnimationCurve:
                                                                        Curves
                                                                            .linear,
                                                                    swapAnimationDuration:
                                                                        Duration(
                                                                            milliseconds:
                                                                                150),
                                                                    // data: List<Map>.from(selectedProduct
                                                                    //         .priceHistory
                                                                    //         .map((p) => p
                                                                    //             .toObject())
                                                                    //         .toList()
                                                                    //         .cast<
                                                                    //             Map>()) +
                                                                    //     [
                                                                    //       selectedProduct
                                                                    //           .toPricePoint()
                                                                    //           .toObject()
                                                                    //     ],
                                                                    // variables: {
                                                                    //   'timestamp':
                                                                    //       Variable(
                                                                    //     accessor: (Map
                                                                    //             map) =>
                                                                    //         map['timestamp']
                                                                    //             as String,
                                                                    //   ),
                                                                    //   'lowestPrice':
                                                                    //       Variable(
                                                                    //     accessor: (Map
                                                                    //             map) =>
                                                                    //         map['lowestPrice']
                                                                    //             as num,
                                                                    //   ),
                                                                    // },
                                                                    // elements: [
                                                                    //   IntervalElement()
                                                                    // ],
                                                                    // axes: [
                                                                    //   Defaults
                                                                    //       .horizontalAxis,
                                                                    //   Defaults
                                                                    //       .verticalAxis,
                                                                    // ],
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                    height: 12),
                                                                ElevatedButton(
                                                                  onPressed:
                                                                      () => {
                                                                    widget.cart
                                                                            .contains(
                                                                                p)
                                                                        ? widget
                                                                            .cart
                                                                            .remove(
                                                                                p)
                                                                        : widget
                                                                            .cart
                                                                            .add(p),
                                                                    Navigator.pop(
                                                                        context)
                                                                  },
                                                                  child: Column(
                                                                    children: [
                                                                      Row(
                                                                          mainAxisAlignment: MainAxisAlignment
                                                                              .center,
                                                                          mainAxisSize: MainAxisSize
                                                                              .min,
                                                                          children: widget.cart.contains(p)
                                                                              ? [
                                                                                  Text("Remove from Cart?"),
                                                                                  Icon(Icons.remove_shopping_cart)
                                                                                ]
                                                                              : [
                                                                                  Text("Add To Cart?"),
                                                                                  Icon(Icons.add_shopping_cart)
                                                                                ]),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        });
                                                  },
                                                  child: SizedBox(
                                                      height: 71,
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            SizedBox(
                                                                height: 34,
                                                                child: Text(
                                                                    p.name,
                                                                    maxLines:
                                                                        2)),
                                                            Row(children: [
                                                              Image.network(
                                                                  p.pictureUrl[
                                                                              0] ==
                                                                          "h"
                                                                      ? p.pictureUrl
                                                                      : "https://${p.pictureUrl}",
                                                                  width: 20,
                                                                  height: 20),
                                                              Text(p.size ==
                                                                      "N/A"
                                                                  ? ""
                                                                  : p.size),
                                                            ]),
                                                            Row(children: [
                                                              Text(
                                                                  p.memberPrice ==
                                                                          p
                                                                              .salePrice
                                                                      ? p
                                                                          .basePrice
                                                                      : "${p.basePrice} ",
                                                                  style: TextStyle(
                                                                      fontWeight: p.memberPrice == p.salePrice
                                                                          ? FontWeight
                                                                              .bold
                                                                          : FontWeight
                                                                              .normal)),
                                                              Text(
                                                                  p.salePrice ==
                                                                          "N/A"
                                                                      ? ""
                                                                      : "${p.salePrice} ",
                                                                  style: TextStyle(
                                                                      fontWeight: p.memberPrice ==
                                                                              "N/A"
                                                                          ? FontWeight
                                                                              .bold
                                                                          : FontWeight
                                                                              .normal,
                                                                      fontStyle:
                                                                          FontStyle
                                                                              .italic)),
                                                              Text(
                                                                  p.memberPrice ==
                                                                          "N/A"
                                                                      ? ""
                                                                      : p
                                                                          .memberPrice,
                                                                  style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold)),
                                                            ])
                                                          ])),
                                                ),
                                              ))
                                          .toList()
                                          .cast<Widget>());
                                } else if (snapshot.hasError) {
                                  return Text('${snapshot.error}');
                                } else {
                                  return CircularProgressIndicator();
                                }
                              },
                            ),
                          )
                        ],
                      ),
                    ))
                .toList()
                .cast<Widget>()));
  }
}
