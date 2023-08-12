import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'chart.dart';

dynamic extractPage(Map<String, dynamic> json) {
  return json['items'];
}

bool local = true;

String addr = 'localhost';
String port = '23451';

String hostname = local ? addr : 'asktheinter.net';

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
    return (other is Product) && (other.id == id) && (other.storeId == storeId);
  }

  @override
  int get hashCode => int.parse("$id$storeId");

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
  return CachedNetworkImage(
      imageUrl: url[0] == "h" ? url : "https://$url",
      width: width,
      height: height);
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
  List<Tag> userTags = [];
  String searchTerm = "";
  void setTags(Tag tag) => setState(
      () => userTags.contains(tag) ? userTags.remove(tag) : userTags.add(tag));

  void setCart(List<Product> newCart) => setState(() => cart = newCart);
  void setCartFinished(List<Product> newCartFinished) =>
      setState(() => cartFinished = newCartFinished);
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
        '/': (context) => Dashboard(
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
              searchTerm: searchTerm,
              setSearchTerm: setSearchTerm,
            )
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
    required this.searchTerm,
    required this.setSearchTerm,
    required this.setStore,
    required this.setCart,
    required this.setCartFinished,
    required this.setTags,
    required this.cart,
    required this.cartFinished,
  }) : super(key: key);

  final List<Company> companies;
  final List<Tag> tags;
  Future<List<Store>> stores;
  List<Store> userStores;
  List<Tag> userTags;
  final Function setStore;
  final Function setCart;
  final Function setCartFinished;
  final Function setTags;
  final List<Product> cart;
  final List<Product> cartFinished;
  final String searchTerm;
  final Function setSearchTerm;

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
            keyboardType: TextInputType.text,
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
            Expanded(
              child: FutureBuilder<List<Store>>(
                  future: widget.stores,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      List<Store> stores = snapshot.data! + widget.userStores;

                      stores = stores.toSet().toList();
                      return GridView.builder(
                        itemCount: stores.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2),
                        shrinkWrap: true,
                        primary: false,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          Store store = stores[index];
                          return Card(
                            color: widget.userStores.contains(store)
                                ? Colors.lightBlue
                                : const Color.fromARGB(255, 144, 220, 255),
                            child: InkWell(
                                splashColor: Colors.blue.withAlpha(30),
                                onTap: () {
                                  widget.setStore(store);
                                },
                                child: Column(children: [
                                  widget.companies.isNotEmpty
                                      ? getImage(
                                          widget.companies[store.companyId - 1]
                                              .logoUrl,
                                          100,
                                          100)
                                      : CircularProgressIndicator(),
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
            SizedBox(height: 20),
            widget.userStores.isEmpty
                ? OutlinedButton(
                    onPressed: () => {}, child: Text("Confirm Stores"))
                : ElevatedButton(
                    onPressed: () => {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (context) {
                            return SearchPage(
                              companies: widget.companies,
                              tags: widget.tags,
                              stores: widget.userStores,
                              userTags: widget.userTags,
                              setTags: widget.setTags,
                              cart: widget.cart,
                              cartFinished: widget.cartFinished,
                              setCart: widget.setCart,
                              setCartFinished: widget.setCartFinished,
                              searchTerm: widget.searchTerm,
                              setSearchTerm: widget.setSearchTerm,
                            );
                          }))
                        },
                    child: Text("Confirm Stores")),
            SizedBox(height: 20),
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
    required this.cartFinished,
    required this.stores,
    required this.setCart,
    required this.setCartFinished,
    required this.companies,
  }) : super(key: key);

  final Function setCart;
  final Function setCartFinished;
  List<Product> cartFinished;
  List<Product> cart;
  final List<Store> stores;
  final List<Company> companies;

  @override
  State<CheckOut> createState() => _CheckOutState();
}

class _CheckOutState extends State<CheckOut> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Checkout"),
        ),
        body: Column(
          children: [
            Text("To Do:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(1),
                  children: widget.stores
                      .map((s) => Column(
                            children: [
                              Row(children: [
                                Text(s.town,
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                getImage(
                                    widget.companies[s.companyId - 1].logoUrl,
                                    75,
                                    50),
                              ]),
                              Expanded(
                                child: SizedBox(
                                  width: 180,
                                  child: ListView(
                                      scrollDirection: Axis.vertical,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(1),
                                      children: widget.cart
                                          .where((p) => p.storeId == s.id)
                                          .map((p) => Card(
                                              color: Colors.white,
                                              clipBehavior: Clip.hardEdge,
                                              child: InkWell(
                                                  onTap: () {
                                                    widget.cart.remove(p);
                                                    widget.cartFinished.add(p);
                                                    widget.setCart(widget.cart);
                                                    widget.setCartFinished(
                                                        widget.cartFinished);
                                                  },
                                                  child: ProductBox(p: p))))
                                          .toList()
                                          .cast<Widget>()),
                                ),
                              ),
                            ],
                          ))
                      .toList()),
            ),
            SizedBox(height: 35),
            Text("Done:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(1),
                  children: widget.stores
                      .map((s) => Column(
                            children: [
                              Row(children: [
                                Text(s.town,
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                getImage(
                                    widget.companies[s.companyId - 1].logoUrl,
                                    75,
                                    50),
                              ]),
                              Expanded(
                                child: SizedBox(
                                  width: 180,
                                  child: ListView(
                                      scrollDirection: Axis.vertical,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(1),
                                      children: widget.cartFinished
                                          .where((p) => p.storeId == s.id)
                                          .map((p) => Card(
                                              color: Colors.white,
                                              clipBehavior: Clip.hardEdge,
                                              child: InkWell(
                                                  onTap: () {
                                                    widget.cart.add(p);
                                                    widget.cartFinished
                                                        .remove(p);
                                                    widget.setCart(widget.cart);
                                                    widget.setCartFinished(
                                                        widget.cartFinished);
                                                  },
                                                  child: ProductBox(p: p))))
                                          .toList()
                                          .cast<Widget>()),
                                ),
                              ),
                            ],
                          ))
                      .toList()),
            ),
          ],
        ));
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
    required this.cartFinished,
    required this.setCart,
    required this.setCartFinished,
    required this.setTags,
    required this.searchTerm,
    required this.setSearchTerm,
  }) : super(key: key);

  final List<Company> companies;
  final List<Tag> tags;
  final Function setCart;
  final Function setCartFinished;
  final Function setTags;
  final Function setSearchTerm;
  final String searchTerm;
  String termt = "";
  final List<Product> cart;
  final List<Product> cartFinished;
  final List<Store> stores;
  Future<List<Product>>? products;
  List<Tag> userTags = [];

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late Product selectedProduct;
  int page = 1;
  int pageLength = 100;
  final ScrollController scrollController = ScrollController();
  TextEditingController searchFieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.products = fetchProducts(widget.stores.map((s) => s.id).toList(),
        search: widget.termt, tags: widget.userTags, page: page);
  }

  @override
  Widget build(BuildContext context) {
    List<int> storeIds = widget.stores.map((s) => s.id).toList();
    void s() {
      setState(() => 1);
    }

    setupScrollListener(
        scrollController: scrollController,
        onAtTop: () => 1,
        onAtBottom: () {
          widget.products?.then((v) {
            if (v.length >= page * pageLength) {
              page++;
              print(page);
            } else {
              print("${v.length} < ${page * pageLength}");
              return;
            }
            widget.products = fetchProducts(
              storeIds,
              search: widget.termt,
              tags: widget.userTags,
              page: page,
              toAdd: v,
            );
          });
        });

    return Scaffold(
        appBar: AppBar(
            title: Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(5)),
              child: TextField(
                onSubmitted: (text) {
                  page = 1;
                  widget.termt = text;
                  widget.products = fetchProducts(
                    storeIds,
                    search: text,
                    tags: widget.userTags,
                  );
                  setState(() {});
                },
                controller: searchFieldController,
                decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchFieldController.clear();
                        widget.termt = "";
                        page = 1;

                        widget.products =
                            fetchProducts(storeIds, tags: widget.userTags);
                        widget.products!.then((v) => setState(() => 1));
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
                        return StatefulBuilder(builder:
                            (BuildContext context, StateSetter setState) {
                          return SizedBox(
                            height: 175,
                            child: Column(
                              children: [
                                Text("Filter By Tags",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(height: 5),
                                SizedBox(
                                  height: 150,
                                  child: SingleChildScrollView(
                                    child: Wrap(
                                        runSpacing: 2,
                                        spacing: 5.0,
                                        children: widget.tags
                                            .map((tag) => FilterChip(
                                                label: Text(tag.name),
                                                selected: widget.userTags
                                                    .contains(tag),
                                                onSelected: (bool selected) {
                                                  page = 1;
                                                  widget.userTags.contains(tag)
                                                      ? widget.userTags
                                                          .remove(tag)
                                                      : widget.userTags
                                                          .add(tag);
                                                  widget.products =
                                                      fetchProducts(
                                                    storeIds,
                                                    search: widget.termt,
                                                    tags: widget.userTags,
                                                  );
                                                  setState(() => 1);
                                                  widget.products!
                                                      .then((v) => s());
                                                }))
                                            .toList()
                                            .cast<Widget>()),
                                  ),
                                ),
                              ],
                            ),
                          );
                        });
                      })
                },
              ),
              Row(
                children: [
                  Text(widget.cart.length.toString()),
                  IconButton(
                      icon: Icon(Icons.shopping_cart_checkout),
                      iconSize: 32,
                      onPressed: () => {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => CheckOut(
                                          companies: widget.companies,
                                          stores: widget.stores,
                                          cart: widget.cart,
                                          cartFinished: widget.cartFinished,
                                          setCart: widget.setCart,
                                          setCartFinished:
                                              widget.setCartFinished,
                                        )))
                          }),
                ],
              )
            ]),
        body: FutureBuilder<List<Product>>(
            future: widget.products,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                List<Product> products = snapshot.data!;
                if (products.isEmpty) {
                  return Text("No Products Found!");
                }

                return ListView.builder(
                    controller: scrollController,
                    itemCount: products.length,
                    scrollDirection: Axis.vertical,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(1),
                    itemBuilder: (context, index) {
                      Product p = products[index];
                      return Card(
                        color: widget.cart.contains(p)
                            ? Colors.lightBlue[100]
                            : Colors.white,
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          splashColor: Colors.blue.withAlpha(30),
                          onTap: () {
                            widget.cart.contains(p)
                                ? widget.cart.remove(p)
                                : widget.cart.add(p);
                            widget.setCart(widget.cart);
                          },
                          onLongPress: () {
                            showModalBottomSheet<void>(
                                context: context,
                                builder: (BuildContext context) {
                                  return SizedBox(
                                    height: 225,
                                    child: Column(
                                      children: [
                                        Text("${p.name}\nPrice History",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        SizedBox(
                                          width: 200,
                                          height: 100,
                                          child: BarChart(
                                            BarChartData(),
                                            swapAnimationCurve: Curves.linear,
                                            swapAnimationDuration:
                                                Duration(milliseconds: 150),
                                          ),
                                        ),
                                        SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: () => {
                                            setState(() =>
                                                widget.cart.contains(p)
                                                    ? widget.cart.remove(p)
                                                    : widget.cart.add(p)),
                                            Navigator.pop(context)
                                          },
                                          child: Column(
                                            children: [
                                              Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: widget.cart
                                                          .contains(p)
                                                      ? [
                                                          Text(
                                                              "Remove from Cart?"),
                                                          Icon(Icons
                                                              .remove_shopping_cart)
                                                        ]
                                                      : [
                                                          Text("Add To Cart?"),
                                                          Icon(Icons
                                                              .add_shopping_cart)
                                                        ]),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                });
                          },
                          child: Row(
                            children: [
                              Expanded(child: ProductBox(p: p)),
                              Expanded(
                                child: getImage(p.pictureUrl, 60, 60),
                              ),
                              StoreRow(
                                  product: p,
                                  store: widget.stores
                                      .firstWhere((s) => s.id == p.storeId),
                                  logoUrl: widget
                                      .companies[widget.stores
                                              .firstWhere(
                                                  (s) => s.id == p.storeId)
                                              .companyId -
                                          1]
                                      .logoUrl),
                            ],
                          ),
                        ),
                      );
                    });
              } else if (snapshot.hasError) {
                return Text('${snapshot.error}');
              } else {
                return CircularProgressIndicator();
              }
            }));
  }
}

class ProductBox extends StatelessWidget {
  const ProductBox({super.key, required this.p});

  final Product p;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 71,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              height: 34,
              child: Text(p.name,
                  overflow: TextOverflow.fade, softWrap: true, maxLines: 2)),
          Row(children: [
            getImage(p.pictureUrl, 24, 24),
            Expanded(
              child: Text(p.size == "N/A" ? "" : "  ${p.size}"),
            ),
          ]),
          Row(children: [
            Text(
                p.memberPrice == p.salePrice
                    ? "\$${p.basePrice}"
                    : "\$${p.basePrice} | ",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: p.memberPrice == p.salePrice
                        ? FontWeight.bold
                        : FontWeight.normal)),
            Text(p.salePrice == "" ? "" : "\$${p.salePrice}",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: p.memberPrice == "N/A"
                      ? FontWeight.bold
                      : FontWeight.normal,
                )),
            Text(p.memberPrice == "" ? "" : " | \$${p.memberPrice}",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            getNotification(p.priceHistory),
          ])
        ]));
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
